// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title Moloch (Majeur) — Snapshot-Weighted Multisig/DAO (no-custody), with ERC-6909 vote receipts,
 *        futarchy (optional), timelock, permits, allowances/pull, token sales, ragequit, and SBT-gated chat.
 *
 * Design goals:
 * - Works for 2/2 multisigs, 256-seat boards, and 100k-holder DAOs.
 * - No ERC20 custody for voting. Uses block-number snapshots (like OZ Governor/Votes).
 * - Simple pass rule: majority FOR, with dynamic quorum (BPS) and optional absolute floors.
 * - Optional timelock delay between "ready" and execution.
 * - ERC6909 receipts (non-transferable) minted on vote; can be burned for futarchy payouts if enabled.
 * - Minimal external deps. All code in one file, readable and auditable.
 */
contract MolochMajeur {
    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/
    error NotOk();
    error NotOwner();
    error NotApprover();
    error AlreadyExecuted();
    error LengthMismatch();
    error Timelocked(uint64 untilWhen);

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/
    /// @dev Restricts a function to be callable only by the Moloch contract itself.
    modifier onlySelf() {
        if (msg.sender != address(this)) revert NotOwner();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                              ORG / METADATA
    //////////////////////////////////////////////////////////////*/
    string public orgName;
    string public orgSymbol;

    /*//////////////////////////////////////////////////////////////
                           GOVERNANCE CONFIG
    //////////////////////////////////////////////////////////////*/
    // Absolute vote thresholds (0 = disabled)
    uint256 public minYesVotesAbsolute; // minimum YES (FOR) votes
    uint256 public quorumAbsolute; // minimum total turnout (FOR+AGAINST+ABSTAIN)

    // Time-based settings (seconds; 0 = off)
    uint64 public proposalTTL; // proposal expiry
    uint64 public timelockDelay; // delay between success and execution

    // Governance versioning / dynamic quorum / global flags
    uint64 public config; // bump salt to invalidate old ids/permits
    uint16 public quorumBps; // dynamic quorum vs snapshot supply (BPS, 0 = off)
    bool public ragequittable;
    bool public transfersLocked; // global Shares transfer lock

    /*//////////////////////////////////////////////////////////////
                      TOKENS: SHARES (ERC20) / BADGE (SBT)
    //////////////////////////////////////////////////////////////*/
    MolochShares public shares;
    MolochBadge public badge;

    event SharesDeployed(address token);
    event BadgeDeployed(address badge);

    /*//////////////////////////////////////////////////////////////
                           PROPOSAL / STATE TRACKING
    //////////////////////////////////////////////////////////////*/
    // Proposal id = keccak(address(this), op, to, value, keccak(data), nonce, config)
    mapping(bytes32 => bool) public executed; // executed latch
    mapping(bytes32 => uint64) public createdAt; // first open/vote time
    mapping(bytes32 => uint256) public snapshotBlock; // block.number - 1
    mapping(bytes32 => uint256) public supplySnapshot; // total supply at snapshotBlock
    mapping(bytes32 => uint64) public queuedAt; // timelock queue time (0 = not queued)

    struct Tally {
        uint256 forVotes;
        uint256 againstVotes;
        uint256 abstainVotes;
    }
    mapping(bytes32 => Tally) public tallies;

    // hasVoted[id][voter] = 0 = not, 1 = FOR, 2 = AGAINST, 3 = ABSTAIN
    mapping(bytes32 => mapping(address => uint8)) public hasVoted;

    enum ProposalState {
        Unopened,
        Active,
        Queued,
        Succeeded,
        Defeated,
        Expired,
        Executed
    }

    event Opened(bytes32 indexed id, uint256 snapshotBlock, uint256 supplyAtSnapshot);
    event Voted(bytes32 indexed id, address indexed voter, uint8 support, uint256 weight);
    event Queued(bytes32 indexed id, uint64 when);
    event Executed(bytes32 indexed id, address indexed by, uint8 op, address to, uint256 value);

    /*//////////////////////////////////////////////////////////////
                           PERMITS (FIXED SPEND)
    //////////////////////////////////////////////////////////////*/
    mapping(bytes32 => uint256) public permits; // remaining uses (max=unlimited)
    event PermitSet(bytes32 indexed hash, uint256 newCount, bool replaced);
    event PermitSpent(
        bytes32 indexed hash, address indexed by, uint8 op, address to, uint256 value
    );

    /* Optional: mirror permits as ERC6909 credits for tooling */
    bool public use6909ForPermits;
    event Use6909ForPermitsSet(bool on);

    /*//////////////////////////////////////////////////////////////
                           ALLOWANCES / PULL
    //////////////////////////////////////////////////////////////*/
    mapping(address => mapping(address => uint256)) public allowance; // token => recipient => amount

    /*//////////////////////////////////////////////////////////////
                           TREASURY SALES (SHARES)
    //////////////////////////////////////////////////////////////*/
    struct Sale {
        uint256 pricePerShare; // in payToken units (wei for ETH)
        uint256 cap; // remaining shares (0 = unlimited)
        bool minting; // true=mint, false=transfer SAW-held
        bool active;
    }
    mapping(address => Sale) public sales; // payToken => Sale

    event SaleUpdated(
        address indexed payToken, uint256 price, uint256 cap, bool minting, bool active
    );
    event SharesPurchased(
        address indexed buyer, address indexed payToken, uint256 shares, uint256 paid
    );

    /*//////////////////////////////////////////////////////////////
                              SBT-GATED CHAT
    //////////////////////////////////////////////////////////////*/
    string[] public messages;
    event Message(address indexed from, uint256 indexed index, string text);

    /*//////////////////////////////////////////////////////////////
                      ERC6909 RECEIPTS (NON-TRANSFERABLE)
    //////////////////////////////////////////////////////////////*/
    // ERC6909 metadata: org name/symbol (shared across ids)
    function name(
        uint256 /*id*/
    )
        public
        view
        returns (string memory)
    {
        return orgName;
    }

    function symbol(
        uint256 /*id*/
    )
        public
        view
        returns (string memory)
    {
        return orgSymbol;
    }

    event Transfer(
        address caller, address indexed from, address indexed to, uint256 indexed id, uint256 amount
    );

    // holder => id => amount
    mapping(address => mapping(uint256 => uint256)) public balanceOf;
    // id => total supply
    mapping(uint256 => uint256) public totalSupply;

    // decode helpers for SVGs & futarchy validation
    mapping(uint256 => uint8) public receiptSupport; // 0=Against, 1=For, 2=Abstain
    mapping(uint256 => bytes32) public receiptProposal; // which proposal this receipt belongs to

    /*//////////////////////////////////////////////////////////////
                             FUTARCHY (OPTIONAL)
    //////////////////////////////////////////////////////////////*/
    struct FutarchyConfig {
        bool enabled; // futarchy mode for this proposal
        address rewardToken; // address(0) = ETH, else ERC20
        uint256 pool; // funded amount
        bool resolved; // set on resolution
        uint8 winner; // 1=YES (For), 0=NO (Against)
        uint256 finalWinningSupply; // total supply of winning receipts at resolve
        uint256 payoutPerUnit; // pool / finalWinningSupply (floor)
    }
    mapping(bytes32 => FutarchyConfig) public futarchy;

    event FutarchyOpened(bytes32 indexed id, address indexed rewardToken);
    event FutarchyFunded(bytes32 indexed id, address indexed from, uint256 amount);
    event FutarchyResolved(
        bytes32 indexed id, uint8 winner, uint256 pool, uint256 finalSupply, uint256 payoutPerUnit
    );
    event FutarchyClaimed(
        bytes32 indexed id, address indexed claimer, uint256 burned, uint256 payout
    );

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    constructor(
        string memory _orgName,
        string memory _orgSymbol,
        uint16 _quorumBps, // e.g. 5000 = 50% turnout of snapshot supply
        bool _ragequittable,
        address[] memory initialHolders,
        uint256[] memory initialAmounts
    ) payable {
        if (initialHolders.length != initialAmounts.length) {
            revert LengthMismatch();
        }

        orgName = _orgName;
        orgSymbol = _orgSymbol;
        quorumBps = _quorumBps;
        ragequittable = _ragequittable;

        // Deploy Shares + Badge; names/symbols are pulled from SAW.
        shares = new MolochShares(initialHolders, initialAmounts, address(this));
        emit SharesDeployed(address(shares));
        badge = new MolochBadge();
        emit BadgeDeployed(address(badge));

        // Seed top-256 via hook.
        for (uint256 i = 0; i < initialHolders.length; ++i) {
            _onSharesChanged(initialHolders[i]);
        }
    }

    /*//////////////////////////////////////////////////////////////
                         PROPOSAL ID / SNAPSHOT
    //////////////////////////////////////////////////////////////*/
    function proposalId(uint8 op, address to, uint256 value, bytes calldata data, bytes32 nonce)
        public
        view
        returns (bytes32)
    {
        return _intentHash(op, to, value, data, nonce);
    }

    /// @notice Explicitly open a proposal (fix snapshot to previous block).
    /// Snapshot at a strictly *past* block so OZ checkpoints are valid.
    /// Also record createdAt and (optionally) supplyAtSnapshot for UX.
    function openProposal(bytes32 id) public {
        if (snapshotBlock[id] != 0) return; // already opened

        // Snapshot at previous block; block.number is never 0 in practice.
        uint32 snap = toUint32(block.number - 1);
        snapshotBlock[id] = snap;

        if (createdAt[id] == 0) {
            createdAt[id] = uint64(block.timestamp);
        }

        // For snap == 0 (first block in test env), fall back to current supply.
        uint256 supply = snap == 0 ? shares.totalSupply() : shares.getPastTotalSupply(snap);

        supplySnapshot[id] = supply;

        emit Opened(id, snap, supply);
    }

    /// @notice Open & set futarchy settings (governance).
    function openFutarchy(bytes32 id, address rewardToken) public payable onlySelf {
        openProposal(id);
        FutarchyConfig storage F = futarchy[id];
        if (F.enabled) revert NotOk();
        F.enabled = true;
        F.rewardToken = rewardToken;
        emit FutarchyOpened(id, rewardToken);
    }

    function fundFutarchy(bytes32 id, uint256 amount) public payable nonReentrant {
        FutarchyConfig storage F = futarchy[id];
        if (!F.enabled || F.resolved) revert NotOk();
        if (F.rewardToken == address(0)) {
            if (msg.value != amount) revert NotOk();
            F.pool += amount;
        } else {
            if (msg.value != 0) revert NotOk();
            uint256 before = _erc20Balance(F.rewardToken);
            _safeTransferFrom(F.rewardToken, msg.sender, address(this), amount);
            uint256 received = _erc20Balance(F.rewardToken) - before;
            if (received == 0) revert NotOk();
            F.pool += received;
        }
        emit FutarchyFunded(id, msg.sender, amount);
    }

    /*//////////////////////////////////////////////////////////////
                              VOTING (SNAPSHOT)
    //////////////////////////////////////////////////////////////*/
    /// @notice support: 0 = AGAINST, 1 = FOR, 2 = ABSTAIN
    function castVote(bytes32 id, uint8 support) public {
        if (executed[id]) revert AlreadyExecuted();
        if (support > 2) revert NotOk();

        // Auto-open on first vote if unopened
        if (snapshotBlock[id] == 0) openProposal(id);

        // Optional expiry gating
        if (proposalTTL != 0) {
            uint64 t0 = createdAt[id];
            if (t0 == 0) revert NotOk();
            if (block.timestamp > t0 + proposalTTL) revert NotOk();
        }

        if (hasVoted[id][msg.sender] != 0) revert NotOk(); // one vote per address

        uint32 snap = toUint32(snapshotBlock[id]);
        uint256 weight = (snap == 0)
            ? shares.getVotes(msg.sender)  // genesis fallback (no valid past block)
            : shares.getPastVotes(msg.sender, snap);

        if (weight == 0) revert NotOk();

        // Tally
        if (support == 1) tallies[id].forVotes += weight;
        else if (support == 0) tallies[id].againstVotes += weight;
        else tallies[id].abstainVotes += weight;

        hasVoted[id][msg.sender] = support + 1;

        // Mint ERC6909 receipt (non-transferable)
        uint256 rid = _receiptId(id, support);
        receiptSupport[rid] = support;
        receiptProposal[rid] = id;
        _mint6909(msg.sender, rid, weight);

        emit Voted(id, msg.sender, support, weight);
    }

    /*//////////////////////////////////////////////////////////////
                       PROPOSAL STATE / RULES / QUEUE+EXEC
    //////////////////////////////////////////////////////////////*/
    function state(bytes32 id) public view returns (ProposalState) {
        if (executed[id]) return ProposalState.Executed;
        if (snapshotBlock[id] == 0) return ProposalState.Unopened;

        // If already queued, TTL no longer applies.
        if (queuedAt[id] != 0) {
            if (block.timestamp < queuedAt[id] + timelockDelay) {
                return ProposalState.Queued;
            }
            // timelock elapsed → continue to gates (ready-to-execute check)
        } else if (proposalTTL != 0) {
            uint64 t0 = createdAt[id];
            if (t0 != 0 && block.timestamp > t0 + proposalTTL) {
                return ProposalState.Expired;
            }
        }

        // Evaluate gates
        uint256 ts = supplySnapshot[id];
        if (ts == 0) return ProposalState.Active; // unusual; treat as active

        Tally memory t = tallies[id];
        uint256 totalCast = t.forVotes + t.againstVotes + t.abstainVotes;

        if (quorumAbsolute != 0 && totalCast < quorumAbsolute) return ProposalState.Active;
        if (quorumBps != 0 && totalCast < mulDiv(uint256(quorumBps), ts, 10000)) {
            return ProposalState.Active;
        }

        if (minYesVotesAbsolute != 0 && t.forVotes < minYesVotesAbsolute) {
            return ProposalState.Defeated;
        }
        if (t.forVotes <= t.againstVotes) return ProposalState.Defeated;

        return ProposalState.Succeeded;
    }

    /// @notice Queue a passing proposal (sets timelock countdown). If no timelock, this is a no-op.
    function queue(bytes32 id) public {
        if (state(id) != ProposalState.Succeeded) revert NotApprover();
        if (timelockDelay == 0) return;
        if (queuedAt[id] == 0) {
            queuedAt[id] = uint64(block.timestamp);
            emit Queued(id, queuedAt[id]);
        }
    }

    /// @notice Execute when the proposal is ready (handles immediate or timelocked).
    function executeByVotes(
        uint8 op, // 0 = call, 1 = delegatecall
        address to,
        uint256 value,
        bytes calldata data,
        bytes32 nonce
    ) public payable nonReentrant returns (bool ok, bytes memory retData) {
        bytes32 id = _intentHash(op, to, value, data, nonce);

        // Keep explicit AlreadyExecuted error semantics.
        if (executed[id]) revert AlreadyExecuted();

        ProposalState st = state(id);

        // Only Succeeded or Queued proposals are allowed through.
        if (st != ProposalState.Succeeded && st != ProposalState.Queued) {
            if (st == ProposalState.Expired) revert NotOk();
            revert NotApprover(); // also covers Unopened / Active / Defeated
        }

        if (timelockDelay != 0) {
            if (queuedAt[id] == 0) {
                // First call → queue & return, like before.
                queuedAt[id] = uint64(block.timestamp);
                emit Queued(id, queuedAt[id]);
                return (true, "");
            }
            uint64 untilWhen = queuedAt[id] + timelockDelay;
            if (block.timestamp < untilWhen) revert Timelocked(untilWhen);
        }

        executed[id] = true;

        (ok, retData) = _execute(op, to, value, data);

        // Futarchy: YES (FOR) side wins upon success
        _resolveFutarchyYes(id);

        emit Executed(id, msg.sender, op, to, value);
    }

    /*//////////////////////////////////////////////////////////////
                             FUTARCHY RESOLUTION
    //////////////////////////////////////////////////////////////*/
    function resolveFutarchyNo(bytes32 id) public {
        FutarchyConfig storage F = futarchy[id];
        if (!F.enabled || F.resolved || executed[id]) revert NotOk();
        if (proposalTTL == 0) revert NotOk();
        uint64 t0 = createdAt[id];
        if (t0 == 0) revert NotOk();
        if (block.timestamp <= t0 + proposalTTL) revert NotOk();

        uint256 idNo = _receiptId(id, 0);
        uint256 winSupply = totalSupply[idNo];
        if (winSupply == 0 || F.pool == 0) {
            F.resolved = true;
            F.winner = 0;
            emit FutarchyResolved(id, 0, F.pool, winSupply, 0);
            return;
        }

        F.finalWinningSupply = winSupply;
        F.payoutPerUnit = F.pool / winSupply;
        F.resolved = true;
        F.winner = 0;
        emit FutarchyResolved(id, 0, F.pool, winSupply, F.payoutPerUnit);
    }

    function cashOutFutarchy(bytes32 id, uint256 amount)
        public
        nonReentrant
        returns (uint256 payout)
    {
        FutarchyConfig storage F = futarchy[id];
        if (!F.enabled || !F.resolved) revert NotOk();

        uint8 winner = F.winner; // 1 or 0
        uint256 rid = _receiptId(id, winner);

        _burn6909(msg.sender, rid, amount);

        payout = amount * F.payoutPerUnit;
        if (payout == 0) {
            emit FutarchyClaimed(id, msg.sender, amount, 0);
            return 0;
        }

        if (F.rewardToken == address(0)) {
            (bool sendOk,) = payable(msg.sender).call{value: payout}("");
            if (!sendOk) revert NotOk();
        } else {
            _safeTransfer(F.rewardToken, msg.sender, payout);
        }
        emit FutarchyClaimed(id, msg.sender, amount, payout);
    }

    function _resolveFutarchyYes(bytes32 id) internal {
        FutarchyConfig storage F = futarchy[id];
        if (!F.enabled || F.resolved) return;
        uint256 idYes = _receiptId(id, 1);
        uint256 winSupply = totalSupply[idYes];
        if (winSupply == 0 || F.pool == 0) {
            F.resolved = true;
            F.winner = 1;
            emit FutarchyResolved(id, 1, F.pool, winSupply, 0);
            return;
        }
        F.finalWinningSupply = winSupply;
        F.payoutPerUnit = F.pool / winSupply;
        F.resolved = true;
        F.winner = 1;
        emit FutarchyResolved(id, 1, F.pool, winSupply, F.payoutPerUnit);
    }

    /*//////////////////////////////////////////////////////////////
                                  PERMITS
    //////////////////////////////////////////////////////////////*/
    function setUse6909ForPermits(bool on) public payable onlySelf {
        use6909ForPermits = on;
        emit Use6909ForPermitsSet(on);
    }

    function setPermit(
        uint8 op,
        address to,
        uint256 value,
        bytes calldata data,
        bytes32 nonce,
        uint256 count,
        bool replaceCount
    ) public payable onlySelf {
        bytes32 id = _intentHash(op, to, value, data, nonce);

        uint256 old = permits[id];

        if (replaceCount) {
            // Hard set (including to MAX).
            permits[id] = count;
        } else {
            // Additive update with saturation and no-op if already MAX.
            if (old == type(uint256).max) {
                // already unlimited → ignore additive updates
            } else if (count == type(uint256).max) {
                // upgrade to MAX
                permits[id] = type(uint256).max;
            } else {
                unchecked {
                    uint256 tmp = old + count;
                    // saturate to MAX on wrap
                    if (tmp < old) tmp = type(uint256).max;
                    permits[id] = tmp;
                }
            }
        }

        emit PermitSet(id, permits[id], replaceCount);

        if (use6909ForPermits) {
            uint256 tokenId = uint256(id);
            uint256 cur = totalSupply[tokenId];

            if (replaceCount) {
                // Mirror replace: burn old mirror; only mint finite counts.
                if (cur > 0) _burn6909(address(this), tokenId, cur);
                if (count > 0 && count != type(uint256).max) {
                    _mint6909(address(this), tokenId, count);
                }
            } else {
                // Mirror add: only when BOTH old and new are finite.
                if (count > 0 && old != type(uint256).max && permits[id] != type(uint256).max) {
                    _mint6909(address(this), tokenId, count);
                }
            }
        }
    }

    /// @notice Spend a permit to execute without votes.
    function permitExecute(uint8 op, address to, uint256 value, bytes calldata data, bytes32 nonce)
        public
        payable
        nonReentrant
        returns (bool ok, bytes memory retData)
    {
        bytes32 id = _intentHash(op, to, value, data, nonce);
        uint256 p = permits[id];
        if (p == 0) revert NotApprover();

        if (!executed[id]) executed[id] = true;
        if (p != type(uint256).max) {
            permits[id] = p - 1;
            if (use6909ForPermits) _burn6909(address(this), uint256(id), 1);
        }

        (ok, retData) = _execute(op, to, value, data);

        // settle YES if futarchy was enabled for this intent hash
        _resolveFutarchyYes(id);

        emit PermitSpent(id, msg.sender, op, to, value);
    }

    /*//////////////////////////////////////////////////////////////
                           ALLOWANCES / PULL
    //////////////////////////////////////////////////////////////*/
    function setAllowanceTo(address token, address to, uint256 amount) public payable onlySelf {
        allowance[token][to] = amount;
    }

    function claimAllowance(address token, uint256 amount) public nonReentrant {
        allowance[token][msg.sender] -= amount;
        if (token == address(0)) {
            (bool ok,) = payable(msg.sender).call{value: amount}("");
            if (!ok) revert NotOk();
            return;
        }
        _safeTransfer(token, msg.sender, amount);
    }

    function pull(address token, address from, uint256 amount) public payable onlySelf {
        if (token == address(0)) revert NotOk(); // ERC20 only
        _safeTransferFrom(token, from, address(this), amount);
    }

    /*//////////////////////////////////////////////////////////////
                              SALES (ETH / ERC20)
    //////////////////////////////////////////////////////////////*/
    function setSale(
        address payToken,
        uint256 pricePerShare,
        uint256 cap,
        bool minting,
        bool active
    ) public payable onlySelf {
        sales[payToken] = Sale({
            pricePerShare: pricePerShare, cap: cap, minting: minting, active: active
        });
        emit SaleUpdated(payToken, pricePerShare, cap, minting, active);
    }

    function buyShares(address payToken, uint256 shareAmount, uint256 maxPay)
        public
        payable
        nonReentrant
    {
        Sale memory s = sales[payToken];
        if (!s.active) revert NotApprover();

        if (s.cap != 0 && shareAmount > s.cap) revert NotOk();
        uint256 cost = shareAmount * s.pricePerShare;
        if (shareAmount != 0 && cost / shareAmount != s.pricePerShare) revert NotOk(); // overflow guard

        // EFFECTS (CEI)
        if (s.cap != 0) sales[payToken].cap = s.cap - shareAmount;

        // Pull funds
        if (payToken == address(0)) {
            if (msg.value > maxPay) revert NotOk();
            if (msg.value != cost) revert NotOk();
        } else {
            if (msg.value != 0) revert NotOk();
            if (maxPay != 0 && cost > maxPay) revert NotOk();
            _safeTransferFrom(payToken, msg.sender, address(this), cost);
        }

        // Issue shares
        if (s.minting) {
            shares.mintFromMolochMajeur(msg.sender, shareAmount);
        } else {
            shares.transfer(msg.sender, shareAmount); // SAW must hold enough
        }

        emit SharesPurchased(msg.sender, payToken, shareAmount, cost);
    }

    /*//////////////////////////////////////////////////////////////
                               RAGE-QUIT
    //////////////////////////////////////////////////////////////*/
    function rageQuit(address[] calldata tokens) public nonReentrant {
        if (!ragequittable) revert NotApprover();
        uint256 amt = shares.balanceOf(msg.sender);
        if (amt == 0) revert NotOk();

        uint256 ts = shares.totalSupply();
        shares.burnFromMolochMajeur(msg.sender, amt);

        address prev = address(0);
        for (uint256 i = 0; i < tokens.length; ++i) {
            address tk = tokens[i];
            if (i != 0 && tk <= prev) revert NotOk();
            prev = tk;

            uint256 pool = (tk == address(0)) ? address(this).balance : _erc20Balance(tk);
            uint256 due = mulDiv(pool, amt, ts);
            if (due != 0) {
                if (tk == address(0)) {
                    (bool ok,) = payable(msg.sender).call{value: due}("");
                    if (!ok) revert NotOk();
                } else {
                    _safeTransfer(tk, msg.sender, due);
                }
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                        SBT-GATED CHAT
    //////////////////////////////////////////////////////////////*/
    function getMessageCount() public view returns (uint256) {
        return messages.length;
    }

    function chat(string calldata text) public payable {
        // Only badge holders (top-256) can post
        if (badge.balanceOf(msg.sender) == 0) revert NotApprover();
        messages.push(text);
        emit Message(msg.sender, messages.length - 1, text);
    }

    /*//////////////////////////////////////////////////////////////
                             GOV HELPERS (SELF)
    //////////////////////////////////////////////////////////////*/
    function setQuorumBps(uint16 bps) public payable onlySelf {
        quorumBps = bps;
    }

    function setMinYesVotesAbsolute(uint256 v) public payable onlySelf {
        minYesVotesAbsolute = v;
    }

    function setQuorumAbsolute(uint256 v) public payable onlySelf {
        quorumAbsolute = v;
    }

    function setProposalTTL(uint64 s) public payable onlySelf {
        proposalTTL = s;
    }

    function setTimelockDelay(uint64 s) public payable onlySelf {
        timelockDelay = s;
    }

    function setRagequittable(bool on) public payable onlySelf {
        ragequittable = on;
    }

    function setTransfersLocked(bool on) public payable onlySelf {
        transfersLocked = on;
    }

    /// @notice Governance "bump" to invalidate pre-bump proposal hashes.
    function bumpConfig() public payable onlySelf {
        unchecked {
            ++config;
        }
    }

    /*//////////////////////////////////////////////////////////////
                          SHARES HOOK (TOP-256 + SBT)
    //////////////////////////////////////////////////////////////*/
    address[256] public topHolders;
    mapping(address => uint16) public topPos;

    /// @notice Slot index 1..256 if in top set, else 0 (not strictly sorted by balance).
    function rankOf(address a) public view returns (uint256) {
        return topPos[a];
    }

    function onSharesChanged(address a) public {
        if (msg.sender != address(shares)) revert NotOwner();
        _onSharesChanged(a);
    }

    function _onSharesChanged(address a) internal {
        uint256 bal = shares.balanceOf(a);
        uint16 pos = topPos[a];

        // If holder has no shares, ensure they are not in the top set and burn badge.
        if (bal == 0) {
            if (pos != 0) {
                topHolders[pos - 1] = address(0);
                topPos[a] = 0;
            }
            if (badge.balanceOf(a) != 0) badge.burn(a);
            return;
        }

        // Already in top set: nothing else to do (we only track membership, not order).
        if (pos != 0) return;

        // Try to insert into any free slot first.
        for (uint16 i = 0; i < 256; ++i) {
            if (topHolders[i] == address(0)) {
                topHolders[i] = a;
                topPos[a] = i + 1;
                if (badge.balanceOf(a) == 0) badge.mint(a);
                return;
            }
        }

        // No free slot: find the lowest-balance current top holder.
        uint16 minI;
        uint256 minBal = type(uint256).max;
        for (uint16 i = 0; i < 256; ++i) {
            address cur = topHolders[i];
            uint256 cbal = shares.balanceOf(cur);
            if (cbal < minBal) {
                minBal = cbal;
                minI = i;
            }
        }

        // Only replace if strictly larger than the current minimum.
        if (bal > minBal) {
            address evict = topHolders[minI];
            topHolders[minI] = a;
            topPos[a] = minI + 1;
            topPos[evict] = 0;

            if (badge.balanceOf(evict) != 0) badge.burn(evict);
            if (badge.balanceOf(a) == 0) badge.mint(a);
        }
    }

    /*//////////////////////////////////////////////////////////////
                             ERC6909 INTERNALS
    //////////////////////////////////////////////////////////////*/
    function _receiptId(bytes32 id, uint8 support) internal pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked("Moloch:receipt", id, support)));
    }

    function _mint6909(address to, uint256 id, uint256 amount) internal {
        totalSupply[id] += amount;
        balanceOf[to][id] += amount;
        emit Transfer(msg.sender, address(0), to, id, amount);
    }

    function _burn6909(address from, uint256 id, uint256 amount) internal {
        balanceOf[from][id] -= amount;
        totalSupply[id] -= amount;
        emit Transfer(msg.sender, from, address(0), id, amount);
    }

    /*//////////////////////////////////////////////////////////////
                              SVG / TOKEN URIs
    //////////////////////////////////////////////////////////////*/
    /// @notice On-chain JSON/SVG card for a proposal id, or routes to receiptURI for vote receipts.
    function tokenURI(uint256 id) public view returns (string memory) {
        // 1) If this id is a vote receipt, delegate to the full receipt renderer.
        if (receiptProposal[id] != bytes32(0)) return receiptURI(id);

        bytes32 h = bytes32(id);

        Tally memory t = tallies[h];
        bool touchedTallies = (t.forVotes | t.againstVotes | t.abstainVotes) != 0;
        bool opened = snapshotBlock[h] != 0 || createdAt[h] != 0;

        bool looksLikePermit = use6909ForPermits && !opened && !touchedTallies
            && (totalSupply[id] != 0 || permits[h] != 0);

        if (looksLikePermit) {
            // ----- Permit card -----
            string memory cnt = permits[h] == type(uint256).max ? "unlimited" : _u2s(permits[h]);

            string memory svgP = string.concat(
                "<svg xmlns='http://www.w3.org/2000/svg' width='520' height='200'>",
                "<rect width='100%' height='100%' fill='#111'/>",
                "<text x='18' y='38' font-family='Courier New, monospace' font-size='18' fill='#fff'>",
                orgName,
                " Permit</text>",
                "<text x='18' y='72' font-family='Courier New, monospace' font-size='12' fill='#fff'>id: ",
                _toHex(h),
                "</text>",
                "<text x='18' y='92' font-family='Courier New, monospace' font-size='12' fill='#fff'>mirror supply: ",
                _u2s(totalSupply[id]),
                "</text>",
                "<text x='18' y='112' font-family='Courier New, monospace' font-size='12' fill='#fff'>remaining: ",
                cnt,
                "</text>",
                "</svg>"
            );

            string memory jsonP = string.concat(
                '{"name":"Permit","description":"Intent/permit mirror (ERC6909)",',
                '"image":"',
                DataURI.svg(svgP),
                '"}'
            );

            return DataURI.json(jsonP);
        }

        // ----- Proposal card -----
        string memory stateStr;
        if (executed[h]) {
            stateStr = "executed";
        } else if (snapshotBlock[h] == 0) {
            stateStr = "unopened";
        } else if (proposalTTL != 0) {
            uint64 t0 = createdAt[h];
            if (t0 != 0 && block.timestamp > t0 + proposalTTL) {
                stateStr = "expired";
            } else {
                stateStr = "open";
            }
        } else {
            stateStr = "open";
        }

        string memory svg = string.concat(
            "<svg xmlns='http://www.w3.org/2000/svg' width='520' height='240'>",
            "<rect width='100%' height='100%' fill='#111'/>",
            "<text x='18' y='36' font-family='Courier New, monospace' font-size='18' fill='#fff'>",
            orgName,
            " Proposal</text>",
            "<text x='18' y='66' font-family='Courier New, monospace' font-size='12' fill='#fff'>id: ",
            _toHex(h),
            "</text>",
            "<text x='18' y='86' font-family='Courier New, monospace' font-size='12' fill='#fff'>snapshot: ",
            _u2s(snapshotBlock[h]),
            " (supply ",
            _u2s(supplySnapshot[h]),
            ")</text>",
            "<text x='18' y='106' font-family='Courier New, monospace' font-size='12' fill='#fff'>for: ",
            _u2s(t.forVotes),
            "  against: ",
            _u2s(t.againstVotes),
            "  abstain: ",
            _u2s(t.abstainVotes),
            "</text>",
            "<text x='18' y='126' font-family='Courier New, monospace' font-size='12' fill='#fff'>state: ",
            stateStr,
            "</text>",
            "</svg>"
        );

        string memory json = string.concat(
            '{"name":"Proposal","description":"Snapshot-weighted proposal",',
            '"image":"',
            DataURI.svg(svg),
            '"}'
        );

        return DataURI.json(json);
    }

    /// @notice On-chain JSON/SVG for a vote receipt id (ERC-6909).
    function receiptURI(uint256 id) public view returns (string memory) {
        uint8 s = receiptSupport[id]; // 0 = NO, 1 = YES, 2 = ABSTAIN
        bytes32 h = receiptProposal[id]; // proposal hash this receipt belongs to
        FutarchyConfig memory F = futarchy[h];

        string memory stance = s == 1 ? "YES" : s == 0 ? "NO" : "ABSTAIN";

        string memory status;
        if (!F.enabled) {
            status = "plain";
        } else if (!F.resolved) {
            status = "open";
        } else {
            status = (F.winner == s) ? "winner" : "loser";
        }

        string memory svg = string.concat(
            "<svg xmlns='http://www.w3.org/2000/svg' width='520' height='220'>",
            "<rect width='100%' height='100%' fill='#111'/>",
            "<text x='18' y='38' font-family='Courier New, monospace' font-size='18' fill='#fff'>",
            orgName,
            " Vote Receipt</text>",
            "<text x='18' y='72' font-family='Courier New, monospace' font-size='12' fill='#fff'>proposal</text>",
            "<text x='18' y='88' font-family='Courier New, monospace' font-size='12' fill='#fff'>",
            _toHex(h),
            "</text>",
            "<text x='18' y='112' font-family='Courier New, monospace' font-size='12' fill='#fff'>stance: ",
            stance,
            "</text>",
            "<text x='18' y='132' font-family='Courier New, monospace' font-size='12' fill='#fff'>status: ",
            status,
            "</text>",
            "<text x='18' y='152' font-family='Courier New, monospace' font-size='12' fill='#fff'>receipt supply: ",
            _u2s(totalSupply[id]),
            "</text>",
            (F.enabled
                    ? string.concat(
                        "<text x='18' y='172' font-family='Courier New, monospace' font-size='12' fill='#fff'>pool: ",
                        _u2s(F.pool),
                        (F.rewardToken == address(0) ? " wei" : " units"),
                        "</text>"
                    )
                    : ""),
            (F.resolved
                    ? string.concat(
                        "<text x='18' y='192' font-family='Courier New, monospace' font-size='12' fill='#fff'>payout/unit: ",
                        _u2s(F.payoutPerUnit),
                        "</text>"
                    )
                    : ""),
            "</svg>"
        );

        string memory json = string.concat(
            '{"name":"Receipt","description":"SBT-like vote receipt; burn to cash out if winning",',
            '"image":"',
            DataURI.svg(svg),
            '"}'
        );

        return DataURI.json(json);
    }

    // Cheap hex for bytes32: "0x" + 64 hex chars.
    function _toHex(bytes32 data) internal pure returns (string memory) {
        bytes16 HEX = 0x30313233343536373839616263646566; // "0123456789abcdef"
        bytes memory str = new bytes(66);
        str[0] = "0";
        str[1] = "x";
        for (uint256 i; i < 32; ++i) {
            uint8 b = uint8(data[i]);
            str[2 + 2 * i] = bytes1(HEX[b >> 4]);
            str[3 + 2 * i] = bytes1(HEX[b & 0x0f]);
        }
        return string(str);
    }

    /*//////////////////////////////////////////////////////////////
                             RECEIVE / ERCs
    //////////////////////////////////////////////////////////////*/
    receive() external payable {}

    function onERC721Received(address, address, uint256, bytes calldata)
        public
        pure
        returns (bytes4)
    {
        return this.onERC721Received.selector;
    }

    function onERC1155Received(address, address, uint256, uint256, bytes calldata)
        public
        pure
        returns (bytes4)
    {
        return this.onERC1155Received.selector;
    }

    /*//////////////////////////////////////////////////////////////
                               INTERNALS
    //////////////////////////////////////////////////////////////*/
    /// @dev Shared low-level executor for call / delegatecall.
    function _execute(uint8 op, address to, uint256 value, bytes calldata data)
        internal
        returns (bool ok, bytes memory retData)
    {
        if (op == 0) {
            (ok, retData) = to.call{value: value}(data);
        } else {
            (ok, retData) = to.delegatecall(data);
        }
        if (!ok) revert NotOk();
    }

    function _intentHash(uint8 op, address to, uint256 value, bytes calldata data, bytes32 nonce)
        internal
        view
        returns (bytes32)
    {
        return keccak256(abi.encode(address(this), op, to, value, keccak256(data), nonce, config));
    }

    function _erc20Balance(address token) internal view returns (uint256 bal) {
        (bool ok, bytes memory ret) =
            token.staticcall(abi.encodeWithSignature("balanceOf(address)", address(this)));
        if (ok && ret.length >= 32) bal = abi.decode(ret, (uint256));
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        (bool ok, bytes memory ret) =
            token.call(abi.encodeWithSelector(IToken.transfer.selector, to, amount));
        if (!(ok && (ret.length == 0 || abi.decode(ret, (bool))))) revert NotOk();
    }

    function _safeTransferFrom(address token, address from, address to, uint256 amount) internal {
        (bool ok, bytes memory ret) =
            token.call(abi.encodeWithSelector(IToken.transferFrom.selector, from, to, amount));
        if (!(ok && (ret.length == 0 || abi.decode(ret, (bool))))) revert NotOk();
    }

    function _u2s(uint256 x) internal pure returns (string memory) {
        if (x == 0) return "0";
        uint256 temp = x;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (x != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + (x % 10)));
            x /= 10;
        }
        return string(buffer);
    }

    /*//////////////////////////////////////////////////////////////
                            REENTRANCY GUARD
    //////////////////////////////////////////////////////////////*/
    /*──────── reentrancy ─*/
    error Reentrancy();

    uint256 constant REENTRANCY_GUARD_SLOT = 0x929eee149b4bd21268;

    modifier nonReentrant() {
        assembly ("memory-safe") {
            if tload(REENTRANCY_GUARD_SLOT) {
                mstore(0x00, 0xab143c06)
                revert(0x1c, 0x04)
            }
            tstore(REENTRANCY_GUARD_SLOT, address())
        }
        _;
        assembly ("memory-safe") {
            tstore(REENTRANCY_GUARD_SLOT, 0)
        }
    }
}

error Overflow();

/// @dev Casts `x` to a uint32. Reverts on overflow.
function toUint32(uint256 x) pure returns (uint32) {
    if (x >= 1 << 32) _revertOverflow();
    return uint32(x);
}

/// @dev Casts `x` to a uint224. Reverts on overflow.
function toUint224(uint256 x) pure returns (uint224) {
    if (x >= 1 << 224) _revertOverflow();
    return uint224(x);
}

function _revertOverflow() pure {
    /// @solidity memory-safe-assembly
    assembly {
        // Store the function selector of `Overflow()`.
        mstore(0x00, 0x35278d12)
        // Revert with (offset, size).
        revert(0x1c, 0x04)
    }
}

error MulDivFailed();

/// @dev Returns `floor(x * y / d)`.
/// Reverts if `x * y` overflows, or `d` is zero.
function mulDiv(uint256 x, uint256 y, uint256 d) pure returns (uint256 z) {
    /// @solidity memory-safe-assembly
    assembly {
        z := mul(x, y)
        // Equivalent to `require(d != 0 && (y == 0 || x <= type(uint256).max / y))`.
        if iszero(mul(or(iszero(x), eq(div(z, x), y)), d)) {
            mstore(0x00, 0xad251c27) // `MulDivFailed()`.
            revert(0x1c, 0x04)
        }
        z := div(z, d)
    }
}

library DataURI {
    function json(string memory raw) internal pure returns (string memory) {
        return string.concat("data:application/json;base64,", Base64.encode(bytes(raw)));
    }

    function svg(string memory raw) internal pure returns (string memory) {
        return string.concat("data:image/svg+xml;base64,", Base64.encode(bytes(raw)));
    }
}

/// @notice Library to encode strings in Base64.
/// @author Solady (https://github.com/vectorized/solady/blob/main/src/utils/Base64.sol)
/// @author Modified from Solmate (https://github.com/transmissions11/solmate/blob/main/src/utils/Base64.sol)
/// @author Modified from (https://github.com/Brechtpd/base64/blob/main/base64.sol) by Brecht Devos - <brecht@loopring.org>.
library Base64 {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    ENCODING / DECODING                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Encodes `data` using the base64 encoding described in RFC 4648.
    /// See: https://datatracker.ietf.org/doc/html/rfc4648
    /// @param fileSafe  Whether to replace '+' with '-' and '/' with '_'.
    /// @param noPadding Whether to strip away the padding.
    function encode(bytes memory data, bool fileSafe, bool noPadding)
        internal
        pure
        returns (string memory result)
    {
        /// @solidity memory-safe-assembly
        assembly {
            let dataLength := mload(data)

            if dataLength {
                // Multiply by 4/3 rounded up.
                // The `shl(2, ...)` is equivalent to multiplying by 4.
                let encodedLength := shl(2, div(add(dataLength, 2), 3))

                // Set `result` to point to the start of the free memory.
                result := mload(0x40)

                // Store the table into the scratch space.
                // Offsetted by -1 byte so that the `mload` will load the character.
                // We will rewrite the free memory pointer at `0x40` later with
                // the allocated size.
                // The magic constant 0x0670 will turn "-_" into "+/".
                mstore(0x1f, "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdef")
                mstore(0x3f, xor("ghijklmnopqrstuvwxyz0123456789-_", mul(iszero(fileSafe), 0x0670)))

                // Skip the first slot, which stores the length.
                let ptr := add(result, 0x20)
                let end := add(ptr, encodedLength)

                let dataEnd := add(add(0x20, data), dataLength)
                let dataEndValue := mload(dataEnd) // Cache the value at the `dataEnd` slot.
                mstore(dataEnd, 0x00) // Zeroize the `dataEnd` slot to clear dirty bits.

                // Run over the input, 3 bytes at a time.
                for {} 1 {} {
                    data := add(data, 3) // Advance 3 bytes.
                    let input := mload(data)

                    // Write 4 bytes. Optimized for fewer stack operations.
                    mstore8(0, mload(and(shr(18, input), 0x3F)))
                    mstore8(1, mload(and(shr(12, input), 0x3F)))
                    mstore8(2, mload(and(shr(6, input), 0x3F)))
                    mstore8(3, mload(and(input, 0x3F)))
                    mstore(ptr, mload(0x00))

                    ptr := add(ptr, 4) // Advance 4 bytes.
                    if iszero(lt(ptr, end)) { break }
                }
                mstore(dataEnd, dataEndValue) // Restore the cached value at `dataEnd`.
                mstore(0x40, add(end, 0x20)) // Allocate the memory.
                // Equivalent to `o = [0, 2, 1][dataLength % 3]`.
                let o := div(2, mod(dataLength, 3))
                // Offset `ptr` and pad with '='. We can simply write over the end.
                mstore(sub(ptr, o), shl(240, 0x3d3d))
                // Set `o` to zero if there is padding.
                o := mul(iszero(iszero(noPadding)), o)
                mstore(sub(ptr, o), 0) // Zeroize the slot after the string.
                mstore(result, sub(encodedLength, o)) // Store the length.
            }
        }
    }

    /// @dev Encodes `data` using the base64 encoding described in RFC 4648.
    /// Equivalent to `encode(data, false, false)`.
    function encode(bytes memory data) internal pure returns (string memory result) {
        result = encode(data, false, false);
    }

    /// @dev Encodes `data` using the base64 encoding described in RFC 4648.
    /// Equivalent to `encode(data, fileSafe, false)`.
    function encode(bytes memory data, bool fileSafe) internal pure returns (string memory result) {
        result = encode(data, fileSafe, false);
    }

    /// @dev Decodes base64 encoded `data`.
    ///
    /// Supports:
    /// - RFC 4648 (both standard and file-safe mode).
    /// - RFC 3501 (63: ',').
    ///
    /// Does not support:
    /// - Line breaks.
    ///
    /// Note: For performance reasons,
    /// this function will NOT revert on invalid `data` inputs.
    /// Outputs for invalid inputs will simply be undefined behaviour.
    /// It is the user's responsibility to ensure that the `data`
    /// is a valid base64 encoded string.
    function decode(string memory data) internal pure returns (bytes memory result) {
        /// @solidity memory-safe-assembly
        assembly {
            let dataLength := mload(data)

            if dataLength {
                let decodedLength := mul(shr(2, dataLength), 3)

                for {} 1 {} {
                    // If padded.
                    if iszero(and(dataLength, 3)) {
                        let t := xor(mload(add(data, dataLength)), 0x3d3d)
                        // forgefmt: disable-next-item
                        decodedLength := sub(
                            decodedLength,
                            add(iszero(byte(30, t)), iszero(byte(31, t)))
                        )
                        break
                    }
                    // If non-padded.
                    decodedLength := add(decodedLength, sub(and(dataLength, 3), 1))
                    break
                }
                result := mload(0x40)

                // Write the length of the bytes.
                mstore(result, decodedLength)

                // Skip the first slot, which stores the length.
                let ptr := add(result, 0x20)
                let end := add(ptr, decodedLength)

                // Load the table into the scratch space.
                // Constants are optimized for smaller bytecode with zero gas overhead.
                // `m` also doubles as the mask of the upper 6 bits.
                let m := 0xfc000000fc00686c7074787c8084888c9094989ca0a4a8acb0b4b8bcc0c4c8cc
                mstore(0x5b, m)
                mstore(0x3b, 0x04080c1014181c2024282c3034383c4044484c5054585c6064)
                mstore(0x1a, 0xf8fcf800fcd0d4d8dce0e4e8ecf0f4)

                for {} 1 {} {
                    // Read 4 bytes.
                    data := add(data, 4)
                    let input := mload(data)

                    // Write 3 bytes.
                    // forgefmt: disable-next-item
                    mstore(ptr, or(
                        and(m, mload(byte(28, input))),
                        shr(6, or(
                            and(m, mload(byte(29, input))),
                            shr(6, or(
                                and(m, mload(byte(30, input))),
                                shr(6, mload(byte(31, input)))
                            ))
                        ))
                    ))
                    ptr := add(ptr, 3)
                    if iszero(lt(ptr, end)) { break }
                }
                mstore(0x40, add(end, 0x20)) // Allocate the memory.
                mstore(end, 0) // Zeroize the slot after the bytes.
                mstore(0x60, 0) // Restore the zero slot.
            }
        }
    }
}

/*//////////////////////////////////////////////////////////////
                         MINIMAL EXTERNALS
//////////////////////////////////////////////////////////////*/
interface IToken {
    function transfer(address, uint256) external;
    function transferFrom(address, address, uint256) external;
}

/*//////////////////////////////////////////////////////////////
             ERC20 SHARES WITH LIGHTWEIGHT SNAPSHOTS/DELEGATION
//////////////////////////////////////////////////////////////*/
contract MolochShares {
    /* ERRORS */
    error Len();
    error Locked();

    /* ERC20 */
    event Approval(address indexed from, address indexed to, uint256 amount);
    event Transfer(address indexed from, address indexed to, uint256 amount);

    uint8 public constant decimals = 18;
    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    /// @notice The parent Moloch (SAW) contract.
    address payable public immutable saw;

    /* VOTES (ERC20Votes-like minimal) */
    event DelegateChanged(
        address indexed delegator, address indexed fromDelegate, address indexed toDelegate
    );
    event DelegateVotesChanged(
        address indexed delegate, uint256 previousBalance, uint256 newBalance
    );

    struct Checkpoint {
        uint32 fromBlock;
        uint224 votes;
    }

    mapping(address => address) internal _delegates; // delegator => primary delegate
    mapping(address => Checkpoint[]) internal _checkpoints; // delegate  => vote history
    Checkpoint[] internal _totalSupplyCheckpoints; // total supply history

    /* --------- Split (sharded) delegation (non-custodial) --------- */
    struct Split {
        address delegate;
        uint32 bps; // parts per 10_000
    }

    uint8 public constant MAX_SPLITS = 4;
    uint32 public constant BPS_DENOM = 10_000;

    // delegator => split config
    mapping(address => Split[]) internal _splits;

    event WeightedDelegationSet(address indexed delegator, address[] delegates, uint32[] bps);

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    constructor(address[] memory to, uint256[] memory amt, address sawAddr) payable {
        if (to.length != amt.length) revert Len();
        saw = payable(sawAddr);

        for (uint256 i = 0; i < to.length; ++i) {
            _mint(to[i], amt[i]); // balances + totalSupply + TS checkpoint
            _autoSelfDelegate(to[i]); // default to self on first sight
            _applyVotingDelta(to[i], int256(amt[i])); // route initial votes via split / primary
        }
    }

    /*//////////////////////////////////////////////////////////////
                           METADATA (FROM SAW)
    //////////////////////////////////////////////////////////////*/
    function name() public view returns (string memory) {
        return string.concat(MolochMajeur(saw).orgName(), " Shares");
    }

    function symbol() public view returns (string memory) {
        return MolochMajeur(saw).orgSymbol();
    }

    /*//////////////////////////////////////////////////////////////
                                  ERC20
    //////////////////////////////////////////////////////////////*/
    function approve(address to, uint256 amount) public returns (bool) {
        allowance[msg.sender][to] = amount;
        emit Approval(msg.sender, to, amount);
        return true;
    }

    function transfer(address to, uint256 amount) public returns (bool) {
        // Global transfer lock: only SAW can be src or dst while locked.
        if (MolochMajeur(saw).transfersLocked() && msg.sender != saw && to != saw) revert Locked();

        _moveTokens(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public returns (bool) {
        if (MolochMajeur(saw).transfersLocked() && from != saw && to != saw) revert Locked();

        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) {
            allowance[from][msg.sender] = allowed - amount;
        }

        _moveTokens(from, to, amount);
        return true;
    }

    /// @notice Mint new shares; callable only by the SAW (MolochMajeur).
    function mintFromMolochMajeur(address to, uint256 amount) public payable {
        require(msg.sender == saw, "SAW");
        _mint(to, amount);
        _autoSelfDelegate(to);
        _applyVotingDelta(to, int256(amount));
        MolochMajeur(saw).onSharesChanged(to);
    }

    /// @notice Burn shares; callable only by the SAW (MolochMajeur).
    function burnFromMolochMajeur(address from, uint256 amount) public payable {
        require(msg.sender == saw, "SAW");

        balanceOf[from] -= amount;
        unchecked {
            totalSupply -= amount;
        }
        emit Transfer(from, address(0), amount);

        _writeTotalSupplyCheckpoint();
        _autoSelfDelegate(from);
        _applyVotingDelta(from, -int256(amount));
        MolochMajeur(saw).onSharesChanged(from);
    }

    function _mint(address to, uint256 amount) internal {
        unchecked {
            totalSupply += amount;
            balanceOf[to] += amount;
        }
        emit Transfer(address(0), to, amount);
        _writeTotalSupplyCheckpoint();
        // votes / delegation handled by caller via _applyVotingDelta(...)
    }

    function _moveTokens(address from, address to, uint256 amount) internal {
        balanceOf[from] -= amount;
        unchecked {
            balanceOf[to] += amount;
        }
        emit Transfer(from, to, amount);

        _autoSelfDelegate(from);
        _autoSelfDelegate(to);

        _applyVotingDelta(from, -int256(amount));
        _applyVotingDelta(to, int256(amount));

        MolochMajeur(saw).onSharesChanged(from);
        MolochMajeur(saw).onSharesChanged(to);
    }

    /*//////////////////////////////////////////////////////////////
                                 VOTING
    //////////////////////////////////////////////////////////////*/
    function delegates(address account) public view returns (address) {
        address del = _delegates[account];
        return del == address(0) ? account : del; // default to self
    }

    function delegate(address delegatee) public {
        _delegate(msg.sender, delegatee);
    }

    function getVotes(address account) public view returns (uint256) {
        uint256 n = _checkpoints[account].length;
        return n == 0 ? 0 : _checkpoints[account][n - 1].votes;
    }

    function getPastVotes(address account, uint32 blockNumber) public view returns (uint256) {
        require(blockNumber < block.number, "bad block");
        return _checkpointsLookup(_checkpoints[account], blockNumber);
    }

    function getPastTotalSupply(uint32 blockNumber) public view returns (uint256) {
        require(blockNumber < block.number, "bad block");
        return _checkpointsLookup(_totalSupplyCheckpoints, blockNumber);
    }

    /*//////////////////////////////////////////////////////////////
                          SPLIT / WEIGHTED DELEGATION
    //////////////////////////////////////////////////////////////*/
    /// @notice Returns the effective split delegation of an account
    /// (defaults to 100% self if no splits set).
    function splitDelegationOf(address account)
        external
        view
        returns (address[] memory delegates_, uint32[] memory bps_)
    {
        return _currentDistribution(account);
    }

    function setSplitDelegation(address[] calldata delegates_, uint32[] calldata bps_) external {
        uint256 n = delegates_.length;
        require(n == bps_.length && n > 0 && n <= MAX_SPLITS, "split/len");

        uint256 sum;
        for (uint256 i = 0; i < n; ++i) {
            address d = delegates_[i];
            require(d != address(0), "split/zero");
            sum += bps_[i];

            // no duplicate delegates
            for (uint256 j = i + 1; j < n; ++j) {
                require(d != delegates_[j], "split/dupe");
            }
        }
        require(sum == BPS_DENOM, "split/sum");

        (address[] memory oldD, uint32[] memory oldB) = _currentDistribution(msg.sender);

        delete _splits[msg.sender];
        for (uint256 i = 0; i < n; ++i) {
            _splits[msg.sender].push(Split({delegate: delegates_[i], bps: bps_[i]}));
        }

        _repointVotesForHolder(msg.sender, oldD, oldB);

        emit WeightedDelegationSet(msg.sender, delegates_, bps_);
    }

    function clearSplitDelegation() external {
        if (_splits[msg.sender].length == 0) return;

        (address[] memory oldD, uint32[] memory oldB) = _currentDistribution(msg.sender);
        delete _splits[msg.sender];

        _repointVotesForHolder(msg.sender, oldD, oldB);

        // now just a single 100% delegate (self or custom primary)
        address[] memory d = _singleton(delegates(msg.sender));
        uint32[] memory b = _singletonBps();
        emit WeightedDelegationSet(msg.sender, d, b);
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL VOTING HELPERS
    //////////////////////////////////////////////////////////////*/
    function _delegate(address delegator, address delegatee) internal {
        address current = delegates(delegator);
        if (delegatee == address(0)) delegatee = delegator; // default to self

        // If unchanged and no splits, nothing to do.
        if (_splits[delegator].length == 0 && current == delegatee) return;

        (address[] memory oldD, uint32[] memory oldB) = _currentDistribution(delegator);

        delete _splits[delegator]; // switch to a single 100% delegate
        _delegates[delegator] = delegatee;

        emit DelegateChanged(delegator, current, delegatee);

        _repointVotesForHolder(delegator, oldD, oldB);
    }

    function _autoSelfDelegate(address account) internal {
        if (_delegates[account] == address(0)) {
            _delegates[account] = account;
            emit DelegateChanged(account, address(0), account);
            // checkpoints are updated only via _applyVotingDelta / _repointVotesForHolder
        }
    }

    /// @dev Returns the current split (or a single 100% primary delegate if unset).
    function _currentDistribution(address account)
        internal
        view
        returns (address[] memory delegates_, uint32[] memory bps_)
    {
        Split[] storage sp = _splits[account];
        if (sp.length == 0) {
            delegates_ = _singleton(delegates(account));
            bps_ = _singletonBps();
            return (delegates_, bps_);
        }

        uint256 n = sp.length;
        delegates_ = new address[](n);
        bps_ = new uint32[](n);
        for (uint256 i = 0; i < n; ++i) {
            delegates_[i] = sp[i].delegate;
            bps_[i] = sp[i].bps;
        }
    }

    /// @dev Apply +/- voting power change for an account according to its split.
    function _applyVotingDelta(address account, int256 delta) internal {
        if (delta == 0) return;

        (address[] memory D, uint32[] memory B) = _currentDistribution(account);

        uint256 abs = delta > 0 ? uint256(delta) : uint256(-delta);
        uint256 remaining = abs;

        for (uint256 i = 0; i < D.length; ++i) {
            uint256 part = (abs * B[i]) / BPS_DENOM;

            // give any rounding remainder to the last delegate
            if (i == D.length - 1) part = remaining;
            else remaining -= part;

            if (part == 0) continue;

            if (delta > 0) _moveVotingPower(address(0), D[i], part);
            else _moveVotingPower(D[i], address(0), part);
        }
    }

    /// @dev Re-route an existing holder's current voting power from `old` distribution to current one.
    function _repointVotesForHolder(address holder, address[] memory oldD, uint32[] memory oldB)
        internal
    {
        uint256 bal = balanceOf[holder];
        if (bal == 0) return;

        (address[] memory newD, uint32[] memory newB) = _currentDistribution(holder);

        uint256 nOld = oldD.length;
        uint256 nNew = newD.length;

        // 1) Adjust delegates that existed before (oldD).
        for (uint256 i = 0; i < nOld; ++i) {
            address d = oldD[i];
            uint32 oldBps = oldB[i];
            uint32 newBps = 0;

            for (uint256 j = 0; j < nNew; ++j) {
                if (newD[j] == d) {
                    newBps = newB[j];
                    break;
                }
            }

            if (oldBps == newBps) continue;

            uint256 oldVotes = (bal * oldBps) / BPS_DENOM;
            uint256 newVotes = (bal * newBps) / BPS_DENOM;

            if (oldVotes > newVotes) {
                _moveVotingPower(d, address(0), oldVotes - newVotes);
            } else if (newVotes > oldVotes) {
                _moveVotingPower(address(0), d, newVotes - oldVotes);
            }
        }

        // 2) Add votes for delegates that are new-only (not in oldD).
        for (uint256 j = 0; j < nNew; ++j) {
            address dNew = newD[j];
            bool found;
            for (uint256 i = 0; i < nOld; ++i) {
                if (oldD[i] == dNew) {
                    found = true;
                    break;
                }
            }
            if (found) continue;

            uint256 newVotes = (bal * newB[j]) / BPS_DENOM;
            if (newVotes != 0) _moveVotingPower(address(0), dNew, newVotes);
        }
    }

    /* ---------- Core checkpoint machinery ---------- */

    function _moveVotingPower(address src, address dst, uint256 amount) internal {
        if (src == dst || amount == 0) return;

        if (src != address(0)) {
            (uint256 oldVal, uint256 newVal) = _writeDelta(_checkpoints[src], false, amount);
            emit DelegateVotesChanged(src, oldVal, newVal);
        }
        if (dst != address(0)) {
            (uint256 oldVal, uint256 newVal) = _writeDelta(_checkpoints[dst], true, amount);
            emit DelegateVotesChanged(dst, oldVal, newVal);
        }
    }

    function _writeDelta(Checkpoint[] storage ckpts, bool add, uint256 amount)
        internal
        returns (uint256 oldVal, uint256 newVal)
    {
        uint256 pos = ckpts.length;
        oldVal = pos == 0 ? 0 : ckpts[pos - 1].votes;
        newVal = add ? oldVal + amount : oldVal - amount;
        _writeCheckpoint(ckpts, oldVal, newVal);
    }

    function _writeCheckpoint(Checkpoint[] storage ckpts, uint256 oldVal, uint256 newVal) internal {
        if (oldVal == newVal) return;

        uint32 blk = toUint32(block.number);
        uint256 len = ckpts.length;

        if (len != 0) {
            Checkpoint storage last = ckpts[len - 1];

            // If we've already written this block, just update it.
            if (last.fromBlock == blk) {
                last.votes = toUint224(newVal);
                return;
            }

            // If the last checkpoint already has this value, skip pushing duplicate.
            if (last.votes == newVal) return;
        }

        ckpts.push(Checkpoint({fromBlock: blk, votes: toUint224(newVal)}));
    }

    function _writeTotalSupplyCheckpoint() internal {
        uint32 blk = toUint32(block.number);
        uint256 len = _totalSupplyCheckpoints.length;

        if (len != 0 && _totalSupplyCheckpoints[len - 1].fromBlock == blk) {
            _totalSupplyCheckpoints[len - 1].votes = toUint224(totalSupply);
        } else {
            _totalSupplyCheckpoints.push(
                Checkpoint({fromBlock: blk, votes: toUint224(totalSupply)})
            );
        }
    }

    function _checkpointsLookup(Checkpoint[] storage ckpts, uint32 blockNumber)
        internal
        view
        returns (uint256)
    {
        uint256 len = ckpts.length;
        if (len == 0) return 0;

        // Most recent
        if (ckpts[len - 1].fromBlock <= blockNumber) {
            return ckpts[len - 1].votes;
        }

        // Before first
        if (ckpts[0].fromBlock > blockNumber) {
            return 0;
        }

        uint256 low = 0;
        uint256 high = len - 1;
        while (high > low) {
            uint256 mid = (high + low + 1) / 2;
            if (ckpts[mid].fromBlock <= blockNumber) {
                low = mid;
            } else {
                high = mid - 1;
            }
        }
        return ckpts[low].votes;
    }

    /* ---------- tiny array helpers ---------- */
    function _singleton(address d) internal pure returns (address[] memory a) {
        a = new address[](1);
        a[0] = d;
    }

    function _singletonBps() internal pure returns (uint32[] memory a) {
        a = new uint32[](1);
        a[0] = BPS_DENOM;
    }
}

/*//////////////////////////////////////////////////////////////
   Non-transferable top-256 vanity badge (SBT). ID = holder address.
//////////////////////////////////////////////////////////////*/
contract MolochBadge {
    /* ERC721-ish */
    event Transfer(address indexed from, address indexed to, uint256 indexed id);

    // Parent Moloch (SAW)
    address payable public immutable mol;

    // Holder => count (0 or 1 in practice)
    mapping(address => uint256) public balanceOf;

    constructor() payable {
        mol = payable(msg.sender);
    }

    // dynamic metadata from SAW
    function name() public view returns (string memory) {
        return string.concat(MolochMajeur(mol).orgName(), " Badge");
    }

    function symbol() public view returns (string memory) {
        return string.concat(MolochMajeur(mol).orgSymbol(), "B");
    }

    function ownerOf(uint256 id) public view returns (address o) {
        o = address(uint160(id));
        require(balanceOf[o] != 0, "NOT_MINTED");
    }

    function tokenURI(uint256 id) public view returns (string memory) {
        address holder = address(uint160(id));
        MolochShares sh = MolochMajeur(mol).shares();

        uint256 bal = sh.balanceOf(holder);
        uint256 ts = sh.totalSupply();
        uint256 rk = MolochMajeur(mol).rankOf(holder); // 0 if not in top set

        string memory addr = _addrHex(holder);
        string memory pct = _percent(bal, ts);
        string memory rankStr = rk == 0 ? "-" : _u2s(rk);

        // On-chain SVG card
        string memory svg = string.concat(
            "<svg xmlns='http://www.w3.org/2000/svg' width='420' height='220'>",
            "<rect width='100%' height='100%' fill='#111'/>",
            "<text x='20' y='40'  font-family='Courier New, monospace' font-size='18' fill='#fff'>",
            name(),
            "</text>",
            "<text x='20' y='70'  font-family='Courier New, monospace' font-size='12' fill='#fff'>holder: ",
            addr,
            "</text>",
            "<text x='20' y='90'  font-family='Courier New, monospace' font-size='12' fill='#fff'>balance: ",
            _u2s(bal),
            "</text>",
            "<text x='20' y='110' font-family='Courier New, monospace' font-size='12' fill='#fff'>supply: ",
            _u2s(ts),
            "</text>",
            "<text x='20' y='130' font-family='Courier New, monospace' font-size='12' fill='#fff'>percent: ",
            pct,
            "</text>",
            "<text x='20' y='150' font-family='Courier New, monospace' font-size='12' fill='#fff'>rank: ",
            rankStr,
            "</text>",
            "</svg>"
        );

        string memory json = string.concat(
            '{"name":"Badge","description":"Top-256 holder badge (slot rank)",',
            '"image":"',
            DataURI.svg(svg),
            '"}'
        );

        return DataURI.json(json);
    }

    function transferFrom(address, address, uint256) public pure {
        revert("SBT");
    }

    function mint(address to) public {
        require(msg.sender == mol, "SAW");
        require(to != address(0) && balanceOf[to] == 0, "MINTED");

        balanceOf[to] = 1;
        emit Transfer(address(0), to, uint256(uint160(to)));
    }

    function burn(address from) public {
        require(msg.sender == mol, "SAW");
        require(balanceOf[from] != 0, "OWN");

        balanceOf[from] = 0;
        emit Transfer(from, address(0), uint256(uint160(from)));
    }

    /* utils */

    // 0x + 40 hex chars
    function _addrHex(address a) internal pure returns (string memory s) {
        bytes20 b = bytes20(a);
        bytes16 H = 0x30313233343536373839616263646566; // "0123456789abcdef"
        bytes memory out = new bytes(42);
        out[0] = "0";
        out[1] = "x";
        for (uint256 i = 0; i < 20; ++i) {
            uint8 v = uint8(b[i]);
            out[2 + 2 * i] = bytes1(H[v >> 4]);
            out[3 + 2 * i] = bytes1(H[v & 0x0f]);
        }
        s = string(out);
    }

    function _u2s(uint256 x) internal pure returns (string memory) {
        if (x == 0) return "0";
        uint256 temp = x;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (x != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + (x % 10)));
            x /= 10;
        }
        return string(buffer);
    }

    function _percent(uint256 a, uint256 b) internal pure returns (string memory) {
        if (b == 0) return "0.00%";
        uint256 p = a * 10000 / b; // basis points
        uint256 i = p / 100;
        uint256 d = p % 100;
        return string.concat(_u2s(i), ".", d < 10 ? "0" : "", _u2s(d), "%");
    }
}

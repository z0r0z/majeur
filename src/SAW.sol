// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title SAW — Snapshot-Weighted Multisig/DAO (no-custody), with ERC-6909 vote receipts, futarchy (optional),
 *         timelock, permits, allowances/pull, token sales, ragequit, and SBT-gated chat.
 *
 * Design goals:
 * - Works for 2/2 multisigs, 256-seat boards, and 100k-holder DAOs.
 * - No ERC20 custody for voting. Uses block-number snapshots (like OZ Governor/Votes).
 * - Simple pass rule: majority FOR, with dynamic quorum (BPS) and optional absolute floors.
 * - Optional timelock delay between "ready" and execution.
 * - ERC6909 receipts (non-transferable) minted on vote; can be burned for futarchy payouts if enabled.
 * - Minimal external deps. All code in one file, readable and auditable.
 */
contract SAW {
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
                              ORG / METADATA
    //////////////////////////////////////////////////////////////*/
    string public orgName;
    string public orgSymbol;

    /*//////////////////////////////////////////////////////////////
                           GOVERNANCE CONFIG
    //////////////////////////////////////////////////////////////*/
    // Dynamic quorum relative to snapshot supply (0 = disabled)
    uint16 public quorumBps;

    // Absolute minimum YES (FOR) votes required (0 = disabled)
    uint256 public minYesVotesAbsolute;

    // Optional absolute turnout (FOR + AGAINST + ABSTAIN) (0 = disabled)
    uint256 public quorumAbsolute;

    // Optional proposal expiry (seconds; 0 = no expiry)
    uint64 public proposalTTL;

    // Optional timelock delay before execution (seconds; 0 = no timelock)
    uint64 public timelockDelay;

    // Governance "bump" salt to invalidate prior proposal ids/permits
    uint64 public config;

    bool public ragequittable;
    bool public transfersLocked; // global Shares transfer lock

    /*//////////////////////////////////////////////////////////////
                      TOKENS: SHARES (ERC20) / BADGE (SBT)
    //////////////////////////////////////////////////////////////*/
    SAWShares public shares;
    SAWBadge public badge;

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
    // hasVoted[h][voter] = 0 = not, 1 = FOR, 2 = AGAINST, 3 = ABSTAIN
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
        external
        view
        returns (string memory)
    {
        return orgName;
    }

    function symbol(
        uint256 /*id*/
    )
        external
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
        shares = new SAWShares(initialHolders, initialAmounts, address(this));
        emit SharesDeployed(address(shares));
        badge = new SAWBadge();
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
    // Snapshot at a strictly *past* block so OZ checkpoints are valid.
    // Also record createdAt and (optionally) supplyAtSnapshot for UX.
    function openProposal(bytes32 id) public {
        if (snapshotBlock[id] != 0) return; // already opened

        // Foundry often opens your *first* proposal while chain is still at block 1.
        // Using (block.number - 1) avoids the “not yet determined” revert in OZ.
        uint32 snap = uint32(block.number > 0 ? block.number - 1 : 0);
        snapshotBlock[id] = snap;

        if (createdAt[id] == 0) {
            createdAt[id] = uint64(block.timestamp);
        }

        uint128 supply;
        if (snap == 0) {
            // genesis-fallback: there may be no checkpoint at block 0
            // so we record current totalSupply for UI purposes
            supply = uint128(shares.totalSupply());
        } else {
            supply = uint128(shares.getPastTotalSupply(snap));
        }
        supplySnapshot[id] = supply;

        emit Opened(id, snap, supply);
    }

    /// @notice Open & set futarchy settings (governance).
    function openFutarchy(bytes32 h, address rewardToken) public {
        if (msg.sender != address(this)) revert NotOwner();
        openProposal(h);
        FutarchyConfig storage F = futarchy[h];
        if (F.enabled) revert NotOk();
        F.enabled = true;
        F.rewardToken = rewardToken;
        emit FutarchyOpened(h, rewardToken);
    }

    function fundFutarchy(bytes32 h, uint256 amount) public payable {
        FutarchyConfig storage F = futarchy[h];
        if (!F.enabled || F.resolved) revert NotOk();
        if (F.rewardToken == address(0)) {
            if (msg.value != amount) revert NotOk();
            F.pool += amount;
        } else {
            if (msg.value != 0) revert NotOk();
            _safeTransferFrom(F.rewardToken, msg.sender, address(this), amount);
            F.pool += amount;
        }
        emit FutarchyFunded(h, msg.sender, amount);
    }

    /*//////////////////////////////////////////////////////////////
                              VOTING (SNAPSHOT)
    //////////////////////////////////////////////////////////////*/
    /// @notice support: 0 = AGAINST, 1 = FOR, 2 = ABSTAIN
    function castVote(bytes32 h, uint8 support) public {
        if (executed[h]) revert AlreadyExecuted();
        if (support > 2) revert NotOk();

        // Auto-open on first vote if unopened
        if (snapshotBlock[h] == 0) openProposal(h);

        // Optional expiry gating
        if (proposalTTL != 0) {
            uint64 t0 = createdAt[h];
            if (t0 == 0) revert NotOk();
            if (block.timestamp > t0 + proposalTTL) revert NotOk();
        }

        if (hasVoted[h][msg.sender] != 0) revert NotOk(); // one vote per address

        uint32 snap = uint32(snapshotBlock[h]);
        uint256 weight = (snap == 0)
            ? shares.getVotes(msg.sender)  // genesis fallback (no valid past block)
            : shares.getPastVotes(msg.sender, snap);

        if (weight == 0) revert NotOk();

        // Tally
        if (support == 1) tallies[h].forVotes += weight;
        else if (support == 0) tallies[h].againstVotes += weight;
        else tallies[h].abstainVotes += weight;

        hasVoted[h][msg.sender] = support + 1;

        // Mint ERC6909 receipt (non-transferable)
        uint256 rid = _receiptId(h, support);
        receiptSupport[rid] = support;
        receiptProposal[rid] = h;
        _mint6909(msg.sender, rid, weight);

        emit Voted(h, msg.sender, support, weight);
    }

    /*//////////////////////////////////////////////////////////////
                       PROPOSAL STATE / RULES / QUEUE+EXEC
    //////////////////////////////////////////////////////////////*/
    function state(bytes32 h) public view returns (ProposalState) {
        if (executed[h]) return ProposalState.Executed;
        if (snapshotBlock[h] == 0) return ProposalState.Unopened;

        // TTL check
        if (proposalTTL != 0) {
            uint64 t0 = createdAt[h];
            if (t0 != 0 && block.timestamp > t0 + proposalTTL) return ProposalState.Expired;
        }

        // If queued and still timelocked → Queued; if delay elapsed → Succeeded (ready)
        if (queuedAt[h] != 0) {
            if (block.timestamp < queuedAt[h] + timelockDelay) return ProposalState.Queued;
            // delay elapsed: consider it "Succeeded" (ready to execute)
        }

        // Evaluate gates
        uint256 ts = supplySnapshot[h];
        if (ts == 0) return ProposalState.Active; // unusual; treat as active

        Tally memory t = tallies[h];
        uint256 totalCast = t.forVotes + t.againstVotes + t.abstainVotes;

        if (quorumAbsolute != 0 && totalCast < quorumAbsolute) return ProposalState.Active;
        if (quorumBps != 0 && totalCast * 10000 < uint256(quorumBps) * ts) {
            return ProposalState.Active;
        }

        if (minYesVotesAbsolute != 0 && t.forVotes < minYesVotesAbsolute) {
            return ProposalState.Defeated;
        }
        if (t.forVotes <= t.againstVotes) return ProposalState.Defeated;

        return ProposalState.Succeeded;
    }

    /// @notice Queue a passing proposal (sets timelock countdown). If no timelock, this is a no-op.
    function queue(bytes32 h) public {
        if (state(h) != ProposalState.Succeeded) revert NotApprover();
        if (timelockDelay == 0) return;
        if (queuedAt[h] == 0) {
            queuedAt[h] = uint64(block.timestamp);
            emit Queued(h, queuedAt[h]);
        }
    }

    /// @notice Execute when the proposal is ready (handles immediate or timelocked).
    function executeByVotes(
        uint8 op, // 0 = call, 1 = delegatecall
        address to,
        uint256 value,
        bytes calldata data,
        bytes32 nonce
    ) public payable returns (bool ok, bytes memory retData) {
        bytes32 h = _intentHash(op, to, value, data, nonce);
        ProposalState st = state(h);

        if (st == ProposalState.Unopened || st == ProposalState.Active) revert NotApprover();
        if (st == ProposalState.Expired) revert NotOk();
        if (executed[h]) revert AlreadyExecuted();

        if (timelockDelay != 0) {
            if (queuedAt[h] == 0) {
                // First call → queue
                queuedAt[h] = uint64(block.timestamp);
                emit Queued(h, queuedAt[h]);
                return (true, "");
            }
            uint64 untilWhen = queuedAt[h] + timelockDelay;
            if (block.timestamp < untilWhen) revert Timelocked(untilWhen);
        }

        executed[h] = true;

        if (op == 0) (ok, retData) = to.call{value: value}(data);
        else (ok, retData) = to.delegatecall(data);
        if (!ok) revert NotOk();

        // Futarchy: YES (FOR) side wins upon success
        _resolveFutarchyYes(h);

        emit Executed(h, msg.sender, op, to, value);
    }

    /*//////////////////////////////////////////////////////////////
                             FUTARCHY RESOLUTION
    //////////////////////////////////////////////////////////////*/
    function resolveFutarchyNo(bytes32 h) public {
        FutarchyConfig storage F = futarchy[h];
        if (!F.enabled || F.resolved || executed[h]) revert NotOk();
        if (proposalTTL == 0) revert NotOk();
        uint64 t0 = createdAt[h];
        if (t0 == 0) revert NotOk();
        if (block.timestamp <= t0 + proposalTTL) revert NotOk();

        uint256 idNo = _receiptId(h, 0);
        uint256 winSupply = totalSupply[idNo];
        if (winSupply == 0 || F.pool == 0) {
            F.resolved = true;
            F.winner = 0;
            emit FutarchyResolved(h, 0, F.pool, winSupply, 0);
            return;
        }

        F.finalWinningSupply = winSupply;
        F.payoutPerUnit = F.pool / winSupply;
        F.resolved = true;
        F.winner = 0;
        emit FutarchyResolved(h, 0, F.pool, winSupply, F.payoutPerUnit);
    }

    function cashOutFutarchy(bytes32 h, uint256 amount) public returns (uint256 payout) {
        FutarchyConfig storage F = futarchy[h];
        if (!F.enabled || !F.resolved) revert NotOk();

        uint8 winner = F.winner; // 1 or 0
        uint256 rid = _receiptId(h, winner);

        _burn6909(msg.sender, rid, amount);

        payout = amount * F.payoutPerUnit;
        if (payout == 0) {
            emit FutarchyClaimed(h, msg.sender, amount, 0);
            return 0;
        }

        if (F.rewardToken == address(0)) {
            (bool sendOk,) = payable(msg.sender).call{value: payout}("");
            if (!sendOk) revert NotOk();
        } else {
            _safeTransfer(F.rewardToken, msg.sender, payout);
        }
        emit FutarchyClaimed(h, msg.sender, amount, payout);
    }

    function _resolveFutarchyYes(bytes32 h) internal {
        FutarchyConfig storage F = futarchy[h];
        if (!F.enabled || F.resolved) return;
        uint256 idYes = _receiptId(h, 1);
        uint256 winSupply = totalSupply[idYes];
        if (winSupply == 0 || F.pool == 0) {
            F.resolved = true;
            F.winner = 1;
            emit FutarchyResolved(h, 1, F.pool, winSupply, 0);
            return;
        }
        F.finalWinningSupply = winSupply;
        F.payoutPerUnit = F.pool / winSupply;
        F.resolved = true;
        F.winner = 1;
        emit FutarchyResolved(h, 1, F.pool, winSupply, F.payoutPerUnit);
    }

    /*//////////////////////////////////////////////////////////////
                                  PERMITS
    //////////////////////////////////////////////////////////////*/
    function setUse6909ForPermits(bool on) public {
        if (msg.sender != address(this)) revert NotOwner();
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
    ) public {
        if (msg.sender != address(this)) revert NotOwner();
        bytes32 h = _intentHash(op, to, value, data, nonce);

        uint256 old = permits[h];

        if (replaceCount) {
            // Hard set (including to MAX).
            permits[h] = count;
        } else {
            // Additive update with saturation and no-op if already MAX.
            if (old == type(uint256).max) {
                // already unlimited → ignore additive updates
            } else if (count == type(uint256).max) {
                // upgrade to MAX
                permits[h] = type(uint256).max;
            } else {
                unchecked {
                    uint256 tmp = old + count;
                    // saturate to MAX on wrap
                    if (tmp < old) tmp = type(uint256).max;
                    permits[h] = tmp;
                }
            }
        }

        emit PermitSet(h, permits[h], replaceCount);

        if (use6909ForPermits) {
            uint256 id = uint256(h);
            uint256 cur = totalSupply[id];

            if (replaceCount) {
                // Mirror replace: burn old mirror; only mint finite counts.
                if (cur > 0) _burn6909(address(this), id, cur);
                if (count > 0 && count != type(uint256).max) {
                    _mint6909(address(this), id, count);
                }
            } else {
                // Mirror add: only when BOTH old and new are finite.
                if (count > 0 && old != type(uint256).max && permits[h] != type(uint256).max) {
                    _mint6909(address(this), id, count);
                }
            }
        }
    }

    /// @notice Spend a permit to execute without votes.
    function permitExecute(uint8 op, address to, uint256 value, bytes calldata data, bytes32 nonce)
        public
        payable
        returns (bool ok, bytes memory retData)
    {
        bytes32 h = _intentHash(op, to, value, data, nonce);
        uint256 p = permits[h];
        if (p == 0) revert NotApprover();

        if (!executed[h]) executed[h] = true;
        if (p != type(uint256).max) {
            permits[h] = p - 1;
            if (use6909ForPermits) _burn6909(address(this), uint256(h), 1);
        }

        if (op == 0) (ok, retData) = to.call{value: value}(data);
        else (ok, retData) = to.delegatecall(data);
        if (!ok) revert NotOk();

        _resolveFutarchyYes(h); // <-- NEW: settle YES if futarchy was enabled for h

        emit PermitSpent(h, msg.sender, op, to, value);
    }

    /*//////////////////////////////////////////////////////////////
                           ALLOWANCES / PULL
    //////////////////////////////////////////////////////////////*/
    function setAllowanceTo(address token, address to, uint256 amount) public {
        if (msg.sender != address(this)) revert NotOwner();
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

    function pull(address token, address from, uint256 amount) public {
        if (msg.sender != address(this)) revert NotOwner();
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
    ) public {
        if (msg.sender != address(this)) revert NotOwner();
        sales[payToken] =
            Sale({pricePerShare: pricePerShare, cap: cap, minting: minting, active: active});
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
            if (msg.value != cost) revert NotOk();
        } else {
            if (maxPay != 0 && cost > maxPay) revert NotOk();
            _safeTransferFrom(payToken, msg.sender, address(this), cost);
        }

        // Issue shares
        if (s.minting) {
            shares.mintFromSAW(msg.sender, shareAmount);
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

        shares.burnFromSAW(msg.sender, amt); // updates top-256 + SBT

        for (uint256 i = 0; i < tokens.length; ++i) {
            address tk = tokens[i];
            if (tk == address(0)) {
                uint256 pool = address(this).balance;
                uint256 due = (pool * amt) / ts;
                if (due != 0) {
                    (bool ok,) = payable(msg.sender).call{value: due}("");
                    if (!ok) revert NotOk();
                }
            } else {
                uint256 pool = _erc20Balance(tk);
                uint256 due = (pool * amt) / ts;
                if (due != 0) _safeTransfer(tk, msg.sender, due);
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
    function setQuorumBps(uint16 bps) public {
        if (msg.sender != address(this)) revert NotOwner();
        quorumBps = bps;
    }

    function setMinYesVotesAbsolute(uint256 v) public {
        if (msg.sender != address(this)) revert NotOwner();
        minYesVotesAbsolute = v;
    }

    function setQuorumAbsolute(uint256 v) public {
        if (msg.sender != address(this)) revert NotOwner();
        quorumAbsolute = v;
    }

    function setProposalTTL(uint64 s) public {
        if (msg.sender != address(this)) revert NotOwner();
        proposalTTL = s;
    }

    function setTimelockDelay(uint64 s) public {
        if (msg.sender != address(this)) revert NotOwner();
        timelockDelay = s;
    }

    function setRagequittable(bool on) public {
        if (msg.sender != address(this)) revert NotOwner();
        ragequittable = on;
    }

    function setTransfersLocked(bool on) public {
        if (msg.sender != address(this)) revert NotOwner();
        transfersLocked = on;
    }

    /// @notice Governance "bump" to invalidate pre-bump proposal hashes.
    function bumpConfig() public {
        if (msg.sender != address(this)) revert NotOwner();
        unchecked {
            ++config;
        }
    }

    /*//////////////////////////////////////////////////////////////
                          SHARES HOOK (TOP-256 + SBT)
    //////////////////////////////////////////////////////////////*/
    address[256] public topHolders;
    uint16 public topCount; // number of filled slots
    mapping(address => uint16) public topPos; // 1..256; 0=not present

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
        bool inTop = (topPos[a] != 0);

        if (bal == 0) {
            _removeFromTop(a);
            if (badge.balanceOf(a) != 0) badge.burn(a);
            return;
        }
        if (inTop) return; // already in set

        if (topCount < 256) {
            _addToTop(a);
            if (badge.balanceOf(a) == 0) badge.mint(a);
        } else {
            // Replace current min if this holder surpasses it
            uint16 minI = 0;
            uint256 minBal = type(uint256).max;
            for (uint16 i = 0; i < 256; ++i) {
                address cur = topHolders[i];
                uint256 cbal = shares.balanceOf(cur);
                if (cbal < minBal) {
                    minBal = cbal;
                    minI = i;
                }
            }
            if (bal > minBal) {
                address evict = topHolders[minI];
                topHolders[minI] = a;
                topPos[a] = minI + 1;
                topPos[evict] = 0;

                // badges
                if (badge.balanceOf(evict) != 0) badge.burn(evict);
                if (badge.balanceOf(a) == 0) badge.mint(a);
            }
        }
    }

    function _addToTop(address a) internal {
        for (uint16 i = 0; i < 256; ++i) {
            if (topHolders[i] == address(0)) {
                topHolders[i] = a;
                topPos[a] = i + 1;
                topCount++;
                return;
            }
        }
    }

    function _removeFromTop(address a) internal {
        uint16 p = topPos[a];
        if (p == 0) return;
        topHolders[p - 1] = address(0);
        topPos[a] = 0;
        if (topCount > 0) topCount--;
    }

    /*//////////////////////////////////////////////////////////////
                             ERC6909 INTERNALS
    //////////////////////////////////////////////////////////////*/
    function _receiptId(bytes32 h, uint8 support) internal pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked("SAW:receipt", h, support)));
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
    /// @notice On-chain JSON/SVG card for an id. Heuristics:
    /// - If it's a 6909 receipt (receiptProposal[id] != 0) → Vote Receipt card.
    /// - Else if it's a known proposal (opened / has tallies / createdAt) → Proposal card.
    /// - Else if use6909ForPermits and id maps to a mirrored permit (supply or count) → Permit card.
    /// - Else → Proposal card (default).
    function tokenURI(uint256 id) public view returns (string memory) {
        // 1) If this id is a vote receipt, delegate to the full receipt renderer.
        if (receiptProposal[id] != bytes32(0)) {
            return receiptURI(id);
        }

        // 2) Otherwise, existing permit/proposal logic…
        bytes32 h = bytes32(id);

        Tally memory t = tallies[h];
        bool touchedTallies = (t.forVotes | t.againstVotes | t.abstainVotes) != 0;
        bool opened = snapshotBlock[h] != 0 || createdAt[h] != 0;

        bool looksLikePermit = use6909ForPermits && !opened && !touchedTallies
            && (totalSupply[id] != 0 || permits[h] != 0);

        if (looksLikePermit) {
            string memory idHex = _toHex(h);
            string memory supply = _u2s(totalSupply[id]);
            string memory cnt = permits[h] == type(uint256).max ? "unlimited" : _u2s(permits[h]);
            string memory svgP = string.concat(
                "<svg xmlns='http://www.w3.org/2000/svg' width='520' height='200'>",
                "<rect width='100%' height='100%' fill='#111'/>",
                "<text x='18' y='38' font-family='Courier New, monospace' font-size='18' fill='#fff'>",
                orgName,
                " Permit</text>",
                "<text x='18' y='72' font-family='Courier New, monospace' font-size='12' fill='#fff'>id: ",
                idHex,
                "</text>",
                "<text x='18' y='92' font-family='Courier New, monospace' font-size='12' fill='#fff'>mirror supply: ",
                supply,
                "</text>",
                "<text x='18' y='112' font-family='Courier New, monospace' font-size='12' fill='#fff'>remaining: ",
                cnt,
                "</text>",
                "</svg>"
            );
            return string.concat(
                "data:application/json;utf8,",
                "{\"name\":\"",
                orgName,
                " Permit\",",
                "\"description\":\"Intent/permit mirror (ERC6909)\",",
                "\"image\":\"data:image/svg+xml;utf8,",
                svgP,
                "\"}"
            );
        }

        // Proposal card (unchanged) ...
        string memory idHex2 = _toHex(h);
        string memory snapStr = _u2s(snapshotBlock[h]);
        string memory supplyStr = _u2s(supplySnapshot[h]);
        string memory forStr = _u2s(t.forVotes);
        string memory agStr = _u2s(t.againstVotes);
        string memory abStr = _u2s(t.abstainVotes);
        string memory stStr = _stateStringNoOpen(h);

        string memory svg = string.concat(
            "<svg xmlns='http://www.w3.org/2000/svg' width='520' height='240'>",
            "<rect width='100%' height='100%' fill='#111'/>",
            "<text x='18' y='36' font-family='Courier New, monospace' font-size='18' fill='#fff'>",
            orgName,
            " Proposal</text>",
            "<text x='18' y='66' font-family='Courier New, monospace' font-size='12' fill='#fff'>id: ",
            idHex2,
            "</text>",
            "<text x='18' y='86' font-family='Courier New, monospace' font-size='12' fill='#fff'>snapshot: ",
            snapStr,
            " (supply ",
            supplyStr,
            ")</text>",
            "<text x='18' y='106' font-family='Courier New, monospace' font-size='12' fill='#fff'>for: ",
            forStr,
            "  against: ",
            agStr,
            "  abstain: ",
            abStr,
            "</text>",
            "<text x='18' y='126' font-family='Courier New, monospace' font-size='12' fill='#fff'>state: ",
            stStr,
            "</text>",
            "</svg>"
        );

        return string.concat(
            "data:application/json;utf8,",
            "{\"name\":\"",
            orgName,
            " Proposal\",",
            "\"description\":\"Snapshot-weighted proposal\",",
            "\"image\":\"data:image/svg+xml;utf8,",
            svg,
            "\"}"
        );
    }

    /// @notice On-chain JSON/SVG for a vote receipt id (ERC-6909).
    function receiptURI(uint256 id) public view returns (string memory) {
        // Which side is this receipt for?
        uint8 s = receiptSupport[id]; // 0 = NO, 1 = YES, 2 = ABSTAIN
        bytes32 h = receiptProposal[id]; // proposal hash this receipt belongs to
        FutarchyConfig memory F = futarchy[h];

        string memory stance = (s == 1) ? "YES" : (s == 0) ? "NO" : "ABSTAIN";
        string memory status = (!F.enabled)
            ? "plain"
            : (!F.resolved) ? "open" : ((F.winner == s) ? "winner" : "loser");

        uint256 supply = totalSupply[id];

        string memory svg = string.concat(
            "<svg xmlns='http://www.w3.org/2000/svg' width='520' height='220'>",
            "<rect width='100%' height='100%' fill='#111'/>",
            "<text x='18' y='38' font-family='Courier New, monospace' font-size='18' fill='#fff'>",
            orgName,
            " Vote Receipt</text>",
            "<text x='18' y='72' font-family='Courier New, monospace' font-size='12' fill='#fff'>proposal: ",
            _toHex(h),
            "</text>",
            "<text x='18' y='92' font-family='Courier New, monospace' font-size='12' fill='#fff'>stance: ",
            stance,
            "</text>",
            "<text x='18' y='112' font-family='Courier New, monospace' font-size='12' fill='#fff'>status: ",
            status,
            "</text>",
            "<text x='18' y='132' font-family='Courier New, monospace' font-size='12' fill='#fff'>receipt supply: ",
            _u2s(supply),
            "</text>",
            (F.enabled
                    ? string.concat(
                        "<text x='18' y='152' font-family='Courier New, monospace' font-size='12' fill='#fff'>pool: ",
                        _u2s(F.pool),
                        (F.rewardToken == address(0) ? " wei" : " units"),
                        "</text>"
                    )
                    : ""),
            (F.resolved
                    ? string.concat(
                        "<text x='18' y='172' font-family='Courier New, monospace' font-size='12' fill='#fff'>payout/unit: ",
                        _u2s(F.payoutPerUnit),
                        "</text>"
                    )
                    : ""),
            "</svg>"
        );

        return string.concat(
            "data:application/json;utf8,",
            "{\"name\":\"",
            orgName,
            " ",
            stance,
            " Receipt\",",
            "\"description\":\"SBT-like vote receipt; burn to cash out if winning\",",
            "\"image\":\"data:image/svg+xml;utf8,",
            svg,
            "\"}"
        );
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

    // A view-only state string that NEVER writes.
    function _stateStringNoOpen(bytes32 h) internal view returns (string memory) {
        if (executed[h]) return "executed";
        if (snapshotBlock[h] == 0) return "unopened";
        // Optional TTL display only (no writes)
        if (proposalTTL != 0) {
            uint64 t0 = createdAt[h];
            if (t0 != 0 && block.timestamp > t0 + proposalTTL) return "expired";
        }
        return "open";
    }

    function _stateString(ProposalState s) internal pure returns (string memory) {
        if (s == ProposalState.Unopened) return "unopened";
        if (s == ProposalState.Active) return "active";
        if (s == ProposalState.Queued) return "queued";
        if (s == ProposalState.Succeeded) return "succeeded";
        if (s == ProposalState.Defeated) return "defeated";
        if (s == ProposalState.Expired) return "expired";
        return "executed";
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
contract SAWShares {
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
    mapping(address => address) internal _delegates;
    mapping(address => Checkpoint[]) internal _checkpoints;
    Checkpoint[] internal _totalSupplyCheckpoints;

    constructor(address[] memory to, uint256[] memory amt, address sawAddr) payable {
        saw = payable(sawAddr);
        if (to.length != amt.length) revert Len();
        for (uint256 i = 0; i < to.length; ++i) {
            _mint(to[i], amt[i]);
            _autoSelfDelegate(to[i]);
        }
    }

    // dynamic metadata from SAW
    function name() public view returns (string memory) {
        return string.concat(SAW(saw).orgName(), " Shares");
    }

    function symbol() public view returns (string memory) {
        return SAW(saw).orgSymbol();
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
        if (SAW(saw).transfersLocked() && msg.sender != saw && to != saw) revert Locked();
        balanceOf[msg.sender] -= amount;
        unchecked {
            balanceOf[to] += amount;
        }
        emit Transfer(msg.sender, to, amount);

        _autoSelfDelegate(to);
        _autoSelfDelegate(msg.sender);
        _moveVotingPower(_delegates[msg.sender], _delegates[to], amount);

        SAW(saw).onSharesChanged(msg.sender);
        SAW(saw).onSharesChanged(to);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public returns (bool) {
        if (SAW(saw).transfersLocked() && from != saw && to != saw) revert Locked();

        // BEFORE: if (to != saw) { ... }
        // AFTER: only SAW may skip allowance decrement
        if (msg.sender != saw && allowance[from][msg.sender] != type(uint256).max) {
            allowance[from][msg.sender] -= amount;
        }

        balanceOf[from] -= amount;
        unchecked {
            balanceOf[to] += amount;
        }
        emit Transfer(from, to, amount);

        _autoSelfDelegate(to);
        _autoSelfDelegate(from);
        _moveVotingPower(_delegates[from], _delegates[to], amount);

        SAW(saw).onSharesChanged(from);
        SAW(saw).onSharesChanged(to);
        return true;
    }

    function mintFromSAW(address to, uint256 amount) public {
        require(msg.sender == saw, "SAW");
        _mint(to, amount);
        _autoSelfDelegate(to);
        SAW(saw).onSharesChanged(to);
    }

    function burnFromSAW(address from, uint256 amount) public {
        require(msg.sender == saw, "SAW");
        balanceOf[from] -= amount;
        unchecked {
            totalSupply -= amount;
        }
        emit Transfer(from, address(0), amount);

        _autoSelfDelegate(from);
        _writeTotalSupplyCheckpoint();
        _moveVotingPower(_delegates[from], address(0), amount);

        SAW(saw).onSharesChanged(from);
    }

    function _mint(address to, uint256 amount) internal {
        unchecked {
            totalSupply += amount;
            balanceOf[to] += amount;
        }
        emit Transfer(address(0), to, amount);

        _writeTotalSupplyCheckpoint();
        _moveVotingPower(address(0), _delegates[to] == address(0) ? to : _delegates[to], amount);
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
        uint256 n = _checkpoints[delegates(account)].length;
        return n == 0 ? 0 : _checkpoints[delegates(account)][n - 1].votes;
    }

    function getPastVotes(address account, uint32 blockNumber) public view returns (uint256) {
        require(blockNumber < block.number, "bad block");
        return _checkpointsLookup(_checkpoints[delegates(account)], blockNumber);
    }

    function getPastTotalSupply(uint32 blockNumber) public view returns (uint256) {
        require(blockNumber < block.number, "bad block");
        return _checkpointsLookup(_totalSupplyCheckpoints, blockNumber);
    }

    function _delegate(address delegator, address delegatee) internal {
        address current = delegates(delegator);
        if (delegatee == address(0)) delegatee = delegator; // self by default
        _delegates[delegator] = delegatee;
        emit DelegateChanged(delegator, current, delegatee);

        uint256 bal = balanceOf[delegator];
        _moveVotingPower(current, delegatee, bal);
    }

    function _autoSelfDelegate(address account) internal {
        if (_delegates[account] == address(0)) {
            _delegates[account] = account;
            emit DelegateChanged(account, address(0), account);
            // write a zero->bal checkpoint when first seen
            uint256 bal = balanceOf[account];
            if (bal != 0) _writeCheckpoint(_checkpoints[account], 0, bal);
        }
    }

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

    /// @dev Casts `x` to a uint32. Reverts on overflow.
    function toUint32(uint256 x) internal pure returns (uint32) {
        if (x >= 1 << 32) _revertOverflow();
        return uint32(x);
    }

    /// @dev Casts `x` to a uint224. Reverts on overflow.
    function toUint224(uint256 x) internal pure returns (uint224) {
        if (x >= 1 << 224) _revertOverflow();
        return uint224(x);
    }

    function _revertOverflow() internal pure {
        /// @solidity memory-safe-assembly
        assembly {
            // Store the function selector of `Overflow()`.
            mstore(0x00, 0x35278d12)
            // Revert with (offset, size).
            revert(0x1c, 0x04)
        }
    }

    function _writeCheckpoint(Checkpoint[] storage ckpts, uint256 oldVal, uint256 newVal) internal {
        if (oldVal == newVal) return; // no-op, save gas

        uint32 blk = toUint32(block.number);
        uint256 len = ckpts.length;

        if (len != 0) {
            Checkpoint storage last = ckpts[len - 1];

            // If we've already written this block, just update it.
            if (last.fromBlock == blk) {
                last.votes = toUint224(newVal);
                return;
            }

            // If the last checkpoint (previous block) already has this value, skip pushing a duplicate.
            if (last.votes == newVal) return;
        }

        ckpts.push(Checkpoint({fromBlock: blk, votes: toUint224(newVal)}));
    }

    function _writeTotalSupplyCheckpoint() internal {
        /*uint256 oldVal =*/
        _totalSupplyCheckpoints.length == 0
            ? 0
            : _totalSupplyCheckpoints[_totalSupplyCheckpoints.length - 1].votes;
        uint256 newVal = totalSupply;
        uint32 blk = uint32(block.number);
        if (
            _totalSupplyCheckpoints.length != 0
                && _totalSupplyCheckpoints[_totalSupplyCheckpoints.length - 1].fromBlock == blk
        ) {
            _totalSupplyCheckpoints[_totalSupplyCheckpoints.length - 1].votes = uint224(newVal);
        } else {
            _totalSupplyCheckpoints.push(Checkpoint({fromBlock: blk, votes: uint224(newVal)}));
        }
    }

    function _checkpointsLookup(Checkpoint[] storage ckpts, uint32 blockNumber)
        internal
        view
        returns (uint256)
    {
        // binary search in ckpts
        uint256 len = ckpts.length;
        if (len == 0) return 0;
        // First check most recent
        if (ckpts[len - 1].fromBlock <= blockNumber) return ckpts[len - 1].votes;
        // Then earliest
        if (ckpts[0].fromBlock > blockNumber) return 0;

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
}

/*//////////////////////////////////////////////////////////////
   Non-transferable top-256 vanity badge (SBT). ID = holder address.
//////////////////////////////////////////////////////////////*/
contract SAWBadge {
    /* ERC721-ish */
    event Transfer(address indexed from, address indexed to, uint256 indexed id);

    address payable public immutable saw;

    mapping(uint256 => address) internal _ownerOf;
    mapping(address => uint256) internal _balanceOf;

    constructor() payable {
        saw = payable(msg.sender);
    }

    // dynamic metadata from SAW
    function name() public view returns (string memory) {
        return string.concat(SAW(saw).orgName(), " Badge");
    }

    function symbol() public view returns (string memory) {
        return string.concat(SAW(saw).orgSymbol(), "B");
    }

    function ownerOf(uint256 id) public view returns (address o) {
        require((o = _ownerOf[id]) != address(0), "NOT_MINTED");
    }

    function balanceOf(address o) public view returns (uint256) {
        require(o != address(0), "ZERO");
        return _balanceOf[o];
    }

    function tokenURI(uint256 id) public view returns (string memory) {
        address holder = address(uint160(id));
        SAWShares sh = SAW(saw).shares();
        uint256 bal = sh.balanceOf(holder);
        uint256 ts = sh.totalSupply();
        uint256 rk = SAW(saw).rankOf(holder); // 0 if not in top set

        string memory addr = _addrHex(holder);
        string memory pct = _percent(bal, ts);
        string memory rank = rk == 0 ? "-" : _u2s(rk);

        string memory svg = string.concat(
            "<svg xmlns='http://www.w3.org/2000/svg' width='420' height='420'>",
            "<rect width='100%' height='100%' fill='#111'/>",
            "<text x='20' y='60'  font-family='Courier New, monospace' font-size='18' fill='#fff'>",
            name(),
            "</text>",
            "<text x='20' y='100' font-family='Courier New, monospace' font-size='12' fill='#fff' letter-spacing='1'>",
            addr,
            "</text>",
            "<text x='20' y='130' font-family='Courier New, monospace' font-size='12' fill='#fff'>balance: ",
            _u2s(bal),
            "</text>",
            "<text x='20' y='150' font-family='Courier New, monospace' font-size='12' fill='#fff'>supply: ",
            _u2s(ts),
            "</text>",
            "<text x='20' y='170' font-family='Courier New, monospace' font-size='12' fill='#fff'>percent: ",
            pct,
            "</text>",
            "<text x='20' y='190' font-family='Courier New, monospace' font-size='12' fill='#fff'>rank: ",
            rank,
            "</text>",
            "</svg>"
        );
        return string.concat(
            "data:application/json;utf8,",
            "{\"name\":\"",
            name(),
            "\",\"description\":\"Top-256 holder badge (slot rank)\",",
            "\"image\":\"data:image/svg+xml;utf8,",
            svg,
            "\"}"
        );
    }

    function transferFrom(address, address, uint256) public pure {
        revert("SBT");
    }

    function mint(address to) public {
        require(msg.sender == saw, "SAW");
        uint256 id = uint256(uint160(to));
        require(to != address(0) && _ownerOf[id] == address(0), "MINTED");
        _ownerOf[id] = to;
        unchecked {
            _balanceOf[to]++;
        }
        emit Transfer(address(0), to, id);
    }

    function burn(address from) public {
        require(msg.sender == saw, "SAW");
        uint256 id = uint256(uint160(from));
        require(_ownerOf[id] == from, "OWN");
        _ownerOf[id] = address(0);
        unchecked {
            _balanceOf[from]--;
        }
        emit Transfer(from, address(0), id);
    }

    /* utils */
    function _addrHex(address a) internal pure returns (string memory s) {
        bytes20 b = bytes20(a);
        bytes16 H = 0x30313233343536373839616263646566;
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
        uint256 p = a * 10000 / b;
        uint256 i = p / 100;
        uint256 d = p % 100;
        return string.concat(_u2s(i), ".", d < 10 ? "0" : "", _u2s(d), "%");
    }
}

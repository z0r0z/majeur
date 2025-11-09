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
    MolochShares public immutable shares;
    MolochBadge public immutable badge;

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
            _safeTransferFrom(F.rewardToken, msg.sender, address(this), amount);
            F.pool += amount;
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

        uint64 queued = queuedAt[id];

        // If already queued, TTL no longer applies.
        if (queued != 0) {
            uint64 delay = timelockDelay;
            // If delay is zero, this condition is always false once block.timestamp >= queued,
            // which matches the original behavior (queuedAt is only set when delay != 0).
            if (delay != 0 && block.timestamp < queued + delay) {
                return ProposalState.Queued;
            }
        } else {
            uint64 ttl = proposalTTL;
            if (ttl != 0) {
                uint64 t0 = createdAt[id];
                if (t0 != 0 && block.timestamp > t0 + ttl) {
                    return ProposalState.Expired;
                }
            }
        }

        // Evaluate gates
        uint256 ts = supplySnapshot[id];
        if (ts == 0) return ProposalState.Active;

        Tally storage t = tallies[id];
        uint256 forVotes = t.forVotes;
        uint256 againstVotes = t.againstVotes;
        uint256 abstainVotes = t.abstainVotes;

        uint256 totalCast = forVotes + againstVotes + abstainVotes;

        // Absolute quorum
        uint256 absQuorum = quorumAbsolute;
        if (absQuorum != 0 && totalCast < absQuorum) return ProposalState.Active;

        // Dynamic quorum (BPS)
        uint16 bps = quorumBps;
        if (bps != 0 && totalCast < mulDiv(uint256(bps), ts, 10000)) {
            return ProposalState.Active;
        }

        // Absolute YES floor
        uint256 minYes = minYesVotesAbsolute;
        if (minYes != 0 && forVotes < minYes) return ProposalState.Defeated;

        if (forVotes <= againstVotes) return ProposalState.Defeated;

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

        uint64 ttl = proposalTTL;
        if (ttl == 0) revert NotOk();

        uint64 t0 = createdAt[id];
        if (t0 == 0 || block.timestamp <= t0 + ttl) revert NotOk();

        _finalizeFutarchy(id, F, 0);
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

        _payout(F.rewardToken, msg.sender, payout);
        emit FutarchyClaimed(id, msg.sender, amount, payout);
    }

    function _resolveFutarchyYes(bytes32 id) internal {
        FutarchyConfig storage F = futarchy[id];
        if (!F.enabled || F.resolved) return;
        _finalizeFutarchy(id, F, 1);
    }

    function _finalizeFutarchy(bytes32 id, FutarchyConfig storage F, uint8 winner) internal {
        uint256 rid = _receiptId(id, winner);
        uint256 winSupply = totalSupply[rid];
        uint256 pool = F.pool;
        uint256 ppu;

        if (winSupply != 0 && pool != 0) {
            F.finalWinningSupply = winSupply;
            ppu = pool / winSupply;
            F.payoutPerUnit = ppu;
        }

        F.resolved = true;
        F.winner = winner;

        emit FutarchyResolved(id, winner, pool, winSupply, ppu);
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

        executed[id] = true;

        if (p != type(uint256).max) {
            unchecked {
                permits[id] = p - 1;
            }
            if (use6909ForPermits) {
                _burn6909(address(this), uint256(id), 1);
            }
        }

        (ok, retData) = _execute(op, to, value, data);

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
        _payout(token, msg.sender, amount);
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
        Sale storage s = sales[payToken];
        if (!s.active) revert NotApprover();

        uint256 cap = s.cap;
        if (cap != 0 && shareAmount > cap) revert NotOk();

        uint256 price = s.pricePerShare;
        uint256 cost = shareAmount * price; // overflow already checked by Solidity

        // EFFECTS (CEI)
        if (cap != 0) {
            unchecked {
                s.cap = cap - shareAmount;
            }
        }

        // Pull funds
        if (payToken == address(0)) {
            // Same logic: require(msg.value <= maxPay && msg.value == cost)
            if (msg.value != cost || msg.value > maxPay) revert NotOk();
        } else {
            if (msg.value != 0 || (maxPay != 0 && cost > maxPay)) revert NotOk();
            _safeTransferFrom(payToken, msg.sender, address(this), cost);
        }

        // Issue shares
        if (s.minting) {
            shares.mintFromMolochMajeur(msg.sender, shareAmount);
        } else {
            shares.transfer(msg.sender, shareAmount);
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

        uint256 len = tokens.length;
        address prev;

        for (uint256 i; i < len; ++i) {
            address tk = tokens[i];
            if (i != 0 && tk <= prev) revert NotOk();
            prev = tk;

            uint256 pool = tk == address(0) ? address(this).balance : _erc20Balance(tk);
            uint256 due = mulDiv(pool, amt, ts);
            if (due == 0) continue;

            _payout(tk, msg.sender, due);
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

    /// Maintains a sticky top-256 set.
    /// - A holder keeps their slot as long as their balance is non-zero.
    /// - We only consider demotion when:
    ///   (a) a non-member's balance changes and exceeds the current minimum, or
    ///   (b) a member's balance falls to zero.
    /// - This means the set may diverge from the true mathematical top-256.
    function _onSharesChanged(address a) internal {
        uint256 bal = shares.balanceOf(a);
        uint16 pos = topPos[a];

        // 1) Zero balance → drop from top set and burn badge if currently in.
        if (bal == 0) {
            if (pos != 0) {
                unchecked {
                    topHolders[pos - 1] = address(0);
                }
                topPos[a] = 0;
                badge.burn(a);
            }
            return;
        }

        // 2) Already in top set → keep slot; we don't rebalance / re-rank.
        if (pos != 0) return;

        // 3) Not in top set, non-zero balance: try to fill a free slot first.
        uint256 len = 256;
        for (uint16 i; i != len; ++i) {
            if (topHolders[i] == address(0)) {
                topHolders[i] = a;
                unchecked {
                    topPos[a] = i + 1;
                }
                badge.mint(a);
                return;
            }
        }

        // 4) Full set: find the lowest-balance current top holder.
        uint16 minI;
        uint256 minBal = type(uint256).max;

        for (uint16 i; i != len; ++i) {
            address cur = topHolders[i];
            uint256 cbal = (cur == address(0)) ? 0 : shares.balanceOf(cur);

            if (cbal < minBal) {
                minBal = cbal;
                minI = i;
            }
        }

        // 5) Only replace if strictly larger than the current minimum.
        if (bal > minBal) {
            address evict = topHolders[minI];

            topHolders[minI] = a;
            unchecked {
                topPos[a] = minI + 1;
            }
            topPos[evict] = 0;

            badge.burn(evict);
            badge.mint(a);
        }
    }

    /*//////////////////////////////////////////////////////////////
                             ERC6909 INTERNALS
    //////////////////////////////////////////////////////////////*/
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
    /*//////////////////////////////////////////////////////////////
                            PROPOSAL CARD URI
    //////////////////////////////////////////////////////////////*/

    /// @notice On-chain JSON/SVG card for a proposal id, or routes to receiptURI for vote receipts.
    function tokenURI(uint256 id) public view returns (string memory) {
        // 1) If this id is a vote receipt, delegate to the full receipt renderer.
        if (receiptProposal[id] != bytes32(0)) return receiptURI(id);

        bytes32 h = bytes32(id);

        Tally memory t = tallies[h];
        bool touchedTallies = (t.forVotes | t.againstVotes | t.abstainVotes) != 0;

        uint256 snap = snapshotBlock[h];
        bool opened = snap != 0 || createdAt[h] != 0;

        bool looksLikePermit = use6909ForPermits && !opened && !touchedTallies
            && (totalSupply[id] != 0 || permits[h] != 0);

        if (looksLikePermit) {
            return _permitCardURI(h, id);
        }

        // ----- Proposal Card -----
        string memory stateStr;
        if (executed[h]) {
            stateStr = "EXECUTED";
        } else if (snap == 0) {
            stateStr = "UNOPENED";
        } else if (proposalTTL != 0) {
            uint64 t0 = createdAt[h];
            if (t0 != 0 && block.timestamp > t0 + proposalTTL) {
                stateStr = "EXPIRED";
            } else {
                stateStr = "ACTIVE";
            }
        } else {
            stateStr = "OPEN";
        }

        string memory svg = _svgCardBase();

        // Title
        svg = string.concat(
            svg,
            "<text x='210' y='55' class='garamond-bold' font-size='18' fill='#fff' text-anchor='middle' letter-spacing='3'>",
            orgName,
            "</text>",
            "<text x='210' y='75' class='garamond' font-size='11' fill='#fff' text-anchor='middle' letter-spacing='2'>PROPOSAL</text>",
            "<line x1='40' y1='90' x2='380' y2='90' stroke='#fff' stroke-width='1'/>"
        );

        // ASCII Eye (minimalist)
        svg = string.concat(
            svg,
            "<text x='210' y='155' class='mono' font-size='9' fill='#fff' text-anchor='middle'>.---------.</text>",
            "<text x='210' y='166' class='mono' font-size='9' fill='#fff' text-anchor='middle'>(     O     )</text>",
            "<text x='210' y='177' class='mono' font-size='9' fill='#fff' text-anchor='middle'>'---------'</text>",
            "<line x1='40' y1='220' x2='380' y2='220' stroke='#fff' stroke-width='1'/>"
        );

        // Data section
        svg = string.concat(
            svg,
            "<text x='60' y='255' class='garamond' font-size='10' fill='#aaa' letter-spacing='1'>ID</text>",
            "<text x='60' y='272' class='mono' font-size='9' fill='#fff'>",
            _shortHex(h),
            "</text>"
        );

        // Snapshot data (only if opened)
        if (opened) {
            svg = string.concat(
                svg,
                "<text x='60' y='305' class='garamond' font-size='10' fill='#aaa' letter-spacing='1'>Snapshot</text>",
                "<text x='60' y='322' class='mono' font-size='9' fill='#fff'>Block ",
                _u2s(snap),
                "</text>",
                "<text x='60' y='335' class='mono' font-size='9' fill='#fff'>Supply ",
                _formatNumber(supplySnapshot[h]),
                "</text>"
            );
        }

        // Tally section (only if votes exist)
        if (touchedTallies) {
            svg = string.concat(
                svg,
                "<text x='60' y='368' class='garamond' font-size='10' fill='#aaa' letter-spacing='1'>Tally</text>",
                "<text x='60' y='385' class='mono' font-size='9' fill='#fff'>For      ",
                _formatNumber(t.forVotes),
                "</text>",
                "<text x='60' y='398' class='mono' font-size='9' fill='#fff'>Against  ",
                _formatNumber(t.againstVotes),
                "</text>",
                "<text x='60' y='411' class='mono' font-size='9' fill='#fff'>Abstain  ",
                _formatNumber(t.abstainVotes),
                "</text>"
            );
        }

        // Status
        svg = string.concat(
            svg,
            "<text x='210' y='465' class='garamond' font-size='12' fill='#fff' text-anchor='middle' letter-spacing='2'>",
            stateStr,
            "</text>",
            "<line x1='40' y1='495' x2='380' y2='495' stroke='#fff' stroke-width='1'/>",
            "</svg>"
        );

        return _jsonImage(
            string.concat(orgName, " Proposal"), "Snapshot-weighted governance proposal", svg
        );
    }

    /*//////////////////////////////////////////////////////////////
                            VOTE RECEIPT CARD URI
    //////////////////////////////////////////////////////////////*/

    function receiptURI(uint256 id) public view returns (string memory) {
        uint8 s = receiptSupport[id]; // 0 = NO, 1 = YES, 2 = ABSTAIN
        bytes32 h = receiptProposal[id];
        FutarchyConfig memory F = futarchy[h];

        string memory stance = s == 1 ? "YES" : s == 0 ? "NO" : "ABSTAIN";

        string memory status;
        if (!F.enabled) {
            status = "SEALED";
        } else if (!F.resolved) {
            status = "OPEN";
        } else {
            status = (F.winner == s) ? "REDEEMABLE" : "SEALED";
        }

        string memory svg = _svgCardBase();

        // Title
        svg = string.concat(
            svg,
            "<text x='210' y='55' class='garamond-bold' font-size='18' fill='#fff' text-anchor='middle' letter-spacing='3'>",
            orgName,
            "</text>",
            "<text x='210' y='75' class='garamond' font-size='11' fill='#fff' text-anchor='middle' letter-spacing='2'>VOTE RECEIPT</text>",
            "<line x1='40' y1='90' x2='380' y2='90' stroke='#fff' stroke-width='1'/>"
        );

        // ASCII symbol based on vote type
        if (s == 1) {
            // YES - pointing up hand
            svg = string.concat(
                svg,
                "<text x='210' y='135' class='mono' font-size='9' fill='#fff' text-anchor='middle'>|</text>",
                "<text x='210' y='146' class='mono' font-size='9' fill='#fff' text-anchor='middle'>/_\\</text>",
                "<text x='210' y='157' class='mono' font-size='9' fill='#fff' text-anchor='middle'>/   \\</text>",
                "<text x='210' y='168' class='mono' font-size='9' fill='#fff' text-anchor='middle'>|  *  |</text>",
                "<text x='210' y='179' class='mono' font-size='9' fill='#fff' text-anchor='middle'>|     |</text>",
                "<text x='210' y='190' class='mono' font-size='9' fill='#fff' text-anchor='middle'>|     |</text>",
                "<text x='210' y='201' class='mono' font-size='9' fill='#fff' text-anchor='middle'>|_____|</text>"
            );
        } else if (s == 0) {
            // NO - X symbol
            svg = string.concat(
                svg,
                "<text x='210' y='145' class='mono' font-size='9' fill='#fff' text-anchor='middle'>\\       /</text>",
                "<text x='210' y='156' class='mono' font-size='9' fill='#fff' text-anchor='middle'> \\     / </text>",
                "<text x='210' y='167' class='mono' font-size='9' fill='#fff' text-anchor='middle'>  \\   /  </text>",
                "<text x='210' y='178' class='mono' font-size='9' fill='#fff' text-anchor='middle'>    X    </text>",
                "<text x='210' y='189' class='mono' font-size='9' fill='#fff' text-anchor='middle'>  /   \\  </text>",
                "<text x='210' y='200' class='mono' font-size='9' fill='#fff' text-anchor='middle'> /     \\ </text>",
                "<text x='210' y='211' class='mono' font-size='9' fill='#fff' text-anchor='middle'>/       \\</text>"
            );
        } else {
            // ABSTAIN - circle
            svg = string.concat(
                svg,
                "<text x='210' y='145' class='mono' font-size='9' fill='#fff' text-anchor='middle'>___</text>",
                "<text x='210' y='156' class='mono' font-size='9' fill='#fff' text-anchor='middle'>/     \\</text>",
                "<text x='210' y='167' class='mono' font-size='9' fill='#fff' text-anchor='middle'>|       |</text>",
                "<text x='210' y='178' class='mono' font-size='9' fill='#fff' text-anchor='middle'>|       |</text>",
                "<text x='210' y='189' class='mono' font-size='9' fill='#fff' text-anchor='middle'>|       |</text>",
                "<text x='210' y='200' class='mono' font-size='9' fill='#fff' text-anchor='middle'>\\     /</text>",
                "<text x='210' y='211' class='mono' font-size='9' fill='#fff' text-anchor='middle'>---</text>"
            );
        }

        svg = string.concat(
            svg, "<line x1='40' y1='240' x2='380' y2='240' stroke='#fff' stroke-width='1'/>"
        );

        // Data
        svg = string.concat(
            svg,
            "<text x='60' y='275' class='garamond' font-size='10' fill='#aaa' letter-spacing='1'>Proposal</text>",
            "<text x='60' y='292' class='mono' font-size='9' fill='#fff'>",
            _shortHex(h),
            "</text>",
            "<text x='60' y='325' class='garamond' font-size='10' fill='#aaa' letter-spacing='1'>Stance</text>",
            "<text x='60' y='345' class='garamond-bold' font-size='14' fill='#fff'>",
            stance,
            "</text>",
            "<text x='60' y='378' class='garamond' font-size='10' fill='#aaa' letter-spacing='1'>Weight</text>",
            "<text x='60' y='395' class='mono' font-size='9' fill='#fff'>",
            _formatNumber(totalSupply[id]),
            " votes</text>"
        );

        // Futarchy info (only if enabled)
        if (F.enabled) {
            svg = string.concat(
                svg,
                "<text x='60' y='428' class='garamond' font-size='10' fill='#aaa' letter-spacing='1'>Futarchy</text>",
                "<text x='60' y='445' class='mono' font-size='9' fill='#fff'>Pool ",
                _formatNumber(F.pool),
                F.rewardToken == address(0) ? " wei" : " units",
                "</text>"
            );

            if (F.resolved) {
                svg = string.concat(
                    svg,
                    "<text x='60' y='458' class='mono' font-size='9' fill='#fff'>Payout ",
                    _formatNumber(F.payoutPerUnit),
                    "/vote</text>"
                );
            }
        }

        // Status
        svg = string.concat(
            svg,
            "<text x='210' y='510' class='garamond' font-size='12' fill='#fff' text-anchor='middle' letter-spacing='2'>",
            status,
            "</text>",
            "<line x1='40' y1='540' x2='380' y2='540' stroke='#fff' stroke-width='1'/>",
            "</svg>"
        );

        return _jsonImage(
            "Vote Receipt",
            string.concat(stance, " vote receipt - burn to claim rewards if winner"),
            svg
        );
    }

    /*//////////////////////////////////////////////////////////////
                            PERMIT CARD URI
    //////////////////////////////////////////////////////////////*/

    function _permitCardURI(bytes32 h, uint256 id) internal view returns (string memory) {
        string memory usesStr;
        uint256 p = permits[h];
        if (p == type(uint256).max) {
            usesStr = "UNLIMITED";
        } else {
            usesStr = _formatNumber(p);
        }

        string memory svg = _svgCardBase();

        // Title
        svg = string.concat(
            svg,
            "<text x='210' y='55' class='garamond-bold' font-size='18' fill='#fff' text-anchor='middle' letter-spacing='3'>",
            orgName,
            "</text>",
            "<text x='210' y='75' class='garamond' font-size='11' fill='#fff' text-anchor='middle' letter-spacing='2'>PERMIT</text>",
            "<line x1='40' y1='90' x2='380' y2='90' stroke='#fff' stroke-width='1'/>"
        );

        // ASCII Key
        svg = string.concat(
            svg,
            "<text x='210' y='140' class='mono' font-size='9' fill='#fff' text-anchor='middle'>___</text>",
            "<text x='210' y='151' class='mono' font-size='9' fill='#fff' text-anchor='middle'>( o )</text>",
            "<text x='210' y='162' class='mono' font-size='9' fill='#fff' text-anchor='middle'>| |</text>",
            "<text x='210' y='173' class='mono' font-size='9' fill='#fff' text-anchor='middle'>| |</text>",
            "<text x='210' y='184' class='mono' font-size='9' fill='#fff' text-anchor='middle'>====###====</text>",
            "<text x='210' y='195' class='mono' font-size='9' fill='#fff' text-anchor='middle'>| |</text>",
            "<text x='210' y='206' class='mono' font-size='9' fill='#fff' text-anchor='middle'>| |</text>",
            "<text x='210' y='217' class='mono' font-size='9' fill='#fff' text-anchor='middle'>|_|</text>",
            "<line x1='40' y1='245' x2='380' y2='245' stroke='#fff' stroke-width='1'/>"
        );

        // Data
        svg = string.concat(
            svg,
            "<text x='60' y='280' class='garamond' font-size='10' fill='#aaa' letter-spacing='1'>Intent ID</text>",
            "<text x='60' y='297' class='mono' font-size='9' fill='#fff'>",
            _shortHex(h),
            "</text>",
            "<text x='60' y='330' class='garamond' font-size='10' fill='#aaa' letter-spacing='1'>Uses</text>",
            "<text x='60' y='350' class='garamond-bold' font-size='14' fill='#fff'>",
            usesStr,
            "</text>"
        );

        // Mirror supply (only if mirrored)
        if (use6909ForPermits && totalSupply[id] > 0) {
            svg = string.concat(
                svg,
                "<text x='60' y='383' class='garamond' font-size='10' fill='#aaa' letter-spacing='1'>Mirror Supply</text>",
                "<text x='60' y='400' class='mono' font-size='9' fill='#fff'>",
                _formatNumber(totalSupply[id]),
                "</text>"
            );
        }

        // Status
        svg = string.concat(
            svg,
            "<text x='210' y='480' class='garamond' font-size='12' fill='#fff' text-anchor='middle' letter-spacing='2'>ACTIVE</text>",
            "<line x1='40' y1='520' x2='380' y2='520' stroke='#fff' stroke-width='1'/>",
            "</svg>"
        );

        return _jsonImage("Permit", "Pre-approved execution permit", svg);
    }

    /// @dev Shortened hex: 0xabcd...1234
    function _shortHex(bytes32 data) internal pure returns (string memory) {
        return _shortHexDisplay(_toHex(data));
    }

    // Cheap hex for bytes32: "0x" + 64 hex chars.
    function _toHex(bytes32 data) internal pure returns (string memory) {
        bytes memory str = new bytes(66);
        str[0] = "0";
        str[1] = "x";

        assembly {
            let _hex := "0123456789abcdef"
            for { let i := 0 } lt(i, 32) { i := add(i, 1) } {
                let b := byte(i, data)
                mstore8(add(add(str, 32), add(mul(i, 2), 2)), byte(shr(4, b), _hex))
                mstore8(add(add(str, 32), add(mul(i, 2), 3)), byte(and(b, 0x0f), _hex))
            }
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

    function _payout(address token, address to, uint256 amount) internal {
        if (token == address(0)) {
            (bool ok,) = payable(to).call{value: amount}("");
            if (!ok) revert NotOk();
        } else {
            _safeTransfer(token, to, amount);
        }
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
             ERC20 SHARES WITH LIGHTWEIGHT SNAPSHOTS/DELEGATION
//////////////////////////////////////////////////////////////*/
contract MolochShares {
    /* ERRORS */
    error Len();
    error Locked();
    error BadBlock();
    error Unauthorized();

    /* ERC20 */
    event Approval(address indexed from, address indexed to, uint256 amount);
    event Transfer(address indexed from, address indexed to, uint256 amount);

    uint8 public constant decimals = 18;
    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    /// @notice The parent Moloch contract.
    address payable public immutable mol;

    modifier onlyMol() {
        require(msg.sender == mol, Unauthorized());
        _;
    }

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
        mol = payable(sawAddr);

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
        return string.concat(MolochMajeur(mol).orgName(), " Shares");
    }

    function symbol() public view returns (string memory) {
        return MolochMajeur(mol).orgSymbol();
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
        _checkUnlocked(msg.sender, to);
        _moveTokens(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public returns (bool) {
        _checkUnlocked(from, to);

        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) {
            allowance[from][msg.sender] = allowed - amount;
        }

        _moveTokens(from, to, amount);
        return true;
    }

    /// @notice Mint new shares; callable only by the Moloch (MolochMajeur).
    function mintFromMolochMajeur(address to, uint256 amount) public payable onlyMol {
        _mint(to, amount);
        _autoSelfDelegate(to);
        _afterVotingBalanceChange(to, int256(amount));
    }

    /// @notice Burn shares; callable only by the Moloch (MolochMajeur).
    function burnFromMolochMajeur(address from, uint256 amount) public payable onlyMol {
        balanceOf[from] -= amount;
        unchecked {
            totalSupply -= amount;
        }
        emit Transfer(from, address(0), amount);

        _writeTotalSupplyCheckpoint();
        _autoSelfDelegate(from);
        _afterVotingBalanceChange(from, -int256(amount));
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

        int256 signed = int256(amount);
        _afterVotingBalanceChange(from, -signed);
        _afterVotingBalanceChange(to, signed);
    }

    function _updateDelegateVotes(
        address delegate_,
        Checkpoint[] storage ckpts,
        bool add,
        uint256 amount
    ) internal {
        uint256 len = ckpts.length;
        uint256 oldVal = len == 0 ? 0 : ckpts[len - 1].votes;
        uint256 newVal = add ? oldVal + amount : oldVal - amount;

        _writeCheckpoint(ckpts, oldVal, newVal);
        emit DelegateVotesChanged(delegate_, oldVal, newVal);
    }

    function _checkUnlocked(address from, address to) internal view {
        bool locked = MolochMajeur(mol).transfersLocked();
        if (locked && from != mol && to != mol) revert Locked();
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
        if (blockNumber >= block.number) revert BadBlock();
        return _checkpointsLookup(_checkpoints[account], blockNumber);
    }

    function getPastTotalSupply(uint32 blockNumber) public view returns (uint256) {
        if (blockNumber >= block.number) revert BadBlock();
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
        address account = msg.sender;
        uint256 n = delegates_.length;
        require(n == bps_.length && n > 0 && n <= MAX_SPLITS, "split/len");

        // Capture the current effective distribution BEFORE we mutate storage.
        (address[] memory oldD, uint32[] memory oldB) = _currentDistribution(account);

        uint256 sum;
        for (uint256 i; i < n; ++i) {
            address d = delegates_[i];
            require(d != address(0), "split/zero");
            uint32 b = bps_[i];
            sum += b;

            // no duplicate delegates
            for (uint256 j = i + 1; j < n; ++j) {
                require(d != delegates_[j], "split/dupe");
            }
        }
        require(sum == BPS_DENOM, "split/sum");

        // Ensure the account has a primary delegate line (defaults to self once).
        _autoSelfDelegate(account);

        // Write the new split set.
        delete _splits[account];
        for (uint256 i; i < n; ++i) {
            _splits[account].push(Split({delegate: delegates_[i], bps: bps_[i]}));
        }

        // Move only the difference in voting power from the old distribution to the new one.
        _repointVotesForHolder(account, oldD, oldB);

        emit WeightedDelegationSet(account, delegates_, bps_);
    }

    function clearSplitDelegation() external {
        address account = msg.sender;

        if (_splits[account].length == 0) {
            // Already single-delegate mode; nothing to do.
            return;
        }

        // Capture the current split BEFORE we mutate storage.
        (address[] memory oldD, uint32[] memory oldB) = _currentDistribution(account);

        // Collapse to single 100% delegate (primary; defaults to self).
        delete _splits[account];
        _autoSelfDelegate(account);

        // Repoint existing votes from the old split back to the single delegate.
        _repointVotesForHolder(account, oldD, oldB);

        // Emit the canonical 100% distribution for tooling/UX.
        address[] memory d = _singleton(delegates(account));
        uint32[] memory b = _singletonBps();
        emit WeightedDelegationSet(account, d, b);
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL VOTING HELPERS
    //////////////////////////////////////////////////////////////*/
    function _delegate(address delegator, address delegatee) internal {
        address account = delegator;
        if (delegatee == address(0)) delegatee = account;

        // Inline `delegates(account)` to avoid extra call:
        address current = _delegates[account];
        if (current == address(0)) current = account;

        Split[] storage sp = _splits[account];
        uint256 splitsLen = sp.length;

        // If no change and no split configured, nothing to do.
        if (splitsLen == 0 && current == delegatee) return;

        // Capture the current effective distribution BEFORE we mutate storage.
        (address[] memory oldD, uint32[] memory oldB) = _currentDistribution(account);

        // Collapse any existing split and set the new primary delegate.
        if (splitsLen != 0) {
            delete _splits[account];
        }
        _delegates[account] = delegatee;

        emit DelegateChanged(account, current, delegatee);

        // Repoint the holder’s current voting power from old distribution to the new single delegate.
        _repointVotesForHolder(account, oldD, oldB);
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
        uint256 n = sp.length;

        if (n == 0) {
            // Stack allocation for single element
            delegates_ = new address[](1);
            delegates_[0] = delegates(account);
            bps_ = new uint32[](1);
            bps_[0] = BPS_DENOM;
            return (delegates_, bps_);
        }

        // Pre-sized allocation
        delegates_ = new address[](n);
        bps_ = new uint32[](n);
        for (uint256 i; i < n; ++i) {
            delegates_[i] = sp[i].delegate;
            bps_[i] = sp[i].bps;
        }
    }

    function _afterVotingBalanceChange(address account, int256 delta) internal {
        _applyVotingDelta(account, delta);
        MolochMajeur(mol).onSharesChanged(account);
    }

    /// @dev Apply +/- voting power change for an account according to its split.
    function _applyVotingDelta(address account, int256 delta) internal {
        if (delta == 0) return;

        (address[] memory D, uint32[] memory B) = _currentDistribution(account);
        uint256 len = D.length;

        uint256 abs = delta > 0 ? uint256(delta) : uint256(-delta);
        uint256 remaining = abs;

        for (uint256 i; i < len; ++i) {
            uint256 part = (abs * B[i]) / BPS_DENOM;

            // give any rounding remainder to the last delegate
            if (i == len - 1) {
                part = remaining;
            } else {
                remaining -= part;
            }

            if (part == 0) continue;

            if (delta > 0) {
                _moveVotingPower(address(0), D[i], part);
            } else {
                _moveVotingPower(D[i], address(0), part);
            }
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
            _updateDelegateVotes(src, _checkpoints[src], false, amount);
        }
        if (dst != address(0)) {
            _updateDelegateVotes(dst, _checkpoints[dst], true, amount);
        }
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
        Checkpoint[] storage ckpts = _totalSupplyCheckpoints;
        uint256 len = ckpts.length;

        uint256 oldVal = len == 0 ? 0 : ckpts[len - 1].votes;
        uint256 newVal = totalSupply;

        _writeCheckpoint(ckpts, oldVal, newVal);
    }

    function _checkpointsLookup(Checkpoint[] storage ckpts, uint32 blockNumber)
        internal
        view
        returns (uint256)
    {
        uint256 len = ckpts.length;
        if (len == 0) return 0;

        // Most recent
        Checkpoint storage last = ckpts[len - 1];
        if (last.fromBlock <= blockNumber) {
            return last.votes;
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

    // Parent Moloch (Majeur)
    address payable public immutable mol = payable(msg.sender);

    // Holder => count (0 or 1 in practice)
    mapping(address => uint256) public balanceOf;

    modifier onlyMol() {
        require(msg.sender == mol, Unauthorized());
        _;
    }

    error SBT();
    error Minted();
    error NotMinted();
    error Unauthorized();

    constructor() payable {}

    // dynamic metadata from Moloch
    function name() public view returns (string memory) {
        return string.concat(MolochMajeur(mol).orgName(), " Badge");
    }

    function symbol() public view returns (string memory) {
        return string.concat(MolochMajeur(mol).orgSymbol(), "B");
    }

    function ownerOf(uint256 id) public view returns (address o) {
        o = address(uint160(id));
        require(balanceOf[o] != 0, NotMinted());
    }

    /// Top-256 badge (seat index, not sorted by balance).
    /// @notice Enhanced minimalist badge card
    function tokenURI(uint256 id) public view returns (string memory) {
        address holder = address(uint160(id));
        MolochShares sh = MolochMajeur(mol).shares();

        uint256 bal = sh.balanceOf(holder);
        uint256 ts = sh.totalSupply();
        uint256 rk = MolochMajeur(mol).rankOf(holder);

        string memory addr = _shortAddr(holder);
        string memory pct = _percent(bal, ts);
        string memory rankStr = rk == 0 ? "UNRANKED" : _u2s(rk);

        string memory svg = _svgCardBase();

        // Title
        svg = string.concat(
            svg,
            "<text x='210' y='55' class='garamond-bold' font-size='18' fill='#fff' text-anchor='middle' letter-spacing='3'>",
            name(),
            "</text>",
            "<text x='210' y='75' class='garamond' font-size='11' fill='#fff' text-anchor='middle' letter-spacing='2'>MEMBER BADGE</text>",
            "<line x1='40' y1='90' x2='380' y2='90' stroke='#fff' stroke-width='1'/>"
        );

        // ASCII Crown
        svg = string.concat(
            svg,
            "<text x='210' y='135' class='mono' font-size='9' fill='#fff' text-anchor='middle'>*    *    *</text>",
            "<text x='210' y='146' class='mono' font-size='9' fill='#fff' text-anchor='middle'>/|\\  /|\\  /|\\</text>",
            "<text x='210' y='157' class='mono' font-size='9' fill='#fff' text-anchor='middle'>+---+---+---+</text>",
            "<text x='210' y='168' class='mono' font-size='9' fill='#fff' text-anchor='middle'>|   | * |   |</text>",
            "<text x='210' y='179' class='mono' font-size='9' fill='#fff' text-anchor='middle'>|   |   |   |</text>",
            "<text x='210' y='190' class='mono' font-size='9' fill='#fff' text-anchor='middle'>+---+---+---+</text>",
            "<text x='210' y='201' class='mono' font-size='9' fill='#fff' text-anchor='middle'>\\         /</text>",
            "<text x='210' y='212' class='mono' font-size='9' fill='#fff' text-anchor='middle'>---------</text>",
            "<line x1='40' y1='240' x2='380' y2='240' stroke='#fff' stroke-width='1'/>"
        );

        // Data
        svg = string.concat(
            svg,
            "<text x='60' y='275' class='garamond' font-size='10' fill='#aaa' letter-spacing='1'>Address</text>",
            "<text x='60' y='292' class='mono' font-size='9' fill='#fff'>",
            addr,
            "</text>",
            "<text x='60' y='325' class='garamond' font-size='10' fill='#aaa' letter-spacing='1'>Rank</text>",
            "<text x='60' y='345' class='garamond-bold' font-size='16' fill='#fff'>",
            rankStr,
            "</text>"
        );

        // Balance
        svg = string.concat(
            svg,
            "<text x='60' y='378' class='garamond' font-size='10' fill='#aaa' letter-spacing='1'>Balance</text>",
            "<text x='60' y='395' class='mono' font-size='9' fill='#fff'>",
            _formatNumber(bal),
            " shares</text>"
        );

        // Ownership
        svg = string.concat(
            svg,
            "<text x='60' y='428' class='garamond' font-size='10' fill='#aaa' letter-spacing='1'>Ownership</text>",
            "<text x='60' y='445' class='mono' font-size='9' fill='#fff'>",
            pct,
            "</text>"
        );

        // Status (only show if in top 256)
        if (rk != 0) {
            svg = string.concat(
                svg,
                "<text x='210' y='500' class='garamond' font-size='12' fill='#fff' text-anchor='middle' letter-spacing='2'>TOP 256</text>"
            );
        }

        svg = string.concat(
            svg,
            "<line x1='40' y1='540' x2='380' y2='540' stroke='#fff' stroke-width='1'/>",
            "<text x='210' y='565' class='garamond' font-size='8' fill='#444' text-anchor='middle' letter-spacing='1'>NON-TRANSFERABLE</text>",
            "</svg>"
        );

        return _jsonImage("Badge", "Top-256 holder badge (SBT)", svg);
    }

    function transferFrom(address, address, uint256) public pure {
        revert SBT();
    }

    function mint(address to) public onlyMol {
        require(to != address(0) && balanceOf[to] == 0, Minted());

        balanceOf[to] = 1;
        emit Transfer(address(0), to, uint256(uint160(to)));
    }

    function burn(address from) public onlyMol {
        require(balanceOf[from] != 0, NotMinted());

        balanceOf[from] = 0;
        emit Transfer(from, address(0), uint256(uint160(from)));
    }

    /* utils */

    /// @dev Shortened address: 0xabcd...1234
    function _shortAddr(address a) internal pure returns (string memory) {
        return _shortHexDisplay(_addrHex(a));
    }

    // 0x + 40 hex chars
    function _addrHex(address a) internal pure returns (string memory s) {
        // 0x + 40 hex chars
        bytes20 b = bytes20(a);
        bytes16 H = 0x30313233343536373839616263646566; // "0123456789abcdef"
        bytes memory out = new bytes(42);

        out[0] = "0";
        out[1] = "x";

        for (uint256 i; i != 20; ++i) {
            unchecked {
                uint8 v = uint8(b[i]); // byte at position i

                // high nibble, then low nibble
                out[2 + 2 * i] = bytes1(H[v >> 4]);
                out[3 + 2 * i] = bytes1(H[v & 0x0f]);
            }
        }

        s = string(out);
    }

    function _percent(uint256 a, uint256 b) internal pure returns (string memory) {
        if (b == 0) return "0.00%";
        uint256 p = a * 10000 / b; // basis points
        uint256 i = p / 100;
        uint256 d = p % 100;
        return string.concat(_u2s(i), ".", d < 10 ? "0" : "", _u2s(d), "%");
    }
}

/*//////////////////////////////////////////////////////////////
                         MINIMAL INTERNALS
//////////////////////////////////////////////////////////////*/

function _formatNumber(uint256 n) pure returns (string memory) {
    if (n == 0) return "0";

    uint256 temp = n;
    uint256 digits;
    while (temp != 0) {
        digits++;
        temp /= 10;
    }

    uint256 commas = (digits - 1) / 3;
    bytes memory buffer = new bytes(digits + commas);

    uint256 i = digits + commas;
    uint256 digitCount = 0;

    while (n != 0) {
        if (digitCount > 0 && digitCount % 3 == 0) {
            unchecked {
                --i;
            }
            buffer[i] = ",";
        }
        unchecked {
            --i;
        }
        buffer[i] = bytes1(uint8(48 + (n % 10)));
        n /= 10;
        digitCount++;
    }

    return string(buffer);
}

function _u2s(uint256 x) pure returns (string memory) {
    if (x == 0) return "0";

    uint256 temp = x;
    uint256 digits;
    unchecked {
        while (temp != 0) {
            ++digits;
            temp /= 10;
        }
    }

    bytes memory buffer = new bytes(digits);
    unchecked {
        while (x != 0) {
            --digits;
            buffer[digits] = bytes1(uint8(48 + (x % 10)));
            x /= 10;
        }
    }
    return string(buffer);
}

function _shortHexDisplay(string memory fullHex) pure returns (string memory) {
    bytes memory full = bytes(fullHex);
    bytes memory result = new bytes(13);

    // "0x" + first 4 hex chars
    for (uint256 i = 0; i < 6; ++i) {
        result[i] = full[i];
    }

    // "..."
    result[6] = ".";
    result[7] = ".";
    result[8] = ".";

    // last 4 hex chars (works for both 0x + 40 and 0x + 64)
    uint256 len = full.length;
    for (uint256 i = 0; i < 4; ++i) {
        result[9 + i] = full[len - 4 + i];
    }

    return string(result);
}

function _svgCardBase() pure returns (string memory) {
    return string.concat(
        "<svg xmlns='http://www.w3.org/2000/svg' width='420' height='600'>",
        "<defs>",
        "<style>",
        ".garamond{font-family:'EB Garamond',serif;font-weight:400;}",
        ".garamond-bold{font-family:'EB Garamond',serif;font-weight:600;}",
        ".mono{font-family:'Courier Prime',monospace;}",
        "</style>",
        "</defs>",
        "<rect width='420' height='600' fill='#000'/>",
        "<rect x='20' y='20' width='380' height='560' fill='none' stroke='#fff' stroke-width='1'/>"
    );
}

function _jsonImage(string memory name_, string memory description_, string memory svg)
    pure
    returns (string memory)
{
    return DataURI.json(
        string.concat(
            '{"name":"',
            name_,
            '","description":"',
            description_,
            '","image":"',
            DataURI.svg(svg),
            '"}'
        )
    );
}

library DataURI {
    function json(string memory raw) internal pure returns (string memory) {
        return string.concat("data:application/json;base64,", Base64.encode(bytes(raw)));
    }

    function svg(string memory raw) internal pure returns (string memory) {
        return string.concat("data:image/svg+xml;base64,", Base64.encode(bytes(raw)));
    }
}

library Base64 {
    function encode(bytes memory data, bool fileSafe, bool noPadding)
        internal
        pure
        returns (string memory result)
    {
        assembly ("memory-safe") {
            let dataLength := mload(data)

            if dataLength {
                let encodedLength := shl(2, div(add(dataLength, 2), 3))

                result := mload(0x40)

                mstore(0x1f, "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdef")
                mstore(0x3f, xor("ghijklmnopqrstuvwxyz0123456789-_", mul(iszero(fileSafe), 0x0670)))

                let ptr := add(result, 0x20)
                let end := add(ptr, encodedLength)

                let dataEnd := add(add(0x20, data), dataLength)
                let dataEndValue := mload(dataEnd)
                mstore(dataEnd, 0x00)

                for {} 1 {} {
                    data := add(data, 3)
                    let input := mload(data)

                    mstore8(0, mload(and(shr(18, input), 0x3F)))
                    mstore8(1, mload(and(shr(12, input), 0x3F)))
                    mstore8(2, mload(and(shr(6, input), 0x3F)))
                    mstore8(3, mload(and(input, 0x3F)))
                    mstore(ptr, mload(0x00))

                    ptr := add(ptr, 4)
                    if iszero(lt(ptr, end)) { break }
                }
                mstore(dataEnd, dataEndValue)
                mstore(0x40, add(end, 0x20))
                let o := div(2, mod(dataLength, 3))
                mstore(sub(ptr, o), shl(240, 0x3d3d))
                o := mul(iszero(iszero(noPadding)), o)
                mstore(sub(ptr, o), 0)
                mstore(result, sub(encodedLength, o))
            }
        }
    }

    function encode(bytes memory data) internal pure returns (string memory result) {
        result = encode(data, false, false);
    }
}

function _receiptId(bytes32 id, uint8 support) pure returns (uint256) {
    return uint256(keccak256(abi.encodePacked("Moloch:receipt", id, support)));
}

error Overflow();

function toUint32(uint256 x) pure returns (uint32) {
    if (x >= 1 << 32) _revertOverflow();
    return uint32(x);
}

function toUint224(uint256 x) pure returns (uint224) {
    if (x >= 1 << 224) _revertOverflow();
    return uint224(x);
}

function _revertOverflow() pure {
    assembly ("memory-safe") {
        mstore(0x00, 0x35278d12)
        revert(0x1c, 0x04)
    }
}

error MulDivFailed();

function mulDiv(uint256 x, uint256 y, uint256 d) pure returns (uint256 z) {
    assembly ("memory-safe") {
        z := mul(x, y)
        if iszero(mul(or(iszero(x), eq(div(z, x), y)), d)) {
            mstore(0x00, 0xad251c27)
            revert(0x1c, 0x04)
        }
        z := div(z, d)
    }
}

/*//////////////////////////////////////////////////////////////
                         MINIMAL EXTERNALS
//////////////////////////////////////////////////////////////*/
interface IToken {
    function transfer(address, uint256) external;
    function transferFrom(address, address, uint256) external;
}

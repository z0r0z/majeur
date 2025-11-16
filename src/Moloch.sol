// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title Moloch (Majeur) — Minimally Maximalized DAO Governance Framework
 * @notice ERC-20 shares (delegatable/split) & Loot + ERC-6909 receipts + ERC-721 badges.
 *         Features: timelock, permits, futarchy, token sales, ragequit, SBT-gated chat.
 * @dev Proposals pass when FOR > AGAINST and quorum met. Snapshots at block N-1.
 */
contract Moloch {
    /* ERRORS */
    error NotOk();
    error Expired();
    error TooEarly();
    error Reentrancy();
    error AlreadyVoted();
    error LengthMismatch();
    error AlreadyExecuted();
    error Timelocked(uint64 untilWhen);

    /* MAJEUR */
    modifier onlyDAO() {
        require(msg.sender == address(this), Unauthorized());
        _;
    }

    /* STATE */
    string _orgName;
    string _orgSymbol;

    /**
     * PROPOSAL STATE
     */
    /// @dev Absolute vote thresholds (0 = disabled):
    uint96 public proposalThreshold; // minimum votes to make proposal
    uint96 public minYesVotesAbsolute; // minimum YES (FOR) votes
    uint96 public quorumAbsolute; // minimum total turnout (FOR+AGAINST+ABSTAIN)

    /// @dev Time-based settings (seconds; 0 = off):
    uint64 public proposalTTL; // proposal expiry
    uint64 public timelockDelay; // delay between success and execution

    /// @dev Governance versioning / dynamic quorum / global flags:
    uint64 public config; // bump salt to invalidate old ids/permits
    uint16 public quorumBps; // dynamic quorum vs snapshot supply (BPS, 0 = off)
    bool public ragequittable; // `true` if owners can ragequit shares

    address immutable SUMMONER = msg.sender;
    address immutable sharesImpl;
    address immutable badgesImpl;
    address immutable lootImpl;

    address public renderer;
    Shares public shares;
    Badges public badges;
    Loot public loot;

    /// @dev Proposal id = keccak(address(this), op, to, value, keccak(data), nonce, config):
    mapping(uint256 id => bool) public executed; // executed latch
    mapping(uint256 id => uint64) public createdAt; // first open/vote time
    mapping(uint256 id => uint48) public snapshotBlock; // block.number - 1
    mapping(uint256 id => uint256) public supplySnapshot; // total supply at snapshotBlock
    mapping(uint256 id => uint64) public queuedAt; // timelock queue time (0 = not queued)

    struct Tally {
        uint96 forVotes;
        uint96 againstVotes;
        uint96 abstainVotes;
    }
    mapping(uint256 id => Tally) public tallies;

    uint256[] public proposalIds;
    mapping(uint256 id => address) public proposerOf;

    /// @dev hasVoted[id][voter] = 0 = not, 1 = FOR, 2 = AGAINST, 3 = ABSTAIN:
    mapping(uint256 id => mapping(address voter => uint8)) public hasVoted;
    mapping(uint256 => mapping(address => uint96)) public voteWeight;

    enum ProposalState {
        Unopened,
        Active,
        Queued,
        Succeeded,
        Defeated,
        Expired,
        Executed
    }

    event Opened(uint256 indexed id, uint48 snapshotBlock, uint256 supplyAtSnapshot);
    event Voted(uint256 indexed id, address indexed voter, uint8 support, uint256 weight);
    event VoteCancelled(uint256 indexed id, address indexed voter, uint8 support, uint256 weight);
    event ProposalCancelled(uint256 indexed id, address indexed by);
    event Queued(uint256 indexed id, uint64 when);
    event Executed(uint256 indexed id, address indexed by, uint8 op, address to, uint256 value);

    /**
     * PERMIT STATE
     */
    event PermitSet(address spender, uint256 indexed id, uint256 newCount);
    event PermitSpent(uint256 indexed id, address indexed by, uint8 op, address to, uint256 value);

    mapping(uint256 id => bool) isPermitReceipt;
    mapping(address token => mapping(address spender => uint256 amount)) public allowance;

    /**
     * SALE STATE
     */
    struct Sale {
        uint256 pricePerShare; // in payToken units (wei for ETH)
        uint256 cap; // remaining shares (0 = unlimited)
        bool minting; // true=mint, false=transfer Moloch-held
        bool active;
        bool isLoot;
    }
    mapping(address payToken => Sale) public sales;

    event SaleUpdated(
        address indexed payToken, uint256 price, uint256 cap, bool minting, bool active, bool isLoot
    );
    event SharesPurchased(
        address indexed buyer, address indexed payToken, uint256 shares, uint256 paid
    );

    /**
     * MSG STATE
     */
    string[] public messages;
    event Message(address indexed from, uint256 indexed index, string text);

    /**
     * META STATE
     */
    /// @dev ERC6909 metadata: org name/symbol (shared across ids):
    function name(
        uint256 /*id*/
    )
        public
        view
        returns (string memory)
    {
        return _orgName;
    }

    function symbol(
        uint256 /*id*/
    )
        public
        view
        returns (string memory)
    {
        return _orgSymbol;
    }

    /// @dev The contract-level URI:
    string _orgURI;

    /**
     * ERC6909 STATE
     */
    event Transfer(
        address caller, address indexed from, address indexed to, uint256 indexed id, uint256 amount
    );

    mapping(address owner => mapping(uint256 id => uint256)) public balanceOf;
    mapping(uint256 id => uint256) public totalSupply;

    /**
     * FUTARCHY STATE
     */
    /// @dev Decode helpers for SVGs & futarchy validation:
    mapping(uint256 id => uint8) public receiptSupport; // 0=Against, 1=For, 2=Abstain
    mapping(uint256 id => uint256) public receiptProposal; // which proposal this receipt belongs to

    struct FutarchyConfig {
        bool enabled; // futarchy pot exists for this proposal
        address rewardToken; // 0 = ETH, this = minted shares, 1007 = minted loot, shares/loot = local
        uint256 pool; // funded amount (ETH or share units)
        bool resolved; // set on resolution
        uint8 winner; // 1=YES (For), 0=NO (Against)
        uint256 finalWinningSupply;
        uint256 payoutPerUnit; // (pool * 1e18 / finalWinningSupply), scaled by 1e18
    }
    mapping(uint256 id => FutarchyConfig) public futarchy;
    // 1..10_000 = BPS of `basis`,
    //             where basis = snapshot supply (shares),
    //             and + loot.totalSupply() if rewardToken is loot/1007
    // >10_000   = absolute amount in token units
    uint256 public autoFutarchyParam; // flexible auto-funding knob
    uint256 public autoFutarchyCap; // per-proposal max; 0 = no cap
    address public rewardToken;

    event FutarchyOpened(uint256 indexed id, address indexed rewardToken);
    event FutarchyFunded(uint256 indexed id, address indexed from, uint256 amount);
    event FutarchyResolved(
        uint256 indexed id, uint8 winner, uint256 pool, uint256 finalSupply, uint256 payoutPerUnit
    );
    event FutarchyClaimed(
        uint256 indexed id, address indexed claimer, uint256 burned, uint256 payout
    );

    /* INIT */
    constructor() payable {
        bytes32 _salt = bytes32(bytes20(address(this)));
        sharesImpl = address(new Shares{salt: _salt}());
        badgesImpl = address(new Badges{salt: _salt}());
        lootImpl = address(new Loot{salt: _salt}());
    }

    function init(
        string calldata orgName,
        string calldata orgSymbol,
        string calldata orgURI,
        uint16 _quorumBps, // e.g. 5000 = 50% turnout of snapshot supply
        bool _ragequittable,
        address _renderer,
        address[] calldata initHolders,
        uint256[] calldata initShares,
        Call[] calldata initCalls
    ) public payable {
        require(msg.sender == SUMMONER, Unauthorized());
        require(initHolders.length == initShares.length, LengthMismatch());

        _orgName = orgName;
        _orgSymbol = orgSymbol;
        if (bytes(orgURI).length != 0) _orgURI = orgURI;
        if (_quorumBps != 0) quorumBps = _quorumBps;
        if (_ragequittable) ragequittable = _ragequittable;
        if (_renderer != address(0)) renderer = _renderer;

        address _badges;
        address _shares;
        address _loot;
        bytes32 _salt = bytes32(bytes20(address(this)));

        badges = Badges(_badges = _init(badgesImpl, _salt));
        Badges(_badges).init();
        shares = Shares(_shares = _init(sharesImpl, _salt));
        Shares(_shares).init(initHolders, initShares);
        loot = Loot(_loot = _init(lootImpl, _salt));
        Loot(_loot).init();

        // initialization calls
        for (uint256 i; i != initCalls.length; ++i) {
            (bool ok,) = initCalls[i].target.call{value: initCalls[i].value}(initCalls[i].data);
            require(ok, NotOk());
        }
    }

    function _init(address _implementation, bytes32 _salt) internal returns (address clone) {
        assembly ("memory-safe") {
            mstore(0x24, 0x5af43d5f5f3e6029573d5ffd5b3d5ff3)
            mstore(0x14, _implementation)
            mstore(0x00, 0x602d5f8160095f39f35f5f365f5f37365f73)
            clone := create2(0, 0x0e, 0x36, _salt)
            if iszero(clone) {
                mstore(0x00, 0x30116425)
                revert(0x1c, 0x04)
            }
            mstore(0x24, 0)
        }
    }

    /* PROPOSALS */
    function proposalId(uint8 op, address to, uint256 value, bytes calldata data, bytes32 nonce)
        public
        view
        returns (uint256)
    {
        return _intentHashId(op, to, value, data, nonce);
    }

    function getProposalCount() public view returns (uint256) {
        return proposalIds.length;
    }

    /// @dev Explicitly open a proposal and fix the snapshot to the previous block,
    /// ensuring Majeur ERC20Votes-style checkpoints can be queried safely:
    function openProposal(uint256 id) public {
        if (snapshotBlock[id] != 0) return;

        Shares _shares = shares;

        uint96 threshold = proposalThreshold;
        if (threshold != 0) {
            require(_shares.getVotes(msg.sender) >= threshold, Unauthorized());
        }

        uint256 supply;
        unchecked {
            uint48 snap = toUint48(block.number - 1);
            snapshotBlock[id] = snap;
            if (createdAt[id] == 0) createdAt[id] = uint64(block.timestamp);

            supply = _shares.getPastTotalSupply(snap);
            if (supply == 0) revert TooEarly();
            supplySnapshot[id] = supply;

            // ---- registry push ----
            proposalIds.push(id);
            proposerOf[id] = msg.sender;

            emit Opened(id, snap, supply);
        }

        // auto-futarchy earmark
        {
            uint256 p = autoFutarchyParam;
            if (p != 0) {
                address rt = rewardToken;
                rt = (rt == address(0) ? address(1007) : rt);
                FutarchyConfig storage F = futarchy[id];
                if (!F.enabled) {
                    F.enabled = true;
                    F.rewardToken = rt;
                    emit FutarchyOpened(id, rt);
                }
                if (F.rewardToken == rt) {
                    Loot _loot = loot;
                    uint256 basis = supply;
                    if (rt == address(1007) || rt == address(_loot)) {
                        unchecked {
                            basis += _loot.totalSupply();
                        }
                    }
                    uint256 amt = (p <= 10_000) ? mulDiv(basis, p, 10_000) : p;
                    uint256 cap = autoFutarchyCap;
                    if (cap != 0 && amt > cap) amt = cap;
                    if (rt == address(_shares)) {
                        uint256 bal = _shares.balanceOf(address(this));
                        if (amt > bal) amt = bal;
                    } else if (rt == address(_loot)) {
                        uint256 bal = _loot.balanceOf(address(this));
                        if (amt > bal) amt = bal;
                    }
                    if (amt != 0) {
                        F.pool += amt; // earmark only
                        emit FutarchyFunded(id, address(this), amt);
                    }
                }
            }
        }
    }

    /// @dev Cast a vote for a proposal:
    /// always uses past checkpoints at the proposal’s snapshot block (no current-state fallback),
    /// auto-opens the proposal on first vote (threshold uses current votes by design):
    function castVote(uint256 id, uint8 support) public {
        if (executed[id]) revert AlreadyExecuted();
        if (support > 2) revert NotOk();

        // auto-open on first vote if unopened
        if (createdAt[id] == 0) openProposal(id);

        uint64 t0 = createdAt[id];
        uint64 ttl = proposalTTL;

        // expiry gating
        if (ttl != 0) {
            if (t0 == 0) revert NotOk();
            if (block.timestamp >= t0 + ttl) revert Expired();
        }

        if (hasVoted[id][msg.sender] != 0) revert AlreadyVoted();

        FutarchyConfig storage F = futarchy[id];
        if (F.enabled && F.resolved) revert Unauthorized();

        uint48 snap = snapshotBlock[id]; // cache snapshot
        uint96 weight = uint96(shares.getPastVotes(msg.sender, snap));
        if (weight == 0) revert Unauthorized();

        // tally
        Tally storage t = tallies[id];
        unchecked {
            if (support == 1) t.forVotes += weight;
            else if (support == 0) t.againstVotes += weight;
            else t.abstainVotes += weight;

            hasVoted[id][msg.sender] = support + 1;
            voteWeight[id][msg.sender] = weight;
        }

        // mint ERC6909 receipt and tag
        uint256 rid = _receiptId(id, support);
        if (receiptProposal[rid] == 0) {
            receiptSupport[rid] = support;
            receiptProposal[rid] = id;
        }
        _mint6909(msg.sender, rid, weight);

        emit Voted(id, msg.sender, support, weight);
    }

    function cancelVote(uint256 id) public {
        unchecked {
            if (state(id) != ProposalState.Active) revert NotOk();

            uint8 hv = hasVoted[id][msg.sender];
            if (hv == 0) revert NotOk(); // nothing to cancel
            uint8 support = hv - 1;

            uint96 weight = voteWeight[id][msg.sender];
            if (weight == 0) revert Unauthorized();
            uint256 rid = _receiptId(id, support);
            _burn6909(msg.sender, rid, weight);

            Tally storage t = tallies[id];
            if (support == 1) t.forVotes -= weight;
            else if (support == 0) t.againstVotes -= weight;
            else t.abstainVotes -= weight;

            delete hasVoted[id][msg.sender];
            delete voteWeight[id][msg.sender];

            emit VoteCancelled(id, msg.sender, support, weight);
        }
    }

    function cancelProposal(uint256 id) public {
        require(msg.sender == proposerOf[id], Unauthorized());
        if (state(id) != ProposalState.Active) revert NotOk();
        if (queuedAt[id] != 0) revert NotOk();

        Tally memory t = tallies[id];
        if ((t.forVotes | t.againstVotes | t.abstainVotes) != 0) revert NotOk();

        FutarchyConfig memory F = futarchy[id];
        if (F.enabled && F.pool != 0) revert NotOk();
        executed[id] = true; // tombstone intent id
        emit ProposalCancelled(id, msg.sender);
    }

    function state(uint256 id) public view returns (ProposalState) {
        if (executed[id]) return ProposalState.Executed;

        uint64 t0 = createdAt[id];
        if (t0 == 0) return ProposalState.Unopened;
        uint64 queued = queuedAt[id];

        // if already queued, TTL no longer applies
        if (queued != 0) {
            uint64 delay = timelockDelay;
            // if delay is zero, this condition is always false once block.timestamp >= queued
            if (delay != 0 && block.timestamp < queued + delay) return ProposalState.Queued;
        } else {
            uint64 ttl = proposalTTL;
            if (ttl != 0 && block.timestamp >= t0 + ttl) return ProposalState.Expired;
        }

        // evaluate gates
        uint256 ts = supplySnapshot[id];
        if (ts == 0) return ProposalState.Active;

        Tally storage t = tallies[id];
        uint256 forVotes = t.forVotes;
        uint256 againstVotes = t.againstVotes;
        uint256 abstainVotes = t.abstainVotes;

        unchecked {
            uint256 totalCast = forVotes + againstVotes + abstainVotes;

            // absolute quorum
            uint96 absQuorum = quorumAbsolute;
            if (absQuorum != 0 && totalCast < absQuorum) return ProposalState.Active;

            // dynamic quorum (BPS)
            uint16 bps = quorumBps;
            if (bps != 0 && totalCast < mulDiv(uint256(bps), ts, 10000)) {
                return ProposalState.Active;
            }
        }

        // absolute YES floor
        uint96 minYes = minYesVotesAbsolute;
        if (minYes != 0 && forVotes < minYes) return ProposalState.Defeated;
        if (forVotes <= againstVotes) return ProposalState.Defeated;

        return ProposalState.Succeeded;
    }

    /// @dev Queue a passing proposal (sets timelock countdown). If no timelock, no-op:
    function queue(uint256 id) public {
        if (state(id) != ProposalState.Succeeded) revert NotOk();
        if (timelockDelay == 0) return;
        if (queuedAt[id] == 0) {
            queuedAt[id] = uint64(block.timestamp);
            emit Queued(id, queuedAt[id]);
        }
    }

    /* EXECUTE */
    /// @dev Execute when the proposal is ready (handles immediate or timelocked):
    function executeByVotes(
        uint8 op, // 0 = call, 1 = delegatecall
        address to,
        uint256 value,
        bytes calldata data,
        bytes32 nonce
    ) public payable nonReentrant returns (bool ok, bytes memory retData) {
        uint256 id = _intentHashId(op, to, value, data, nonce);

        if (executed[id]) revert AlreadyExecuted();

        ProposalState st = state(id);

        // only Succeeded or Queued proposals are allowed through
        if (st != ProposalState.Succeeded && st != ProposalState.Queued) revert NotOk();

        if (timelockDelay != 0) {
            if (queuedAt[id] == 0) {
                queuedAt[id] = uint64(block.timestamp);
                emit Queued(id, queuedAt[id]);
                return (true, "");
            }
            uint64 untilWhen = queuedAt[id] + timelockDelay;
            if (block.timestamp < untilWhen) revert Timelocked(untilWhen);
        }

        executed[id] = true;

        (ok, retData) = _execute(op, to, value, data);
        // futarchy: YES (FOR) side wins upon success
        _resolveFutarchyYes(id);
        emit Executed(id, msg.sender, op, to, value);
    }

    /**
     * FUTARCHY
     */
    function fundFutarchy(uint256 id, address token, uint256 amount) public payable {
        if (amount == 0) revert NotOk();
        if (
            token != address(0) && token != address(this) && token != address(1007)
                && token != address(shares) && token != address(loot)
        ) {
            revert Unauthorized();
        }

        FutarchyConfig storage F = futarchy[id];
        if (F.resolved) revert NotOk();
        if (snapshotBlock[id] == 0) openProposal(id);

        // choose the reward token once
        address rt;
        if (!F.enabled) {
            // if governance set a global default, enforce it; else use the first funder's choice
            address preset = rewardToken;
            rt = (preset != address(0)) ? preset : token;
            if (preset != address(0) && token != preset) revert NotOk(); // must match preset
            F.enabled = true;
            F.rewardToken = rt;
            emit FutarchyOpened(id, rt);
        } else {
            rt = F.rewardToken;
            if (token != rt) revert NotOk(); // all later fundings must match
        }

        // pull funds according to the authoritative rt
        if (rt == address(0)) {
            if (msg.value != amount) revert NotOk();
        } else if (rt == address(this) || rt == address(1007)) {
            if (msg.value != 0) revert NotOk();
            if (msg.sender != address(this)) revert Unauthorized();
        } else {
            if (msg.value != 0) revert NotOk();
            safeTransferFrom(rt, amount);
        }

        F.pool += amount;
        emit FutarchyFunded(id, msg.sender, amount);
    }

    function resolveFutarchyNo(uint256 id) public {
        FutarchyConfig storage F = futarchy[id];
        if (!F.enabled || F.resolved || executed[id]) revert NotOk();

        ProposalState st = state(id);
        if (st != ProposalState.Defeated && st != ProposalState.Expired) revert NotOk();

        _finalizeFutarchy(id, F, 0);
    }

    function cashOutFutarchy(uint256 id, uint256 amount)
        public
        nonReentrant
        returns (uint256 payout)
    {
        FutarchyConfig storage F = futarchy[id];
        if (!F.enabled || !F.resolved) revert NotOk();

        uint8 winner = F.winner; // 1 or 0
        uint256 rid = _receiptId(id, winner);

        _burn6909(msg.sender, rid, amount);

        payout = mulDiv(amount, F.payoutPerUnit, 1e18);
        if (payout == 0) {
            emit FutarchyClaimed(id, msg.sender, amount, 0);
            return 0;
        }

        _payout(F.rewardToken, msg.sender, payout);
        emit FutarchyClaimed(id, msg.sender, amount, payout);
    }

    function _resolveFutarchyYes(uint256 id) internal {
        FutarchyConfig storage F = futarchy[id];
        if (!F.enabled || F.resolved) return;
        _finalizeFutarchy(id, F, 1);
    }

    function _finalizeFutarchy(uint256 id, FutarchyConfig storage F, uint8 winner) internal {
        unchecked {
            uint256 rid = _receiptId(id, winner);
            uint256 winSupply = totalSupply[rid];
            uint256 pool = F.pool;
            uint256 ppu;
            if (winSupply != 0 && pool != 0) {
                F.finalWinningSupply = winSupply;
                ppu = mulDiv(pool, 1e18, winSupply); // scaled by 1e18
                F.payoutPerUnit = ppu;
            }

            F.resolved = true;
            F.winner = winner;

            emit FutarchyResolved(id, winner, pool, winSupply, ppu);
        }
    }

    /* PERMIT */
    function setPermit(
        uint8 op,
        address to,
        uint256 value,
        bytes calldata data,
        bytes32 nonce,
        address spender,
        uint256 count
    ) public payable onlyDAO {
        uint256 tokenId = _intentHashId(op, to, value, data, nonce);
        isPermitReceipt[tokenId] = true;
        uint256 bal = balanceOf[spender][tokenId];
        uint256 diff;

        unchecked {
            if (count > bal) {
                diff = count - bal;
                _mint6909(spender, tokenId, diff);
            } else if (count < bal) {
                diff = bal - count;
                _burn6909(spender, tokenId, diff);
            }
        }

        emit PermitSet(spender, tokenId, count);
    }

    function spendPermit(uint8 op, address to, uint256 value, bytes calldata data, bytes32 nonce)
        public
        payable
        nonReentrant
        returns (bool ok, bytes memory retData)
    {
        uint256 tokenId = _intentHashId(op, to, value, data, nonce);
        require(isPermitReceipt[tokenId], Unauthorized());

        executed[tokenId] = true;

        _burn6909(msg.sender, tokenId, 1);

        (ok, retData) = _execute(op, to, value, data);

        if (futarchy[tokenId].enabled) _resolveFutarchyYes(tokenId);
        emit PermitSpent(tokenId, msg.sender, op, to, value);
    }

    /**
     * ALLOWANCE
     */
    function setAllowance(address spender, address token, uint256 amount) public payable onlyDAO {
        allowance[token][spender] = amount;
    }

    function spendAllowance(address token, uint256 amount) public nonReentrant {
        allowance[token][msg.sender] -= amount;
        _payout(token, msg.sender, amount);
    }

    /* SALE */
    function setSale(
        address payToken,
        uint256 pricePerShare,
        uint256 cap,
        bool minting,
        bool active,
        bool isLoot
    ) public payable onlyDAO {
        require(pricePerShare != 0, NotOk());
        sales[payToken] = Sale({
            pricePerShare: pricePerShare, cap: cap, minting: minting, active: active, isLoot: isLoot
        });
        emit SaleUpdated(payToken, pricePerShare, cap, minting, active, isLoot);
    }

    function buyShares(address payToken, uint256 shareAmount, uint256 maxPay)
        public
        payable
        nonReentrant
    {
        if (shareAmount == 0) revert NotOk();
        Sale storage s = sales[payToken];
        if (!s.active) revert NotOk();

        uint256 cap = s.cap;
        if (cap != 0 && shareAmount > cap) revert NotOk();

        uint256 price = s.pricePerShare;
        uint256 cost = shareAmount * price;

        if (maxPay != 0 && cost > maxPay) revert NotOk();

        // EFFECTS (CEI)
        if (cap != 0) {
            unchecked {
                s.cap = cap - shareAmount;
            }
        }

        // pull funds
        if (payToken == address(0)) {
            require(msg.value >= cost, NotOk());
            if (msg.value > cost) {
                unchecked {
                    safeTransferETH(msg.sender, msg.value - cost);
                }
            }
        } else {
            // ERC20 path
            if (msg.value != 0) revert NotOk();
            safeTransferFrom(payToken, cost);
        }

        // issue shares/loot
        if (s.minting) {
            s.isLoot
                ? loot.mintFromMoloch(msg.sender, shareAmount)
                : shares.mintFromMoloch(msg.sender, shareAmount);
        } else {
            s.isLoot
                ? loot.transfer(msg.sender, shareAmount)
                : shares.transfer(msg.sender, shareAmount);
        }

        emit SharesPurchased(msg.sender, payToken, shareAmount, cost);
    }

    /* RAGEQUIT */
    function ragequit(address[] calldata tokens, uint256 sharesToBurn, uint256 lootToBurn)
        public
        nonReentrant
    {
        uint256 amt = sharesToBurn + lootToBurn;
        unchecked {
            if (!ragequittable) revert NotOk();
            require(tokens.length != 0, LengthMismatch());
            if (sharesToBurn == 0 && lootToBurn == 0) revert NotOk();

            Shares _shares = shares;
            Loot _loot = loot;

            uint256 total = _shares.totalSupply() + _loot.totalSupply();
            if (sharesToBurn != 0) _shares.burnFromMoloch(msg.sender, sharesToBurn);
            if (lootToBurn != 0) _loot.burnFromMoloch(msg.sender, lootToBurn);

            address prev;
            address tk;
            uint256 pool;
            uint256 due;
            for (uint256 i; i != tokens.length; ++i) {
                tk = tokens[i];
                require(tk != address(shares), Unauthorized());
                require(tk != address(loot), Unauthorized());
                require(tk != address(this), Unauthorized());
                require(tk != address(1007), Unauthorized());

                if (i != 0 && tk <= prev) revert NotOk();
                prev = tk;

                pool = tk == address(0) ? address(this).balance : balanceOfThis(tk);
                due = mulDiv(pool, amt, total);
                if (due == 0) continue;

                _payout(tk, msg.sender, due);
            }
        }
    }

    /* CHATROOM */
    function getMessageCount() public view returns (uint256) {
        return messages.length;
    }

    function chat(string calldata message) public payable {
        unchecked {
            require(badges.balanceOf(msg.sender) != 0, Unauthorized());
            messages.push(message);
            emit Message(msg.sender, messages.length - 1, message);
        }
    }

    /* SETTINGS */
    function setQuorumBps(uint16 bps) public payable onlyDAO {
        if (bps > 10_000) revert NotOk();
        quorumBps = bps;
    }

    function setMinYesVotesAbsolute(uint96 v) public payable onlyDAO {
        minYesVotesAbsolute = v;
    }

    function setQuorumAbsolute(uint96 v) public payable onlyDAO {
        quorumAbsolute = v;
    }

    function setProposalTTL(uint64 s) public payable onlyDAO {
        proposalTTL = s;
    }

    function setTimelockDelay(uint64 s) public payable onlyDAO {
        timelockDelay = s;
    }

    function setRagequittable(bool on) public payable onlyDAO {
        ragequittable = on;
    }

    function setTransfersLocked(bool sharesLocked, bool lootLocked) public payable onlyDAO {
        shares.setTransfersLocked(sharesLocked);
        loot.setTransfersLocked(lootLocked);
    }

    function setProposalThreshold(uint96 v) public payable onlyDAO {
        proposalThreshold = v;
    }

    function setRenderer(address r) public payable onlyDAO {
        renderer = r;
    }

    function setMetadata(string calldata n, string calldata s, string calldata uri)
        public
        payable
        onlyDAO
    {
        (_orgName, _orgSymbol, _orgURI) = (n, s, uri);
    }

    /// @dev Configure automatic futarchy earmark per proposal:
    /// @param param 0 = off; 1..10_000 = BPS of basis (snapshot share supply,
    /// plus loot supply if rewardToken is loot/1007); >10_000 = absolute token amount
    /// @param cap Hard per-proposal cap applied after param calculation (0 = no cap)
    function setAutoFutarchy(uint256 param, uint256 cap) public payable onlyDAO {
        (autoFutarchyParam, autoFutarchyCap) = (param, cap);
    }

    /// @dev Default reward token for futarchy pools:
    function setFutarchyRewardToken(address _rewardToken) public payable onlyDAO {
        if (
            _rewardToken != address(0) && _rewardToken != address(this)
                && _rewardToken != address(1007) && _rewardToken != address(shares)
                && _rewardToken != address(loot)
        ) revert NotOk();
        rewardToken = _rewardToken;
    }

    /// @dev Governance "bump" to invalidate pre-bump proposal hashes:
    function bumpConfig() public payable onlyDAO {
        unchecked {
            ++config;
        }
    }

    /// @dev Governance batch external call helper:
    function batchCalls(Call[] calldata calls) public payable onlyDAO {
        for (uint256 i; i != calls.length; ++i) {
            (bool ok,) = calls[i].target.call{value: calls[i].value}(calls[i].data);
            require(ok, NotOk());
        }
    }

    /// @dev Execute sequence of calls to this Majeur contract:
    function multicall(bytes[] calldata data) public returns (bytes[] memory results) {
        results = new bytes[](data.length);
        for (uint256 i; i != data.length; ++i) {
            (bool success, bytes memory result) = address(this).delegatecall(data[i]);
            if (!success) {
                assembly ("memory-safe") {
                    revert(add(result, 0x20), mload(result))
                }
            }
            results[i] = result;
        }
    }

    function onSharesChanged(address a) public payable {
        require(msg.sender == address(shares), Unauthorized());
        badges.onSharesChanged(a);
    }

    /*ERC-6909*/
    event OperatorSet(address indexed owner, address indexed operator, bool approved);
    mapping(address owner => mapping(address operator => bool)) public isOperator;

    function transfer(address receiver, uint256 id, uint256 amount) public returns (bool) {
        if (isPermitReceipt[id]) revert SBT();
        balanceOf[msg.sender][id] -= amount;
        unchecked {
            balanceOf[receiver][id] += amount;
        }
        emit Transfer(msg.sender, msg.sender, receiver, id, amount);
        return true;
    }

    function transferFrom(address sender, address receiver, uint256 id, uint256 amount)
        public
        returns (bool)
    {
        if (isPermitReceipt[id]) revert SBT();
        require(msg.sender == sender || isOperator[sender][msg.sender], Unauthorized());
        balanceOf[sender][id] -= amount;
        unchecked {
            balanceOf[receiver][id] += amount;
        }
        emit Transfer(msg.sender, sender, receiver, id, amount);
        return true;
    }

    function setOperator(address operator, bool approved) public returns (bool) {
        isOperator[msg.sender][operator] = approved;
        emit OperatorSet(msg.sender, operator, approved);
        return true;
    }

    function _mint6909(address to, uint256 id, uint256 amount) internal {
        totalSupply[id] += amount;
        unchecked {
            balanceOf[to][id] += amount;
        }
        emit Transfer(msg.sender, address(0), to, id, amount);
    }

    function _burn6909(address from, uint256 id, uint256 amount) internal {
        balanceOf[from][id] -= amount;
        unchecked {
            totalSupply[id] -= amount;
        }
        emit Transfer(msg.sender, from, address(0), id, amount);
    }

    /*UTILS*/
    function _receiptId(uint256 id, uint8 support) internal pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked("Moloch:receipt", id, support)));
    }

    function _intentHashId(uint8 op, address to, uint256 value, bytes calldata data, bytes32 nonce)
        internal
        view
        returns (uint256)
    {
        return uint256(
            keccak256(abi.encode(address(this), op, to, value, keccak256(data), nonce, config))
        );
    }

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

    function _payout(address token, address to, uint256 amount) internal {
        if (amount == 0) return;
        if (token == address(0)) {
            safeTransferETH(to, amount);
        } else if (token == address(this)) {
            shares.mintFromMoloch(to, amount);
        } else if (token == address(1007)) {
            loot.mintFromMoloch(to, amount);
        } else {
            safeTransfer(token, to, amount);
        }
    }

    uint256 constant REENTRANCY_GUARD_SLOT = 0x929eee149b4bd21268;

    modifier nonReentrant() virtual {
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

    /* URI */
    function contractURI() public view returns (string memory) {
        string memory orgURI = _orgURI;
        if (bytes(orgURI).length != 0) return orgURI;
        address _r = renderer;
        if (_r == address(0)) return "";
        return IMajeurRenderer(_r).daoContractURI(this);
    }

    function tokenURI(uint256 id) public view returns (string memory) {
        address _r = renderer;
        if (_r == address(0)) return "";
        return IMajeurRenderer(_r).daoTokenURI(this, id);
    }

    /* RECEIVERS */
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
}

contract Shares {
    /* ERRORS */
    error BadBlock();
    error SplitLen();
    error SplitSum();
    error SplitZero();
    error SplitDupe();

    /* ERC20 */
    event Approval(address indexed from, address indexed to, uint256 amount);
    event Transfer(address indexed from, address indexed to, uint256 amount);

    uint8 public constant decimals = 18;

    bool public transfersLocked;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    /* MAJEUR */
    address payable public DAO;

    modifier onlyDAO() {
        require(msg.sender == DAO, Unauthorized());
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
        uint48 fromBlock;
        uint96 votes;
    }

    mapping(address delegator => address primaryDelegate) internal _delegates;
    mapping(address delegate => Checkpoint[] voteHistory) internal _checkpoints;
    Checkpoint[] internal _totalSupplyCheckpoints; // total supply history

    /* --------- Split (sharded) delegation (non-custodial) --------- */

    struct Split {
        address delegate;
        uint32 bps; // parts per 10_000
    }

    uint8 constant MAX_SPLITS = 4;
    uint32 constant BPS_DENOM = 10_000;

    mapping(address delegator => Split[] splitConfig) internal _splits;

    event WeightedDelegationSet(address indexed delegator, address[] delegates, uint32[] bps);

    constructor() payable {}

    function init(address[] memory initHolders, uint256[] memory initShares) public payable {
        require(DAO == address(0), Unauthorized());
        DAO = payable(msg.sender);

        for (uint256 i; i != initHolders.length; ++i) {
            _mint(initHolders[i], initShares[i]);
            _autoSelfDelegate(initHolders[i]);
            _afterVotingBalanceChange(initHolders[i], int256(initShares[i]));
        }
    }

    function name() public view returns (string memory) {
        return string.concat(Moloch(DAO).name(0), " Shares");
    }

    function symbol() public view returns (string memory) {
        return Moloch(DAO).symbol(0);
    }

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
        if (allowed != type(uint256).max) allowance[from][msg.sender] = allowed - amount;

        _moveTokens(from, to, amount);
        return true;
    }

    function setTransfersLocked(bool locked) public payable onlyDAO {
        transfersLocked = locked;
    }

    function mintFromMoloch(address to, uint256 amount) public payable onlyDAO {
        _mint(to, amount);
        _autoSelfDelegate(to);
        _afterVotingBalanceChange(to, int256(amount));
    }

    function burnFromMoloch(address from, uint256 amount) public payable onlyDAO {
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
        totalSupply += amount;
        unchecked {
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
        unchecked {
            uint256 len = ckpts.length;
            uint256 oldVal = len == 0 ? 0 : ckpts[len - 1].votes;
            uint256 newVal = add ? oldVal + amount : oldVal - amount;
            if (oldVal == newVal) return;

            _writeCheckpoint(ckpts, oldVal, newVal);
            emit DelegateVotesChanged(delegate_, oldVal, newVal);
        }
    }

    function _checkUnlocked(address from, address to) internal view {
        if (transfersLocked && from != DAO && to != DAO) {
            revert Locked();
        }
    }

    function delegates(address account) public view returns (address) {
        address del = _delegates[account];
        return del == address(0) ? account : del; // default to self
    }

    function delegate(address delegatee) public {
        _delegate(msg.sender, delegatee);
    }

    function getVotes(address account) public view returns (uint256) {
        unchecked {
            Checkpoint[] storage ckpts = _checkpoints[account];
            uint256 n = ckpts.length;
            return n == 0 ? 0 : ckpts[n - 1].votes;
        }
    }

    function getPastVotes(address account, uint48 blockNumber) public view returns (uint256) {
        if (blockNumber >= block.number) revert BadBlock();
        return _checkpointsLookup(_checkpoints[account], blockNumber);
    }

    function getPastTotalSupply(uint48 blockNumber) public view returns (uint256) {
        if (blockNumber >= block.number) revert BadBlock();
        return _checkpointsLookup(_totalSupplyCheckpoints, blockNumber);
    }

    /// @dev Returns the effective split delegation of an account
    /// (defaults to 100% self if no splits set):
    function splitDelegationOf(address account)
        public
        view
        returns (address[] memory delegates_, uint32[] memory bps_)
    {
        return _currentDistribution(account);
    }

    function setSplitDelegation(address[] calldata delegates_, uint32[] calldata bps_) public {
        address account = msg.sender;
        uint256 n = delegates_.length;
        require(n == bps_.length && n > 0 && n <= MAX_SPLITS, SplitLen());

        // capture the current effective distribution BEFORE we mutate storage
        (address[] memory oldD, uint32[] memory oldB) = _currentDistribution(account);

        uint256 sum;
        for (uint256 i; i != n; ++i) {
            address d = delegates_[i];
            require(d != address(0), SplitZero());
            uint32 b = bps_[i];
            sum += b;

            // no duplicate delegates
            for (uint256 j = i + 1; j != n; ++j) {
                require(d != delegates_[j], SplitDupe());
            }
        }
        require(sum == BPS_DENOM, SplitSum());

        // ensure the account has a primary delegate line (defaults to self once)
        _autoSelfDelegate(account);

        // write the new split set.
        delete _splits[account];
        for (uint256 i; i != n; ++i) {
            _splits[account].push(Split({delegate: delegates_[i], bps: bps_[i]}));
        }

        // move only the difference in voting power from the old distribution to the new one
        _repointVotesForHolder(account, oldD, oldB);

        emit WeightedDelegationSet(account, delegates_, bps_);
    }

    function clearSplitDelegation() public {
        address account = msg.sender;

        // already single-delegate mode; nothing to do
        if (_splits[account].length == 0) return;

        // capture the current split BEFORE we mutate storage
        (address[] memory oldD, uint32[] memory oldB) = _currentDistribution(account);

        // collapse to single 100% delegate (primary; defaults to self)
        delete _splits[account];
        _autoSelfDelegate(account);

        // repoint existing votes from the old split back to the single delegate
        _repointVotesForHolder(account, oldD, oldB);

        // emit the canonical 100% distribution for tooling/UX
        address[] memory d = _singleton(delegates(account));
        uint32[] memory b = _singletonBps();
        emit WeightedDelegationSet(account, d, b);
    }

    function _delegate(address delegator, address delegatee) internal {
        address account = delegator;
        if (delegatee == address(0)) delegatee = account;

        // inline `delegates(account)` to avoid extra call
        address current = _delegates[account];
        if (current == address(0)) current = account;

        Split[] storage sp = _splits[account];
        uint256 splitsLen = sp.length;

        // if no change and no split configured, nothing to do
        if (splitsLen == 0 && current == delegatee) return;

        // capture the current effective distribution BEFORE we mutate storage
        (address[] memory oldD, uint32[] memory oldB) = _currentDistribution(account);

        // collapse any existing split and set the new primary delegate
        if (splitsLen != 0) delete _splits[account];

        _delegates[account] = delegatee;

        emit DelegateChanged(account, current, delegatee);

        // repoint the holder’s current voting power from old distribution to the new single delegate
        _repointVotesForHolder(account, oldD, oldB);
    }

    function _autoSelfDelegate(address account) internal {
        if (_delegates[account] == address(0)) {
            _delegates[account] = account;
            emit DelegateChanged(account, address(0), account);
            // checkpoints are updated only via _applyVotingDelta / _repointVotesForHolder
        }
    }

    /// @dev Returns the current split (or a single 100% primary delegate if unset):
    function _currentDistribution(address account)
        internal
        view
        returns (address[] memory delegates_, uint32[] memory bps_)
    {
        Split[] storage sp = _splits[account];
        uint256 n = sp.length;

        if (n == 0) {
            // small single-element array
            delegates_ = new address[](1);
            delegates_[0] = delegates(account);
            bps_ = new uint32[](1);
            bps_[0] = BPS_DENOM;
            return (delegates_, bps_);
        }

        // pre-sized allocation
        delegates_ = new address[](n);
        bps_ = new uint32[](n);
        for (uint256 i; i != n; ++i) {
            delegates_[i] = sp[i].delegate;
            bps_[i] = sp[i].bps;
        }
    }

    function _afterVotingBalanceChange(address account, int256 delta) internal {
        _applyVotingDelta(account, delta);
        Moloch(DAO).onSharesChanged(account);
    }

    /// @dev Apply +/- voting power change for an account according to its split,
    ///      in a *path-independent* way based on old vs new target allocations:
    function _applyVotingDelta(address account, int256 delta) internal {
        if (delta == 0) return;

        // we are always called *after* balanceOf[account] has been updated
        uint256 balAfter = balanceOf[account];
        uint256 balBefore;

        if (delta > 0) {
            // Mint / incoming transfer:
            // newBalance = oldBalance + delta  =>  oldBalance = newBalance - delta
            uint256 absDelta = uint256(delta);
            balBefore = balAfter - absDelta;
        } else {
            // Burn / outgoing transfer:
            // newBalance = oldBalance - |delta|  =>  oldBalance = newBalance + |delta|
            uint256 absDelta = uint256(-delta);
            balBefore = balAfter + absDelta;
        }

        (address[] memory D, uint32[] memory B) = _currentDistribution(account);
        uint256 len = D.length;
        if (len == 0) return; // should never happen

        uint256[] memory oldA = _targetAlloc(balBefore, D, B);
        uint256[] memory newA = _targetAlloc(balAfter, D, B);

        for (uint256 i; i != len; ++i) {
            uint256 oldAmt = oldA[i];
            uint256 newAmt = newA[i];

            if (newAmt > oldAmt) {
                _moveVotingPower(address(0), D[i], newAmt - oldAmt);
            } else if (oldAmt > newAmt) {
                _moveVotingPower(D[i], address(0), oldAmt - newAmt);
            }
        }
    }

    /// @dev Re-route an existing holder's current voting power from `old` distribution to
    ///      the holder's *current* distribution (as returned by _currentDistribution),
    ///      in a path-independent way based on old vs new target allocations:
    function _repointVotesForHolder(address holder, address[] memory oldD, uint32[] memory oldB)
        internal
    {
        uint256 bal = balanceOf[holder];
        if (bal == 0) return;

        // new distribution after the caller updated _splits / _delegates
        (address[] memory newD, uint32[] memory newB) = _currentDistribution(holder);

        uint256 oldLen = oldD.length;
        uint256 newLen = newD.length;

        // if distributions are identical (same delegates + weights), nothing to do
        if (oldLen == newLen) {
            bool same = true;
            for (uint256 i; i < oldLen; ++i) {
                if (oldD[i] != newD[i] || oldB[i] != newB[i]) {
                    same = false;
                    break;
                }
            }
            if (same) return;
        }

        // compute old & new target allocations for this holder
        uint256[] memory oldA = _targetAlloc(bal, oldD, oldB);
        uint256[] memory newA = _targetAlloc(bal, newD, newB);

        // 1) handle all delegates that existed in the old distribution:
        //    - if also in new, move delta
        //    - if not in new, move full oldAmt -> 0
        for (uint256 i; i < oldLen; ++i) {
            address d = oldD[i];
            uint256 oldAmt = oldA[i];
            uint256 newAmt;

            // find matching delegate in newD (if any)
            for (uint256 j; j < newLen; ++j) {
                if (newD[j] == d) {
                    newAmt = newA[j];
                    newD[j] = address(0);
                    break;
                }
            }

            if (newAmt > oldAmt) {
                _moveVotingPower(address(0), d, newAmt - oldAmt);
            } else if (oldAmt > newAmt) {
                _moveVotingPower(d, address(0), oldAmt - newAmt);
            }
        }

        // 2) any delegates still left in newD (non-zero) are new-only;
        //    they had oldAmt = 0, so just add their newAmt
        for (uint256 j; j < newLen; ++j) {
            address d = newD[j];
            if (d == address(0)) continue; // already handled above

            uint256 newAmt = newA[j];
            if (newAmt != 0) {
                _moveVotingPower(address(0), d, newAmt);
            }
        }
    }

    /// @dev Helper: exact target allocation with "remainder to last":
    function _targetAlloc(uint256 bal, address[] memory D, uint32[] memory B)
        internal
        pure
        returns (uint256[] memory A)
    {
        uint256 n = D.length;
        A = new uint256[](n);
        uint256 remaining = bal;
        for (uint256 i; i != n; ++i) {
            if (i == n - 1) {
                A[i] = remaining;
                break;
            }
            uint256 part = mulDiv(bal, B[i], BPS_DENOM);
            A[i] = part;
            remaining -= part;
        }
    }

    /* ---------- Core checkpoint machinery ---------- */

    function _moveVotingPower(address src, address dst, uint256 amount) internal {
        if (src == dst || amount == 0) return;
        if (src != address(0)) _updateDelegateVotes(src, _checkpoints[src], false, amount);
        if (dst != address(0)) _updateDelegateVotes(dst, _checkpoints[dst], true, amount);
    }

    function _writeCheckpoint(Checkpoint[] storage ckpts, uint256 oldVal, uint256 newVal) internal {
        unchecked {
            if (oldVal == newVal) return;

            uint48 blk = toUint48(block.number);
            uint256 len = ckpts.length;

            if (len != 0) {
                Checkpoint storage last = ckpts[len - 1];

                // if we've already written this block, just update it
                if (last.fromBlock == blk) {
                    last.votes = toUint96(newVal);
                    return;
                }

                // if the last checkpoint already has this value, skip pushing duplicate
                if (last.votes == newVal) return;
            }

            ckpts.push(Checkpoint({fromBlock: blk, votes: toUint96(newVal)}));
        }
    }

    function _writeTotalSupplyCheckpoint() internal {
        unchecked {
            Checkpoint[] storage ckpts = _totalSupplyCheckpoints;
            uint256 len = ckpts.length;

            uint256 oldVal = len == 0 ? 0 : ckpts[len - 1].votes;
            uint256 newVal = totalSupply;

            _writeCheckpoint(ckpts, oldVal, newVal);
        }
    }

    function _checkpointsLookup(Checkpoint[] storage ckpts, uint48 blockNumber)
        internal
        view
        returns (uint256)
    {
        unchecked {
            uint256 len = ckpts.length;
            if (len == 0) return 0;

            // most recent
            Checkpoint storage last = ckpts[len - 1];
            if (last.fromBlock <= blockNumber) {
                return last.votes;
            }

            // before first
            if (ckpts[0].fromBlock > blockNumber) {
                return 0;
            }

            uint256 low;
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

contract Loot {
    /* ERC20 */
    event Approval(address indexed from, address indexed to, uint256 amount);
    event Transfer(address indexed from, address indexed to, uint256 amount);

    uint8 public constant decimals = 18;

    bool public transfersLocked;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    /* MAJEUR */
    address payable public DAO;

    modifier onlyDAO() {
        require(msg.sender == DAO, Unauthorized());
        _;
    }

    constructor() payable {}

    function init() public payable {
        require(DAO == address(0), Unauthorized());
        DAO = payable(msg.sender);
    }

    function name() public view returns (string memory) {
        return string.concat(Moloch(DAO).name(0), " Loot");
    }

    function symbol() public view returns (string memory) {
        return Moloch(DAO).symbol(0);
    }

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
        if (allowed != type(uint256).max) allowance[from][msg.sender] = allowed - amount;

        _moveTokens(from, to, amount);
        return true;
    }

    function setTransfersLocked(bool locked) public payable onlyDAO {
        transfersLocked = locked;
    }

    function mintFromMoloch(address to, uint256 amount) public payable onlyDAO {
        _mint(to, amount);
    }

    function burnFromMoloch(address from, uint256 amount) public payable onlyDAO {
        balanceOf[from] -= amount;
        unchecked {
            totalSupply -= amount;
        }
        emit Transfer(from, address(0), amount);
    }

    function _mint(address to, uint256 amount) internal {
        totalSupply += amount;
        unchecked {
            balanceOf[to] += amount;
        }
        emit Transfer(address(0), to, amount);
    }

    function _moveTokens(address from, address to, uint256 amount) internal {
        balanceOf[from] -= amount;
        unchecked {
            balanceOf[to] += amount;
        }
        emit Transfer(from, to, amount);
    }

    function _checkUnlocked(address from, address to) internal view {
        if (transfersLocked && from != DAO && to != DAO) {
            revert Locked();
        }
    }
}

contract Badges {
    /* ERC721-ish */
    event Transfer(address indexed from, address indexed to, uint256 indexed id);

    /* MAJEUR */
    address payable public DAO;

    /// @dev ERC721-ish SBT state:
    mapping(uint256 id => address) _ownerOf;
    mapping(address id => uint256) public seatOf;
    mapping(address id => uint256) public balanceOf;

    modifier onlyDAO() {
        require(msg.sender == DAO, Unauthorized());
        _;
    }

    error Minted();
    error NotMinted();

    constructor() payable {}

    function init() public payable {
        require(DAO == address(0), Unauthorized());
        DAO = payable(msg.sender);
    }

    /// @dev Dynamic metadata from Majeur:
    function name() public view returns (string memory) {
        return string.concat(Moloch(DAO).name(0), " Badges");
    }

    function symbol() public view returns (string memory) {
        return string.concat(Moloch(DAO).symbol(0), "B");
    }

    function ownerOf(uint256 id) public view returns (address o) {
        o = _ownerOf[id];
        require(o != address(0), NotMinted());
    }

    function supportsInterface(bytes4 interfaceId) public pure returns (bool) {
        return interfaceId == 0x01ffc9a7 // ERC165
            || interfaceId == 0x80ac58cd // ERC721
            || interfaceId == 0x5b5e139f; // ERC721Metadata
    }

    function transferFrom(address, address, uint256) public pure {
        revert SBT();
    }

    /// @dev seat: 1..256:
    function mintSeat(address to, uint16 seat) public payable onlyDAO {
        uint256 id = uint256(seat);
        require(seat >= 1 && seat <= 256, NotMinted());
        require(to != address(0) && _ownerOf[id] == address(0) && balanceOf[to] == 0, Minted());
        _ownerOf[id] = to;
        balanceOf[to] = 1;
        seatOf[to] = id;
        emit Transfer(address(0), to, id);
    }

    function burnSeat(uint16 seat) public payable onlyDAO {
        uint256 id = uint256(seat);
        address from = _ownerOf[id];
        require(from != address(0), NotMinted());
        delete _ownerOf[id];
        delete seatOf[from];
        delete balanceOf[from];
        emit Transfer(from, address(0), id);
    }

    function tokenURI(uint256 id) public view returns (string memory) {
        address r = Moloch(DAO).renderer();
        if (r == address(0)) return "";
        return IMajeurRenderer(r).badgeTokenURI(Moloch(DAO), id);
    }

    /* ───────────── Top-256 seat bitmap logic ───────────── */

    uint256 occupied; // bit i set => seat i (0..255) used

    struct Seat {
        address holder;
        uint96 bal;
    }
    Seat[256] seats;

    uint16 minSlot; // 0..255
    uint96 minBal; // cutline

    function getSeats() public view returns (Seat[] memory out) {
        unchecked {
            uint256 m = occupied;
            uint256 s;
            while (m != 0) {
                m &= (m - 1);

                ++s;
            }
            out = new Seat[](s);
            m = occupied;
            uint256 n;
            while (m != 0) {
                uint16 i = uint16(_ffs(m)); // 0..255, because m != 0
                out[n++] = seats[i];
                m &= (m - 1);
            }
        }
    }

    /// @dev Called by DAO (Moloch) whenever a holder's share balance changes;
    /// Maintains a sticky top-256 of share holders and keeps badges in sync:
    function onSharesChanged(address a) public payable onlyDAO {
        unchecked {
            Shares _shares = Moloch(DAO).shares();

            uint256 bal256 = _shares.balanceOf(a);
            require(bal256 <= type(uint96).max, Overflow());
            uint96 bal = uint96(bal256);

            // seatOf maps holder -> tokenId (1..256), 0 if not seated
            uint16 pos = uint16(seatOf[a]); // tokenId

            // 1) zero balance => drop seat if seated
            if (bal == 0) {
                if (pos != 0) {
                    uint16 slot = pos - 1;

                    seats[slot] = Seat({holder: address(0), bal: 0});
                    _setFree(slot);

                    // burnSeat will clear seatOf[holder] and balanceOf[holder]
                    burnSeat(pos); // pos == slot + 1

                    if (slot == minSlot) _recomputeMin();
                }
                return;
            }

            // 2) already seated => update cached balance, keep seat (sticky)
            if (pos != 0) {
                uint16 slot = pos - 1;
                seats[slot].bal = bal;

                if (slot == minSlot) {
                    if (bal > minBal) {
                        _recomputeMin(); // old min grew; find new min
                    } else {
                        minBal = bal; // still the min
                    }
                } else if (minBal == 0 || bal < minBal) {
                    minSlot = slot; // new cutline
                    minBal = bal;
                }
                return;
            }

            // 3) not seated, non-zero balance => insert into free slot if any
            (uint16 freeSlot, bool ok) = _firstFree();
            if (ok) {
                seats[freeSlot] = Seat({holder: a, bal: bal});
                _setUsed(freeSlot);

                // mintSeat sets seatOf[a] and balanceOf[a]
                mintSeat(a, freeSlot + 1);

                if (minBal == 0 || bal < minBal) {
                    minSlot = freeSlot;
                    minBal = bal;
                }
                return;
            }

            // 4) full => compare to cutline; evict min if strictly larger
            if (bal > minBal) {
                uint16 slot = minSlot;

                // burn old holder's badge (clears seatOf[old] + balanceOf[old])
                burnSeat(slot + 1);

                // overwrite seat with newcomer
                seats[slot] = Seat({holder: a, bal: bal});

                // mint badge for newcomer at same seat index
                mintSeat(a, slot + 1);

                _recomputeMin(); // rare
            }
            // else: newcomer didn’t beat the cutline => do nothing (sticky)
        }
    }

    /// @dev Returns (slot, ok) - ok=false means no free slot:
    function _firstFree() internal view returns (uint16 slot, bool ok) {
        uint256 z = ~occupied;
        if (z == 0) return (0, false); // full
        // z != 0 => _ffs(z) in [0, 255] for 256-bit mask
        return (uint16(_ffs(z)), true);
    }

    function _setUsed(uint16 slot) internal {
        occupied |= (uint256(1) << slot);
    }

    function _setFree(uint16 slot) internal {
        occupied &= ~(uint256(1) << slot);
    }

    function _recomputeMin() internal {
        unchecked {
            uint16 ms;
            uint96 mb = type(uint96).max;

            for (uint256 m = occupied; m != 0; m &= (m - 1)) {
                uint16 i = uint16(_ffs(m));
                uint96 b = seats[i].bal;
                if (b != 0 && b < mb) {
                    mb = b;
                    ms = i;
                }
            }

            minSlot = ms;
            minBal = (mb == type(uint96).max) ? 0 : mb;
        }
    }

    function _ffs(uint256 x) internal pure returns (uint256 r) {
        assembly ("memory-safe") {
            x := and(x, add(not(x), 1))
            // forgefmt: disable-next-item
            r := shl(5, shr(252, shl(shl(2, shr(250, mul(x,
                0xb6db6db6ddddddddd34d34d349249249210842108c6318c639ce739cffffffff))),
                0x8040405543005266443200005020610674053026020000107506200176117077)))
            // forgefmt: disable-next-item
            r := or(r, byte(and(div(0xd76453e0, shr(r, x)), 0x1f),
                0x001f0d1e100c1d070f090b19131c1706010e11080a1a141802121b1503160405))
        }
    }
}

interface IMajeurRenderer {
    function daoContractURI(Moloch dao) external view returns (string memory);
    function daoTokenURI(Moloch dao, uint256 id) external view returns (string memory);
    function badgeTokenURI(Moloch dao, uint256 seatId) external view returns (string memory);
}

// Call structure:
struct Call {
    address target;
    uint256 value;
    bytes data;
}

// Global errors:
error SBT();
error Locked();
error Overflow();
error MulDivFailed();
error Unauthorized();
error TransferFailed();
error DeploymentFailed();
error ETHTransferFailed();
error TransferFromFailed();

// Safe cast utils:
function toUint48(uint256 x) pure returns (uint48) {
    if (x >= 1 << 48) _revertOverflow();
    return uint48(x);
}

function toUint96(uint256 x) pure returns (uint96) {
    if (x >= 1 << 96) _revertOverflow();
    return uint96(x);
}

function _revertOverflow() pure {
    assembly ("memory-safe") {
        mstore(0x00, 0x35278d12)
        revert(0x1c, 0x04)
    }
}

// Math utils:
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

// Safe token utils:
function balanceOfThis(address token) view returns (uint256 amount) {
    assembly ("memory-safe") {
        mstore(0x14, address())
        mstore(0x00, 0x70a08231000000000000000000000000)
        amount := mul(
            mload(0x20),
            and(gt(returndatasize(), 0x1f), staticcall(gas(), token, 0x10, 0x24, 0x20, 0x20))
        )
    }
}

function safeTransferETH(address to, uint256 amount) {
    assembly ("memory-safe") {
        if iszero(call(gas(), to, amount, codesize(), 0x00, codesize(), 0x00)) {
            mstore(0x00, 0xb12d13eb)
            revert(0x1c, 0x04)
        }
    }
}

function safeTransfer(address token, address to, uint256 amount) {
    assembly ("memory-safe") {
        mstore(0x14, to)
        mstore(0x34, amount)
        mstore(0x00, 0xa9059cbb000000000000000000000000)
        let success := call(gas(), token, 0, 0x10, 0x44, 0x00, 0x20)
        if iszero(and(eq(mload(0x00), 1), success)) {
            if iszero(lt(or(iszero(extcodesize(token)), returndatasize()), success)) {
                mstore(0x00, 0x90b8ec18)
                revert(0x1c, 0x04)
            }
        }
        mstore(0x34, 0)
    }
}

function safeTransferFrom(address token, uint256 amount) {
    assembly ("memory-safe") {
        let m := mload(0x40)
        mstore(0x60, amount)
        mstore(0x40, address())
        mstore(0x2c, shl(96, caller()))
        mstore(0x0c, 0x23b872dd000000000000000000000000)
        let success := call(gas(), token, 0, 0x1c, 0x64, 0x00, 0x20)
        if iszero(and(eq(mload(0x00), 1), success)) {
            if iszero(lt(or(iszero(extcodesize(token)), returndatasize()), success)) {
                mstore(0x00, 0x7939f424)
                revert(0x1c, 0x04)
            }
        }
        mstore(0x60, 0)
        mstore(0x40, m)
    }
}

/// @title Moloch (Majeur) Summoner
contract Summoner {
    event NewDAO(address indexed summoner, Moloch indexed dao);

    Moloch[] public daos;
    Moloch immutable implementation;

    constructor() payable {
        emit NewDAO(address(this), implementation = new Moloch{salt: bytes32(0)}());
    }

    /// @dev Summon new Majeur clone with initialization calls:
    function summon(
        string calldata orgName,
        string calldata orgSymbol,
        string calldata orgURI,
        uint16 quorumBps, // e.g. 5000 = 50% turnout of snapshot supply
        bool ragequittable,
        address renderer,
        bytes32 salt,
        address[] calldata initHolders,
        uint256[] calldata initShares,
        Call[] calldata initCalls
    ) public payable returns (Moloch dao) {
        bytes32 _salt = keccak256(abi.encode(initHolders, initShares, salt));
        Moloch _implementation = implementation;
        assembly ("memory-safe") {
            mstore(0x24, 0x5af43d5f5f3e6029573d5ffd5b3d5ff3)
            mstore(0x14, _implementation)
            mstore(0x00, 0x602d5f8160095f39f35f5f365f5f37365f73)
            dao := create2(callvalue(), 0x0e, 0x36, _salt)
            if iszero(dao) {
                mstore(0x00, 0x30116425)
                revert(0x1c, 0x04)
            }
            mstore(0x24, 0)
        }
        dao.init(
            orgName,
            orgSymbol,
            orgURI,
            quorumBps,
            ragequittable,
            renderer,
            initHolders,
            initShares,
            initCalls
        );
        daos.push(dao);
        emit NewDAO(msg.sender, dao);
    }

    /// @dev Get dao array push count:
    function getDAOCount() public view returns (uint256) {
        return daos.length;
    }
}

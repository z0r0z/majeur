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
    error TooEarly();
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
    uint256 public proposalThreshold; // minimum votes to make proposal
    uint256 public minYesVotesAbsolute; // minimum YES (FOR) votes
    uint256 public quorumAbsolute; // minimum total turnout (FOR+AGAINST+ABSTAIN)

    /// @dev Time-based settings (seconds; 0 = off):
    uint64 public proposalTTL; // proposal expiry
    uint64 public timelockDelay; // delay between success and execution

    /// @dev Governance versioning / dynamic quorum / global flags:
    uint64 public config; // bump salt to invalidate old ids/permits
    uint16 public quorumBps; // dynamic quorum vs snapshot supply (BPS, 0 = off)
    bool public ragequittable; // `true` if owners can ragequit shares

    address immutable SUMMONER = msg.sender;
    address immutable sharesImpl;
    address immutable badgeImpl;
    address immutable lootImpl;

    Shares public shares;
    Badge public badge;
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
    mapping(uint256 => address) public proposerOf;

    /// @dev hasVoted[id][voter] = 0 = not, 1 = FOR, 2 = AGAINST, 3 = ABSTAIN:
    mapping(uint256 id => mapping(address voter => uint8)) public hasVoted;

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
    event PermitSet(address spender, uint256 indexed hash, uint256 newCount);
    event PermitSpent(uint256 indexed id, address indexed by, uint8 op, address to, uint256 value);

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
        address rewardToken; // 0 = ETH, this = minted shares, shares = existing share tokens
        uint256 pool; // funded amount (ETH or share units)
        bool resolved; // set on resolution
        uint8 winner; // 1=YES (For), 0=NO (Against)
        uint256 finalWinningSupply;
        uint256 payoutPerUnit; // pool / finalWinningSupply (floor)
    }
    mapping(uint256 => FutarchyConfig) public futarchy;
    // 0 = off
    // 1..10_000 = BPS of snapshot supply per proposal
    // >10_000   = absolute amount (18 dp)
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
        badgeImpl = address(new Badge{salt: _salt}());
        lootImpl = address(new Loot{salt: _salt}());
    }

    function init(
        string calldata orgName,
        string calldata orgSymbol,
        string calldata orgURI,
        uint16 _quorumBps, // e.g. 5000 = 50% turnout of snapshot supply
        bool _ragequittable,
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

        address _badge;
        address _shares;
        address _loot;
        bytes32 _salt = bytes32(bytes20(address(this)));

        badge = Badge(_badge = _init(badgeImpl, _salt));
        Badge(_badge).init();
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

        if (proposalThreshold != 0) {
            require(shares.getVotes(msg.sender) >= proposalThreshold, Unauthorized());
        }

        uint48 snap = toUint48(block.number - 1);
        snapshotBlock[id] = snap;
        if (createdAt[id] == 0) createdAt[id] = uint64(block.timestamp);

        uint256 supply = shares.getPastTotalSupply(snap);
        if (supply == 0) revert TooEarly();
        supplySnapshot[id] = supply;

        // ---- registry push ----
        proposalIds.push(id);
        proposerOf[id] = msg.sender;

        emit Opened(id, snap, supply);

        // auto-futarchy earmark
        {
            uint256 p = autoFutarchyParam;
            if (p != 0) {
                address rt = (rewardToken == address(0)) ? address(this) : rewardToken;
                FutarchyConfig storage F = futarchy[id];
                if (!F.enabled) {
                    F.enabled = true;
                    F.rewardToken = rt;
                    emit FutarchyOpened(id, rt);
                }
                if (F.rewardToken == rt) {
                    uint256 amt = (p <= 10_000) ? mulDiv(supply, p, 10_000) : p;
                    uint256 cap = autoFutarchyCap;
                    if (cap != 0 && amt > cap) amt = cap;
                    if (rt == address(shares)) {
                        uint256 bal = shares.balanceOf(address(this));
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

        // expiry gating
        if (proposalTTL != 0) {
            uint64 t0 = createdAt[id];
            if (t0 == 0) revert NotOk();
            if (block.timestamp >= t0 + proposalTTL) revert NotOk();
        }

        if (hasVoted[id][msg.sender] != 0) revert NotOk();

        uint48 snap = snapshotBlock[id];
        uint96 weight = uint96(shares.getPastVotes(msg.sender, snap));
        if (weight == 0) revert NotOk();

        // tally
        if (support == 1) tallies[id].forVotes += weight;
        else if (support == 0) tallies[id].againstVotes += weight;
        else tallies[id].abstainVotes += weight;

        hasVoted[id][msg.sender] = support + 1;

        // mint ERC6909 receipt
        uint256 rid = _receiptId(id, support);
        receiptSupport[rid] = support;
        receiptProposal[rid] = id;
        _mint6909(msg.sender, rid, weight);

        emit Voted(id, msg.sender, support, weight);
    }

    function cancelVote(uint256 id) public {
        if (state(id) != ProposalState.Active) revert NotOk();

        uint8 hv = hasVoted[id][msg.sender];
        if (hv == 0) revert NotOk(); // nothing to cancel
        uint8 support = hv - 1;

        uint256 rid = _receiptId(id, support);
        uint96 weight = uint96(balanceOf[msg.sender][rid]);
        if (weight == 0) revert NotOk();

        _burn6909(msg.sender, rid, weight);

        Tally storage t = tallies[id];
        if (support == 1) t.forVotes -= weight;
        else if (support == 0) t.againstVotes -= weight;
        else t.abstainVotes -= weight;

        delete hasVoted[id][msg.sender];

        emit VoteCancelled(id, msg.sender, support, weight);
    }

    function cancelProposal(uint256 id) public {
        if (proposerOf[id] != msg.sender) revert Unauthorized();
        if (state(id) != ProposalState.Active) revert NotOk();
        if (queuedAt[id] != 0) revert NotOk();

        Tally memory t = tallies[id];
        if ((t.forVotes | t.againstVotes | t.abstainVotes) != 0) revert NotOk();

        FutarchyConfig memory F = futarchy[id];
        if (F.enabled && F.pool != 0) revert NotOk(); // don’t strand pot

        executed[id] = true; // tombstone the intent id
        emit ProposalCancelled(id, msg.sender);
    }

    function state(uint256 id) public view returns (ProposalState) {
        if (executed[id]) return ProposalState.Executed;
        if (createdAt[id] == 0) return ProposalState.Unopened;

        uint64 queued = queuedAt[id];

        // if already queued, TTL no longer applies
        if (queued != 0) {
            uint64 delay = timelockDelay;
            // if delay is zero, this condition is always false once block.timestamp >= queued
            if (delay != 0 && block.timestamp < queued + delay) return ProposalState.Queued;
        } else {
            uint64 ttl = proposalTTL;
            if (ttl != 0) {
                uint64 t0 = createdAt[id];
                if (t0 != 0 && block.timestamp >= t0 + ttl) return ProposalState.Expired;
            }
        }

        // evaluate gates
        uint256 ts = supplySnapshot[id];
        if (ts == 0) return ProposalState.Active;

        Tally storage t = tallies[id];
        uint256 forVotes = t.forVotes;
        uint256 againstVotes = t.againstVotes;
        uint256 abstainVotes = t.abstainVotes;

        uint256 totalCast = forVotes + againstVotes + abstainVotes;

        // absolute quorum
        uint256 absQuorum = quorumAbsolute;
        if (absQuorum != 0 && totalCast < absQuorum) return ProposalState.Active;

        // dynamic quorum (BPS)
        uint16 bps = quorumBps;
        if (bps != 0 && totalCast < mulDiv(uint256(bps), ts, 10000)) {
            return ProposalState.Active;
        }

        // absolute YES floor
        uint256 minYes = minYesVotesAbsolute;
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
    function fundFutarchy(uint256 id, address token, uint256 amount) public payable nonReentrant {
        if (amount == 0) revert NotOk();
        if (token != address(0) && token != address(this) && token != address(shares)) {
            revert NotOk();
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
        } else if (rt == address(this)) {
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

        payout = amount * F.payoutPerUnit;
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
        if (!ragequittable) revert NotOk();
        require(tokens.length != 0, LengthMismatch());
        if (sharesToBurn == 0 && lootToBurn == 0) revert NotOk();

        Shares _shares = shares;
        Loot _loot = loot;

        uint256 total = _shares.totalSupply() + _loot.totalSupply();
        uint256 amt = sharesToBurn + lootToBurn;

        if (sharesToBurn != 0) _shares.burnFromMoloch(msg.sender, sharesToBurn);
        if (lootToBurn != 0) _loot.burnFromMoloch(msg.sender, lootToBurn);

        address prev;
        address tk;
        uint256 pool;
        uint256 due;
        for (uint256 i; i != tokens.length; ++i) {
            tk = tokens[i];
            require(tk != address(this), Unauthorized());
            require(tk != address(shares), Unauthorized());
            if (i != 0 && tk <= prev) revert NotOk();
            prev = tk;

            pool = tk == address(0) ? address(this).balance : balanceOfThis(tk);
            due = mulDiv(pool, amt, total);
            if (due == 0) continue;

            _payout(tk, msg.sender, due);
        }
    }

    /* CHATROOM */
    function getMessageCount() public view returns (uint256) {
        return messages.length;
    }

    function chat(string calldata text) public payable {
        if (badge.balanceOf(msg.sender) == 0) revert NotOk();
        messages.push(text);
        emit Message(msg.sender, messages.length - 1, text);
    }

    /* SETTINGS */
    function setQuorumBps(uint16 bps) public payable onlyDAO {
        if (bps > 10_000) revert NotOk();
        quorumBps = bps;
    }

    function setMinYesVotesAbsolute(uint256 v) public payable onlyDAO {
        minYesVotesAbsolute = v;
    }

    function setQuorumAbsolute(uint256 v) public payable onlyDAO {
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

    function setProposalThreshold(uint256 v) public payable onlyDAO {
        proposalThreshold = v;
    }

    function setMetadata(string calldata n, string calldata s, string calldata uri)
        public
        payable
        onlyDAO
    {
        (_orgName, _orgSymbol, _orgURI) = (n, s, uri);
    }

    /// @dev Configure automatic futarchy earmark per proposal:
    /// @dev param: 0=off; 1..10_000=BPS of snapshot supply; >10_000=absolute (18 dp),
    ///      cap: hard per-proposal maximum after param calculation (0 = no cap):
    function setAutoFutarchy(uint256 param, uint256 cap) public payable onlyDAO {
        autoFutarchyParam = param;
        autoFutarchyCap = cap;
    }

    /// @dev Default reward token for futarchy pools:
    /// rewardToken: 0 = ETH, address(this) = minted shares, address(shares) = treasury shares,
    /// auto-earmark always uses minted shares if rewardToken is ETH; manual fundFutarchy can still use ETH:
    function setFutarchyRewardToken(address _rewardToken) public payable onlyDAO {
        if (
            _rewardToken != address(0) && _rewardToken != address(this)
                && _rewardToken != address(shares)
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

    /* HOLDERS (seat bitmap) */
    uint256 occupied; // bit i set => seat i (0..255) used

    struct Seat {
        address holder;
        uint96 bal;
    }
    Seat[256] seats;

    uint16 minSlot; // 0..255
    uint96 minBal; // cutline

    mapping(address => uint16) public seatOf; // 1..256 if in top set, else 0

    function getSeats() public view returns (Seat[] memory out) {
        uint256 m = occupied;
        uint256 s;
        while (m != 0) {
            m &= (m - 1);
            unchecked {
                ++s;
            }
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

    function onSharesChanged(address a) public payable {
        require(msg.sender == address(shares), Unauthorized());
        _onSharesChanged(a);
    }

    /// @dev Maintains a sticky top-256 set:
    /// - A holder keeps their slot as long as their balance is non-zero
    /// - We only consider demotion when:
    ///   (a) a non-member's balance changes and exceeds the current minimum, or
    ///   (b) a member's balance falls to zero
    /// - This means the set may diverge from the true mathematical top-256:
    function _onSharesChanged(address a) internal {
        Shares _shares = shares;

        uint256 bal256 = _shares.balanceOf(a);
        require(bal256 <= type(uint96).max, Overflow());
        uint96 bal = uint96(bal256);

        uint16 pos = seatOf[a]; // 0 => not seated; else seat = pos-1

        // 1) zero balance => drop seat if seated
        if (bal == 0) {
            if (pos != 0) {
                uint16 slot = pos - 1;

                seats[slot] = Seat({holder: address(0), bal: 0});
                _setFree(slot);
                delete seatOf[a];

                badge.burnSeat(slot + 1);

                if (slot == minSlot) _recomputeMin();
            }
            return;
        }

        // 2) already seated => update cached balance, keep seat (sticky)
        if (pos != 0) {
            uint16 slot = pos - 1;
            seats[slot].bal = bal;

            if (slot == minSlot) {
                if (bal > minBal) _recomputeMin(); // old min grew; find new min
                else minBal = bal; // still the min
            } else if (minBal == 0 || bal < minBal) {
                minSlot = slot; // new cutline
                minBal = bal;
            }
            return;
        }

        // 3) not seated, non-zero balance => insert
        (uint16 freeSlot, bool ok) = _firstFree();
        if (ok) {
            seats[freeSlot] = Seat({holder: a, bal: bal});
            _setUsed(freeSlot);
            unchecked {
                seatOf[a] = freeSlot + 1;
            }
            badge.mintSeat(a, freeSlot + 1);

            if (minBal == 0 || bal < minBal) {
                minSlot = freeSlot;
                minBal = bal;
            }
            return;
        }

        // 4) full => compare to cutline; evict min if strictly larger
        if (bal > minBal) {
            uint16 slot = minSlot;
            address evict = seats[slot].holder;

            delete seatOf[evict];
            badge.burnSeat(slot + 1);

            seats[slot] = Seat({holder: a, bal: bal});
            unchecked {
                seatOf[a] = slot + 1;
            }

            badge.mintSeat(a, slot + 1);

            _recomputeMin(); // rare
        }
        // else: newcomer didn’t beat the cutline => do nothing (sticky)
    }

    /// @dev Returns (slot, ok) - ok=false means no free slot:
    function _firstFree() internal view returns (uint16 slot, bool ok) {
        uint256 z = ~occupied;
        if (z == 0) return (0, false); // full

        // z != 0 => _ffs(z) in [0, 255] for 256-bit mask.
        return (uint16(_ffs(z)), true);
    }

    function _setUsed(uint16 slot) internal {
        occupied |= (uint256(1) << slot);
    }

    function _setFree(uint16 slot) internal {
        occupied &= ~(uint256(1) << slot);
    }

    function _recomputeMin() internal {
        uint16 ms = 0;
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

    function _ffs(uint256 x) internal pure returns (uint256 r) {
        assembly ("memory-safe") {
            x := and(x, add(not(x), 1))
            r := shl(
                5,
                shr(
                    252,
                    shl(
                        shl(
                            2,
                            shr(
                                250,
                                mul(
                                    x,
                                    0xb6db6db6ddddddddd34d34d349249249210842108c6318c639ce739cffffffff
                                )
                            )
                        ),
                        0x8040405543005266443200005020610674053026020000107506200176117077
                    )
                )
            )
            r := or(
                r,
                byte(
                    and(div(0xd76453e0, shr(r, x)), 0x1f),
                    0x001f0d1e100c1d070f090b19131c1706010e11080a1a141802121b1503160405
                )
            )
        }
    }

    /* URI-SVG */
    function contractURI() public view returns (string memory) {
        // if custom URI is set, return it
        string memory orgURI = _orgURI;
        if (bytes(orgURI).length != 0) return orgURI;

        // cache dynamic bits
        string memory rawOrgName = _orgName;
        string memory orgName =
            bytes(rawOrgName).length != 0 ? Display.esc(rawOrgName) : "UNNAMED DAO";
        string memory orgSymbol = bytes(_orgSymbol).length != 0 ? Display.esc(_orgSymbol) : "N/A";
        string memory orgShort = Display.shortAddr4(address(this)); // "0xAbCd...1234"

        // supplies
        uint256 shareSupply = shares.totalSupply();
        uint256 lootSupply = loot.totalSupply();

        string memory svg = string.concat(
            "<svg xmlns='http://www.w3.org/2000/svg' width='420' height='600' viewBox='0 0 420 600' preserveAspectRatio='xMidYMid meet' xml:space='preserve' aria-labelledby='title desc' role='img'>",
            "<title id='title'>",
            orgName,
            " - DUNA Covenant</title>",
            "<desc id='desc'>Wyoming Decentralized Unincorporated Nonprofit Association operating charter and member agreement.</desc>",
            "<defs>",
            "<style>",
            ".garamond{font-family:'EB Garamond',serif;font-weight:400;}",
            ".garamond-bold{font-family:'EB Garamond',serif;font-weight:600;}",
            ".mono{font-family:'Courier Prime',monospace;font-variant-ligatures:none;}",
            ".covenant{font-family:'EB Garamond',serif;font-style:italic;font-size:8px;fill:#ccc;}",
            "text{ text-rendering:geometricPrecision; }",
            "</style>",
            "</defs>",
            "<rect width='420' height='600' fill='#000'/>",
            "<rect x='20' y='20' width='380' height='560' fill='none' stroke='#8b0000' stroke-width='2'/>"
        );

        // title section - uses org name
        svg = string.concat(
            svg,
            "<text x='210' y='55' class='garamond-bold' font-size='18' fill='#fff' text-anchor='middle' letter-spacing='3px'>",
            orgName,
            "</text>",
            "<text x='210' y='75' class='garamond' font-size='10' fill='#8b0000' text-anchor='middle' letter-spacing='2px'>DUNA COVENANT</text>",
            "<line x1='40' y1='90' x2='380' y2='90' stroke='#8b0000' stroke-width='1'/>"
        );

        // ASCII sigil
        svg = string.concat(
            svg,
            "<text x='210' y='115' class='mono' font-size='7' fill='#8b0000' text-anchor='middle'>___/\\___</text>",
            "<text x='210' y='124' class='mono' font-size='7' fill='#8b0000' text-anchor='middle'>/  \\  /  \\</text>",
            "<text x='210' y='133' class='mono' font-size='7' fill='#8b0000' text-anchor='middle'>/    \\/    \\</text>",
            "<text x='210' y='142' class='mono' font-size='7' fill='#8b0000' text-anchor='middle'>\\  /\\  /\\  /</text>",
            "<text x='210' y='151' class='mono' font-size='7' fill='#8b0000' text-anchor='middle'>\\/  \\/  \\/</text>",
            "<text x='210' y='160' class='mono' font-size='7' fill='#8b0000' text-anchor='middle'>*</text>",
            "<line x1='60' y1='175' x2='360' y2='175' stroke='#8b0000' stroke-width='0.5' opacity='0.5'/>"
        );

        // organization data
        svg = string.concat(
            svg,
            "<text x='60' y='195' class='garamond' font-size='9' fill='#aaa'>Organization</text>",
            "<text x='60' y='208' class='mono' font-size='8' fill='#fff'>",
            orgShort,
            "</text>",
            "<text x='60' y='228' class='garamond' font-size='9' fill='#aaa'>Name / Symbol</text>",
            "<text x='60' y='241' class='mono' font-size='8' fill='#fff'>",
            orgName,
            " / ",
            orgSymbol,
            "</text>"
        );

        svg = string.concat(
            svg,
            "<text x='60' y='261' class='garamond' font-size='9' fill='#aaa'>Share Supply</text>",
            "<text x='60' y='274' class='mono' font-size='8' fill='#fff'>",
            Display.fmtComma(shareSupply / 1e18),
            "</text>"
        );

        if (lootSupply != 0) {
            svg = string.concat(
                svg,
                "<text x='220' y='261' class='garamond' font-size='9' fill='#aaa'>Loot Supply</text>",
                "<text x='220' y='274' class='mono' font-size='8' fill='#fff'>",
                Display.fmtComma(lootSupply / 1e18),
                "</text>"
            );
        }

        // DUNA covenant text - centered
        svg = string.concat(
            svg,
            "<line x1='60' y1='290' x2='360' y2='290' stroke='#8b0000' stroke-width='0.5' opacity='0.5'/>",
            "<text x='210' y='310' class='garamond' font-size='10' fill='#8b0000' text-anchor='middle'>WYOMING DUNA</text>",
            "<text x='210' y='325' class='covenant' text-anchor='middle'>W.S. 17-32-101 et seq.</text>"
        );

        // covenant terms - centered alignment
        svg = string.concat(
            svg,
            "<text x='210' y='345' class='covenant' text-anchor='middle'>By transacting with address ",
            orgShort,
            ", you</text>",
            "<text x='210' y='355' class='covenant' text-anchor='middle'>acknowledge this organization operates as a Decentralized</text>",
            "<text x='210' y='365' class='covenant' text-anchor='middle'>Unincorporated Nonprofit Association under Wyoming law.</text>",
            "<text x='210' y='385' class='covenant' text-anchor='middle'>Members agree to: (i) algorithmic governance via this smart contract,</text>",
            "<text x='210' y='395' class='covenant' text-anchor='middle'>(ii) limited liability considerations per W.S. 17-32-107,</text>",
            "<text x='210' y='405' class='covenant' text-anchor='middle'>(iii) dispute resolution through code-as-law principles,</text>",
            "<text x='210' y='415' class='covenant' text-anchor='middle'>(iv) good faith participation in DAO governance,</text>",
            "<text x='210' y='425' class='covenant' text-anchor='middle'>(v) adherence to applicable laws and self-help.</text>"
        );

        // transfer and ragequit status
        svg = string.concat(
            svg,
            "<text x='210' y='445' class='covenant' text-anchor='middle'>Share tokens represent governance rights.</text>",
            "<text x='210' y='455' class='covenant' text-anchor='middle'>Share transfers are ",
            shares.transfersLocked() ? "DISABLED" : "ENABLED",
            ". Ragequit rights are ",
            ragequittable ? "ENABLED" : "DISABLED",
            ".</text>"
        );

        // conditionally show loot transfers and adjust positioning
        uint256 nextY = 465;
        if (lootSupply != 0) {
            svg = string.concat(
                svg,
                "<text x='210' y='",
                Display.toString(nextY),
                "' class='covenant' text-anchor='middle'>Loot transfers are ",
                loot.transfersLocked() ? "DISABLED" : "ENABLED",
                ".</text>"
            );
            unchecked {
                nextY += 10;
            }
        }

        svg = string.concat(
            svg,
            "<text x='210' y='",
            Display.toString(nextY),
            "' class='covenant' text-anchor='middle'>This Covenant is amendable by DAO vote.</text>"
        );

        // disclaimer - positioned dynamically
        svg = string.concat(
            svg,
            "<text x='210' y='",
            Display.toString(nextY + 20),
            "' class='covenant' text-anchor='middle'>No warranty, express or implied. Members participate at</text>",
            "<text x='210' y='",
            Display.toString(nextY + 30),
            "' class='covenant' text-anchor='middle'>own risk. Not legal, tax, or investment advice.</text>"
        );

        // bottom seal
        svg = string.concat(
            svg,
            "<line x1='60' y1='520' x2='360' y2='520' stroke='#8b0000' stroke-width='0.5' opacity='0.5'/>",
            "<text x='210' y='540' class='mono' font-size='8' fill='#8b0000' text-anchor='middle'><![CDATA[ < THE DAO DEMANDS SACRIFICE > ]]></text>",
            "<text x='210' y='560' class='garamond' font-size='7' fill='#444' text-anchor='middle' letter-spacing='1px'>CODE IS LAW - DUNA PROTECTED</text>",
            "</svg>"
        );

        // final JSON with embedded image
        return Display.jsonImage(
            string.concat(
                bytes(rawOrgName).length != 0 ? rawOrgName : "UNNAMED DAO", " DUNA Covenant"
            ),
            "Wyoming Decentralized Unincorporated Nonprofit Association operating charter and member agreement",
            svg
        );
    }

    /// @dev On-chain JSON/SVG card for a proposal id, or routes to receiptURI for vote receipts:
    function tokenURI(uint256 id) public view returns (string memory) {
        // 1) if this id is a vote receipt, delegate to the full receipt renderer
        if (receiptProposal[id] != 0) return _receiptURI(id);

        Tally memory t = tallies[id];
        bool touchedTallies = (t.forVotes | t.againstVotes | t.abstainVotes) != 0;

        uint256 snap = snapshotBlock[id];
        bool opened = snap != 0 || createdAt[id] != 0;

        bool looksLikePermit = !opened && !touchedTallies && totalSupply[id] != 0;
        if (looksLikePermit) return _permitCardURI(id);

        // ----- Proposal Card -----
        string memory stateStr;
        ProposalState st = state(id);

        if (st == ProposalState.Unopened) {
            stateStr = "UNOPENED";
        } else if (st == ProposalState.Active) {
            stateStr = "ACTIVE";
        } else if (st == ProposalState.Queued) {
            stateStr = "QUEUED";
        } else if (st == ProposalState.Succeeded) {
            stateStr = "SUCCEEDED";
        } else if (st == ProposalState.Defeated) {
            stateStr = "DEFEATED";
        } else if (st == ProposalState.Expired) {
            stateStr = "EXPIRED";
        } else if (st == ProposalState.Executed) {
            stateStr = "EXECUTED";
        }

        string memory rawOrgName = _orgName;
        string memory svg = Display.svgCardBase();
        string memory orgName = Display.esc(rawOrgName);

        // title
        svg = string.concat(
            svg,
            "<text x='210' y='55' class='garamond-bold' font-size='18' fill='#fff' text-anchor='middle' letter-spacing='3'>",
            orgName,
            "</text>",
            "<text x='210' y='75' class='garamond' font-size='11' fill='#fff' text-anchor='middle' letter-spacing='2'>PROPOSAL</text>",
            "<line x1='40' y1='90' x2='380' y2='90' stroke='#fff' stroke-width='1'/>"
        );

        // ASCII eye (minimalist)
        svg = string.concat(
            svg,
            "<text x='210' y='155' class='mono' font-size='9' fill='#fff' text-anchor='middle'>.---------.</text>",
            "<text x='210' y='166' class='mono' font-size='9' fill='#fff' text-anchor='middle'>(     O     )</text>",
            "<text x='210' y='177' class='mono' font-size='9' fill='#fff' text-anchor='middle'>'---------'</text>",
            "<line x1='40' y1='220' x2='380' y2='220' stroke='#fff' stroke-width='1'/>"
        );

        // data section
        svg = string.concat(
            svg,
            "<text x='60' y='255' class='garamond' font-size='10' fill='#aaa' letter-spacing='1'>ID</text>",
            "<text x='60' y='272' class='mono' font-size='9' fill='#fff'>",
            Display.shortDec4(id), // decimal "1234...5678" if long
            "</text>"
        );

        // snapshot data (only if opened)
        if (opened) {
            svg = string.concat(
                svg,
                "<text x='60' y='305' class='garamond' font-size='10' fill='#aaa' letter-spacing='1'>Snapshot</text>",
                "<text x='60' y='322' class='mono' font-size='9' fill='#fff'>Block ",
                Display.toString(snap),
                "</text>",
                "<text x='60' y='335' class='mono' font-size='9' fill='#fff'>Supply ",
                Display.fmtComma(supplySnapshot[id] / 1e18),
                "</text>"
            );
        }

        // tally section (only if votes exist)
        if (touchedTallies) {
            svg = string.concat(
                svg,
                "<text x='60' y='368' class='garamond' font-size='10' fill='#aaa' letter-spacing='1'>Tally</text>",
                "<text x='60' y='385' class='mono' font-size='9' fill='#fff'>For      ",
                Display.fmtComma(t.forVotes / 1e18),
                "</text>",
                "<text x='60' y='398' class='mono' font-size='9' fill='#fff'>Against  ",
                Display.fmtComma(t.againstVotes / 1e18),
                "</text>",
                "<text x='60' y='411' class='mono' font-size='9' fill='#fff'>Abstain  ",
                Display.fmtComma(t.abstainVotes / 1e18),
                "</text>"
            );
        }

        // status
        svg = string.concat(
            svg,
            "<text x='210' y='465' class='garamond' font-size='12' fill='#fff' text-anchor='middle' letter-spacing='2'>",
            stateStr,
            "</text>",
            "<line x1='40' y1='495' x2='380' y2='495' stroke='#fff' stroke-width='1'/>",
            "</svg>"
        );

        return Display.jsonImage(
            string.concat(rawOrgName, " Proposal"), "Snapshot-weighted governance proposal", svg
        );
    }

    function _receiptURI(uint256 id) internal view returns (string memory) {
        uint8 s = receiptSupport[id]; // 0 = NO, 1 = YES, 2 = ABSTAIN

        uint256 proposalId_ = receiptProposal[id];
        FutarchyConfig memory F = futarchy[proposalId_];

        string memory stance = s == 1 ? "YES" : s == 0 ? "NO" : "ABSTAIN";

        string memory status;
        if (!F.enabled) {
            status = "SEALED";
        } else if (!F.resolved) {
            status = "OPEN";
        } else {
            status = (F.winner == s) ? "REDEEMABLE" : "SEALED";
        }

        string memory svg = Display.svgCardBase();
        string memory orgName = Display.esc(_orgName);

        // title
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

        // data
        svg = string.concat(
            svg,
            "<text x='60' y='275' class='garamond' font-size='10' fill='#aaa' letter-spacing='1'>Proposal</text>",
            "<text x='60' y='292' class='mono' font-size='9' fill='#fff'>",
            Display.shortDec4(proposalId_), // e.g. 1234...5678
            "</text>",
            "<text x='60' y='325' class='garamond' font-size='10' fill='#aaa' letter-spacing='1'>Stance</text>",
            "<text x='60' y='345' class='garamond-bold' font-size='14' fill='#fff'>",
            stance,
            "</text>",
            "<text x='60' y='378' class='garamond' font-size='10' fill='#aaa' letter-spacing='1'>Weight</text>",
            "<text x='60' y='395' class='mono' font-size='9' fill='#fff'>",
            Display.fmtComma(totalSupply[id] / 1e18),
            " votes</text>"
        );

        // futarchy info (only if enabled)
        if (F.enabled) {
            svg = string.concat(
                svg,
                "<text x='60' y='428' class='garamond' font-size='10' fill='#aaa' letter-spacing='1'>Futarchy</text>",
                "<text x='60' y='445' class='mono' font-size='9' fill='#fff'>Pool ",
                Display.fmtComma(F.pool / 1e18),
                F.rewardToken == address(0) ? " ETH" : " shares",
                "</text>"
            );

            if (F.resolved) {
                svg = string.concat(
                    svg,
                    "<text x='60' y='458' class='mono' font-size='9' fill='#fff'>Payout ",
                    Display.fmtComma(F.payoutPerUnit / 1e18),
                    "/vote</text>"
                );
            }
        }

        // status
        svg = string.concat(
            svg,
            "<text x='210' y='510' class='garamond' font-size='12' fill='#fff' text-anchor='middle' letter-spacing='2'>",
            status,
            "</text>",
            "<line x1='40' y1='540' x2='380' y2='540' stroke='#fff' stroke-width='1'/>",
            "</svg>"
        );

        return Display.jsonImage(
            "Vote Receipt",
            string.concat(stance, " vote receipt - burn to claim rewards if winner"),
            svg
        );
    }

    function _permitCardURI(uint256 id) internal view returns (string memory) {
        string memory usesStr;
        uint256 supply = totalSupply[id];

        usesStr = (supply == 0) ? "NONE" : Display.fmtComma(supply);

        string memory svg = Display.svgCardBase();
        string memory orgName = Display.esc(_orgName);

        // title
        svg = string.concat(
            svg,
            "<text x='210' y='55' class='garamond-bold' font-size='18' fill='#fff' text-anchor='middle' letter-spacing='3'>",
            orgName,
            "</text>",
            "<text x='210' y='75' class='garamond' font-size='11' fill='#fff' text-anchor='middle' letter-spacing='2'>PERMIT</text>",
            "<line x1='40' y1='90' x2='380' y2='90' stroke='#fff' stroke-width='1'/>"
        );

        // ASCII key
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

        // data
        svg = string.concat(
            svg,
            "<text x='60' y='280' class='garamond' font-size='10' fill='#aaa' letter-spacing='1'>Intent ID</text>",
            "<text x='60' y='297' class='mono' font-size='9' fill='#fff'>",
            Display.shortDec4(id), // e.g. 1234...5678
            "</text>",
            "<text x='60' y='330' class='garamond' font-size='10' fill='#aaa' letter-spacing='1'>Total Supply</text>", // ← Changed label
            "<text x='60' y='350' class='garamond-bold' font-size='14' fill='#fff'>",
            usesStr,
            "</text>"
        );

        // status
        svg = string.concat(
            svg,
            "<text x='210' y='480' class='garamond' font-size='12' fill='#fff' text-anchor='middle' letter-spacing='2'>ACTIVE</text>",
            "<line x1='40' y1='520' x2='380' y2='520' stroke='#fff' stroke-width='1'/>",
            "</svg>"
        );

        return Display.jsonImage("Permit", "Pre-approved execution permit", svg);
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

    /* HELPERS */
    /// @dev Shared low-level executor for call / delegatecall:
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

    function _payout(address token, address to, uint256 amount) internal {
        if (amount == 0) return;
        if (token == address(0)) {
            safeTransferETH(to, amount);
        } else if (token == address(this)) {
            shares.mintFromMoloch(to, amount);
        } else {
            safeTransfer(token, to, amount);
        }
    }

    /*──────── reentrancy ─*/

    error Reentrancy();

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
        uint256 len = ckpts.length;
        uint256 oldVal = len == 0 ? 0 : ckpts[len - 1].votes;
        uint256 newVal = add ? oldVal + amount : oldVal - amount;
        if (oldVal == newVal) return;

        _writeCheckpoint(ckpts, oldVal, newVal);
        emit DelegateVotesChanged(delegate_, oldVal, newVal);
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
        uint256 n = _checkpoints[account].length;
        return n == 0 ? 0 : _checkpoints[account][n - 1].votes;
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
            // stack allocation for single element
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

        // build a union of delegates that appear in either old or new
        uint256 oldLen = oldD.length;
        uint256 newLen = newD.length;

        // worst case union size = oldLen + newLen
        address[] memory allD = new address[](oldLen + newLen);
        uint256 allLen;

        // insert old delegates
        for (uint256 i; i != oldLen; ++i) {
            address d = oldD[i];
            allD[allLen++] = d;
        }

        // insert new delegates if not already present
        for (uint256 j; j != newLen; ++j) {
            address d = newD[j];
            bool found;
            for (uint256 k; k != allLen; ++k) {
                if (allD[k] == d) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                allD[allLen++] = d;
            }
        }

        // compute old & new target allocations for this holder
        uint256[] memory oldA = _targetAlloc(bal, oldD, oldB);
        uint256[] memory newA = _targetAlloc(bal, newD, newB);

        // for each delegate in the union, compute oldAmt/newAmt
        for (uint256 i; i != allLen; ++i) {
            address d = allD[i];
            uint256 oldAmt;
            uint256 newAmt;

            // find in oldD
            for (uint256 u; u != oldLen; ++u) {
                if (oldD[u] == d) {
                    oldAmt = oldA[u];
                    break;
                }
            }

            // find in newD
            for (uint256 v; v != newLen; ++v) {
                if (newD[v] == d) {
                    newAmt = newA[v];
                    break;
                }
            }

            if (newAmt > oldAmt) {
                _moveVotingPower(address(0), d, newAmt - oldAmt);
            } else if (oldAmt > newAmt) {
                _moveVotingPower(d, address(0), oldAmt - newAmt);
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

    function _writeTotalSupplyCheckpoint() internal {
        Checkpoint[] storage ckpts = _totalSupplyCheckpoints;
        uint256 len = ckpts.length;

        uint256 oldVal = len == 0 ? 0 : ckpts[len - 1].votes;
        uint256 newVal = totalSupply;

        _writeCheckpoint(ckpts, oldVal, newVal);
    }

    function _checkpointsLookup(Checkpoint[] storage ckpts, uint48 blockNumber)
        internal
        view
        returns (uint256)
    {
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

contract Badge {
    /* ERC721-ish */
    event Transfer(address indexed from, address indexed to, uint256 indexed id);

    /* MAJEUR */
    address payable public DAO;

    mapping(uint256 id => address) _ownerOf;
    mapping(address => uint256) public seatOf;
    mapping(address => uint256) public balanceOf;

    modifier onlyDAO() {
        require(msg.sender == DAO, Unauthorized());
        _;
    }

    error SBT();
    error Minted();
    error NotMinted();

    constructor() payable {}

    function init() public payable {
        require(DAO == address(0), Unauthorized());
        DAO = payable(msg.sender);
    }

    /// @dev Dynamic metadata from Majeur:
    function name() public view returns (string memory) {
        return string.concat(Moloch(DAO).name(0), " Badge");
    }

    function symbol() public view returns (string memory) {
        return string.concat(Moloch(DAO).symbol(0), "B");
    }

    function ownerOf(uint256 id) public view returns (address o) {
        o = _ownerOf[id];
        require(o != address(0), NotMinted());
    }

    function supportsInterface(bytes4 interfaceId) public pure returns (bool) {
        return interfaceId == 0x01ffc9a7 // ERC165 Interface ID for ERC165
            || interfaceId == 0x80ac58cd // ERC165 Interface ID for ERC721
            || interfaceId == 0x5b5e139f; // ERC165 Interface ID for ERC721Metadata
    }

    /// @dev Top-256 badge (seat index; tokenId == seat, not sorted by balance):
    function tokenURI(uint256 id) public view returns (string memory) {
        // reverts if the seat token isn't minted; guarantees we're seated
        address holder = ownerOf(id);

        Shares sh = Moloch(DAO).shares();
        uint256 bal = sh.balanceOf(holder);
        uint256 balInTokens = bal / 1e18;
        uint256 ts = sh.totalSupply();

        // seat string comes straight from tokenId
        string memory addr = Display.shortAddr4(holder);
        string memory pct = Display.percent2(bal, ts);
        string memory seatStr = Display.toString(id);
        string memory svg = Display.svgCardBase();

        // title
        svg = string.concat(
            svg,
            "<text x='210' y='55' class='garamond-bold' font-size='18' fill='#fff' text-anchor='middle' letter-spacing='3'>",
            Display.esc(name()),
            "</text>",
            "<text x='210' y='75' class='garamond' font-size='11' fill='#fff' text-anchor='middle' letter-spacing='2'>MEMBER BADGE</text>",
            "<line x1='40' y1='90' x2='380' y2='90' stroke='#fff' stroke-width='1'/>"
        );

        // ASCII crown
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

        // data
        svg = string.concat(
            svg,
            "<text x='60' y='275' class='garamond' font-size='10' fill='#aaa' letter-spacing='1'>Address</text>",
            "<text x='60' y='292' class='mono' font-size='9' fill='#fff'>",
            addr,
            "</text>",
            "<text x='60' y='325' class='garamond' font-size='10' fill='#aaa' letter-spacing='1'>Seat</text>",
            "<text x='60' y='345' class='garamond-bold' font-size='16' fill='#fff'>",
            seatStr,
            "</text>"
        );

        // balance
        svg = string.concat(
            svg,
            "<text x='60' y='378' class='garamond' font-size='10' fill='#aaa' letter-spacing='1'>Balance</text>",
            "<text x='60' y='395' class='mono' font-size='9' fill='#fff'>",
            Display.fmtComma(balInTokens), // 123,456,789
            " shares</text>"
        );

        // ownership
        svg = string.concat(
            svg,
            "<text x='60' y='428' class='garamond' font-size='10' fill='#aaa' letter-spacing='1'>Ownership</text>",
            "<text x='60' y='445' class='mono' font-size='9' fill='#fff'>",
            pct,
            "</text>"
        );

        // status — token exists only for top-256, so always show the banner
        svg = string.concat(
            svg,
            "<text x='210' y='500' class='garamond' font-size='12' fill='#fff' text-anchor='middle' letter-spacing='2'>TOP 256 - SEAT ",
            seatStr,
            "</text>"
        );

        svg = string.concat(
            svg,
            "<line x1='40' y1='540' x2='380' y2='540' stroke='#fff' stroke-width='1'/>",
            "<text x='210' y='565' class='garamond' font-size='8' fill='#444' text-anchor='middle' letter-spacing='1'>NON-TRANSFERABLE</text>",
            "</svg>"
        );

        return Display.jsonImage("Badge", "Top-256 holder badge (SBT)", svg);
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
}

// Call structure:
struct Call {
    address target;
    uint256 value;
    bytes data;
}

// Global errors:
error Locked();
error Overflow();
error Unauthorized();
error TransferFailed();
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

/// @dev Display — minimal helpers for on-chain SVG / string rendering:
library Display {
    /*──────────────────────  DATA URIs  ─────────────────────*/

    function jsonDataURI(string memory raw) internal pure returns (string memory) {
        return string.concat("data:application/json;base64,", encode(bytes(raw)));
    }

    function svgDataURI(string memory raw) internal pure returns (string memory) {
        return string.concat("data:image/svg+xml;base64,", encode(bytes(raw)));
    }

    function jsonImage(string memory name_, string memory description_, string memory svg_)
        internal
        pure
        returns (string memory)
    {
        return jsonDataURI(
            string.concat(
                '{"name":"',
                name_,
                '","description":"',
                description_,
                '","image":"',
                svgDataURI(svg_),
                '"}'
            )
        );
    }

    /*──────────────────────  SVG BASE  ─────────────────────*/

    function svgCardBase() internal pure returns (string memory) {
        return string.concat(
            "<svg xmlns='http://www.w3.org/2000/svg' width='420' height='600'>",
            "<defs><style>",
            ".garamond{font-family:'EB Garamond',serif;font-weight:400;}",
            ".garamond-bold{font-family:'EB Garamond',serif;font-weight:600;}",
            ".mono{font-family:'Courier Prime',monospace;}",
            "</style></defs>",
            "<rect width='420' height='600' fill='#000'/>",
            "<rect x='20' y='20' width='380' height='560' fill='none' stroke='#fff' stroke-width='1'/>"
        );
    }

    /*──────────────────────  DECIMAL IDs  ─────────────────────*/

    /// @dev "1234...5678" from a big decimal id:
    function shortDec4(uint256 v) internal pure returns (string memory) {
        string memory s = toString(v);
        uint256 n = bytes(s).length;
        if (n <= 11) return s;
        unchecked {
            return string.concat(slice(s, 0, 4), "...", slice(s, n - 4, n));
        }
    }

    /*──────────────────────  ADDRESSES  ─────────────────────*/

    /// @dev EIP-55 "0xAbCd...1234" (0x + 4 nibbles ... 4 nibbles):
    function shortAddr4(address a) internal pure returns (string memory) {
        string memory full = toHexStringChecksummed(a);
        uint256 n = bytes(full).length;
        unchecked {
            return string.concat(slice(full, 0, 6), "...", slice(full, n - 4, n));
        }
    }

    /*──────────────────────  NUMBERS  ─────────────────────*/

    /// @dev Decimal with commas: 123_456_789 => "123,456,789":
    function fmtComma(uint256 n) internal pure returns (string memory) {
        if (n == 0) return "0";
        uint256 temp = n;
        uint256 digits;
        while (temp != 0) {
            unchecked {
                ++digits;
                temp /= 10;
            }
        }
        uint256 commas = (digits - 1) / 3;
        bytes memory buf = new bytes(digits + commas);
        uint256 i = buf.length;
        uint256 dcount;
        while (n != 0) {
            if (dcount != 0 && dcount % 3 == 0) {
                unchecked {
                    buf[--i] = ",";
                }
            }
            unchecked {
                buf[--i] = bytes1(uint8(48 + (n % 10)));
                n /= 10;
                ++dcount;
            }
        }
        return string(buf);
    }

    /// @dev Percent with 2 decimals from a/b, e.g. 1234/10000 => "12.34%":
    function percent2(uint256 a, uint256 b) internal pure returns (string memory) {
        if (b == 0) return "0.00%";
        uint256 p = (a * 10000) / b; // basis points
        uint256 whole = p / 100;
        uint256 frac = p % 100;
        return string.concat(toString(whole), ".", (frac < 10) ? "0" : "", toString(frac), "%");
    }

    /*──────────────────────  ESCAPE  ─────────────────────*/

    function esc(string memory s) internal pure returns (string memory result) {
        assembly ("memory-safe") {
            result := mload(0x40)
            let end := add(s, mload(s))
            let o := add(result, 0x20)
            mstore(0x1f, 0x900094)
            mstore(0x08, 0xc0000000a6ab)
            mstore(0x00, shl(64, 0x2671756f743b26616d703b262333393b266c743b2667743b))
            for {} iszero(eq(s, end)) {} {
                s := add(s, 1)
                let c := and(mload(s), 0xff)
                if iszero(and(shl(c, 1), 0x500000c400000000)) {
                    mstore8(o, c)
                    o := add(o, 1)
                    continue
                }
                let t := shr(248, mload(c))
                mstore(o, mload(and(t, 0x1f)))
                o := add(o, shr(5, t))
            }
            mstore(o, 0)
            mstore(result, sub(o, add(result, 0x20)))
            mstore(0x40, add(o, 0x20))
        }
    }

    /*──────────────────────  MINI STRING PRIMS  ─────────────────────*/

    function toString(uint256 value) internal pure returns (string memory result) {
        assembly ("memory-safe") {
            result := add(mload(0x40), 0x80)
            mstore(0x40, add(result, 0x20))
            mstore(result, 0)
            let end := result
            let w := not(0)
            for { let temp := value } 1 {} {
                result := add(result, w)
                mstore8(result, add(48, mod(temp, 10)))
                temp := div(temp, 10)
                if iszero(temp) { break }
            }
            let n := sub(end, result)
            result := sub(result, 0x20)
            mstore(result, n)
        }
    }

    function slice(string memory subject, uint256 start, uint256 end)
        internal
        pure
        returns (string memory result)
    {
        assembly ("memory-safe") {
            let l := mload(subject)
            if iszero(gt(l, end)) { end := l }
            if iszero(gt(l, start)) { start := l }
            if lt(start, end) {
                result := mload(0x40)
                let n := sub(end, start)
                let i := add(subject, start)
                let w := not(0x1f)
                for { let j := and(add(n, 0x1f), w) } 1 {} {
                    mstore(add(result, j), mload(add(i, j)))
                    j := add(j, w)
                    if iszero(j) { break }
                }
                let o := add(add(result, 0x20), n)
                mstore(o, 0)
                mstore(0x40, add(o, 0x20))
                mstore(result, n)
            }
        }
    }

    /*──────────────────────  MINI HEX PRIMS  ─────────────────────*/

    function toHexStringChecksummed(address value) internal pure returns (string memory result) {
        assembly ("memory-safe") {
            result := mload(0x40)
            mstore(0x40, add(result, 0x80))
            mstore(0x0f, 0x30313233343536373839616263646566)
            result := add(result, 2)
            mstore(result, 40)
            let o := add(result, 0x20)
            mstore(add(o, 40), 0)
            value := shl(96, value)
            for { let i := 0 } 1 {} {
                let p := add(o, add(i, i))
                let temp := byte(i, value)
                mstore8(add(p, 1), mload(and(temp, 15)))
                mstore8(p, mload(shr(4, temp)))
                i := add(i, 1)
                if eq(i, 20) { break }
            }
            mstore(result, 0x3078)
            result := sub(result, 2)
            mstore(result, 42)
            let mask := shl(6, div(not(0), 255))
            o := add(result, 0x22)
            let hashed := and(keccak256(o, 40), mul(34, mask))
            let t := shl(240, 136)
            for { let i := 0 } 1 {} {
                mstore(add(i, i), mul(t, byte(i, hashed)))
                i := add(i, 1)
                if eq(i, 20) { break }
            }
            mstore(o, xor(mload(o), shr(1, and(mload(0x00), and(mload(o), mask)))))
            o := add(o, 0x20)
            mstore(o, xor(mload(o), shr(1, and(mload(0x20), and(mload(o), mask)))))
        }
    }

    /*──────────────────────  MINI BASE64  ─────────────────────*/

    function encode(bytes memory data) internal pure returns (string memory result) {
        assembly ("memory-safe") {
            let dataLength := mload(data)
            if dataLength {
                let encodedLength := shl(2, div(add(dataLength, 2), 3))
                result := mload(0x40)
                mstore(0x1f, "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdef")
                mstore(0x3f, "ghijklmnopqrstuvwxyz0123456789+/")
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
                mstore(ptr, 0)
                mstore(result, encodedLength)
            }
        }
    }
}

/// @title Moloch Majeur Summoner
contract Summoner {
    event NewDAO(address indexed summoner, Moloch indexed dao);

    Moloch[] public daos;
    Moloch immutable implementation;

    error DeploymentFailed();

    constructor() payable {
        emit NewDAO(address(this), implementation = new Moloch{salt: bytes32(0)}());
    }

    /// @dev Summon new Majeur clone with initialization calls:
    function summon(
        string calldata orgName,
        string calldata orgSymbol,
        string calldata orgURI,
        uint16 _quorumBps, // e.g. 5000 = 50% turnout of snapshot supply
        bool _ragequittable,
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
            _quorumBps,
            _ragequittable,
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

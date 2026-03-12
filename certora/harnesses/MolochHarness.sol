// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

// Minimal interface stubs
interface IShares {
    function getVotes(address) external view returns (uint256);
    function getPastVotes(address, uint48) external view returns (uint256);
    function getPastTotalSupply(uint48) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function balanceOf(address) external view returns (uint256);
    function mintFromMoloch(address, uint256) external;
    function burnFromMoloch(address, uint256) external;
    function setTransfersLocked(bool) external;
    function transfer(address, uint256) external returns (bool);
}

interface ILoot {
    function totalSupply() external view returns (uint256);
    function balanceOf(address) external view returns (uint256);
    function mintFromMoloch(address, uint256) external;
    function burnFromMoloch(address, uint256) external;
    function setTransfersLocked(bool) external;
    function transfer(address, uint256) external returns (bool);
}

interface IBadges {
    function balanceOf(address) external view returns (uint256);
    function onSharesChanged(address) external;
}

error SBT();
error Unauthorized();

struct Call {
    address target;
    uint256 value;
    bytes data;
}

/// @dev Simplified Moloch harness for Certora.
/// Strips: init/CREATE2 deployment, complex futarchy, ragequit token loop, assembly helpers,
/// transient storage reentrancy guard, multicall, batchCalls, URI/render functions.
/// Preserves: ERC-6909, proposal state, voting, settings, sale, allowance, permit (simplified).
contract MolochHarness {
    /* ERRORS */
    error NotOk();
    error Expired();
    error TooEarly();
    error Reentrancy();
    error AlreadyVoted();
    error LengthMismatch();
    error AlreadyExecuted();
    error Timelocked(uint64 untilWhen);

    modifier onlyDAO() {
        require(msg.sender == address(this), Unauthorized());
        _;
    }

    /* STATE */
    uint96 public proposalThreshold;
    uint96 public minYesVotesAbsolute;
    uint96 public quorumAbsolute;
    uint64 public proposalTTL;
    uint64 public timelockDelay;
    uint64 public config;
    uint16 public quorumBps;
    bool public ragequittable;

    address public renderer;
    address public shares;  // IShares
    address public badges;  // IBadges
    address public loot;    // ILoot

    mapping(uint256 id => bool) public executed;
    mapping(uint256 id => uint64) public createdAt;
    mapping(uint256 id => uint48) public snapshotBlock;
    mapping(uint256 id => uint256) public supplySnapshot;
    mapping(uint256 id => uint64) public queuedAt;

    struct Tally {
        uint96 forVotes;
        uint96 againstVotes;
        uint96 abstainVotes;
    }
    mapping(uint256 id => Tally) public tallies;

    mapping(uint256 id => mapping(address voter => uint8)) public hasVoted;
    mapping(uint256 => mapping(address => uint96)) public voteWeight;

    enum ProposalState {
        Unopened, Active, Queued, Succeeded, Defeated, Expired, Executed
    }

    /* PERMIT STATE */
    mapping(uint256 id => bool) public isPermitReceipt;
    mapping(address token => mapping(address spender => uint256 amount)) public allowance;

    /* SALE STATE */
    struct Sale {
        uint256 pricePerShare;
        uint256 cap;
        bool minting;
        bool active;
        bool isLoot;
    }
    mapping(address payToken => Sale) public sales;

    /* FUTARCHY (minimal) */
    uint256 public autoFutarchyParam;
    uint256 public autoFutarchyCap;
    address public rewardToken;

    struct FutarchyConfig {
        bool enabled;
        address rewardToken;
        uint256 pool;
        bool resolved;
        uint8 winner;
        uint256 finalWinningSupply;
        uint256 payoutPerUnit;
    }
    mapping(uint256 id => FutarchyConfig) public futarchy;

    /* ERC6909 STATE */
    mapping(address owner => mapping(uint256 id => uint256)) public balanceOf;
    mapping(uint256 id => uint256) public totalSupply;
    mapping(address owner => mapping(address operator => bool)) public isOperator;

    constructor() payable {}

    // ──── ERC-6909 (Invariants 1-3) ────

    function transfer(address receiver, uint256 id, uint256 amount) public returns (bool) {
        if (isPermitReceipt[id]) revert SBT();
        balanceOf[msg.sender][id] -= amount;
        unchecked {
            balanceOf[receiver][id] += amount;
        }
        return true;
    }

    function transferFrom(address sender, address receiver, uint256 id, uint256 amount)
        public returns (bool)
    {
        if (isPermitReceipt[id]) revert SBT();
        require(msg.sender == sender || isOperator[sender][msg.sender], Unauthorized());
        balanceOf[sender][id] -= amount;
        unchecked {
            balanceOf[receiver][id] += amount;
        }
        return true;
    }

    function setOperator(address operator, bool approved) public returns (bool) {
        isOperator[msg.sender][operator] = approved;
        return true;
    }

    function _mint6909(address to, uint256 id, uint256 amount) internal {
        totalSupply[id] += amount;
        unchecked {
            balanceOf[to][id] += amount;
        }
    }

    function _burn6909(address from, uint256 id, uint256 amount) internal {
        balanceOf[from][id] -= amount;
        unchecked {
            totalSupply[id] -= amount;
        }
    }

    // ──── Voting (Invariants 13-16) ────
    // Simplified: no auto-open, no futarchy check

    function castVote(uint256 id, uint8 support) public {
        if (executed[id]) revert AlreadyExecuted();
        if (support > 2) revert NotOk();

        if (hasVoted[id][msg.sender] != 0) revert AlreadyVoted();

        // Use snapshotBlock to get past voting power
        uint48 snap = snapshotBlock[id];
        require(snap != 0, NotOk()); // must be opened
        uint96 weight = uint96(IShares(shares).getPastVotes(msg.sender, snap));
        if (weight == 0) revert Unauthorized();

        Tally storage t = tallies[id];
        unchecked {
            if (support == 1) t.forVotes += weight;
            else if (support == 0) t.againstVotes += weight;
            else t.abstainVotes += weight;

            hasVoted[id][msg.sender] = support + 1;
            voteWeight[id][msg.sender] = weight;
        }
    }

    // ──── Proposal state monotonicity (Invariants 4-8, 11) ────
    // These are parametric rules; we need the state-changing functions

    function openProposal(uint256 id) public {
        if (snapshotBlock[id] != 0) return;
        if (createdAt[id] == 0) createdAt[id] = uint64(block.timestamp);
        unchecked {
            snapshotBlock[id] = uint48(block.number - 1);
        }
        supplySnapshot[id] = IShares(shares).getPastTotalSupply(snapshotBlock[id]);
    }

    function cancelProposal(uint256 id) public {
        Tally memory t = tallies[id];
        if ((t.forVotes | t.againstVotes | t.abstainVotes) != 0) revert NotOk();
        executed[id] = true;
    }

    // Simplified execute (Invariants 51-52)
    // Adds Unopened state rejection matching real code's state(id) != Succeeded/Queued
    function executeByVotes(uint256 id) public {
        if (executed[id]) revert AlreadyExecuted();
        if (snapshotBlock[id] == 0) revert NotOk(); // Unopened proposals cannot execute

        if (timelockDelay != 0) {
            if (queuedAt[id] == 0) {
                queuedAt[id] = uint64(block.timestamp);
                return;
            }
            uint64 untilWhen = queuedAt[id] + timelockDelay;
            if (block.timestamp < untilWhen) revert Timelocked(untilWhen);
        }

        executed[id] = true;
    }

    function queue(uint256 id) public {
        if (timelockDelay == 0) return;
        if (queuedAt[id] == 0) {
            queuedAt[id] = uint64(block.timestamp);
        }
    }

    // ──── Settings (Invariants 30-40) ────

    function setProposalThreshold(uint96 v) public payable onlyDAO {
        proposalThreshold = v;
    }

    function setProposalTTL(uint64 s) public payable onlyDAO {
        proposalTTL = s;
    }

    function setTimelockDelay(uint64 s) public payable onlyDAO {
        timelockDelay = s;
    }

    function setQuorumAbsolute(uint96 v) public payable onlyDAO {
        quorumAbsolute = v;
    }

    function setMinYesVotesAbsolute(uint96 v) public payable onlyDAO {
        minYesVotesAbsolute = v;
    }

    function setQuorumBps(uint16 bps) public payable onlyDAO {
        if (bps > 10_000) revert NotOk();
        quorumBps = bps;
    }

    function setRagequittable(bool on) public payable onlyDAO {
        ragequittable = on;
    }

    function setRenderer(address r) public payable onlyDAO {
        renderer = r;
    }

    function setAutoFutarchy(uint256 param, uint256 cap) public payable onlyDAO {
        (autoFutarchyParam, autoFutarchyCap) = (param, cap);
    }

    function setFutarchyRewardToken(address _rewardToken) public payable onlyDAO {
        rewardToken = _rewardToken;
    }

    function setPermitReceipt(uint256 id) public payable onlyDAO {
        isPermitReceipt[id] = true;
    }

    function bumpConfig() public payable onlyDAO {
        unchecked {
            ++config;
        }
    }

    // ──── Sale (Invariants 43-47) ────

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
    }

    function buyShares(address payToken, uint256 shareAmount, uint256 maxPay) public payable {
        if (shareAmount == 0) revert NotOk();
        Sale storage s = sales[payToken];
        if (!s.active) revert NotOk();

        uint256 cap = s.cap;
        if (cap != 0 && shareAmount > cap) revert NotOk();

        uint256 price = s.pricePerShare;
        uint256 cost = shareAmount * price;

        if (maxPay != 0 && cost > maxPay) revert NotOk();

        if (cap != 0) {
            unchecked {
                s.cap = cap - shareAmount;
            }
        }
    }

    // ──── Allowance (Invariants 48-49) ────

    function setAllowance(address spender, address token, uint256 amount) public payable onlyDAO {
        allowance[token][spender] = amount;
    }

    function spendAllowance(address token, uint256 amount) public {
        allowance[token][msg.sender] -= amount;
    }

    // ──── Harness getters ────

    function getExecuted(uint256 id) external view returns (bool) {
        return executed[id];
    }

    function getCreatedAt(uint256 id) external view returns (uint64) {
        return createdAt[id];
    }

    function getSnapshotBlock(uint256 id) external view returns (uint48) {
        return snapshotBlock[id];
    }

    function getSupplySnapshot(uint256 id) external view returns (uint256) {
        return supplySnapshot[id];
    }

    function getQueuedAt(uint256 id) external view returns (uint64) {
        return queuedAt[id];
    }

    function getIsPermitReceipt(uint256 id) external view returns (bool) {
        return isPermitReceipt[id];
    }

    function getAllowance(address token, address spender) external view returns (uint256) {
        return allowance[token][spender];
    }

    function getSaleActive(address payToken) external view returns (bool) {
        return sales[payToken].active;
    }

    function getSaleCap(address payToken) external view returns (uint256) {
        return sales[payToken].cap;
    }

    function getSalePrice(address payToken) external view returns (uint256) {
        return sales[payToken].pricePerShare;
    }

    function getHasVoted(uint256 id, address voter) external view returns (uint8) {
        return hasVoted[id][voter];
    }

    function getVoteWeight(uint256 id, address voter) external view returns (uint96) {
        return voteWeight[id][voter];
    }

    function getForVotes(uint256 id) external view returns (uint96) {
        return tallies[id].forVotes;
    }

    function getAgainstVotes(uint256 id) external view returns (uint96) {
        return tallies[id].againstVotes;
    }

    function getAbstainVotes(uint256 id) external view returns (uint96) {
        return tallies[id].abstainVotes;
    }

    function getState(uint256 id) external view returns (uint8) {
        if (executed[id]) return uint8(ProposalState.Executed);
        if (snapshotBlock[id] == 0) return uint8(ProposalState.Unopened);
        if (queuedAt[id] != 0) return uint8(ProposalState.Queued);
        return uint8(ProposalState.Active);
    }

    // ──── Futarchy (Invariants 19-23) ────
    // Simplified: strips token validation, ETH/ERC20 pull logic, state machine checks.
    // Preserves core state transitions and revert conditions.

    // Deterministic receipt ID (replaces keccak256 which is opaque to prover)
    function _receiptId(uint256 id, uint8 support) internal pure returns (uint256) {
        return id * 3 + support;
    }

    function fundFutarchy(uint256 id, uint256 amount) public {
        if (amount == 0) revert NotOk();
        FutarchyConfig storage F = futarchy[id];
        if (F.resolved) revert NotOk();

        if (!F.enabled) {
            F.enabled = true;
        }
        F.pool += amount;
    }

    function resolveFutarchyNo(uint256 id) public {
        FutarchyConfig storage F = futarchy[id];
        if (!F.enabled || F.resolved || executed[id]) revert NotOk();
        _finalizeFutarchy(id, F, 0);
    }

    function cashOutFutarchy(uint256 id, uint256 amount) public {
        FutarchyConfig storage F = futarchy[id];
        if (!F.enabled || !F.resolved) revert NotOk();

        uint8 winner = F.winner;
        uint256 rid = _receiptId(id, winner);
        _burn6909(msg.sender, rid, amount);
        // payout transfer stripped — not relevant to state invariants
    }

    function _finalizeFutarchy(uint256 id, FutarchyConfig storage F, uint8 winner) internal {
        unchecked {
            uint256 rid = _receiptId(id, winner);
            uint256 winSupply = totalSupply[rid];
            uint256 pool = F.pool;
            if (winSupply != 0 && pool != 0) {
                F.finalWinningSupply = winSupply;
                F.payoutPerUnit = mulDiv(pool, 1e18, winSupply);
            }
            F.resolved = true;
            F.winner = winner;
        }
    }

    // Harness: expose _finalizeFutarchy for CVL rule testing
    function finalizeFutarchyHarness(uint256 id, uint8 winner) public {
        FutarchyConfig storage F = futarchy[id];
        if (!F.enabled || F.resolved) revert NotOk();
        _finalizeFutarchy(id, F, winner);
    }

    // ──── Futarchy harness getters ────

    function getFutarchyEnabled(uint256 id) external view returns (bool) {
        return futarchy[id].enabled;
    }

    function getFutarchyResolved(uint256 id) external view returns (bool) {
        return futarchy[id].resolved;
    }

    function getFutarchyPool(uint256 id) external view returns (uint256) {
        return futarchy[id].pool;
    }

    function getFutarchyPayoutPerUnit(uint256 id) external view returns (uint256) {
        return futarchy[id].payoutPerUnit;
    }

    function getFutarchyFinalWinningSupply(uint256 id) external view returns (uint256) {
        return futarchy[id].finalWinningSupply;
    }

    function getFutarchyWinner(uint256 id) external view returns (uint8) {
        return futarchy[id].winner;
    }

    function getReceiptId(uint256 id, uint8 support) external pure returns (uint256) {
        return _receiptId(id, support);
    }

    // ──── Ragequit (Invariants 27-28) ────
    // Simplified: strips token array loop, external transfers, ascending order check,
    // banned address checks. Preserves core revert conditions.

    function ragequit(uint256 sharesToBurn, uint256 lootToBurn) public {
        if (!ragequittable) revert NotOk();
        if (sharesToBurn == 0 && lootToBurn == 0) revert NotOk();
    }

    // ──── Math (Invariant 24) ────

    function mulDiv(uint256 x, uint256 y, uint256 denominator) public pure returns (uint256 result) {
        require(denominator != 0);
        uint256 prod0 = x * y;
        require(prod0 / x == y || x == 0); // overflow check
        result = prod0 / denominator;
    }

    receive() external payable {}
}

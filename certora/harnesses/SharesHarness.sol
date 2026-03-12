// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

// Minimal interfaces
interface IMolochView {
    function name(uint256 id) external view returns (string memory);
    function symbol(uint256 id) external view returns (string memory);
    function onSharesChanged(address) external;
}

// Global errors and utils used by Shares
error Locked();
error Unauthorized();

contract SharesHarness {
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

    /* VOTES */
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
    Checkpoint[] internal _totalSupplyCheckpoints;

    /* Split delegation */
    struct Split {
        address delegate;
        uint32 bps;
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
        }
    }

    function name() public view returns (string memory) {
        return string.concat(IMolochView(DAO).name(0), " Shares");
    }

    function symbol() public view returns (string memory) {
        return IMolochView(DAO).symbol(0);
    }

    function approve(address to, uint256 amount) public returns (bool) {
        allowance[msg.sender][to] = amount;
        emit Approval(msg.sender, to, amount);
        return true;
    }

    function transfer(address to, uint256 amount) public returns (bool) {
        _checkUnlocked(msg.sender, to);
        balanceOf[msg.sender] -= amount;
        unchecked { balanceOf[to] += amount; }
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public returns (bool) {
        _checkUnlocked(from, to);
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) allowance[from][msg.sender] = allowed - amount;
        balanceOf[from] -= amount;
        unchecked { balanceOf[to] += amount; }
        emit Transfer(from, to, amount);
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
        unchecked { totalSupply -= amount; }
        emit Transfer(from, address(0), amount);
        _writeTotalSupplyCheckpoint();
    }

    function delegates(address account) public view returns (address) {
        address del = _delegates[account];
        return del == address(0) ? account : del;
    }

    function delegate(address delegatee) public {
        address account = msg.sender;
        if (delegatee == address(0)) delegatee = account;
        address current = _delegates[account];
        if (current == address(0)) current = account;
        if (_splits[account].length != 0) delete _splits[account];
        _delegates[account] = delegatee;
        emit DelegateChanged(account, current, delegatee);
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
        Checkpoint[] storage ckpts = _checkpoints[account];
        uint256 len = ckpts.length;
        if (len == 0) return 0;
        return ckpts[len - 1].votes;
    }

    function getPastTotalSupply(uint48 blockNumber) public view returns (uint256) {
        if (blockNumber >= block.number) revert BadBlock();
        Checkpoint[] storage ckpts = _totalSupplyCheckpoints;
        uint256 len = ckpts.length;
        if (len == 0) return 0;
        return ckpts[len - 1].votes;
    }

    function setSplitDelegation(address[] calldata delegates_, uint32[] calldata bps_) public {
        address account = msg.sender;
        uint256 n = delegates_.length;
        require(n == bps_.length && n > 0 && n <= MAX_SPLITS, SplitLen());

        uint256 sum;
        for (uint256 i; i != n; ++i) {
            address d = delegates_[i];
            require(d != address(0), SplitZero());
            uint32 b = bps_[i];
            sum += b;
            for (uint256 j = i + 1; j != n; ++j) {
                require(d != delegates_[j], SplitDupe());
            }
        }
        require(sum == BPS_DENOM, SplitSum());

        delete _splits[account];
        for (uint256 i; i != n; ++i) {
            _splits[account].push(Split({delegate: delegates_[i], bps: bps_[i]}));
        }
        emit WeightedDelegationSet(account, delegates_, bps_);
    }

    function clearSplitDelegation() public {
        address account = msg.sender;
        if (_splits[account].length == 0) return;
        delete _splits[account];
    }

    // ──── Internal functions ────

    function _mint(address to, uint256 amount) internal {
        totalSupply += amount;
        unchecked { balanceOf[to] += amount; }
        emit Transfer(address(0), to, amount);
        _writeTotalSupplyCheckpoint();
    }

    function _checkUnlocked(address from, address to) internal view {
        if (transfersLocked && from != DAO && to != DAO) { revert Locked(); }
    }

    function _writeTotalSupplyCheckpoint() internal {
        unchecked {
            Checkpoint[] storage ckpts = _totalSupplyCheckpoints;
            uint256 len = ckpts.length;
            uint256 oldVal = len == 0 ? 0 : ckpts[len - 1].votes;
            uint256 newVal = totalSupply;
            if (oldVal == newVal) return;
            uint48 blk = uint48(block.number);
            if (len != 0 && ckpts[len - 1].fromBlock == blk) {
                ckpts[len - 1].votes = uint96(newVal);
                return;
            }
            ckpts.push(Checkpoint({fromBlock: blk, votes: uint96(newVal)}));
        }
    }

    // ──── targetAlloc harness (Invariant 64) ────
    // Mirrors _targetAlloc: for each split, compute mulDiv(bal, bps, BPS_DENOM),
    // remainder assigned to last. Returns sum of allocations.
    function targetAllocSum(uint256 bal, address account) external view returns (uint256) {
        Split[] storage splits = _splits[account];
        uint256 n = splits.length;
        if (n == 0) return bal; // no splits means full balance to self

        uint256 sum;
        uint256 remainder = bal;
        for (uint256 i; i < n; ++i) {
            uint256 alloc;
            if (i == n - 1) {
                alloc = remainder;
            } else {
                alloc = (bal * splits[i].bps) / BPS_DENOM;
                remainder -= alloc;
            }
            sum += alloc;
        }
        return sum;
    }

    // ───── Harness getters for internal state ─────

    function getPrimaryDelegate(address delegator) external view returns (address) {
        return _delegates[delegator];
    }

    function getCheckpointCount(address delegate_) external view returns (uint256) {
        return _checkpoints[delegate_].length;
    }

    function getCheckpointFromBlock(address delegate_, uint256 index)
        external view returns (uint48)
    {
        return _checkpoints[delegate_][index].fromBlock;
    }

    function getCheckpointVotes(address delegate_, uint256 index)
        external view returns (uint96)
    {
        return _checkpoints[delegate_][index].votes;
    }

    function getTotalSupplyCheckpointCount() external view returns (uint256) {
        return _totalSupplyCheckpoints.length;
    }

    function getSplitCount(address delegator) external view returns (uint256) {
        return _splits[delegator].length;
    }

    function getSplitDelegate(address delegator, uint256 index) external view returns (address) {
        return _splits[delegator][index].delegate;
    }

    function getSplitBps(address delegator, uint256 index) external view returns (uint32) {
        return _splits[delegator][index].bps;
    }
}

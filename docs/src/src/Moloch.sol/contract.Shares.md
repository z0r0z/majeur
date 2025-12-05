# Shares
[Git Source](https://github.com/z0r0z/SAW/blob/5b287591f19dce0ac310dc192604a613e25f6e34/src/Moloch.sol)


## State Variables
### decimals

```solidity
uint8 public constant decimals = 18
```


### transfersLocked

```solidity
bool public transfersLocked
```


### totalSupply

```solidity
uint256 public totalSupply
```


### balanceOf

```solidity
mapping(address => uint256) public balanceOf
```


### allowance

```solidity
mapping(address => mapping(address => uint256)) public allowance
```


### DAO

```solidity
address payable public DAO
```


### _delegates

```solidity
mapping(address delegator => address primaryDelegate) internal _delegates
```


### _checkpoints

```solidity
mapping(address delegate => Checkpoint[] voteHistory) internal _checkpoints
```


### _totalSupplyCheckpoints

```solidity
Checkpoint[] internal _totalSupplyCheckpoints
```


### MAX_SPLITS

```solidity
uint8 constant MAX_SPLITS = 4
```


### BPS_DENOM

```solidity
uint32 constant BPS_DENOM = 10_000
```


### _splits

```solidity
mapping(address delegator => Split[] splitConfig) internal _splits
```


## Functions
### onlyDAO


```solidity
modifier onlyDAO() ;
```

### constructor


```solidity
constructor() payable;
```

### init


```solidity
function init(address[] memory initHolders, uint256[] memory initShares) public payable;
```

### name


```solidity
function name() public view returns (string memory);
```

### symbol


```solidity
function symbol() public view returns (string memory);
```

### approve


```solidity
function approve(address to, uint256 amount) public returns (bool);
```

### transfer


```solidity
function transfer(address to, uint256 amount) public returns (bool);
```

### transferFrom


```solidity
function transferFrom(address from, address to, uint256 amount) public returns (bool);
```

### setTransfersLocked


```solidity
function setTransfersLocked(bool locked) public payable onlyDAO;
```

### mintFromMoloch


```solidity
function mintFromMoloch(address to, uint256 amount) public payable onlyDAO;
```

### burnFromMoloch


```solidity
function burnFromMoloch(address from, uint256 amount) public payable onlyDAO;
```

### _mint


```solidity
function _mint(address to, uint256 amount) internal;
```

### _moveTokens


```solidity
function _moveTokens(address from, address to, uint256 amount) internal;
```

### _updateDelegateVotes


```solidity
function _updateDelegateVotes(
    address delegate_,
    Checkpoint[] storage ckpts,
    bool add,
    uint256 amount
) internal;
```

### _checkUnlocked


```solidity
function _checkUnlocked(address from, address to) internal view;
```

### delegates


```solidity
function delegates(address account) public view returns (address);
```

### delegate


```solidity
function delegate(address delegatee) public;
```

### getVotes


```solidity
function getVotes(address account) public view returns (uint256);
```

### getPastVotes


```solidity
function getPastVotes(address account, uint48 blockNumber) public view returns (uint256);
```

### getPastTotalSupply


```solidity
function getPastTotalSupply(uint48 blockNumber) public view returns (uint256);
```

### splitDelegationOf

Returns the effective split delegation of an account
(defaults to 100% self if no splits set):


```solidity
function splitDelegationOf(address account)
    public
    view
    returns (address[] memory delegates_, uint32[] memory bps_);
```

### setSplitDelegation


```solidity
function setSplitDelegation(address[] calldata delegates_, uint32[] calldata bps_) public;
```

### clearSplitDelegation


```solidity
function clearSplitDelegation() public;
```

### _delegate


```solidity
function _delegate(address delegator, address delegatee) internal;
```

### _autoSelfDelegate


```solidity
function _autoSelfDelegate(address account) internal;
```

### _currentDistribution

Returns the current split (or a single 100% primary delegate if unset):


```solidity
function _currentDistribution(address account)
    internal
    view
    returns (address[] memory delegates_, uint32[] memory bps_);
```

### _afterVotingBalanceChange


```solidity
function _afterVotingBalanceChange(address account, int256 delta) internal;
```

### _applyVotingDelta

Apply +/- voting power change for an account according to its split,
in a *path-independent* way based on old vs new target allocations:


```solidity
function _applyVotingDelta(address account, int256 delta) internal;
```

### _repointVotesForHolder

Re-route an existing holder's current voting power from `old` distribution to
the holder's *current* distribution (as returned by _currentDistribution),
in a path-independent way based on old vs new target allocations:


```solidity
function _repointVotesForHolder(address holder, address[] memory oldD, uint32[] memory oldB)
    internal;
```

### _targetAlloc

Helper: exact target allocation with "remainder to last":


```solidity
function _targetAlloc(uint256 bal, address[] memory D, uint32[] memory B)
    internal
    pure
    returns (uint256[] memory A);
```

### _moveVotingPower


```solidity
function _moveVotingPower(address src, address dst, uint256 amount) internal;
```

### _writeCheckpoint


```solidity
function _writeCheckpoint(Checkpoint[] storage ckpts, uint256 oldVal, uint256 newVal) internal;
```

### _writeTotalSupplyCheckpoint


```solidity
function _writeTotalSupplyCheckpoint() internal;
```

### _checkpointsLookup


```solidity
function _checkpointsLookup(Checkpoint[] storage ckpts, uint48 blockNumber)
    internal
    view
    returns (uint256);
```

### _singleton


```solidity
function _singleton(address d) internal pure returns (address[] memory a);
```

### _singletonBps


```solidity
function _singletonBps() internal pure returns (uint32[] memory a);
```

## Events
### Approval

```solidity
event Approval(address indexed from, address indexed to, uint256 amount);
```

### Transfer

```solidity
event Transfer(address indexed from, address indexed to, uint256 amount);
```

### DelegateChanged

```solidity
event DelegateChanged(
    address indexed delegator, address indexed fromDelegate, address indexed toDelegate
);
```

### DelegateVotesChanged

```solidity
event DelegateVotesChanged(
    address indexed delegate, uint256 previousBalance, uint256 newBalance
);
```

### WeightedDelegationSet

```solidity
event WeightedDelegationSet(address indexed delegator, address[] delegates, uint32[] bps);
```

## Errors
### BadBlock

```solidity
error BadBlock();
```

### SplitLen

```solidity
error SplitLen();
```

### SplitSum

```solidity
error SplitSum();
```

### SplitZero

```solidity
error SplitZero();
```

### SplitDupe

```solidity
error SplitDupe();
```

## Structs
### Checkpoint

```solidity
struct Checkpoint {
    uint48 fromBlock;
    uint96 votes;
}
```

### Split

```solidity
struct Split {
    address delegate;
    uint32 bps; // parts per 10_000
}
```


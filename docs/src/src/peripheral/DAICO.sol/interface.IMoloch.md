# IMoloch
[Git Source](https://github.com/z0r0z/SAW/blob/f78263900b4c307a2192ed2fbea7f7f40f54ee72/src/peripheral/DAICO.sol)

Minimal Moloch interface for tap mechanism.


## Functions
### spendAllowance


```solidity
function spendAllowance(address token, uint256 amount) external;
```

### setAllowance


```solidity
function setAllowance(address spender, address token, uint256 amount) external;
```

### allowance


```solidity
function allowance(address token, address spender) external view returns (uint256);
```

### setTransfersLocked


```solidity
function setTransfersLocked(bool sharesLocked, bool lootLocked) external;
```


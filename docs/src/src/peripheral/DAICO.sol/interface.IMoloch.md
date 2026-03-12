# IMoloch
[Git Source](https://github.com/z0r0z/majeur/blob/e68de9077c329150fa27252eafcfb094e7170075/src/peripheral/DAICO.sol)

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


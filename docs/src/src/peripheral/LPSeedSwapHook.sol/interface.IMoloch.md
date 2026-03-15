# IMoloch
[Git Source](https://github.com/z0r0z/majeur/blob/51bf2cf41940c30a56dd06b7564697883db9ead0/src/peripheral/LPSeedSwapHook.sol)

Minimal Moloch interface.


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

### shares


```solidity
function shares() external view returns (address);
```

### loot


```solidity
function loot() external view returns (address);
```


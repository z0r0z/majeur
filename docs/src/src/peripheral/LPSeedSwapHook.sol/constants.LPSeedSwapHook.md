# Constants
[Git Source](https://github.com/z0r0z/majeur/blob/13360a942bd5f358d43ac5a53ba3981007990305/src/peripheral/LPSeedSwapHook.sol)

### ZAMM
ZAMM singleton address.


```solidity
IZAMM constant ZAMM = IZAMM(0x000000000000040470635EB91b7CE4D132D616eD)
```

### FLAG_BEFORE
Hook encoding flag — only beforeAction is used (afterAction is not registered).


```solidity
uint256 constant FLAG_BEFORE = 1 << 255
```

### DEFAULT_FEE_BPS
Default swap fee when none configured (30 bps = 0.30%).


```solidity
uint16 constant DEFAULT_FEE_BPS = 30
```


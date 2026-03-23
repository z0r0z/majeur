# Constants
[Git Source](https://github.com/z0r0z/majeur/blob/376bbb9940915c61b80e913ec9f3094c9c5ef7bc/src/peripheral/LPSeedSwapHook.sol)

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
Default swap fee when none configured (25 bps = 0.25%).


```solidity
uint16 constant DEFAULT_FEE_BPS = 25
```


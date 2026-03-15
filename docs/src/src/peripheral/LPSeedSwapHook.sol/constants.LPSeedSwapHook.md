# Constants
[Git Source](https://github.com/z0r0z/majeur/blob/7b0b09c645157c41733569026978219fbad0e559/src/peripheral/LPSeedSwapHook.sol)

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


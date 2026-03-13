# ensureApproval
[Git Source](https://github.com/z0r0z/majeur/blob/ae954c8dacf035c306a2f543ff58bff38b7c1bef/src/peripheral/LPSeedSwapHook.sol)

Ensures approval to spender is sufficient (>= type(uint128).max threshold).
Works with USDT-style tokens because the first approval starts from 0,
and subsequent calls skip the branch since allowance stays above threshold.


```solidity
function ensureApproval(address token, address spender) ;
```


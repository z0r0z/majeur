# ensureApproval
[Git Source](https://github.com/z0r0z/majeur/blob/7b0b09c645157c41733569026978219fbad0e559/src/peripheral/LPSeedSwapHook.sol)

Ensures approval to spender is sufficient (>= type(uint128).max threshold).
Works with USDT-style tokens because the first approval starts from 0,
and subsequent calls skip the branch since allowance stays above threshold.


```solidity
function ensureApproval(address token, address spender) ;
```


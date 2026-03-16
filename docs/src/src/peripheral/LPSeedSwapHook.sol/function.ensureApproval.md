# ensureApproval
[Git Source](https://github.com/z0r0z/majeur/blob/676b7eee1f7e1cd8bc1842d11a4fbdc43b31c4ac/src/peripheral/LPSeedSwapHook.sol)

Ensures approval to spender is sufficient (>= type(uint128).max threshold).
Works with USDT-style tokens because the first approval starts from 0,
and subsequent calls skip the branch since allowance stays above threshold.


```solidity
function ensureApproval(address token, address spender) ;
```


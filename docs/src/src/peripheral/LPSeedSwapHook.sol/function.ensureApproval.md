# ensureApproval
[Git Source](https://github.com/z0r0z/majeur/blob/13360a942bd5f358d43ac5a53ba3981007990305/src/peripheral/LPSeedSwapHook.sol)

Ensures approval to spender is sufficient (>= type(uint128).max threshold).
Works with USDT-style tokens because the first approval starts from 0,
and subsequent calls skip the branch since allowance stays above threshold.


```solidity
function ensureApproval(address token, address spender) ;
```


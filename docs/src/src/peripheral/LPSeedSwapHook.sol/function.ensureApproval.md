# ensureApproval
[Git Source](https://github.com/z0r0z/majeur/blob/7a39232caba6bdf1dca11fa0402ac5168540b811/src/peripheral/LPSeedSwapHook.sol)

Ensures approval to spender is sufficient (>= type(uint128).max threshold).
Works with USDT-style tokens because the first approval starts from 0,
and subsequent calls skip the branch since allowance stays above threshold.


```solidity
function ensureApproval(address token, address spender) ;
```


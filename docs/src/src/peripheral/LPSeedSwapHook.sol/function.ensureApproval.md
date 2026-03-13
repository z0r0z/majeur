# ensureApproval
[Git Source](https://github.com/z0r0z/majeur/blob/26195c42ab2bc92f824f7691eb427e6f0f067100/src/peripheral/LPSeedSwapHook.sol)

Ensures approval to spender is sufficient (>= type(uint128).max threshold).
Works with USDT-style tokens because the first approval starts from 0,
and subsequent calls skip the branch since allowance stays above threshold.


```solidity
function ensureApproval(address token, address spender) ;
```


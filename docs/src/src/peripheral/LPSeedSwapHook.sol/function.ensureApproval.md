# ensureApproval
[Git Source](https://github.com/z0r0z/majeur/blob/51bf2cf41940c30a56dd06b7564697883db9ead0/src/peripheral/LPSeedSwapHook.sol)

Ensures approval to spender is sufficient (>= type(uint128).max threshold).
Works with USDT-style tokens because the first approval starts from 0,
and subsequent calls skip the branch since allowance stays above threshold.


```solidity
function ensureApproval(address token, address spender) ;
```


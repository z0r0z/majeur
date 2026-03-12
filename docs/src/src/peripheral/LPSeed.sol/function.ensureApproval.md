# ensureApproval
[Git Source](https://github.com/z0r0z/majeur/blob/e68de9077c329150fa27252eafcfb094e7170075/src/peripheral/LPSeed.sol)

Ensures approval to spender is sufficient (>= type(uint128).max threshold).
Compatible with USDT-style tokens that require allowance to be 0 before setting non-zero.


```solidity
function ensureApproval(address token, address spender) ;
```


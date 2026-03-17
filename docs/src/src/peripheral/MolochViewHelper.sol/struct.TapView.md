# TapView
[Git Source](https://github.com/z0r0z/majeur/blob/13360a942bd5f358d43ac5a53ba3981007990305/src/peripheral/MolochViewHelper.sol)


```solidity
struct TapView {
address ops; // beneficiary
address tribTkn; // token being tapped
uint128 ratePerSec; // rate in smallest units/sec
uint64 lastClaim; // last claim timestamp
uint256 claimable; // currently claimable amount
uint256 pending; // pending based on time (ignoring caps)
uint256 treasuryBalance; // tribTkn balance in DAO (available to tap)
uint256 tapAllowance; // Moloch treasury allowance to DAICO for tribTkn (tap budget)
}
```


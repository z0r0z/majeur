# TapView
[Git Source](https://github.com/z0r0z/majeur/blob/ae954c8dacf035c306a2f543ff58bff38b7c1bef/src/peripheral/MolochViewHelper.sol)


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


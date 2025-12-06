# TapView
[Git Source](https://github.com/z0r0z/SAW/blob/f78263900b4c307a2192ed2fbea7f7f40f54ee72/src/peripheral/MolochViewHelper.sol)


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


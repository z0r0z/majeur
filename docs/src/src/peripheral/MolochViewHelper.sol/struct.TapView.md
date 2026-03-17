# TapView
[Git Source](https://github.com/z0r0z/majeur/blob/44b014e70c45a531ab7ef5f4e32dcfcda5ea81fa/src/peripheral/MolochViewHelper.sol)


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


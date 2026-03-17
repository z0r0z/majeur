# VoterView
[Git Source](https://github.com/z0r0z/majeur/blob/44b014e70c45a531ab7ef5f4e32dcfcda5ea81fa/src/peripheral/MolochViewHelper.sol)


```solidity
struct VoterView {
address voter;
uint8 support; // 0 = AGAINST, 1 = FOR, 2 = ABSTAIN
uint256 weight; // voting weight at snapshot
}
```


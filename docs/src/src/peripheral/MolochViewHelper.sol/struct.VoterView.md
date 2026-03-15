# VoterView
[Git Source](https://github.com/z0r0z/majeur/blob/51bf2cf41940c30a56dd06b7564697883db9ead0/src/peripheral/MolochViewHelper.sol)


```solidity
struct VoterView {
address voter;
uint8 support; // 0 = AGAINST, 1 = FOR, 2 = ABSTAIN
uint256 weight; // voting weight at snapshot
}
```


# VoterView
[Git Source](https://github.com/z0r0z/SAW/blob/f78263900b4c307a2192ed2fbea7f7f40f54ee72/src/peripheral/MolochViewHelper.sol)


```solidity
struct VoterView {
address voter;
uint8 support; // 0 = AGAINST, 1 = FOR, 2 = ABSTAIN
uint256 weight; // voting weight at snapshot
}
```


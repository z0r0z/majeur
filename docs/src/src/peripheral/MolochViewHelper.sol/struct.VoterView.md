# VoterView
[Git Source](https://github.com/z0r0z/majeur/blob/d27ebad6d0eaf0dd2eddab2488ea43fd282fd832/src/peripheral/MolochViewHelper.sol)


```solidity
struct VoterView {
address voter;
uint8 support; // 0 = AGAINST, 1 = FOR, 2 = ABSTAIN
uint256 weight; // voting weight at snapshot
}
```


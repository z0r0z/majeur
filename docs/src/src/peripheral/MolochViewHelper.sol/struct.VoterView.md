# VoterView
[Git Source](https://github.com/z0r0z/majeur/blob/13360a942bd5f358d43ac5a53ba3981007990305/src/peripheral/MolochViewHelper.sol)


```solidity
struct VoterView {
address voter;
uint8 support; // 0 = AGAINST, 1 = FOR, 2 = ABSTAIN
uint256 weight; // voting weight at snapshot
}
```


# FutarchyView
[Git Source](https://github.com/z0r0z/majeur/blob/693e65b2d5461c8bced186f4330ea1fc0aee9dc9/src/peripheral/MolochViewHelper.sol)


```solidity
struct FutarchyView {
bool enabled;
address rewardToken;
uint256 pool;
bool resolved;
uint8 winner; // 1 = YES/FOR, 0 = NO/AGAINST
uint256 finalWinningSupply;
uint256 payoutPerUnit; // scaled by 1e18
}
```


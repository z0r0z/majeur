# FutarchyView
[Git Source](https://github.com/z0r0z/majeur/blob/376bbb9940915c61b80e913ec9f3094c9c5ef7bc/src/peripheral/MolochViewHelper.sol)


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


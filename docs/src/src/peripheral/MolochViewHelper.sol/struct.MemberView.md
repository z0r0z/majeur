# MemberView
[Git Source](https://github.com/z0r0z/majeur/blob/676b7eee1f7e1cd8bc1842d11a4fbdc43b31c4ac/src/peripheral/MolochViewHelper.sol)


```solidity
struct MemberView {
address account;
uint256 shares;
uint256 loot;
uint16 seatId; // 1..256, or 0 if none

uint256 votingPower; // current getVotes(account)
address[] delegates; // split delegation targets
uint32[] delegatesBps; // bps per delegate
}
```


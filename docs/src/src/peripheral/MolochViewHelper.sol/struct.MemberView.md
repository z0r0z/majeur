# MemberView
[Git Source](https://github.com/z0r0z/majeur/blob/7b0b09c645157c41733569026978219fbad0e559/src/peripheral/MolochViewHelper.sol)


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


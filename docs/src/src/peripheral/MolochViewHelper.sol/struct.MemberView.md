# MemberView
[Git Source](https://github.com/z0r0z/SAW/blob/f78263900b4c307a2192ed2fbea7f7f40f54ee72/src/peripheral/MolochViewHelper.sol)


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


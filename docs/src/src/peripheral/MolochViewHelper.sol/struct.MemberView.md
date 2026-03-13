# MemberView
[Git Source](https://github.com/z0r0z/majeur/blob/26195c42ab2bc92f824f7691eb427e6f0f067100/src/peripheral/MolochViewHelper.sol)


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


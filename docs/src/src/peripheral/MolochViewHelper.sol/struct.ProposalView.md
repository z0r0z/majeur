# ProposalView
[Git Source](https://github.com/z0r0z/SAW/blob/f78263900b4c307a2192ed2fbea7f7f40f54ee72/src/peripheral/MolochViewHelper.sol)


```solidity
struct ProposalView {
uint256 id;
address proposer;
uint8 state;

uint48 snapshotBlock;
uint64 createdAt;
uint64 queuedAt;
uint256 supplySnapshot;

uint96 forVotes;
uint96 againstVotes;
uint96 abstainVotes;

FutarchyView futarchy;
VoterView[] voters; // only members who actually voted
}
```


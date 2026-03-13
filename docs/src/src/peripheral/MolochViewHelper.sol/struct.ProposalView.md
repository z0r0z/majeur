# ProposalView
[Git Source](https://github.com/z0r0z/majeur/blob/ae954c8dacf035c306a2f543ff58bff38b7c1bef/src/peripheral/MolochViewHelper.sol)


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


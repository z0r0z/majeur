# DAOLens
[Git Source](https://github.com/z0r0z/majeur/blob/ae954c8dacf035c306a2f543ff58bff38b7c1bef/src/peripheral/MolochViewHelper.sol)


```solidity
struct DAOLens {
address dao;
DAOMeta meta;
DAOGovConfig gov;
DAOTokenSupplies supplies;
DAOTreasury treasury;
MemberView[] members;
ProposalView[] proposals;
MessageView[] messages;
}
```


# DAOLens
[Git Source](https://github.com/z0r0z/majeur/blob/51bf2cf41940c30a56dd06b7564697883db9ead0/src/peripheral/MolochViewHelper.sol)


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


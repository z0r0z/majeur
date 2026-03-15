# ISummoner
[Git Source](https://github.com/z0r0z/majeur/blob/51bf2cf41940c30a56dd06b7564697883db9ead0/src/peripheral/SafeSummoner.sol)


## Functions
### summon


```solidity
function summon(
    string calldata orgName,
    string calldata orgSymbol,
    string calldata orgURI,
    uint16 quorumBps,
    bool ragequittable,
    address renderer,
    bytes32 salt,
    address[] calldata initHolders,
    uint256[] calldata initShares,
    Call[] calldata initCalls
) external payable returns (address);
```


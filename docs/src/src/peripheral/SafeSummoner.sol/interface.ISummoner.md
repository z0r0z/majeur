# ISummoner
[Git Source](https://github.com/z0r0z/majeur/blob/26195c42ab2bc92f824f7691eb427e6f0f067100/src/peripheral/SafeSummoner.sol)


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


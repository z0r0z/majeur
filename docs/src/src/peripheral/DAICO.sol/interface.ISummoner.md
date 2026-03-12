# ISummoner
[Git Source](https://github.com/z0r0z/majeur/blob/d27ebad6d0eaf0dd2eddab2488ea43fd282fd832/src/peripheral/DAICO.sol)

Minimal Summoner interface.


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


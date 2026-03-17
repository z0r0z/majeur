# IMoloch
[Git Source](https://github.com/z0r0z/majeur/blob/44b014e70c45a531ab7ef5f4e32dcfcda5ea81fa/src/peripheral/ShareBurner.sol)


## Functions
### spendPermit


```solidity
function spendPermit(uint8 op, address to, uint256 value, bytes calldata data, bytes32 nonce)
    external;
```

### setPermit


```solidity
function setPermit(
    uint8 op,
    address to,
    uint256 value,
    bytes calldata data,
    bytes32 nonce,
    address spender,
    uint256 count
) external;
```


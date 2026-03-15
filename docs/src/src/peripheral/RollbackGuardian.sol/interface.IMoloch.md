# IMoloch
[Git Source](https://github.com/z0r0z/majeur/blob/51bf2cf41940c30a56dd06b7564697883db9ead0/src/peripheral/RollbackGuardian.sol)


## Functions
### bumpConfig


```solidity
function bumpConfig() external;
```

### setAutoFutarchy


```solidity
function setAutoFutarchy(uint256 param, uint256 cap) external;
```

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


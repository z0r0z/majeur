# IMoloch
[Git Source](https://github.com/z0r0z/majeur/blob/7b0b09c645157c41733569026978219fbad0e559/src/peripheral/RollbackGuardian.sol)


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


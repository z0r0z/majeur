# IShares
[Git Source](https://github.com/z0r0z/majeur/blob/376bbb9940915c61b80e913ec9f3094c9c5ef7bc/src/peripheral/MolochViewHelper.sol)


## Functions
### totalSupply


```solidity
function totalSupply() external view returns (uint256);
```

### balanceOf


```solidity
function balanceOf(address) external view returns (uint256);
```

### getVotes


```solidity
function getVotes(address) external view returns (uint256);
```

### splitDelegationOf


```solidity
function splitDelegationOf(address account)
    external
    view
    returns (address[] memory delegates_, uint32[] memory bps_);
```


# IShares
[Git Source](https://github.com/z0r0z/majeur/blob/7b0b09c645157c41733569026978219fbad0e559/src/peripheral/MolochViewHelper.sol)


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


# IShareSale
[Git Source](https://github.com/z0r0z/majeur/blob/7b0b09c645157c41733569026978219fbad0e559/src/peripheral/LPSeedSwapHook.sol)

Minimal ShareSale interface for checking remaining allowance.


## Functions
### sales


```solidity
function sales(address dao)
    external
    view
    returns (address token, address payToken, uint40 deadline, uint256 price);
```


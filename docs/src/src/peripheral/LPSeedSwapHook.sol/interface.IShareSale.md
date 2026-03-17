# IShareSale
[Git Source](https://github.com/z0r0z/majeur/blob/13360a942bd5f358d43ac5a53ba3981007990305/src/peripheral/LPSeedSwapHook.sol)

Minimal ShareSale interface for checking remaining allowance.


## Functions
### sales


```solidity
function sales(address dao)
    external
    view
    returns (address token, address payToken, uint40 deadline, uint256 price);
```


# IShareSale
[Git Source](https://github.com/z0r0z/majeur/blob/7a39232caba6bdf1dca11fa0402ac5168540b811/src/peripheral/LPSeedSwapHook.sol)

Minimal ShareSale interface for checking remaining allowance.


## Functions
### sales


```solidity
function sales(address dao)
    external
    view
    returns (address token, address payToken, uint40 deadline, uint256 price);
```


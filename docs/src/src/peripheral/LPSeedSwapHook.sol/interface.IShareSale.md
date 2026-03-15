# IShareSale
[Git Source](https://github.com/z0r0z/majeur/blob/51bf2cf41940c30a56dd06b7564697883db9ead0/src/peripheral/LPSeedSwapHook.sol)

Minimal ShareSale interface for checking remaining allowance.


## Functions
### sales


```solidity
function sales(address dao)
    external
    view
    returns (address token, address payToken, uint40 deadline, uint256 price);
```


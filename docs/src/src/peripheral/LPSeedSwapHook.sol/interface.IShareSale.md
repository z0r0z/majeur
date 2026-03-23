# IShareSale
[Git Source](https://github.com/z0r0z/majeur/blob/376bbb9940915c61b80e913ec9f3094c9c5ef7bc/src/peripheral/LPSeedSwapHook.sol)

Minimal ShareSale interface for checking remaining allowance.


## Functions
### sales


```solidity
function sales(address dao)
    external
    view
    returns (address token, address payToken, uint40 deadline, uint256 price);
```


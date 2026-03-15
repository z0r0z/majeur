# IZAMMHook
[Git Source](https://github.com/z0r0z/majeur/blob/7a39232caba6bdf1dca11fa0402ac5168540b811/src/peripheral/LPSeedSwapHook.sol)

ZAMM hook interface.


## Functions
### beforeAction


```solidity
function beforeAction(bytes4 sig, uint256 poolId, address sender, bytes calldata data)
    external
    payable
    returns (uint256 feeBps);
```

### afterAction


```solidity
function afterAction(
    bytes4 sig,
    uint256 poolId,
    address sender,
    int256 d0,
    int256 d1,
    int256 dLiq,
    bytes calldata data
) external payable;
```


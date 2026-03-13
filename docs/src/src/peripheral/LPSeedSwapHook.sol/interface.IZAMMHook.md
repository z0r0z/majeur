# IZAMMHook
[Git Source](https://github.com/z0r0z/majeur/blob/26195c42ab2bc92f824f7691eb427e6f0f067100/src/peripheral/LPSeedSwapHook.sol)

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


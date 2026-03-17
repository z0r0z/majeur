# IZAMM
[Git Source](https://github.com/z0r0z/majeur/blob/44b014e70c45a531ab7ef5f4e32dcfcda5ea81fa/src/peripheral/LPSeedSwapHook.sol)

Minimal ZAMM interface for LP, swap, and pool state operations.


## Functions
### pools


```solidity
function pools(uint256 poolId)
    external
    view
    returns (
        uint112 reserve0,
        uint112 reserve1,
        uint32 blockTimestampLast,
        uint256 price0CumulativeLast,
        uint256 price1CumulativeLast,
        uint256 kLast,
        uint256 supply
    );
```

### addLiquidity


```solidity
function addLiquidity(
    PoolKey calldata poolKey,
    uint256 amount0Desired,
    uint256 amount1Desired,
    uint256 amount0Min,
    uint256 amount1Min,
    address to,
    uint256 deadline
) external payable returns (uint256 amount0, uint256 amount1, uint256 liquidity);
```

### swapExactIn


```solidity
function swapExactIn(
    PoolKey calldata poolKey,
    uint256 amountIn,
    uint256 amountOutMin,
    bool zeroForOne,
    address to,
    uint256 deadline
) external payable returns (uint256 amountOut);
```

### swapExactOut


```solidity
function swapExactOut(
    PoolKey calldata poolKey,
    uint256 amountOut,
    uint256 amountInMax,
    bool zeroForOne,
    address to,
    uint256 deadline
) external payable returns (uint256 amountIn);
```

### swap


```solidity
function swap(
    PoolKey calldata poolKey,
    uint256 amount0Out,
    uint256 amount1Out,
    address to,
    bytes calldata data
) external;
```

## Structs
### PoolKey

```solidity
struct PoolKey {
    uint256 id0;
    uint256 id1;
    address token0;
    address token1;
    uint256 feeOrHook;
}
```


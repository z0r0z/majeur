# LPSeedSwapHook
[Git Source](https://github.com/z0r0z/majeur/blob/ae954c8dacf035c306a2f543ff58bff38b7c1bef/src/peripheral/LPSeedSwapHook.sol)

**Inherits:**
[IZAMMHook](/src/peripheral/LPSeedSwapHook.sol/interface.IZAMMHook.md)

**Title:**
LPSeedSwapHook

Singleton hook for seeding ZAMM liquidity from DAO treasury tokens.
Acts as a ZAMM hook to give DAOs exclusive control over pool initialization:
- Pre-seed: blocks all addLiquidity (prevents frontrun pool creation)
- Post-seed: returns DAO-configured fee on swaps, open LP for all
DAOs configure a seed by calling `configure()` in an initCall and granting
this contract allowances for both tokens via `setAllowance()`.
Seeding is gated by optional conditions:
- deadline:    seed only after a timestamp (e.g. after a sale ends)
- shareSale:   seed only after a ShareSale allowance is fully spent (sale sold out)
- minSupply:   seed only after DAO's forTkn balance drops to this threshold
Uses the Moloch allowance system for both tokens. The DAO retains custody
until seed() pulls via spendAllowance.
Setup (include in Summoner initCalls or SafeSummoner extraCalls):
1. dao.setAllowance(lpSeed, tokenA, amountA)
2. dao.setAllowance(lpSeed, tokenB, amountB)
3. lpSeed.configure(tokenA, amountA, tokenB, amountB, deadline, shareSale, minSupply)
Usage:
lpSeed.seed(dao)              // permissionless once conditions met
lpSeed.seedable(dao)          // view: check if conditions are met
DAO governance:
lpSeed.cancel()               // cancel seeding, DAO reclaims allowances
lpSeed.setFee(feeBps)         // update swap fee for the pool


## State Variables
### seeds
Keyed by DAO address. Set via configure() called by the DAO itself.


```solidity
mapping(address dao => SeedConfig) public seeds
```


### poolDAO
Reverse mapping: poolId → DAO address. Set during seed().


```solidity
mapping(uint256 poolId => address dao) public poolDAO
```


### SEEDING_SLOT
Transient storage slot for reentrancy guard during seed().
Signals to beforeAction that addLiquidity is from seed(), not external.


```solidity
uint256 constant SEEDING_SLOT = 0x4c505365656453696e676c65746f6e
```


## Functions
### configure

Configure LP seed parameters. Must be called by the DAO (e.g. in initCalls).


```solidity
function configure(
    address tokenA,
    uint128 amountA,
    address tokenB,
    uint128 amountB,
    uint40 deadline,
    address shareSale,
    uint128 minSupply
) public;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`tokenA`|`address`|    First token (address(0) = ETH)|
|`amountA`|`uint128`|   Amount of tokenA to seed|
|`tokenB`|`address`|    Second token (must be nonzero ERC20)|
|`amountB`|`uint128`|   Amount of tokenB to seed|
|`deadline`|`uint40`|  Seed only after this timestamp (0 = no time gate)|
|`shareSale`|`address`| ShareSale address to check for sale completion (address(0) = no check)|
|`minSupply`|`uint128`| Seed only after DAO's tokenB balance <= this (0 = no check)|


### seed

Seed ZAMM liquidity. Permissionless — anyone can trigger once conditions are met.
LP shares go to the DAO. One-shot: reverts if already seeded.


```solidity
function seed(address dao) public returns (uint256 liquidity);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`dao`|`address`|The DAO to seed liquidity for|


### seedable

View: whether seed conditions are met.


```solidity
function seedable(address dao) public view returns (bool);
```

### cancel

Cancel the seed config. Only callable by the DAO.
DAO should reclaim allowances separately via setAllowance(lpSeed, token, 0).


```solidity
function cancel() public;
```

### setFee

Update swap fee for the pool. Only callable by the DAO.


```solidity
function setFee(uint16 newFeeBps) public;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newFeeBps`|`uint16`|New fee in basis points (0 = use DEFAULT_FEE_BPS).|


### hookFeeOrHook

Get the encoded feeOrHook value for pool keys using LPSeed as hook.


```solidity
function hookFeeOrHook() public view returns (uint256);
```

### beforeAction

ZAMM hook: gate addLiquidity pre-seed, return fee on swaps.

Pre-seed: only seed() can addLiquidity (blocks frontrun pool creation).
Post-seed: all LP operations allowed, swaps charged DAO-configured fee.
Unregistered pools (poolDAO not set): LP allowed, swaps revert.


```solidity
function beforeAction(bytes4 sig, uint256 poolId, address, bytes calldata)
    external
    payable
    override
    returns (uint256 feeBps);
```

### afterAction

ZAMM hook: no-op after action.


```solidity
function afterAction(bytes4, uint256, address, int256, int256, int256, bytes calldata)
    external
    payable
    override;
```

### _isReady


```solidity
function _isReady(address dao, SeedConfig memory cfg) internal view returns (bool);
```

### _checkReady


```solidity
function _checkReady(address dao, SeedConfig memory cfg) internal view;
```

### receive

Accept ETH from DAO via spendAllowance.


```solidity
receive() external payable;
```

### seedInitCalls

Generate initCalls for setting up an LP seed.

Returns 3 calls: setAllowance(tokenA), setAllowance(tokenB), configure().


```solidity
function seedInitCalls(
    address dao,
    address tokenA,
    uint128 amountA,
    address tokenB,
    uint128 amountB,
    uint40 deadline,
    address shareSale,
    uint128 minSupply
)
    public
    view
    returns (
        address target1,
        bytes memory data1,
        address target2,
        bytes memory data2,
        address target3,
        bytes memory data3
    );
```

## Events
### Configured

```solidity
event Configured(
    address indexed dao, address tokenA, uint256 amountA, address tokenB, uint256 amountB
);
```

### Seeded

```solidity
event Seeded(address indexed dao, uint256 amount0, uint256 amount1, uint256 liquidity);
```

### Cancelled

```solidity
event Cancelled(address indexed dao);
```

### FeeUpdated

```solidity
event FeeUpdated(address indexed dao, uint16 oldFee, uint16 newFee);
```

## Errors
### NotReady

```solidity
error NotReady();
```

### NotConfigured

```solidity
error NotConfigured();
```

### AlreadySeeded

```solidity
error AlreadySeeded();
```

### InvalidParams

```solidity
error InvalidParams();
```

### Unauthorized

```solidity
error Unauthorized();
```

## Structs
### SeedConfig

```solidity
struct SeedConfig {
    address tokenA; // first token (ERC20, or address(0) for ETH)
    address tokenB; // second token (ERC20, must be nonzero)
    uint128 amountA; // amount of tokenA to seed
    uint128 amountB; // amount of tokenB to seed
    uint16 feeBps; // swap fee (0 = DEFAULT_FEE_BPS)
    uint40 deadline; // seed only after this timestamp (0 = no time gate)
    address shareSale; // if set, seed only after this ShareSale's allowance is spent
    uint128 minSupply; // if set, seed only after DAO's tokenB balance <= minSupply
    bool seeded; // true after seed() succeeds
}
```


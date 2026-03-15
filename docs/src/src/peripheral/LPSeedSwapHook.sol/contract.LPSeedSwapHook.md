# LPSeedSwapHook
[Git Source](https://github.com/z0r0z/majeur/blob/7b0b09c645157c41733569026978219fbad0e559/src/peripheral/LPSeedSwapHook.sol)

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
- minSupply:   seed only after DAO's tokenB balance drops to this threshold
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
lpSeed.setFee(feeBps)         // update LP swap fee for the pool
lpSeed.setLaunchFee(bps, t)   // set launch premium that decays to feeBps
lpSeed.setDaoFee(...)         // set DAO revenue fee on routed swaps
lpSeed.setBeneficiary(addr)   // update fee beneficiary


## State Variables
### seeds
Keyed by DAO address. Set via configure() called by the DAO itself.


```solidity
mapping(address dao => SeedConfig) public seeds
```


### daoFees
DAO fee config, keyed by DAO address. Set via setDaoFee().


```solidity
mapping(address dao => DaoFeeConfig) public daoFees
```


### poolDAO
Reverse mapping: poolId → DAO address. Set during configure() and seed().


```solidity
mapping(uint256 poolId => address dao) public poolDAO
```


### SEEDING_SLOT
Transient storage slot for seeding bypass flag.
Signals to beforeAction that addLiquidity is from seed(), not external.


```solidity
uint256 constant SEEDING_SLOT = 0x4c505365656453696e676c65746f6e
```


### SWAP_LOCK_SLOT
Reentrancy guard for swap routing.


```solidity
uint256 constant SWAP_LOCK_SLOT = 0x4c5053656564537761704c6f636b
```


## Functions
### configure

Configure with default fee (backwards-compatible with SafeSummoner).


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

### configure

Configure LP seed parameters. Must be called by the DAO (e.g. in initCalls).


```solidity
function configure(
    address tokenA,
    uint128 amountA,
    address tokenB,
    uint128 amountB,
    uint16 feeBps,
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
|`feeBps`|`uint16`|    Swap fee in basis points (0 = DEFAULT_FEE_BPS, max 10_000)|
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


### setLaunchFee

Set launch fee premium. Fee starts at launchBps post-seed and linearly
decays to feeBps over decayPeriod seconds. Must be called before seed().


```solidity
function setLaunchFee(uint16 launchBps, uint40 decayPeriod) public;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`launchBps`|`uint16`|  Initial fee in basis points (0 = no launch premium, max 10_000)|
|`decayPeriod`|`uint40`|Seconds to decay from launchBps to feeBps (0 = instant target)|


### setDaoFee

Set DAO revenue fee. When beneficiary is set, swaps must route through
this contract's swapExactIn/swapExactOut — direct ZAMM swaps are blocked.


```solidity
function setDaoFee(
    address beneficiary,
    uint16 buyBps,
    uint16 sellBps,
    bool buyOnInput,
    bool sellOnInput
) public;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`beneficiary`|`address`| Recipient of fee revenue (address(0) disables routing enforcement)|
|`buyBps`|`uint16`|      Fee bps on zeroForOne swaps (token0 → token1)|
|`sellBps`|`uint16`|     Fee bps on !zeroForOne swaps (token1 → token0)|
|`buyOnInput`|`bool`|  true = buy fee deducted from input (token0), false = from output (token1)|
|`sellOnInput`|`bool`| true = sell fee deducted from input (token1), false = from output (token0)|


### setBeneficiary

Update fee beneficiary without changing fee rates. Only callable by DAO.
Setting to address(0) disables routing enforcement (allows direct ZAMM swaps).
Setting to non-zero requires existing fee rates (set via setDaoFee first).


```solidity
function setBeneficiary(address beneficiary) public;
```

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
function beforeAction(bytes4 sig, uint256 poolId, address sender, bytes calldata)
    public
    payable
    returns (uint256 feeBps);
```

### effectiveFee

Current effective ZAMM pool fee for a DAO's pool, in basis points.
Accounts for launch fee decay. Returns 0 if not seeded.


```solidity
function effectiveFee(address dao) public view returns (uint256 feeBps);
```

### poolKeyOf

Derive the ZAMM PoolKey and pool ID for a DAO's configured pair.
Reverts if the DAO has no seed config.


```solidity
function poolKeyOf(address dao) public view returns (IZAMM.PoolKey memory key, uint256 poolId);
```

### quoteSwap

One-call swap quoter. Returns the pool key, all fees, and routing info.


```solidity
function quoteSwap(address dao, bool zeroForOne)
    public
    view
    returns (
        IZAMM.PoolKey memory key,
        uint256 poolFeeBps,
        uint256 daoFeeBps,
        bool feeOnInput,
        address beneficiary
    );
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`dao`|`address`|        The DAO whose pool you're quoting|
|`zeroForOne`|`bool`| Swap direction (true = token0 → token1)|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`key`|`IZAMM.PoolKey`|         ZAMM PoolKey (pass directly to swap functions)|
|`poolFeeBps`|`uint256`|  Current ZAMM pool fee (with launch decay, 0 if not seeded)|
|`daoFeeBps`|`uint256`|   DAO revenue fee for this direction (0 if disabled)|
|`feeOnInput`|`bool`|  Whether DAO fee is deducted from input (true) or output (false)|
|`beneficiary`|`address`| Fee recipient (address(0) = swap via ZAMM directly, non-zero = route via this contract)|


### quoteExactIn

Quote exact-input swap: given `amountIn`, returns net `amountOut` after all fees.


```solidity
function quoteExactIn(address dao, uint256 amountIn, bool zeroForOne)
    public
    view
    returns (uint256 amountOut, uint256 daoTax);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`dao`|`address`|        The DAO whose pool you're quoting|
|`amountIn`|`uint256`|   Input amount (gross, before any DAO fee)|
|`zeroForOne`|`bool`| Swap direction (true = token0 → token1)|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`amountOut`|`uint256`| Net output amount the user receives|
|`daoTax`|`uint256`|    DAO fee amount deducted (in input or output token depending on config)|


### quoteExactOut

Quote exact-output swap: given desired net `amountOut`, returns gross `amountIn` needed.


```solidity
function quoteExactOut(address dao, uint256 amountOut, bool zeroForOne)
    public
    view
    returns (uint256 amountIn, uint256 daoTax);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`dao`|`address`|        The DAO whose pool you're quoting|
|`amountOut`|`uint256`|  Desired net output amount the user receives|
|`zeroForOne`|`bool`| Swap direction (true = token0 → token1)|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`amountIn`|`uint256`|  Gross input amount required (including any DAO fee)|
|`daoTax`|`uint256`|    DAO fee amount deducted (in input or output token depending on config)|


### _getAmountOut

Constant-product getAmountOut (mirrors ZAMM._getAmountOut).


```solidity
function _getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut, uint256 swapFee)
    internal
    pure
    returns (uint256);
```

### _getAmountIn

Constant-product getAmountIn (mirrors ZAMM._getAmountIn).


```solidity
function _getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut, uint256 swapFee)
    internal
    pure
    returns (uint256);
```

### lock


```solidity
modifier lock() ;
```

### swapExactIn

Swap exact input through ZAMM with DAO fee.
Required for pools with an active DAO fee (direct ZAMM swaps are blocked).

When feeOnInput: fee deducted from input before ZAMM swap, amountOutMin checked by ZAMM.
When feeOnOutput: fee deducted from ZAMM output, amountOutMin checked against net received.


```solidity
function swapExactIn(
    IZAMM.PoolKey calldata poolKey,
    uint256 amountIn,
    uint256 amountOutMin,
    bool zeroForOne,
    address to,
    uint256 deadline
) public payable lock returns (uint256 amountOut);
```

### swapExactOut

Swap exact output through ZAMM with DAO fee.
`amountOut` is the net amount `to` receives after fees.


```solidity
function swapExactOut(
    IZAMM.PoolKey calldata poolKey,
    uint256 amountOut,
    uint256 amountInMax,
    bool zeroForOne,
    address to,
    uint256 deadline
) public payable lock returns (uint256 amountIn);
```

### _isReady


```solidity
function _isReady(address dao, SeedConfig memory cfg) internal view returns (bool);
```

### receive

Accept ETH from DAO via spendAllowance and from ZAMM during fee-on-output swaps.


```solidity
receive() external payable;
```

### seedInitCalls

Generate initCalls for setting up an LP seed with shares premint.

Returns 4 calls: mintFromMoloch(tokenB → DAO), setAllowance(tokenA),
setAllowance(tokenB), configure(). Use when tokenB is DAO shares/loot.
For external ERC20 tokenB, drop calls[0] and use the last 3 only.


```solidity
function seedInitCalls(
    address dao,
    address tokenA,
    uint128 amountA,
    address tokenB,
    uint128 amountB,
    uint16 feeBps,
    uint40 deadline,
    address shareSale,
    uint128 minSupply
) public view returns (address[4] memory targets, bytes[4] memory data);
```

### daoFeeInitCall

Generate an initCall for setting the DAO revenue fee.


```solidity
function daoFeeInitCall(
    address beneficiary,
    uint16 buyBps,
    uint16 sellBps,
    bool buyOnInput,
    bool sellOnInput
) public view returns (address target, uint256 value, bytes memory data);
```

### launchFeeInitCall

Generate an initCall for setting the launch fee premium.
Include after seedInitCalls in the DAO's initCalls array.


```solidity
function launchFeeInitCall(uint16 launchBps, uint40 decayPeriod)
    public
    view
    returns (address target, uint256 value, bytes memory data);
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

### DaoFeeUpdated

```solidity
event DaoFeeUpdated(address indexed dao, address beneficiary, uint16 buyBps, uint16 sellBps);
```

### BeneficiaryUpdated

```solidity
event BeneficiaryUpdated(address indexed dao, address beneficiary);
```

## Errors
### NotReady

```solidity
error NotReady();
```

### Slippage

```solidity
error Slippage();
```

### NotHooked

```solidity
error NotHooked();
```

### Unauthorized

```solidity
error Unauthorized();
```

### AlreadySeeded

```solidity
error AlreadySeeded();
```

### InvalidParams

```solidity
error InvalidParams();
```

### NotConfigured

```solidity
error NotConfigured();
```

## Structs
### SeedConfig

```solidity
struct SeedConfig {
    address tokenA; // first token (ERC20, or address(0) for ETH)
    address tokenB; // second token (ERC20, must be nonzero)
    uint128 amountA; // amount of tokenA to seed
    uint128 amountB; // amount of tokenB to seed
    uint16 feeBps; // target swap fee (0 = DEFAULT_FEE_BPS)
    uint16 launchBps; // initial fee post-seed, decays to feeBps (0 = no launch premium)
    uint40 deadline; // seed only after this timestamp (0 = no time gate)
    uint40 decayPeriod; // seconds to decay from launchBps to feeBps (0 = instant target)
    address shareSale; // if set, seed only after this ShareSale's allowance is spent
    uint128 minSupply; // if set, seed only after DAO's tokenB balance <= minSupply
    uint40 seeded; // 0 = not seeded, else block.timestamp when seeded
}
```

### DaoFeeConfig
DAO fee config for routed swaps. Separate from seed config so fees
can be updated independently. When beneficiary != 0, swaps must route
through this contract's swapExactIn/swapExactOut.


```solidity
struct DaoFeeConfig {
    address beneficiary; // fee recipient (address(0) = disabled, allows direct ZAMM swaps)
    uint16 buyBps; // fee bps when zeroForOne (token0 → token1)
    uint16 sellBps; // fee bps when !zeroForOne (token1 → token0)
    bool buyOnInput; // true = buy fee on input (token0), false = on output (token1)
    bool sellOnInput; // true = sell fee on input (token1), false = on output (token0)
}
```


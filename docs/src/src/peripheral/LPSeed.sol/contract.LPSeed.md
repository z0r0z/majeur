# LPSeed
[Git Source](https://github.com/z0r0z/majeur/blob/e68de9077c329150fa27252eafcfb094e7170075/src/peripheral/LPSeed.sol)

**Title:**
LPSeed

Singleton for seeding ZAMM liquidity from DAO treasury tokens.
DAOs configure a seed by calling `configure()` in an initCall and granting
this contract allowances for both tokens via `setAllowance()`.
The contract holds paired token amounts and seeds them as LP on ZAMM when
`seed()` is called. Seeding is gated by optional conditions:
- deadline:    seed only after a timestamp (e.g. after a sale ends)
- shareSale:   seed only after a ShareSale allowance is fully spent (sale sold out)
- minSupply:   seed only after DAO's forTkn balance drops to this threshold
(e.g. all sale supply distributed)
Uses the Moloch allowance system for both tokens. The DAO retains custody
until seed() pulls via spendAllowance.
Setup (include in Summoner initCalls or SafeSummoner extraCalls):
1. dao.setAllowance(lpSeed, tokenA, amountA)
2. dao.setAllowance(lpSeed, tokenB, amountB)
3. lpSeed.configure(tokenA, amountA, tokenB, amountB, feeOrHook, maxSlipBps, deadline, shareSale, minSupply)
Usage:
lpSeed.seed(dao)              // permissionless once conditions met
lpSeed.seedable(dao)          // view: check if conditions are met
DAO governance:
lpSeed.cancel()               // cancel seeding, DAO reclaims allowances


## State Variables
### seeds
Keyed by DAO address. Set via configure() called by the DAO itself.


```solidity
mapping(address dao => SeedConfig) public seeds
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
    uint256 feeOrHook,
    uint16 maxSlipBps,
    uint40 deadline,
    address shareSale,
    uint128 minSupply
) public;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`tokenA`|`address`|     First token (address(0) = ETH)|
|`amountA`|`uint128`|    Amount of tokenA to seed|
|`tokenB`|`address`|     Second token (must be nonzero ERC20)|
|`amountB`|`uint128`|    Amount of tokenB to seed|
|`feeOrHook`|`uint256`|  ZAMM pool fee in bps or hook address|
|`maxSlipBps`|`uint16`| Max slippage (0 defaults to 100 = 1%)|
|`deadline`|`uint40`|   Seed only after this timestamp (0 = no time gate)|
|`shareSale`|`address`|  ShareSale address to check for sale completion (address(0) = no check)|
|`minSupply`|`uint128`|  Seed only after DAO's tokenB balance <= this (0 = no check)|


### seed

Seed ZAMM liquidity. Permissionless — anyone can trigger once conditions are met.
LP shares go to the DAO. One-shot: reverts if already seeded.


```solidity
function seed(address dao) public payable returns (uint256 liquidity);
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
If tokenA is address(0) (ETH), the DAO must hold sufficient ETH balance
and the first call sets the ETH allowance on the DAO.


```solidity
function seedInitCalls(
    address dao,
    address tokenA,
    uint128 amountA,
    address tokenB,
    uint128 amountB,
    uint256 feeOrHook,
    uint16 maxSlipBps,
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
    address indexed dao,
    address tokenA,
    uint256 amountA,
    address tokenB,
    uint256 amountB,
    uint256 feeOrHook
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

## Structs
### SeedConfig

```solidity
struct SeedConfig {
    address tokenA; // first token (ERC20, or address(0) for ETH)
    address tokenB; // second token (ERC20, must be nonzero)
    uint128 amountA; // amount of tokenA to seed
    uint128 amountB; // amount of tokenB to seed
    uint256 feeOrHook; // ZAMM pool fee in bps or hook address
    uint16 maxSlipBps; // max slippage for LP add (default 100 = 1%)
    uint40 deadline; // seed only after this timestamp (0 = no time gate)
    address shareSale; // if set, seed only after this ShareSale's allowance is spent
    uint128 minSupply; // if set, seed only after DAO's tokenB balance <= minSupply
    bool seeded; // true after seed() succeeds
}
```


# BondingCurveSale
[Git Source](https://github.com/z0r0z/majeur/blob/44b014e70c45a531ab7ef5f4e32dcfcda5ea81fa/src/peripheral/BondingCurveSale.sol)

**Title:**
BondingCurveSale

Singleton for selling DAO shares or loot on a linear bonding curve.
Drop-in alternative to ShareSale — same allowance system, same IShareSale
interface for LPSeedSwapHook compatibility.
Price rises linearly from startPrice to endPrice as tokens are sold.
Cost for N tokens = N * averagePrice, where averagePrice is the midpoint
of the price at the current position and the price after buying N tokens.
The `sales()` getter returns endPrice as `price` so that LPSeedSwapHook's
arb protection clamp uses the highest (final) sale price for LP seeding.
Setup (via SafeSummoner extraCalls):
1. dao.setAllowance(bondingCurveSale, address(dao), cap)
2. bondingCurveSale.configure(address(dao), payToken, startPrice, endPrice, cap, deadline)
Usage:
bondingCurveSale.buy{value: cost}(dao, amount)


## State Variables
### sales
Keyed by DAO address. Set via configure() called by the DAO itself.


```solidity
mapping(address dao => Sale) public sales
```


## Functions
### constructor


```solidity
constructor() payable;
```

### configure

Configure bonding curve sale parameters. Must be called by the DAO.


```solidity
function configure(
    address token,
    address payToken,
    uint256 startPrice,
    uint256 endPrice,
    uint256 cap,
    uint40 deadline
) public;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`token`|`address`|     Allowance token: use address(dao) for shares, address(1007) for loot|
|`payToken`|`address`|  Payment token (address(0) = ETH)|
|`startPrice`|`uint256`|Price at 0% sold (1e18 scaled), must be > 0|
|`endPrice`|`uint256`|  Price at 100% sold (1e18 scaled), must be >= startPrice|
|`cap`|`uint256`|       Total tokens for sale (should match the allowance granted)|
|`deadline`|`uint40`|  Unix timestamp after which buys revert (0 = no deadline)|


### quote

Compute the cost for buying `amount` tokens from `dao` at current curve position.


```solidity
function quote(address dao, uint256 amount) public view returns (uint256 cost);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`cost`|`uint256`|The payment required (in payToken units or wei)|


### buy

Buy shares or loot from a DAO on the bonding curve (exact-out).
Caps to remaining allowance if amount exceeds it.
Refunds excess ETH for ETH-priced sales.


```solidity
function buy(address dao, uint256 amount) public payable;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`dao`|`address`|   The DAO to buy from|
|`amount`|`uint256`|Max shares/loot to buy (capped to remaining)|


### buyExactIn

Buy shares or loot with exact ETH input on the bonding curve.
Computes max amount from msg.value via quadratic formula, caps to remaining, refunds excess.


```solidity
function buyExactIn(address dao) public payable;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`dao`|`address`|The DAO to buy from|


### saleInitCalls

Generate initCalls for setting up a BondingCurveSale.

Returns (target, data) pairs for use in initCalls or extraCalls.


```solidity
function saleInitCalls(
    address dao,
    address token,
    uint256 cap,
    address payToken,
    uint256 startPrice,
    uint256 endPrice,
    uint40 deadline
)
    public
    view
    returns (address target1, bytes memory data1, address target2, bytes memory data2);
```

### _cost

Compute cost for `amount` tokens starting at position `sold` on the curve.
Linear curve: price(x) = startPrice + (endPrice - startPrice) * x / cap
Cost = amount * avgPrice / 1e18, where avgPrice = (price(sold) + price(sold+amount)) / 2
Rounded up to prevent dust.


```solidity
function _cost(Sale memory s, uint256 sold, uint256 amount) internal pure returns (uint256);
```

## Events
### Configured

```solidity
event Configured(
    address indexed dao,
    address token,
    address payToken,
    uint256 startPrice,
    uint256 endPrice,
    uint256 cap,
    uint40 deadline
);
```

### Purchase

```solidity
event Purchase(address indexed dao, address indexed buyer, uint256 amount, uint256 cost);
```

## Errors
### InsufficientPayment

```solidity
error InsufficientPayment();
```

### NotConfigured

```solidity
error NotConfigured();
```

### UnexpectedETH

```solidity
error UnexpectedETH();
```

### ZeroAmount

```solidity
error ZeroAmount();
```

### ZeroPrice

```solidity
error ZeroPrice();
```

### Expired

```solidity
error Expired();
```

### InvalidCurve

```solidity
error InvalidCurve();
```

## Structs
### Sale

```solidity
struct Sale {
    address token; // allowance token: address(dao) for shares, address(1007) for loot
    address payToken; // address(0) = ETH
    uint40 deadline; // unix timestamp after which buys revert (0 = no deadline)
    uint256 price; // endPrice — for IShareSale compatibility (LPSeedSwapHook reads this)
    uint256 startPrice; // price at 0% sold
    uint256 cap; // total tokens for sale (should match allowance)
}
```


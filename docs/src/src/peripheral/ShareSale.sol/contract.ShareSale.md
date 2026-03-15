# ShareSale
[Git Source](https://github.com/z0r0z/majeur/blob/51bf2cf41940c30a56dd06b7564697883db9ead0/src/peripheral/ShareSale.sol)

**Title:**
ShareSale

Singleton for selling DAO shares or loot via the allowance system.
DAOs configure a sale by calling `configure()` in an initCall and granting
this contract an allowance via `setAllowance(ShareSale, token, cap)`.
Mint path uses Moloch's _payout sentinel addresses:
token = address(dao)  -> mints shares
token = address(1007) -> mints loot
Pricing uses 1e18 scaling: cost = amount * price / 1e18
e.g. price = 0.01e18 means 0.01 ETH per whole share (1e18 units)
Works naturally with any payToken decimals.
Setup (include in Summoner initCalls or SafeSummoner extraCalls):
1. dao.setAllowance(shareSale, address(dao), cap)   // or address(1007) for loot
2. shareSale.configure(address(dao), payToken, price) // called BY dao -> keyed to msg.sender
Usage:
shareSale.buy{value: cost}(dao, amount)


## State Variables
### sales
Keyed by DAO address. Set via configure() called by the DAO itself.


```solidity
mapping(address dao => Sale) public sales
```


## Functions
### configure

Configure sale parameters. Must be called by the DAO (e.g. in initCalls).


```solidity
function configure(address token, address payToken, uint256 price, uint40 deadline) public;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`token`|`address`|   Allowance token: use address(dao) for shares, address(1007) for loot|
|`payToken`|`address`|Payment token (address(0) = ETH)|
|`price`|`uint256`|   Price per whole token (1e18 units), e.g. 0.01e18 = 0.01 ETH/share|
|`deadline`|`uint40`|Unix timestamp after which buys revert (0 = no deadline)|


### buy

Buy shares or loot from a DAO.


```solidity
function buy(address dao, uint256 amount) public payable;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`dao`|`address`|   The DAO to buy from|
|`amount`|`uint256`|Number of shares/loot to buy|


### saleInitCalls

Generate initCalls for setting up a ShareSale.

Returns (target, value, data) tuples for use in initCalls or extraCalls.
Call 1: dao.setAllowance(shareSale, token, cap)
Call 2: shareSale.configure(token, payToken, price, deadline)  (target = this contract)


```solidity
function saleInitCalls(
    address dao,
    address token,
    uint256 cap,
    address payToken,
    uint256 price,
    uint40 deadline
)
    public
    view
    returns (address target1, bytes memory data1, address target2, bytes memory data2);
```

## Events
### Configured

```solidity
event Configured(
    address indexed dao, address token, address payToken, uint256 price, uint40 deadline
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

## Structs
### Sale

```solidity
struct Sale {
    address token; // allowance token: address(dao) for shares, address(1007) for loot
    address payToken; // address(0) = ETH
    uint40 deadline; // unix timestamp after which buys revert (0 = no deadline)
    uint256 price; // cost per whole token (1e18 units), scaled by 1e18
    // e.g. 0.01 ETH per share = 0.01e18 = 1e16
    // cost = amount * price / 1e18
}
```


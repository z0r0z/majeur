# TapVest
[Git Source](https://github.com/z0r0z/majeur/blob/13360a942bd5f358d43ac5a53ba3981007990305/src/peripheral/TapVest.sol)

**Title:**
TapVest

Singleton for linear vesting from a DAO treasury via the allowance system.
DAOs configure a tap by calling `configure()` in an initCall and granting
this contract an allowance via `setAllowance(Tap, token, budget)`.
Vesting formula: owed = ratePerSec * elapsed
Claimed = min(owed, allowance, daoBalance), rounded to whole seconds when capped.
Allowance acts as the total budget cap.
When capped, lastClaim advances proportionally (unclaimed time is preserved).
Setup (include in Summoner initCalls or SafeSummoner extraCalls):
1. dao.setAllowance(tap, token, totalBudget)
2. tap.configure(token, beneficiary, ratePerSec) // called BY dao -> keyed to msg.sender
Usage:
tap.claim(dao)           // beneficiary claims accrued funds
tap.claimable(dao)       // view: how much can be claimed now
DAO governance:
tap.setBeneficiary(newAddr)  // change recipient (dao-only)
tap.setRate(newRate)         // change rate, non-retroactive (dao-only)


## State Variables
### taps
Keyed by DAO address. Set via configure() called by the DAO itself.


```solidity
mapping(address dao => TapConfig) public taps
```


## Functions
### constructor


```solidity
constructor() payable;
```

### configure

Configure tap parameters. Must be called by the DAO (e.g. in initCalls).
Overwrites any existing config — resets lastClaim, forfeiting accrued time.
Use setBeneficiary/setRate for parameter changes on an active tap.


```solidity
function configure(address token, address beneficiary, uint128 ratePerSec) public;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`token`|`address`|      Token to vest (address(0) = ETH)|
|`beneficiary`|`address`|Recipient of vested funds|
|`ratePerSec`|`uint128`| Vesting rate in smallest token units per second|


### claim

Claim accrued funds. Permissionless — funds always go to the beneficiary.


```solidity
function claim(address dao) public returns (uint256 claimed);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`dao`|`address`|The DAO to claim from|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`claimed`|`uint256`|The amount actually claimed (may be less than owed)|


### claimable

View: how much can be claimed now.


```solidity
function claimable(address dao) public view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`dao`|`address`|The DAO to query|


### pending

View: total owed based on time (ignoring allowance/balance caps).


```solidity
function pending(address dao) public view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`dao`|`address`|The DAO to query|


### setBeneficiary

Update the beneficiary. Only callable by the DAO. Works on frozen (rate=0) taps.


```solidity
function setBeneficiary(address newBeneficiary) public;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newBeneficiary`|`address`|New recipient of vested funds|


### setRate

Update the vesting rate. Non-retroactive: unclaimed time at old rate is
forfeited, new rate applies from this moment forward. Only callable by the DAO.


```solidity
function setRate(uint128 newRate) public;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newRate`|`uint128`|New rate in smallest units per second. 0 = freeze tap.|


### receive

Accept ETH from DAO via spendAllowance.


```solidity
receive() external payable;
```

### tapInitCalls

Generate initCalls for setting up a Tap.


```solidity
function tapInitCalls(
    address dao,
    address token,
    uint256 budget,
    address beneficiary,
    uint128 ratePerSec
)
    public
    view
    returns (address target1, bytes memory data1, address target2, bytes memory data2);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`dao`|`address`|        The DAO address (used as setAllowance target)|
|`token`|`address`|      Token to vest (address(0) = ETH)|
|`budget`|`uint256`|     Total allowance budget|
|`beneficiary`|`address`|Recipient of vested funds|
|`ratePerSec`|`uint128`| Vesting rate in smallest token units per second|


## Events
### Configured

```solidity
event Configured(
    address indexed dao, address indexed beneficiary, address token, uint128 ratePerSec
);
```

### Claimed

```solidity
event Claimed(address indexed dao, address indexed beneficiary, address token, uint256 amount);
```

### BeneficiaryUpdated

```solidity
event BeneficiaryUpdated(address indexed dao, address indexed oldBen, address indexed newBen);
```

### RateUpdated

```solidity
event RateUpdated(address indexed dao, uint128 oldRate, uint128 newRate);
```

## Errors
### NothingToClaim

```solidity
error NothingToClaim();
```

### NotConfigured

```solidity
error NotConfigured();
```

### ZeroRate

```solidity
error ZeroRate();
```

## Structs
### TapConfig

```solidity
struct TapConfig {
    address token; // address(0) = ETH, or ERC20
    address beneficiary; // recipient of vested funds
    uint128 ratePerSec; // smallest-unit/sec (e.g. wei/sec for ETH, 1e-6/sec for USDC)
    uint64 lastClaim; // last claim timestamp
}
```


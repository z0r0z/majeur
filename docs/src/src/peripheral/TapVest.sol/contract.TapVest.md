# TapVest
[Git Source](https://github.com/z0r0z/majeur/blob/51bf2cf41940c30a56dd06b7564697883db9ead0/src/peripheral/TapVest.sol)

**Title:**
TapVest

Singleton for linear vesting from a DAO treasury via the allowance system.
DAOs configure a tap by calling `configure()` in an initCall and granting
this contract an allowance via `setAllowance(Tap, token, budget)`.
Vesting formula: owed = ratePerSec * elapsed
Claimed = min(owed, allowance, daoBalance)
Allowance acts as the total budget cap.
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
### configure

Configure tap parameters. Must be called by the DAO (e.g. in initCalls).


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


### claimable

View: how much can be claimed now.


```solidity
function claimable(address dao) public view returns (uint256);
```

### pending

View: total owed based on time (ignoring allowance/balance caps).


```solidity
function pending(address dao) public view returns (uint256);
```

### setBeneficiary

Update the beneficiary. Only callable by the DAO.


```solidity
function setBeneficiary(address newBeneficiary) public;
```

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


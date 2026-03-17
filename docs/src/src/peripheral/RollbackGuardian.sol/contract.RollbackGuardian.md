# RollbackGuardian
[Git Source](https://github.com/z0r0z/majeur/blob/13360a942bd5f358d43ac5a53ba3981007990305/src/peripheral/RollbackGuardian.sol)

**Title:**
RollbackGuardian

Singleton that lets a designated guardian emergency-bump a DAO's config,
invalidating all pending proposals and preventing malicious execution.
The guardian holds a pre-authorized permit to call `bumpConfig()` on the DAO.
After one bump, the config change invalidates the permit itself (config is part
of the permit ID hash), making this inherently one-shot. The DAO must re-authorize
via governance to restore the guardian's power.
Setup (include in Summoner initCalls or SafeSummoner extraCalls):
1. rollbackGuardian.configure(guardian, expiry)
2. dao.setPermit(0, dao, 0, bumpConfig(), "rollback", rollbackGuardian, 1)
Or use permitCall() / initCalls() helpers to generate both.
Emergency use:
rollbackGuardian.rollback(dao)        // nuclear: bump config, orphan all proposals
rollbackGuardian.killFutarchy(dao)    // lighter: disable auto-futarchy earmarks
DAO governance:
rollbackGuardian.setGuardian(newGuardian)  // rotate guardian
rollbackGuardian.setExpiry(newExpiry)       // extend or shorten window
rollbackGuardian.revoke()                   // remove guardian entirely


## State Variables
### configs

```solidity
mapping(address dao => Config) public configs
```


### NONCE

```solidity
bytes32 public constant NONCE = keccak256("RollbackGuardian")
```


### FUTARCHY_NONCE

```solidity
bytes32 public constant FUTARCHY_NONCE = keccak256("RollbackGuardian.killFutarchy")
```


## Functions
### configure

Configure the guardian. Called by the DAO in initCalls.


```solidity
function configure(address guardian, uint40 expiry) public;
```

### rollback

Emergency config bump. Callable only by the guardian, before expiry.
Spends the pre-authorized permit to call dao.bumpConfig().
Inherently one-shot: the config bump invalidates the permit ID.


```solidity
function rollback(address dao) public;
```

### killFutarchy

Disable auto-futarchy. Lighter alternative to rollback — stops
NO-coalition futarchy reward farming without invalidating all proposals.
Inherently one-shot: the DAO must re-authorize via governance.


```solidity
function killFutarchy(address dao) public;
```

### setGuardian

Replace the guardian. Only callable by the DAO.


```solidity
function setGuardian(address newGuardian) public;
```

### setExpiry

Update the expiry. Only callable by the DAO.


```solidity
function setExpiry(uint40 newExpiry) public;
```

### revoke

Remove the guardian entirely. Only callable by the DAO.


```solidity
function revoke() public;
```

### rollbackPermitCall

Generate the setPermit call for bumpConfig authorization.


```solidity
function rollbackPermitCall(address dao)
    public
    view
    returns (address target, uint256 value, bytes memory data);
```

### futarchyPermitCall

Generate the setPermit call for killFutarchy authorization.


```solidity
function futarchyPermitCall(address dao)
    public
    view
    returns (address target, uint256 value, bytes memory data);
```

### initCalls

Generate all initCalls: configure + rollback permit + futarchy permit.


```solidity
function initCalls(address dao, address guardian, uint40 expiry)
    public
    view
    returns (Call[3] memory calls);
```

## Events
### Configured

```solidity
event Configured(address indexed dao, address guardian, uint40 expiry);
```

### Rolled

```solidity
event Rolled(address indexed dao, address guardian);
```

### FutarchyKilled

```solidity
event FutarchyKilled(address indexed dao, address guardian);
```

### GuardianUpdated

```solidity
event GuardianUpdated(address indexed dao, address oldGuardian, address newGuardian);
```

### ExpiryUpdated

```solidity
event ExpiryUpdated(address indexed dao, uint40 oldExpiry, uint40 newExpiry);
```

### Revoked

```solidity
event Revoked(address indexed dao);
```

## Errors
### Expired

```solidity
error Expired();
```

### Unauthorized

```solidity
error Unauthorized();
```

### NotConfigured

```solidity
error NotConfigured();
```

## Structs
### Config

```solidity
struct Config {
    address guardian;
    uint40 expiry; // unix timestamp, 0 = no expiry
}
```


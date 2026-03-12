# ShareBurner
[Git Source](https://github.com/z0r0z/majeur/blob/d27ebad6d0eaf0dd2eddab2488ea43fd282fd832/src/peripheral/ShareBurner.sol)

**Title:**
ShareBurner

Stateless singleton for burning unsold DAO shares after a sale deadline.
Both the delegatecall target AND the permit spender — one contract, one address.
Setup (include in DAICO customCalls or Summoner initCalls):
Use permitCall() to generate the setPermit init call, or encode manually:
dao.setPermit(1, burner, 0, burnData, salt, burner, 1)
After deadline:
burner.closeSale(dao, shares, deadline, salt)


## Functions
### burnUnsold

Delegatecall entry — runs in DAO context (address(this) = DAO).
Burns all shares held by the DAO after deadline. Payable to
skip msg.value check in delegatecall.


```solidity
function burnUnsold(address shares, uint256 deadline) public payable;
```

### closeSale

Burn unsold DAO shares. Fully permissionless — deadline is
enforced inside burnUnsold's delegatecall. One-shot (permit
count=1), so second call reverts in Moloch.


```solidity
function closeSale(address dao, address shares, uint256 deadline, bytes32 nonce) public;
```

### permitCall

Generate the setPermit Call for inclusion in init/custom calls.
Spender = this contract. Count = 1 (one-shot).


```solidity
function permitCall(address dao, address shares, uint256 deadline, bytes32 salt)
    public
    view
    returns (address, uint256, bytes memory);
```

## Events
### SaleClosed

```solidity
event SaleClosed(address indexed dao, uint256 sharesBurned);
```

## Errors
### SaleActive

```solidity
error SaleActive();
```


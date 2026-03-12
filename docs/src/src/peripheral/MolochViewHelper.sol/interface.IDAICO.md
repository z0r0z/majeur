# IDAICO
[Git Source](https://github.com/z0r0z/majeur/blob/d27ebad6d0eaf0dd2eddab2488ea43fd282fd832/src/peripheral/MolochViewHelper.sol)


## Functions
### sales


```solidity
function sales(address dao, address tribTkn)
    external
    view
    returns (uint256 tribAmt, uint256 forAmt, address forTkn, uint40 deadline);
```

### taps


```solidity
function taps(address dao)
    external
    view
    returns (address ops, address tribTkn, uint128 ratePerSec, uint64 lastClaim);
```

### lpConfigs


```solidity
function lpConfigs(address dao, address tribTkn)
    external
    view
    returns (uint16 lpBps, uint16 maxSlipBps, uint256 feeOrHook);
```

### claimableTap


```solidity
function claimableTap(address dao) external view returns (uint256);
```

### pendingTap


```solidity
function pendingTap(address dao) external view returns (uint256);
```


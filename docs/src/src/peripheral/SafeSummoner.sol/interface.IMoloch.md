# IMoloch
[Git Source](https://github.com/z0r0z/majeur/blob/d27ebad6d0eaf0dd2eddab2488ea43fd282fd832/src/peripheral/SafeSummoner.sol)


## Functions
### setProposalThreshold


```solidity
function setProposalThreshold(uint96 v) external;
```

### setProposalTTL


```solidity
function setProposalTTL(uint64 s) external;
```

### setTimelockDelay


```solidity
function setTimelockDelay(uint64 s) external;
```

### setQuorumAbsolute


```solidity
function setQuorumAbsolute(uint96 v) external;
```

### setMinYesVotesAbsolute


```solidity
function setMinYesVotesAbsolute(uint96 v) external;
```

### setTransfersLocked


```solidity
function setTransfersLocked(bool sharesLocked, bool lootLocked) external;
```

### setAutoFutarchy


```solidity
function setAutoFutarchy(uint256 param, uint256 cap) external;
```

### setFutarchyRewardToken


```solidity
function setFutarchyRewardToken(address _rewardToken) external;
```

### setSale


```solidity
function setSale(
    address payToken,
    uint256 pricePerShare,
    uint256 cap,
    bool minting,
    bool active,
    bool isLoot
) external;
```

### setPermit


```solidity
function setPermit(
    uint8 op,
    address to,
    uint256 value,
    bytes calldata data,
    bytes32 nonce,
    address spender,
    uint256 count
) external;
```


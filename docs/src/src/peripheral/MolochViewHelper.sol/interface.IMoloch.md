# IMoloch
[Git Source](https://github.com/z0r0z/SAW/blob/5b287591f19dce0ac310dc192604a613e25f6e34/src/peripheral/MolochViewHelper.sol)


## Functions
### name


```solidity
function name(uint256 id) external view returns (string memory);
```

### symbol


```solidity
function symbol(uint256 id) external view returns (string memory);
```

### contractURI


```solidity
function contractURI() external view returns (string memory);
```

### renderer


```solidity
function renderer() external view returns (address);
```

### proposalThreshold


```solidity
function proposalThreshold() external view returns (uint96);
```

### minYesVotesAbsolute


```solidity
function minYesVotesAbsolute() external view returns (uint96);
```

### quorumAbsolute


```solidity
function quorumAbsolute() external view returns (uint96);
```

### proposalTTL


```solidity
function proposalTTL() external view returns (uint64);
```

### timelockDelay


```solidity
function timelockDelay() external view returns (uint64);
```

### quorumBps


```solidity
function quorumBps() external view returns (uint16);
```

### ragequittable


```solidity
function ragequittable() external view returns (bool);
```

### autoFutarchyParam


```solidity
function autoFutarchyParam() external view returns (uint256);
```

### autoFutarchyCap


```solidity
function autoFutarchyCap() external view returns (uint256);
```

### rewardToken


```solidity
function rewardToken() external view returns (address);
```

### shares


```solidity
function shares() external view returns (address);
```

### loot


```solidity
function loot() external view returns (address);
```

### badges


```solidity
function badges() external view returns (address);
```

### getProposalCount


```solidity
function getProposalCount() external view returns (uint256);
```

### proposalIds


```solidity
function proposalIds(uint256) external view returns (uint256);
```

### proposerOf


```solidity
function proposerOf(uint256) external view returns (address);
```

### snapshotBlock


```solidity
function snapshotBlock(uint256) external view returns (uint48);
```

### createdAt


```solidity
function createdAt(uint256) external view returns (uint64);
```

### queuedAt


```solidity
function queuedAt(uint256) external view returns (uint64);
```

### supplySnapshot


```solidity
function supplySnapshot(uint256) external view returns (uint256);
```

### tallies


```solidity
function tallies(uint256 id)
    external
    view
    returns (uint96 forVotes, uint96 againstVotes, uint96 abstainVotes);
```

### state


```solidity
function state(uint256 id) external view returns (uint8);
```

### hasVoted


```solidity
function hasVoted(uint256 id, address voter) external view returns (uint8);
```

### voteWeight


```solidity
function voteWeight(uint256 id, address voter) external view returns (uint96);
```

### futarchy


```solidity
function futarchy(uint256 id)
    external
    view
    returns (
        bool enabled,
        address rewardToken,
        uint256 pool,
        bool resolved,
        uint8 winner,
        uint256 finalWinningSupply,
        uint256 payoutPerUnit
    );
```

### getMessageCount


```solidity
function getMessageCount() external view returns (uint256);
```

### messages


```solidity
function messages(uint256) external view returns (string memory);
```

### allowance


```solidity
function allowance(address token, address spender) external view returns (uint256);
```


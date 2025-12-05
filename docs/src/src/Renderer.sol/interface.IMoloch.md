# IMoloch
[Git Source](https://github.com/z0r0z/SAW/blob/5b287591f19dce0ac310dc192604a613e25f6e34/src/Renderer.sol)


## Functions
### name


```solidity
function name(uint256) external view returns (string memory);
```

### symbol


```solidity
function symbol(uint256) external view returns (string memory);
```

### supplySnapshot


```solidity
function supplySnapshot(uint256) external view returns (uint256);
```

### transfersLocked


```solidity
function transfersLocked() external view returns (bool);
```

### totalSupply


```solidity
function totalSupply() external view returns (uint256);
```

### balanceOf


```solidity
function balanceOf(address) external view returns (uint256);
```

### shares


```solidity
function shares() external view returns (address);
```

### badges


```solidity
function badges() external view returns (address);
```

### loot


```solidity
function loot() external view returns (address);
```

### ownerOf


```solidity
function ownerOf(uint256) external view returns (address);
```

### ragequittable


```solidity
function ragequittable() external view returns (bool);
```

### receiptProposal


```solidity
function receiptProposal(uint256) external view returns (uint256);
```

### receiptSupport


```solidity
function receiptSupport(uint256) external view returns (uint8);
```

### totalSupply


```solidity
function totalSupply(uint256) external view returns (uint256);
```

### futarchy


```solidity
function futarchy(uint256) external view returns (FutarchyConfig memory);
```

### tallies


```solidity
function tallies(uint256) external view returns (Tally memory);
```

### createdAt


```solidity
function createdAt(uint256) external view returns (uint64);
```

### snapshotBlock


```solidity
function snapshotBlock(uint256) external view returns (uint48);
```

### state


```solidity
function state(uint256) external view returns (ProposalState);
```

## Structs
### FutarchyConfig

```solidity
struct FutarchyConfig {
    bool enabled;
    address rewardToken;
    uint256 pool;
    bool resolved;
    uint8 winner;
    uint256 finalWinningSupply;
    uint256 payoutPerUnit;
}
```

### Tally

```solidity
struct Tally {
    uint96 forVotes;
    uint96 againstVotes;
    uint96 abstainVotes;
}
```

## Enums
### ProposalState

```solidity
enum ProposalState {
    Unopened,
    Active,
    Queued,
    Succeeded,
    Defeated,
    Expired,
    Executed
}
```


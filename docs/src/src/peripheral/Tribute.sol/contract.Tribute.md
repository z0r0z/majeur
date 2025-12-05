# Tribute
[Git Source](https://github.com/z0r0z/SAW/blob/5b287591f19dce0ac310dc192604a613e25f6e34/src/peripheral/Tribute.sol)

Simple tribute OTC escrow maker for DAO proposals.


## State Variables
### tributes

```solidity
mapping(
    address proposer => mapping(address dao => mapping(address tribTkn => TributeOffer))
) public tributes
```


### daoTributeRefs
Per-DAO view: "what tributes are pointing at this DAO?":


```solidity
mapping(address dao => DaoTributeRef[]) public daoTributeRefs
```


### proposerTributeRefs
Per-proposer view: "what tributes has this address created?":


```solidity
mapping(address proposer => ProposerTributeRef[]) public proposerTributeRefs
```


### REENTRANCY_GUARD_SLOT

```solidity
uint256 constant REENTRANCY_GUARD_SLOT = 0x929eee149b4bd21268
```


## Functions
### constructor


```solidity
constructor() payable;
```

### proposeTribute

Propose an OTC tribute:
- proposer locks up tribTkn (ERC20 or ETH)
- sets desired forTkn/forAmt from the DAO
- tribTkn == address(0) means ETH
- forTkn == address(0) means ETH


```solidity
function proposeTribute(
    address dao,
    address tribTkn,
    uint256 tribAmt,
    address forTkn,
    uint256 forAmt
) public payable nonReentrant;
```

### cancelTribute

Proposer cancels their own tribute and gets tribTkn back.


```solidity
function cancelTribute(address dao, address tribTkn) public nonReentrant;
```

### claimTribute

DAO claims a tribute and atomically performs the OTC escrow swap:
- DAO receives tribTkn
- Proposer receives forTkn
For ERC20 forTkn:
- DAO must `approve` this contract for at least forAmt before calling.
For ETH forTkn:
- DAO must send exactly forAmt as msg.value.


```solidity
function claimTribute(address proposer, address tribTkn) public payable nonReentrant;
```

### getDaoTributeCount


```solidity
function getDaoTributeCount(address dao) public view returns (uint256);
```

### getProposerTributeCount


```solidity
function getProposerTributeCount(address proposer) public view returns (uint256);
```

### getActiveDaoTributes


```solidity
function getActiveDaoTributes(address dao)
    public
    view
    returns (ActiveTributeView[] memory result);
```

### nonReentrant


```solidity
modifier nonReentrant() ;
```

## Events
### TributeProposed

```solidity
event TributeProposed(
    address indexed proposer,
    address indexed dao,
    address tribTkn,
    uint256 tribAmt,
    address forTkn,
    uint256 forAmt
);
```

### TributeCancelled

```solidity
event TributeCancelled(
    address indexed proposer,
    address indexed dao,
    address tribTkn,
    uint256 tribAmt,
    address forTkn,
    uint256 forAmt
);
```

### TributeClaimed

```solidity
event TributeClaimed(
    address indexed proposer,
    address indexed dao,
    address tribTkn,
    uint256 tribAmt,
    address forTkn,
    uint256 forAmt
);
```

## Errors
### NoTribute

```solidity
error NoTribute();
```

### InvalidParams

```solidity
error InvalidParams();
```

## Structs
### TributeOffer

```solidity
struct TributeOffer {
    uint256 tribAmt; // amount of tribTkn locked up
    address forTkn; // token (or ETH) for proposer
    uint256 forAmt; // amount of forTkn expected
}
```

### DaoTributeRef

```solidity
struct DaoTributeRef {
    address proposer;
    address tribTkn;
}
```

### ProposerTributeRef

```solidity
struct ProposerTributeRef {
    address dao;
    address tribTkn;
}
```

### ActiveTributeView

```solidity
struct ActiveTributeView {
    address proposer;
    address tribTkn;
    uint256 tribAmt;
    address forTkn;
    uint256 forAmt;
}
```


# Badges
[Git Source](https://github.com/z0r0z/SAW/blob/58989be3b007e6ed4d89f25206c3132a7dc08ab6/src/Moloch.sol)


## State Variables
### DAO

```solidity
address payable public DAO
```


### _ownerOf
ERC721-ish SBT state:


```solidity
mapping(uint256 id => address) _ownerOf
```


### seatOf

```solidity
mapping(address id => uint256) public seatOf
```


### balanceOf

```solidity
mapping(address id => uint256) public balanceOf
```


### occupied

```solidity
uint256 occupied
```


### seats

```solidity
Seat[256] seats
```


### minSlot

```solidity
uint16 minSlot
```


### minBal

```solidity
uint96 minBal
```


## Functions
### onlyDAO


```solidity
modifier onlyDAO() ;
```

### constructor


```solidity
constructor() payable;
```

### init


```solidity
function init() public payable;
```

### name

Dynamic metadata from Majeur:


```solidity
function name() public view returns (string memory);
```

### symbol


```solidity
function symbol() public view returns (string memory);
```

### ownerOf


```solidity
function ownerOf(uint256 id) public view returns (address o);
```

### supportsInterface


```solidity
function supportsInterface(bytes4 interfaceId) public pure returns (bool);
```

### transferFrom


```solidity
function transferFrom(address, address, uint256) public pure;
```

### mintSeat

seat: 1..256:


```solidity
function mintSeat(address to, uint16 seat) public payable onlyDAO;
```

### burnSeat


```solidity
function burnSeat(uint16 seat) public payable onlyDAO;
```

### tokenURI


```solidity
function tokenURI(uint256 id) public view returns (string memory);
```

### getSeats


```solidity
function getSeats() public view returns (Seat[] memory out);
```

### onSharesChanged

Called by DAO (Moloch) whenever a holder's share balance changes;
Maintains a sticky top-256 of share holders and keeps badges in sync:


```solidity
function onSharesChanged(address a) external payable onlyDAO;
```

### _firstFree

Returns (slot, ok) - ok=false means no free slot:


```solidity
function _firstFree() internal view returns (uint16 slot, bool ok);
```

### _setUsed


```solidity
function _setUsed(uint16 slot) internal;
```

### _setFree


```solidity
function _setFree(uint16 slot) internal;
```

### _recomputeMin


```solidity
function _recomputeMin() internal;
```

### _ffs


```solidity
function _ffs(uint256 x) internal pure returns (uint256 r);
```

## Events
### Transfer

```solidity
event Transfer(address indexed from, address indexed to, uint256 indexed id);
```

## Errors
### SBT

```solidity
error SBT();
```

### Minted

```solidity
error Minted();
```

### NotMinted

```solidity
error NotMinted();
```

## Structs
### Seat

```solidity
struct Seat {
    address holder;
    uint96 bal;
}
```


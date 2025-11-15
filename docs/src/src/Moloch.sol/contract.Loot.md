# Loot
[Git Source](https://github.com/z0r0z/SAW/blob/58989be3b007e6ed4d89f25206c3132a7dc08ab6/src/Moloch.sol)


## State Variables
### decimals

```solidity
uint8 public constant decimals = 18
```


### transfersLocked

```solidity
bool public transfersLocked
```


### totalSupply

```solidity
uint256 public totalSupply
```


### balanceOf

```solidity
mapping(address => uint256) public balanceOf
```


### allowance

```solidity
mapping(address => mapping(address => uint256)) public allowance
```


### DAO

```solidity
address payable public DAO
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


```solidity
function name() public view returns (string memory);
```

### symbol


```solidity
function symbol() public view returns (string memory);
```

### approve


```solidity
function approve(address to, uint256 amount) public returns (bool);
```

### transfer


```solidity
function transfer(address to, uint256 amount) public returns (bool);
```

### transferFrom


```solidity
function transferFrom(address from, address to, uint256 amount) public returns (bool);
```

### setTransfersLocked


```solidity
function setTransfersLocked(bool locked) public payable onlyDAO;
```

### mintFromMoloch


```solidity
function mintFromMoloch(address to, uint256 amount) public payable onlyDAO;
```

### burnFromMoloch


```solidity
function burnFromMoloch(address from, uint256 amount) public payable onlyDAO;
```

### _mint


```solidity
function _mint(address to, uint256 amount) internal;
```

### _moveTokens


```solidity
function _moveTokens(address from, address to, uint256 amount) internal;
```

### _checkUnlocked


```solidity
function _checkUnlocked(address from, address to) internal view;
```

## Events
### Approval

```solidity
event Approval(address indexed from, address indexed to, uint256 amount);
```

### Transfer

```solidity
event Transfer(address indexed from, address indexed to, uint256 amount);
```


# ERC20
[Git Source](https://github.com/z0r0z/majeur/blob/376bbb9940915c61b80e913ec9f3094c9c5ef7bc/src/peripheral/ClassicalCurveSale.sol)

**Author:**
Zolidity (https://github.com/z0r0z/zolidity/blob/main/src/ERC20.sol)

Standard fungible token (https://eips.ethereum.org/EIPS/eip-20).


## State Variables
### name

```solidity
string public name
```


### symbol

```solidity
string public symbol
```


### contractURI

```solidity
string public contractURI
```


### decimals

```solidity
uint256 public constant decimals = 18
```


### totalSupply

```solidity
uint256 public totalSupply
```


### hook

```solidity
address immutable hook = msg.sender
```


### zamm

```solidity
address constant zamm = 0x000000000000040470635EB91b7CE4D132D616eD
```


### zrouter

```solidity
address constant zrouter = 0x000000000000FB114709235f1ccBFfb925F600e4
```


### balanceOf

```solidity
mapping(address holder => uint256) public balanceOf
```


### allowance

```solidity
mapping(address holder => mapping(address spender => uint256)) public allowance
```


## Functions
### constructor


```solidity
constructor() payable;
```

### init


```solidity
function init(
    string calldata _name,
    string calldata _symbol,
    string calldata _uri,
    uint256 supply,
    address to
) public payable;
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

## Events
### Approval

```solidity
event Approval(address indexed from, address indexed to, uint256 amount);
```

### Transfer

```solidity
event Transfer(address indexed from, address indexed to, uint256 amount);
```

## Errors
### InvalidInit

```solidity
error InvalidInit();
```

### Initialized

```solidity
error Initialized();
```


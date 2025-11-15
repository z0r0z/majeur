# Display
[Git Source](https://github.com/z0r0z/SAW/blob/58989be3b007e6ed4d89f25206c3132a7dc08ab6/src/Renderer.sol)

Display — Solady helpers for on-chain SVG / string rendering:


## Functions
### jsonDataURI


```solidity
function jsonDataURI(string memory raw) internal pure returns (string memory);
```

### svgDataURI


```solidity
function svgDataURI(string memory raw) internal pure returns (string memory);
```

### jsonImage


```solidity
function jsonImage(string memory name_, string memory description_, string memory svg_)
    internal
    pure
    returns (string memory);
```

### svgCardBase


```solidity
function svgCardBase() internal pure returns (string memory);
```

### shortDec4

"1234...5678" from a big decimal id:


```solidity
function shortDec4(uint256 v) internal pure returns (string memory);
```

### shortAddr4

EIP-55 "0xAbCd...1234" (0x + 4 nibbles ... 4 nibbles):


```solidity
function shortAddr4(address a) internal pure returns (string memory);
```

### fmtComma

Decimal with commas: 123_456_789 => "123,456,789":


```solidity
function fmtComma(uint256 n) internal pure returns (string memory);
```

### percent2

Percent with 2 decimals from a/b, e.g. 1234/10000 => "12.34%":


```solidity
function percent2(uint256 a, uint256 b) internal pure returns (string memory);
```

### esc


```solidity
function esc(string memory s) internal pure returns (string memory result);
```

### toString


```solidity
function toString(uint256 value) internal pure returns (string memory result);
```

### slice


```solidity
function slice(string memory subject, uint256 start, uint256 end)
    internal
    pure
    returns (string memory result);
```

### toHexStringChecksummed


```solidity
function toHexStringChecksummed(address value) internal pure returns (string memory result);
```

### encode


```solidity
function encode(bytes memory data) internal pure returns (string memory result);
```


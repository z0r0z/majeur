# Renderer
[Git Source](https://github.com/z0r0z/SAW/blob/7a1cdeb117d089c989e0c6b15508846c72bbe337/src/Renderer.sol)

Moloch (Majeur) URI SVG renderer singleton.


## Functions
### daoContractURI


```solidity
function daoContractURI(IMoloch dao) public view returns (string memory);
```

### daoTokenURI

On-chain JSON/SVG card for a proposal id, or routes to receiptURI for vote receipts:


```solidity
function daoTokenURI(IMoloch dao, uint256 id) public view returns (string memory);
```

### _receiptURI


```solidity
function _receiptURI(IMoloch dao, uint256 id) internal view returns (string memory);
```

### _permitCardURI


```solidity
function _permitCardURI(IMoloch dao, uint256 id) internal view returns (string memory);
```

### badgeTokenURI

Top-256 badge (seat index; tokenId == seat, not sorted by balance):


```solidity
function badgeTokenURI(IMoloch dao, uint256 seatId) public view returns (string memory);
```

### _svgHeader


```solidity
function _svgHeader(string memory orgNameEsc, string memory subtitle)
    internal
    pure
    returns (string memory svg);
```


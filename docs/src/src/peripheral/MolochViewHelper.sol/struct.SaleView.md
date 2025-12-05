# SaleView
[Git Source](https://github.com/z0r0z/SAW/blob/5b287591f19dce0ac310dc192604a613e25f6e34/src/peripheral/MolochViewHelper.sol)


```solidity
struct SaleView {
address tribTkn; // payment token (ETH = address(0))
uint256 tribAmt; // base pay amount
uint256 forAmt; // base receive amount
address forTkn; // token being sold
uint40 deadline; // unix timestamp (0 = no deadline)
uint256 remainingSupply; // forTkn balance in DAO (available for sale)
uint256 totalSupply; // forTkn total supply
uint256 treasuryBalance; // tribTkn balance in DAO (raised so far)
uint256 allowance; // forTkn allowance to DAICO (approved for sale)
// LP config
uint16 lpBps;
uint16 maxSlipBps;
uint256 feeOrHook;
}
```


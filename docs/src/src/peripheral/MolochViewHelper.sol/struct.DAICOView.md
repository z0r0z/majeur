# DAICOView
[Git Source](https://github.com/z0r0z/majeur/blob/51bf2cf41940c30a56dd06b7564697883db9ead0/src/peripheral/MolochViewHelper.sol)


```solidity
struct DAICOView {
address dao;
DAOMeta meta;
SaleView[] sales; // active sales (may be multiple tribute tokens)
TapView tap; // tap config (if any)
}
```


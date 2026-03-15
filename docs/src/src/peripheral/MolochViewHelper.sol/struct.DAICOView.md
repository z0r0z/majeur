# DAICOView
[Git Source](https://github.com/z0r0z/majeur/blob/7a39232caba6bdf1dca11fa0402ac5168540b811/src/peripheral/MolochViewHelper.sol)


```solidity
struct DAICOView {
address dao;
DAOMeta meta;
SaleView[] sales; // active sales (may be multiple tribute tokens)
TapView tap; // tap config (if any)
}
```


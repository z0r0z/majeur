# DAICOView
[Git Source](https://github.com/z0r0z/majeur/blob/13360a942bd5f358d43ac5a53ba3981007990305/src/peripheral/MolochViewHelper.sol)


```solidity
struct DAICOView {
address dao;
DAOMeta meta;
SaleView[] sales; // active sales (may be multiple tribute tokens)
TapView tap; // tap config (if any)
}
```


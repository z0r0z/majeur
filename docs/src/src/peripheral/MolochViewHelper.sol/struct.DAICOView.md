# DAICOView
[Git Source](https://github.com/z0r0z/majeur/blob/676b7eee1f7e1cd8bc1842d11a4fbdc43b31c4ac/src/peripheral/MolochViewHelper.sol)


```solidity
struct DAICOView {
address dao;
DAOMeta meta;
SaleView[] sales; // active sales (may be multiple tribute tokens)
TapView tap; // tap config (if any)
}
```


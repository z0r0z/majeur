# DAICOView
[Git Source](https://github.com/z0r0z/majeur/blob/d27ebad6d0eaf0dd2eddab2488ea43fd282fd832/src/peripheral/MolochViewHelper.sol)


```solidity
struct DAICOView {
address dao;
DAOMeta meta;
SaleView[] sales; // active sales (may be multiple tribute tokens)
TapView tap; // tap config (if any)
}
```


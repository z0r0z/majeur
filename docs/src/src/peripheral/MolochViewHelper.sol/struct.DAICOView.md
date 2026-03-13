# DAICOView
[Git Source](https://github.com/z0r0z/majeur/blob/26195c42ab2bc92f824f7691eb427e6f0f067100/src/peripheral/MolochViewHelper.sol)


```solidity
struct DAICOView {
address dao;
DAOMeta meta;
SaleView[] sales; // active sales (may be multiple tribute tokens)
TapView tap; // tap config (if any)
}
```


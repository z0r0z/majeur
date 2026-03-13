# DAICOView
[Git Source](https://github.com/z0r0z/majeur/blob/693e65b2d5461c8bced186f4330ea1fc0aee9dc9/src/peripheral/MolochViewHelper.sol)


```solidity
struct DAICOView {
address dao;
DAOMeta meta;
SaleView[] sales; // active sales (may be multiple tribute tokens)
TapView tap; // tap config (if any)
}
```


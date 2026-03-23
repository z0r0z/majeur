# DAICOView
[Git Source](https://github.com/z0r0z/majeur/blob/376bbb9940915c61b80e913ec9f3094c9c5ef7bc/src/peripheral/MolochViewHelper.sol)


```solidity
struct DAICOView {
address dao;
DAOMeta meta;
SaleView[] sales; // active sales (may be multiple tribute tokens)
TapView tap; // tap config (if any)
}
```


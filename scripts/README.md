# Scripts

## DeploymentPredictor.sol

On-chain helper to predict Moloch DAO and token clone addresses via CREATE2. Can be deployed standalone or used off-chain via `eth_call`.

```bash
forge create scripts/DeploymentPredictor.sol:DeploymentPredictor
```

Predict all addresses in one call:

```solidity
(address dao, address shares, address badges, address loot) = predictor.predictAllAddresses(
    summoner, molochImpl, sharesImpl, badgesImpl, lootImpl,
    initHolders, initShares, salt
);
```

Mirrors the CREATE2 logic in `Moloch._init()` (line 249) and `Summoner.summon()` (line 2081).

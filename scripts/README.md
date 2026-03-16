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

## VanityMiner

Mine CREATE2 salts for vanity addresses on contracts deployed via `SafeSummoner.create2Deploy`.

### Setup

```bash
cd scripts/vanity-miner && cargo build --release && cd ../..
```

### Usage

```bash
./scripts/vanity-miner/target/release/vanity-miner --deployer <SafeSummoner> --init-code <bytecode> --prefix <hex>
```

| Flag | Description |
|------|-------------|
| `--deployer` | SafeSummoner address (CREATE2 factory) |
| `--init-code` | Full creation bytecode (hex) |
| `--init-code-hash` | Alternative: pass keccak256 hash of init code directly |
| `--prefix` | Desired leading hex bytes (e.g. `000000` = 3 zero bytes) |
| `--caller` | Optional: mix msg.sender into salt for front-run protection |
| `--output` | Optional: JSON file to save results (default = `vanity-results.json`) |
| `--threads` | Optional: override thread count (default = all cores) |

The winning `salt` is printed to stdout. Pass it to `SafeSummoner.create2Deploy(creationCode, salt)`.

Results are automatically saved to `scripts/vanity-miner/results/results.json` (or the path given by `--output`) so they persist across sessions. The file accumulates results as a JSON array.

### Example: mine vanity address for Tribute.sol

```bash
export DEPLOYER=0x00000000004473e1f31c8266612e7fd5504e6f2a
export INIT_CODE=$(forge inspect Tribute bytecode)
export PREFIX=000000
./scripts/vanity-miner/target/release/vanity-miner -o scripts/vanity-miner/results/tribute.json
```

Or with short flags:

```bash
./scripts/vanity-miner/target/release/vanity-miner -d 0x00000000004473e1f31c8266612e7fd5504e6f2a -i $(forge inspect Tribute bytecode) -p 000000 -o scripts/vanity-miner/results/tribute.json
```

### Difficulty reference

| Prefix | Leading hex chars | Expected tries | ~Time (2 cores) |
|--------|-------------------|----------------|-----------------|
| `0000` | 4 | ~65K | instant |
| `000000` | 6 | ~16M | ~10s |
| `00000000` | 8 | ~4.3B | ~40min |

A Solidity version is also available at `scripts/VanityMiner.sol` for on-chain verification or light mining via `forge script`.

# ZeroSkills / Slot Sleuth — SafeSummoner.sol

**Skill:** [zerocoolailabs/ZeroSkills](https://github.com/zerocoolailabs/ZeroSkills) (Slot Sleuth — EVM Storage-Safety Vulnerability Detector)
**Scan of:** `SafeSummoner.sol` (~1117 lines, 1 contract + interfaces + constants)
**Mode:** Full 5-phase analysis (Storage Inventory → Lost Write Detection → Attacker-Influenced Slot Writes → Upgrade Collision Analysis → Storage Semantics Issues)

Findings found: 0

## Review Summary

> **Reviewed 2026-03-13. No storage-safety vulnerabilities identified.**
>
> - **0 findings across all 5 detection phases.** SafeSummoner is a **stateless factory** — it has zero persistent storage variables. The Slot Sleuth methodology's primary targets (lost writes, slot collisions, attacker-influenced slot writes, upgrade layout drift) are structurally absent.
> - **Applicability gates:** Phase 1 immediately reveals zero storage surface. Phases 2-5 are included for completeness but trivially pass.
> - **Assembly usage:** Two assembly blocks — `multicall` revert bubbling and `create2Deploy` contract creation. Neither performs `SSTORE`.
> - **Key strength:** By maintaining zero persistent state, SafeSummoner eliminates the entire class of storage-safety vulnerabilities by construction.

---

## Phase 1: Storage Inventory

### Persistent State Surface

| Contract | Storage Variables | Mutation Paths |
|---|---|---|
| **SafeSummoner** | **0** — no state variables, no mappings, no arrays, no structs in storage | None — all functions are stateless |

The contract declares:
- `constructor() payable {}` — empty constructor, no state initialization
- No `mapping`, `uint`, `address`, `bool`, `struct` or any other storage declaration at contract level
- All data flows through calldata → memory → external call (SUMMONER.summon) → return

### Assembly Operations Inventory

| Location | Opcode | Target | Storage Risk |
|---|---|---|---|
| `multicall()` L211-213 | `REVERT` | Memory (revert bubbling) | **None** — no `SSTORE`, no `TSTORE` |
| `create2Deploy()` L232-235 | `MLOAD`, `CALLDATACOPY`, `CREATE2` | Memory + contract creation | **None** — no `SSTORE` |

**Conclusion:** Zero `SSTORE` operations in the entire contract — neither in assembly nor in compiler-generated code. SafeSummoner has no persistent storage to write to.

---

## Phase 2: Lost Write Detection

Scanned all functions for the pattern: storage-backed value copied to non-storage temporary → mutated → never persisted back.

**Not applicable.** SafeSummoner has zero storage variables. All data structures are `memory` or `calldata`:

| Location | Pattern | Analysis | Finding? |
|---|---|---|---|
| `_buildCalls()` L687 | `Call[] memory calls` | Memory allocation. No storage source. | No |
| `_buildModuleCalls()` L878 | `Call[] memory calls` | Memory allocation. No storage source. | No |
| `_buildLootMints()` L1014 | `Call[] memory calls` | Memory allocation. No storage source. | No |
| `safeSummonDAICO()` L445 | `Call[] memory allExtra` | Memory allocation. Merges three arrays. No storage source. | No |
| `summonFounder()` L366-368 | `address[] memory h`, `uint256[] memory s` | Memory allocation of hardcoded values. No storage source. | No |
| `_defaultThreshold()` L1055 | `uint256 total` (stack) | Stack variable. Sum of calldata array. No storage source. | No |
| All `SafeConfig memory c` in presets | Memory struct | Constructed in memory from hardcoded values. No storage source. | No |

**Conclusion:** No lost write patterns possible — there is no storage to lose writes from.

---

## Phase 3: Attacker-Influenced Slot Writes

Scanned for cases where untrusted input determines which persistent storage slot receives a write.

**Not applicable.** SafeSummoner performs zero persistent storage writes. All state mutations occur on external contracts:

| Vector | Analysis | Finding? |
|---|---|---|
| **`SUMMONER.summon()` call** | SafeSummoner calls `SUMMONER.summon{value: msg.value}(...)` which creates a new DAO and writes to the *Summoner's* and *new DAO's* storage — not SafeSummoner's. The initCalls array is executed by the new DAO in its own storage context. | No |
| **`create2Deploy()` CREATE2** | Deploys a new contract. The deployed contract has its own storage. SafeSummoner's storage is unaffected. | No |
| **`multicall()` delegatecall** | `address(this).delegatecall(data[i])` — target is hardcoded `address(this)`. Runs SafeSummoner's own functions in SafeSummoner's storage context. But SafeSummoner has no storage variables, so no slots can be written regardless of calldata. | No |
| **`extraCalls` passthrough** | User-supplied `Call[]` structs are passed through to `SUMMONER.summon()` as initCalls. They execute in the new DAO's context, not SafeSummoner's. | No |

**Conclusion:** No attacker-influenced slot writes. SafeSummoner has no storage slots to target.

---

## Phase 4: Upgrade Collision Analysis

### Architecture: Stateless Factory (No Proxy, No Upgradeability)

SafeSummoner is a **standalone contract**, not a proxy:

1. **No proxy pattern.** Not EIP-1167, not UUPS, not Transparent, not Diamond.
2. **No `implementation` reference.** No `delegatecall` to an external implementation (the `multicall` delegatecall targets `address(this)` — the same contract).
3. **No storage layout.** Zero storage variables means zero layout collision risk.
4. **No `upgradeTo` or `initialize` functions.**
5. **Immutable singleton references** (`SUMMONER`, `MOLOCH_IMPL`, etc.) are file-level constants compiled into bytecode, not storage.

**No upgrade path exists.** Phase 4 is not applicable.

**Conclusion:** No upgrade collision risk. Contract is a stateless factory with no proxy architecture.

---

## Phase 5: Storage Semantics Issues

Scanned for state desynchronization, failed bit-clearing, uninitialized reads, and similar persistent-state integrity issues.

**Not applicable.** SafeSummoner has no persistent state to desynchronize.

For completeness, the contract's **memory-based** data integrity was verified:

### 5.1 Call Array Count Consistency

`_buildCalls()` pre-counts required calls into `n`, allocates `new Call[](n + extra.length)`, then fills via `calls[i++]`. The count must match exactly — over-count wastes gas (zero-initialized trailing entries), under-count causes array out-of-bounds revert.

| Config Path | Counted | Written | Match? |
|---|---|---|---|
| proposalThreshold + proposalTTL | Always +2 | Always written | ✓ |
| timelockDelay > 0 | +1 | Conditional write | ✓ |
| quorumAbsolute > 0 | +1 | Conditional write | ✓ |
| minYesVotes > 0 | +1 | Conditional write | ✓ |
| lockShares \|\| lockLoot | +1 | Conditional write | ✓ |
| autoFutarchyParam > 0 | +1 | Conditional write | ✓ |
| futarchyRewardToken != 0 (nested) | +1 | Conditional write | ✓ |
| saleActive | +1 | Conditional write | ✓ |
| saleBurnDeadline > 0 | +1 | Conditional write | ✓ |
| rollbackGuardian != 0 | +3 | 3 conditional writes | ✓ |

All conditional writes are guarded by the same conditions used for counting. No mismatch possible.

### 5.2 Module Call Count Consistency

`_buildModuleCalls()` similarly pre-counts and fills:

| Module | Counted | Written | Match? |
|---|---|---|---|
| SaleModule (singleton != 0) | +2 | setAllowance + configure | ✓ |
| TapModule (singleton != 0) | +2 | setAllowance + configure | ✓ |
| SeedModule (singleton != 0) | +3 base | 2x setAllowance + configure | ✓ |
| SeedModule sentinel tokenA | +1 if sentinel | mintFromMoloch | ✓ |
| SeedModule sentinel tokenB | +1 if sentinel | mintFromMoloch | ✓ |

All conditional writes match their count conditions. No mismatch possible.

### 5.3 Loot Mint Array Sizing

`_buildLootMints()` does a two-pass approach: first counts non-zero loot entries, then allocates and fills. The second pass uses the same `loot[i] > 0` condition. No mismatch.

**Conclusion:** No storage semantics issues. Memory array sizing is consistent across all builders.

---

## Findings Summary

| Phase | Detection Target | Result |
|---|---|---|
| 1. Storage Inventory | Map all persistent state and mutation paths | **0 storage variables**, 2 assembly blocks (no `SSTORE`) |
| 2. Lost Write Detection | Memory copies of storage values mutated without write-back | **Not applicable** — no storage to copy from |
| 3. Attacker-Influenced Slot Writes | Untrusted input determining storage slot targets | **Not applicable** — no storage slots exist |
| 4. Upgrade Collision Analysis | Layout conflicts across proxy/implementation boundaries | **Not applicable** — stateless factory, no proxy |
| 5. Storage Semantics Issues | State desynchronization, failed clearing, uninitialized reads | **Not applicable** — no persistent state; memory array sizing verified correct |

---

## Assessment

The Slot Sleuth detector's 5 phases found **no storage-safety vulnerabilities** in SafeSummoner.sol. This is trivially expected given the contract's architecture:

1. **Zero persistent storage.** SafeSummoner declares no state variables. It is a pure factory/builder that constructs calldata arrays in memory and forwards them to the Summoner singleton. All persistent state lives in the deployed DAOs.

2. **No proxy pattern.** The contract is deployed directly, not behind a proxy. The `multicall` delegatecall targets `address(this)` (self), not an external implementation.

3. **No assembly `SSTORE`.** Both assembly blocks operate on memory only — revert bubbling in `multicall` and `CREATE2` in `create2Deploy`.

4. **Memory integrity verified.** Although not a storage concern, the call array count/fill consistency in `_buildCalls`, `_buildModuleCalls`, and `_buildLootMints` was verified — all pre-counts match their conditional writes exactly.

SafeSummoner's stateless architecture makes it a **zero-signal target** for the Slot Sleuth methodology. The contract's security risks lie in validation logic (covered by Pashov Audit #1) and vulnerability class scanning (covered by SCV Scan #2) — not in storage safety.

---

> This review was performed using the ZeroSkills Slot Sleuth methodology (5-phase EVM storage-safety analysis) with manual code tracing across all ~1117 lines of SafeSummoner.sol.

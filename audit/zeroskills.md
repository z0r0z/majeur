
# ZeroSkills / Slot Sleuth — Moloch.sol

**Skill:** [zerocoolailabs/ZeroSkills](https://github.com/zerocoolailabs/ZeroSkills) (Slot Sleuth — EVM Storage-Safety Vulnerability Detector)
**Scan of:** `Moloch.sol` (2110 lines, 5 contracts)
**Mode:** Full 5-phase analysis (Storage Inventory → Lost Write Detection → Attacker-Influenced Slot Writes → Upgrade Collision Analysis → Storage Semantics Issues)

Findings found: 0

## Review Summary

> **Reviewed 2026-03-11. No storage-safety vulnerabilities identified.**
>
> - **0 findings across all 5 detection phases.** The contract does not exhibit patterns targeted by Slot Sleuth: no manual slot arithmetic, no lost writes, no proxy upgrade layouts, and no attacker-influenced storage slot determination.
> - **Applicability gates passed:** The contract has extensive persistent storage (mappings, structs, arrays across 5 contracts) and uses inline assembly — however, assembly usage is confined to transient storage (`TSTORE`/`TLOAD`), `CREATE2`, pure math (`mulDiv`, `_ffs`), and Solady-style safe transfer wrappers. No assembly performs `SSTORE` to persistent storage.
> - **EIP-1167 clone architecture** uses immutable implementation references with no upgradeability, eliminating Phase 4 (upgrade collision) as a risk surface.
> - **Key strength:** All storage mutations use Solidity's native mapping/struct access via `storage` pointers (e.g., `FutarchyConfig storage F = futarchy[id]`), which guarantees write-back. The one pattern that could appear suspicious — `Tally memory t = tallies[id]` in `cancelProposal` — is correctly read-only.

---

## Phase 1: Storage Inventory

### Persistent State Surface

| Contract | Storage Variables | Mutation Paths |
|---|---|---|
| **Moloch** | 2 strings, 7 config scalars, 4 immutables, 4 contract refs, 10 mappings, 2 arrays, 1 struct mapping (Tally), 1 struct mapping (Sale), 1 struct mapping (FutarchyConfig), 3 ERC6909 mappings, 3 futarchy scalars | 25+ external/public functions, 6 internal helpers |
| **Shares** | 4 ERC20 fields, `DAO`, 3 vote mappings, 1 split mapping | `init`, `transfer`, `transferFrom`, `mintFromMoloch`, `burnFromMoloch`, `delegate`, `setSplitDelegation`, `clearSplitDelegation`, `setTransfersLocked` |
| **Loot** | 4 ERC20 fields, `DAO` | `init`, `transfer`, `transferFrom`, `mintFromMoloch`, `burnFromMoloch`, `setTransfersLocked` |
| **Badges** | `DAO`, 3 NFT mappings, bitmap `occupied`, `seats[256]`, `minSlot`, `minBal` | `init`, `mintSeat`, `burnSeat`, `onSharesChanged` |
| **Summoner** | `daos[]`, immutable `implementation` | `summon` |

### Assembly Operations Inventory

| Location | Opcode | Target | Storage Risk |
|---|---|---|---|
| `nonReentrant` (L1004-1015) | `TSTORE`/`TLOAD` | Transient storage (EIP-1153) | **None** — transient, not persistent |
| `_init` (L250-261) | `CREATE2`, `MSTORE` | Memory + contract creation | **None** — no `SSTORE` |
| `Summoner.summon` (L2080-2090) | `CREATE2`, `MSTORE` | Memory + contract creation | **None** — no `SSTORE` |
| `mulDiv` (L1988-1996) | `MUL`, `DIV`, `MULMOD` | Stack/memory only | **None** — pure |
| `_ffs` (L1931-1941) | Arithmetic only | Stack only | **None** — pure |
| `safeTransfer` (L2020-2033) | `CALL`, `MSTORE`, `MLOAD` | Memory + external call | **None** — no `SSTORE` |
| `safeTransferFrom` (L2036-2052) | `CALL`, `MSTORE`, `MLOAD` | Memory + external call | **None** — no `SSTORE` |
| `safeTransferETH` (L2011-2017) | `CALL` | External call | **None** — no `SSTORE` |
| `balanceOfThis` (L2000-2008) | `STATICCALL`, `MSTORE` | Memory + static call | **None** — no `SSTORE` |
| `_revertOverflow` (L1980-1983) | `MSTORE`, `REVERT` | Memory | **None** — reverts |
| `multicall` revert (L898-900) | `REVERT` | Memory | **None** — reverts |

**Conclusion:** Zero `SSTORE` operations in inline assembly. All persistent storage mutations go through Solidity-generated storage access code.

---

## Phase 2: Lost Write Detection

Scanned all functions for the pattern: storage-backed value copied to non-storage temporary → mutated → never persisted back.

| Location | Pattern | Analysis | Finding? |
|---|---|---|---|
| `cancelProposal` L424 | `Tally memory t = tallies[id]` | **Read-only.** Used only in condition `(t.forVotes \| t.againstVotes \| t.abstainVotes) != 0`. No mutation of `t`. | No |
| `cancelProposal` L427 | `FutarchyConfig memory F = futarchy[id]` | **Read-only.** Used in condition `F.enabled && F.pool != 0`. No mutation. | No |
| `buyShares` L715 | `uint256 cap = s.cap` | **Scalar copy for guard check.** The actual decrement goes through `s.cap = cap - shareAmount` (L726), writing back to the `Sale storage s` pointer. | No |
| `buyShares` L718 | `uint256 price = s.pricePerShare` | **Read-only.** Used for cost calculation. No intent to persist. | No |
| `castVote` L368 | `uint48 snap = snapshotBlock[id]` | **Read-only cache.** Used as argument to `getPastVotes`. | No |
| `state()` L451-457 | Reads from `Tally storage t` | **View function.** No mutations. `storage` pointer used correctly. | No |
| `Shares._applyVotingDelta` L1393 | `uint256 balAfter = balanceOf[account]` | **Read-only.** Used to compute `balBefore` for delta application. | No |
| `Shares._repointVotesForHolder` L1470 | `newD[j] = address(0)` | **Memory array mutation.** Intentional marking of "already handled" delegates. `newD` is a memory copy from `_currentDistribution`, used as scratch. Not intended to persist. | No |
| `Shares._targetAlloc` | Returns `uint256[] memory A` | **Pure computation.** Builds allocation array in memory. Never meant to be storage. | No |

**All storage-writing functions use `storage` pointers correctly:**
- `castVote`: `Tally storage t = tallies[id]` → `t.forVotes += weight` writes through
- `cancelVote`: `Tally storage t = tallies[id]` → `t.forVotes -= weight` writes through
- `fundFutarchy`: `FutarchyConfig storage F = futarchy[id]` → `F.pool += amount` writes through
- `openProposal`: `FutarchyConfig storage F = futarchy[id]` → `F.enabled = true`, `F.pool += amt` write through
- `_finalizeFutarchy`: `FutarchyConfig storage F` parameter → `F.resolved = true`, etc. write through
- `buyShares`: `Sale storage s = sales[payToken]` → `s.cap = cap - shareAmount` writes through
- `setPermit`: Direct mapping writes, no struct copy
- `Shares._writeCheckpoint`: `Checkpoint storage last = ckpts[len - 1]` → `last.votes = toUint96(newVal)` writes through
- `Badges.onSharesChanged`: `seats[slot].bal = bal` writes through directly

**Conclusion:** No lost write patterns found. All storage mutations use `storage` pointers that guarantee persistence.

---

## Phase 3: Attacker-Influenced Slot Writes

Scanned for cases where untrusted input determines which persistent storage slot receives a write.

| Vector | Analysis | Finding? |
|---|---|---|
| **ERC6909 `balanceOf[owner][id]`** | `id` is user-influenced in `transfer`/`transferFrom`. However, these are standard Solidity mapping accesses — slot = `keccak256(id, keccak256(owner, baseSlot))`. No custom slot arithmetic. Standard pattern, not a vulnerability. | No |
| **`_intentHashId` output as mapping key** | User-controlled `(op, to, value, data, nonce)` determine the hash used as key in `executed`, `createdAt`, `snapshotBlock`, etc. Standard mapping key derivation — no raw slot targeting. | No |
| **`tallies[id]` struct writes** | `id` derived from `_intentHashId`. Struct fields written via `storage` pointer. Standard Solidity struct-in-mapping access. | No |
| **`futarchy[id]` struct writes** | Same as above. Standard mapping access. | No |
| **`sales[payToken]` writes** | `payToken` is user-supplied to `buyShares`. Writes go through `Sale storage s` pointer to standard mapping slot. The `payToken` address must correspond to an active sale (checked: `if (!s.active) revert`). | No |
| **`delegatecall` in `_execute` (L983)** | `to.delegatecall(data)` — arbitrary code runs in Moloch's storage context. **This IS an attacker-influenced slot write vector.** However, it requires a passing governance vote (Known Finding #14 — intentional by design). Privileged-role rule applies. | No (KF#14) |
| **`delegatecall` in `multicall` (L896)** | `address(this).delegatecall(data[i])` — target is always `address(this)`, constraining execution to Moloch's own functions. User controls calldata but not the target contract. Cannot access arbitrary slots beyond what Moloch's own functions permit. | No |
| **Assembly `TSTORE` (L1009)** | `tstore(REENTRANCY_GUARD_SLOT, address())` — constant slot `0x929eee149b4bd21268`. No user influence. Transient storage only. | No |

**Conclusion:** No attacker-influenced persistent slot writes. The only delegatecall-to-arbitrary-target path (`_execute` with `op=1`) is governance-gated and documented as Known Finding #14.

---

## Phase 4: Upgrade Collision Analysis

### Architecture: EIP-1167 Minimal Proxy Clones (No Upgradeability)

The contract uses EIP-1167 minimal proxies, NOT upgradeable proxies:

1. **Moloch implementation** created once by Summoner constructor (L2062)
2. **Moloch clones** created by `Summoner.summon()` via `CREATE2` with EIP-1167 bytecode
3. **Shares/Loot/Badges implementations** created once in Moloch's constructor (L204-206)
4. **Shares/Loot/Badges clones** created per-DAO in `Moloch.init()` via `_init()` (L235-240)

**Key properties:**
- Implementation addresses are **immutable** — stored in contract bytecode, not storage
- No `upgradeTo`, no `UUPS`, no Diamond facets, no beacon pattern
- Clone bytecode is fixed at deployment — the implementation pointer cannot change
- Each clone has its own storage space; implementation's storage is never accessed

**Immutable variable handling in clones:**
- `SUMMONER`, `sharesImpl`, `badgesImpl`, `lootImpl` are Solidity `immutable` values
- For EIP-1167 clones, `delegatecall` to the implementation reads the implementation's bytecode, so all clones share the same immutable values
- `SUMMONER` = Summoner contract address (correct for all clones — `init()` is called by Summoner)
- `sharesImpl`/`badgesImpl`/`lootImpl` = shared implementation addresses (correct — all DAOs use same implementations)

**Storage layout consistency:**
- All Moloch clones run the same implementation code → identical storage layout
- All Shares clones run the same Shares implementation → identical layout
- Same for Loot and Badges

**No upgrade path exists** — implementations are immutable references. Phase 4 is not applicable.

**Conclusion:** No upgrade collision risk. Architecture uses immutable clones with no upgrade mechanism.

---

## Phase 5: Storage Semantics Issues

Scanned for state desynchronization, failed bit-clearing, uninitialized reads, and similar persistent-state integrity issues.

### 5.1 Badges Bitmap Synchronization

The `Badges` contract maintains a `uint256 occupied` bitmap alongside a `Seat[256] seats` array, `seatOf` mapping, `balanceOf` mapping, and `_ownerOf` mapping. These must stay synchronized.

| Operation | `occupied` | `seats[]` | `seatOf` | `balanceOf` | `_ownerOf` | Sync? |
|---|---|---|---|---|---|---|
| `onSharesChanged` — insert (L1863-1867) | `_setUsed(freeSlot)` ✓ | `seats[freeSlot] = Seat(...)` ✓ | Set by `mintSeat` ✓ | Set by `mintSeat` ✓ | Set by `mintSeat` ✓ | **OK** |
| `onSharesChanged` — evict (L1881-1888) | Not cleared (seat reused) ✓ | `seats[slot] = Seat(newcomer)` ✓ | Cleared by `burnSeat`, set by `mintSeat` ✓ | Cleared by `burnSeat`, set by `mintSeat` ✓ | Cleared by `burnSeat`, set by `mintSeat` ✓ | **OK** |
| `onSharesChanged` — remove (L1829-1835) | `_setFree(slot)` ✓ | `seats[slot] = Seat(0, 0)` ✓ | Cleared by `burnSeat` ✓ | Cleared by `burnSeat` ✓ | Cleared by `burnSeat` ✓ | **OK** |
| `onSharesChanged` — update (L1845) | Unchanged ✓ | `seats[slot].bal = bal` ✓ | Unchanged ✓ | Unchanged ✓ | Unchanged ✓ | **OK** |

`minSlot`/`minBal` are recomputed via `_recomputeMin()` when the current minimum is affected. The recompute iterates all occupied bits — correct.

### 5.2 ERC6909 Balance/Supply Invariant

`totalSupply[id] == sum(balanceOf[*][id])` must hold.

- `_mint6909` (L945-951): `totalSupply[id] += amount` (checked), then `balanceOf[to][id] += amount` (unchecked). The unchecked addition is safe because `balanceOf[to][id] <= totalSupply[id]` (pre-increment) and `totalSupply[id] + amount` didn't overflow. ✓
- `_burn6909` (L953-958): `balanceOf[from][id] -= amount` (checked), then `totalSupply[id] -= amount` (unchecked). Safe because `totalSupply >= balanceOf[from] >= amount`. ✓
- `transfer` (L915-923): `balanceOf[sender] -= amount` (checked), `balanceOf[receiver] += amount` (unchecked). `totalSupply` unchanged. Safe — receiver's balance bounded by totalSupply. ✓
- `transferFrom` (L925-937): Same pattern as `transfer`. ✓

### 5.3 Shares Checkpoint Integrity

- `_writeCheckpoint` (L1523-1545): Same-block writes overwrite the last checkpoint (`last.votes = toUint96(newVal)`). Different-block writes push a new entry. The `if (last.votes == newVal) return` deduplication skips redundant pushes. No data loss — `getPastVotes` binary search over `fromBlock` always finds the correct historical value.
- `_writeTotalSupplyCheckpoint` (L1547-1557): Reads current `totalSupply` and delegates to `_writeCheckpoint`. Called after every mint/burn. Consistent.

### 5.4 Split Delegation State Consistency

- `setSplitDelegation` (L1260-1295): Captures old distribution BEFORE mutating `_splits`, then `delete _splits[account]` and rebuilds. `_repointVotesForHolder` moves voting power from old to new distribution. The path-independent `_targetAlloc` computation ensures no votes are created or destroyed.
- `clearSplitDelegation` (L1297-1317): Captures old, deletes splits, repoints. Same pattern.
- `_delegate` (L1319-1345): Captures old, deletes splits if any, sets new `_delegates[account]`, repoints. Consistent.
- `_autoSelfDelegate` (L1347-1353): Only sets `_delegates[account] = account` if currently `address(0)`. Idempotent. No checkpoint mutation — only recording the delegate address.

### 5.5 Proposal State Latch Consistency

- `executed[id]` set in three places: `executeByVotes` (L519), `spendPermit` (L668), `cancelProposal` (L429). Never cleared. One-way latch verified.
- `snapshotBlock[id]` set in `openProposal` (L291) guarded by `if (snapshotBlock[id] != 0) return`. Write-once.
- `supplySnapshot[id]` set in `openProposal` (L296) within the same guard. Write-once.
- `createdAt[id]` set in `openProposal` (L292) guarded by `if (createdAt[id] == 0)`. Write-once.
- `queuedAt[id]` set in `queue()` (L486) and `executeByVotes` (L511), both guarded by `if (queuedAt[id] == 0)`. Write-once.
- `futarchy[id].resolved` set in `_finalizeFutarchy` (L624), guarded by `!F.resolved` checks in callers. Write-once.

All latches are correctly one-way with appropriate guards.

### 5.6 Ragequit Token Exclusion Safety

`ragequit` (L759-797) prevents ragequitting Shares, Loot, the DAO itself, or address(1007):
```solidity
require(tk != address(shares), Unauthorized());
require(tk != address(loot), Unauthorized());
require(tk != address(this), Unauthorized());
require(tk != address(1007), Unauthorized());
```

The sorted ascending check (`if (i != 0 && tk <= prev) revert NotOk()`) prevents duplicate tokens. No storage desynchronization possible — burns happen before distribution, using a pre-burn `total`.

**Conclusion:** No storage semantics issues found. All auxiliary state (bitmaps, counters, latches) is kept in sync with primary state.

---

## Findings Summary

| Phase | Detection Target | Result |
|---|---|---|
| 1. Storage Inventory | Map all persistent state and mutation paths | 5 contracts, 50+ storage variables, 0 assembly `SSTORE` |
| 2. Lost Write Detection | Memory copies of storage values mutated without write-back | **0 findings** — all mutations use `storage` pointers |
| 3. Attacker-Influenced Slot Writes | Untrusted input determining storage slot targets | **0 findings** — standard mapping access only; delegatecall is KF#14 |
| 4. Upgrade Collision Analysis | Layout conflicts across proxy/implementation boundaries | **Not applicable** — immutable EIP-1167 clones, no upgrade path |
| 5. Storage Semantics Issues | State desynchronization, failed clearing, uninitialized reads | **0 findings** — bitmap/checkpoint/latch integrity verified |

---

## Assessment

The Slot Sleuth detector's 5 phases found **no storage-safety vulnerabilities** in Moloch.sol. This is expected given the contract's architecture:

1. **No manual slot arithmetic.** All storage access uses Solidity's native mapping/struct syntax, eliminating the primary class of bugs this detector targets (miscomputed slots, collision across namespaces).

2. **No upgradeable proxies.** EIP-1167 minimal proxy clones use fixed implementation references stored as immutables in bytecode. There is no `upgradeTo` path, so storage layout drift between versions cannot occur.

3. **No assembly `SSTORE`.** All 11 assembly blocks in the codebase operate on memory, transient storage, or perform external calls. Persistent storage writes are exclusively compiler-generated.

4. **Disciplined `storage` pointer usage.** Every struct mutation (Tally, Sale, FutarchyConfig, Checkpoint, Seat) goes through a Solidity `storage` pointer, guaranteeing automatic write-back. The two `memory` copies of structs (`cancelProposal`'s Tally and FutarchyConfig reads) are correctly read-only.

The Slot Sleuth skill is designed to catch bugs "outside the model's training distribution" — edge cases in manual slot computation, proxy layout collisions, and lost writes from storage-to-memory copies. Moloch.sol's architecture avoids all three patterns by design, making it a low-signal target for this particular detector. The contract's security risks lie in governance logic, economic interactions, and access control — areas covered by the other 18 audit tools in this repository.

---

> This review was performed using the ZeroSkills Slot Sleuth methodology (5-phase EVM storage-safety analysis) with manual code tracing across all 2110 lines of Moloch.sol.

# LPSeedSwapHook.sol Security

> **Purpose:** Aggregated security analysis for `LPSeedSwapHook.sol` — the singleton hook
> for seeding ZAMM liquidity from DAO treasury tokens. This document indexes all audits,
> tracks known findings, and documents mitigations.

---

## Contract Overview

| Property | Value |
|----------|-------|
| **File** | `src/peripheral/LPSeedSwapHook.sol` |
| **Lines** | ~511 |
| **Role** | Singleton ZAMM hook — seeds LP from DAO treasury, gates pre-seed actions, applies swap fees |
| **State** | `mapping(dao => SeedConfig)`, `mapping(poolId => dao)` — per-DAO seed config and pool ownership |
| **Access** | `seed` is permissionless (gated by conditions); `configure` is DAO-only (msg.sender keying); `cancel`/`setFee` are DAO-only |
| **Dependencies** | ZAMM singleton, Moloch allowance system, optional ShareSale gate |

---

## Audit History

| # | Date | Tool / Auditor | Mode | Findings | Report |
|---|------|----------------|------|----------|--------|
| 1 | 2026-03-15 | Winfunc | Multi-phase deep validation | 4 (2 High, 1 High, 1 Medium) | [`winfunc-20260315.md`](winfunc-20260315.md) |
| 2 | 2026-03-15 | Zellic V12 | Autonomous scan | 4 (2 High → Invalid, 1 Medium → Invalid, 1 Medium → Duplicate) | [`zellic-20260315.md`](zellic-20260315.md) |

**Aggregate: 2 audits, 4 unique findings (all addressed). 0 Critical, 1 High (after review), 1 Medium.**

---

## Known Findings

| # | Finding | Severity | Status | First Found | Also Confirmed By |
|---|---------|----------|--------|-------------|-------------------|
| 1 | Cross-DAO pool takeover via `poolDAO` last-writer-wins — theoretical pool ID collision | High | Accepted | Winfunc #3 | Zellic #4 |
| 2 | Pre-creation pricing attack — `poolDAO[poolId]` unset until `seed()` runs, allowing frontrun `addLiquidity` | High | Patched | Winfunc #5/9 | — |
| 3 | minSupply dusting griefing — attacker donates tokenB to push DAO balance above threshold | Medium | Accepted | Winfunc #24 | Zellic #6 |

### Finding 1 — Assessment

**Severity: High (theoretical, impractical in deployment). Accepted.**

The `poolDAO[poolId]` mapping is keyed by a deterministic `poolId` derived from the token pair. In theory, any caller could overwrite the mapping. In practice:

1. **`tokenB` is always the DAO's unique shares/loot token** — each DAO has a unique shares contract deployed by the Summoner. No two DAOs share the same shares token.
2. **Pool collision requires identical token pairs** — since tokenB is unique per DAO, an attacker cannot produce a colliding `poolId`.
3. **Winfunc's PoC required manually transferring victim DAO shares** to an attacker DAO — not possible without governance.

The recommended fix (`id0 = uint256(uint160(dao))`) is also invalid: ZAMM `id0`/`id1` are ERC-6909 token IDs, not arbitrary namespace fields.

### Finding 2 — Assessment & Patch

**Severity: High (patched).**

Pool ID is now reserved at `configure()` time (L209–213) so `beforeAction` blocks frontrun `addLiquidity` before `seed()` runs. This closes the window where `poolDAO[poolId]` was unset and the hook permitted attacker LP adds.

### Finding 3 — Assessment

**Severity: Medium (accepted, minimal impact).**

Dusting requires the attacker to permanently transfer their own tokens to the DAO (which become DAO treasury assets). The DAO can reconfigure with `cancel()` + re-`configure()` with an updated `minSupply` threshold, or set `minSupply = 0` to bypass the gate entirely.

---

## Dismissed Findings

| Source | Finding | Reason |
|--------|---------|--------|
| Zellic #9 (High) | Global seeding flag cross-pool bypass | **Invalid.** Requires attacker-controlled callback token, but tokens are DAO-configured. ZAMM is a trusted singleton. Cross-pool collision impossible (unique shares tokens). See [`zellic-20260315.md`](zellic-20260315.md). |
| Zellic #5 (Medium) | Inverted minSupply readiness gate | **Invalid.** Misinterprets semantics — `minSupply` is a ceiling ("seed when remaining supply drops below"), not a floor. NatSpec explicitly states: "seed only after DAO's tokenB balance <= minSupply". Implementation is correct. See [`zellic-20260315.md`](zellic-20260315.md). |

---

## Design Choices (Documented, Not Findings)

| # | Observation | Status | Source |
|---|-------------|--------|--------|
| DC-1 | `seed` is permissionless — anyone can trigger once all conditions are met | By design | Both audits |
| DC-2 | `minSupply` is a ceiling (max remaining balance for readiness), not a floor | By design | Zellic #5 (misinterpreted) |
| DC-3 | Transient `SEEDING_SLOT` flag scoped to `seed()` call only | By design | Zellic #9 |

---

## Hardening Patches

| Patch | Finding | Description |
|-------|---------|-------------|
| Pool ID reservation at `configure()` | KF#2 | `poolDAO[poolId] = msg.sender` set in `configure()` (L209–213), not just in `seed()` — blocks frontrun addLiquidity |

---

## Defense Mechanisms

| Defense | Mechanism | What It Prevents |
|---------|-----------|-----------------|
| **msg.sender keying** | `configure` keys to `msg.sender` | Only DAO can configure its own seed |
| **ZAMM-only hook calls** | `msg.sender != address(ZAMM)` check | Unauthorized hook invocations |
| **One-shot seeding** | `if (cfg.seeded) revert AlreadySeeded` | Double-seed |
| **CEI in seed()** | `cfg.seeded = true` before external calls | Reentrancy in seeding flow |
| **Pre-seed LP blocking** | `beforeAction` reverts `NotReady` for non-swap actions on unseeded pools | Frontrun pool creation |
| **Transient seeding flag** | `SEEDING_SLOT` set/cleared within `seed()` | Only seed() can addLiquidity pre-seed |
| **Condition gates** | Deadline, ShareSale completion, minSupply checks | Premature seeding |

---

## Invariants

1. **One-shot seed** — `seed()` can only succeed once per DAO configuration
2. **DAO-only configuration** — only the DAO (msg.sender) can set/change its seed parameters
3. **Pre-seed LP blocked** — no addLiquidity permitted before seeding (except by `seed()` itself)
4. **Post-seed swaps only** — swaps require the pool to be seeded and registered
5. **Allowance-bounded** — seed amounts cannot exceed DAO-approved allowances

---

## Cross-Audit Coverage Matrix

| Vulnerability Class | #1 Winfunc | #2 Zellic |
|---|---|---|
| Reentrancy | Clean (CEI) | #8 Invalid (CEI confirmed) |
| Access control | #3 (theoretical) | #4 Duplicate, #9 Invalid |
| Frontrunning/MEV | **#5/9 (patched)** | — |
| DoS / griefing | **#24 (accepted)** | **#6 Duplicate** |
| Readiness logic | — | #5 Invalid (correct semantics) |
| Pool identity | **#3 (accepted)** | **#4 Duplicate** |

---

## Expanding Coverage

To add new audit results:
1. Save the report as `{tool}-{date}.md` in this directory
2. Update the **Audit History** table above
3. Deduplicate new findings into **Known Findings**
4. Update finding statuses as fixes are applied

Recommended next scans:
- [ ] Cross-module scan: LPSeedSwapHook + ShareSale + SafeSummoner together
- [ ] Fuzz testing of `_isReady` with edge-case balances and timestamps
- [ ] Formal verification of seeding state machine (configure → seed → seeded)

# LPSeedSwapHook.sol Security

> **Purpose:** Aggregated security analysis for `LPSeedSwapHook.sol` — the singleton hook
> for seeding ZAMM liquidity from DAO treasury tokens. This document indexes all audits,
> tracks known findings, and documents mitigations.

### Instructions

You are a senior Solidity security auditor. Analyze `LPSeedSwapHook.sol` (~520 lines) — a ZAMM hook singleton that seeds LP from DAO treasury, gates pre-seed actions, and applies swap fees with optional DAO revenue. Work in **two rounds**:

**Round 1: Defense Verification.** For each defense mechanism in the table below, verify it works as described by tracing the actual code. Cite specific line numbers. State whether the defense holds or is broken. Then verify each invariant. Produce a conclusion for every defense and every invariant — "Verified" or "Violated" with evidence.

**Round 2: Adversarial Hunt.** Attempt to find vulnerabilities NOT covered by the Known Findings table or the Design Choices / Dismissed Findings tables. For each candidate: (1) check it against Known Findings — discard if duplicate, (2) check it against Design Choices / Dismissed Findings — discard if intentional or already disproved, (3) attempt disproof, (4) rate confidence 0-100. Only include findings that survive all checks.

**Report format:** For each finding: `[SEVERITY-N] Title`, severity, confidence, location (file:lines), description, attack path, disproof attempt, recommendation.

---

## Contract Overview

| Property | Value |
|----------|-------|
| **File** | `src/peripheral/LPSeedSwapHook.sol` |
| **Lines** | ~520 |
| **Role** | Singleton ZAMM hook — seeds LP from DAO treasury, gates pre-seed actions, applies swap fees + optional DAO revenue fees |
| **State** | `mapping(dao => SeedConfig)`, `mapping(dao => DaoFeeConfig)`, `mapping(poolId => dao)` — per-DAO seed/fee config and pool ownership |
| **Access** | `seed` is permissionless (gated by conditions); `configure` is DAO-only (msg.sender keying); `cancel`/`setFee`/`setDaoFee`/`setBeneficiary` are DAO-only |
| **Dependencies** | ZAMM singleton, Moloch allowance system, optional ShareSale gate |

---

## Audit History

| # | Date | Tool / Auditor | Mode | Findings | Report |
|---|------|----------------|------|----------|--------|
| 1 | 2026-03-15 | Winfunc | Multi-phase deep validation | 4 (2 High, 1 High, 1 Medium) | [`winfunc-20260315.md`](winfunc-20260315.md) |
| 2 | 2026-03-15 | Zellic V12 | Autonomous scan | 4 (2 High → Invalid, 1 Medium → Invalid, 1 Medium → Duplicate) | [`zellic-20260315.md`](zellic-20260315.md) |
| 3 | 2026-03-15 | Pashov Skills v1 | 4-agent parallel vector scan | 5 (1 Duplicate, 2 Patched, 2 Accepted) | [`pashov-20260315.md`](pashov-20260315.md) |
| 4 | 2026-03-18 | Pashov Skills v1 | Post-patch re-scan | 0 (1 FP, 1 Duplicate) | [`pashov-20260318.md`](pashov-20260318.md) |
| 5 | 2026-03-18 | Grimoire (Sigil+Familiar) | 4-agent parallel hunt + adversarial triage | 1 (1 Low — patched) | [`grimoire-20260318.md`](grimoire-20260318.md) |

**Aggregate: 5 audits, 8 unique findings. 0 Critical, 1 High (accepted theoretical), 4 Medium (2 patched, 2 accepted), 2 Low (both patched).**

---

## Known Findings

| # | Finding | Severity | Status | First Found | Also Confirmed By |
|---|---------|----------|--------|-------------|-------------------|
| 1 | Cross-DAO pool takeover via `poolDAO` last-writer-wins — theoretical pool ID collision | High | Accepted | Winfunc #3 | Zellic #4, Pashov #1 |
| 2 | Pre-creation pricing attack — `poolDAO[poolId]` unset until `seed()` runs, allowing frontrun `addLiquidity` | High | Patched | Winfunc #5/9 | — |
| 3 | minSupply dusting griefing — attacker donates tokenB to push DAO balance above threshold | Medium | Accepted | Winfunc #24 | Zellic #6 |
| 4 | Fee-on-output slippage bypass — `amountOutMin` checked on gross not net in `swapExactIn` | Medium | Patched | Pashov #2 | — |
| 5 | Launch fee underflow — `launchBps < feeBps` causes revert in `beforeAction` decay math | Medium | Patched | Pashov #5 | — |
| 6 | `swapExactOut` ERC20 fee-on-input missing `netMax` — ZAMM cap not reduced for tax, causing underflow on refund | Low | Patched | Pre-audit review | — |
| 7 | `quoteExactOut` fee-on-input floor rounding returns insufficient `amountIn`, causing swap revert | Low | Patched | Grimoire L-01 | — |

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

### Finding 4 — Assessment & Patch

**Severity: Medium (patched).**

In `swapExactIn` with fee-on-output, `amountOutMin` was forwarded to ZAMM as a gross (pre-tax) floor. After ZAMM returned `amountOut`, the hook deducted `tax`, and the user received `net = amountOut - tax` which could be less than their intended minimum. A sandwich attacker could exploit this gap.

**Fix:** Pass `0` to ZAMM as minimum, enforce `if (net < amountOutMin) revert Slippage()` after tax deduction. The user's `amountOutMin` now protects the actual net amount received.

Note: `swapExactOut` fee-on-output is not affected — the user specifies exact net `amountOut`, and the contract computes `gross` correctly.

### Finding 5 — Assessment & Patch

**Severity: Medium (patched).**

If `launchBps` was set lower than `feeBps` (possible via `setFee()` after `setLaunchFee()`), the expression `launch - (launch - target)` in `beforeAction` triggered a Solidity 0.8 underflow revert on every swap during the decay period.

**Fix:** Made decay bidirectional — handles both `launch >= target` (decay down) and `launch < target` (decay up).

### Finding 6 — Assessment & Patch

**Severity: Low (patched via pre-audit review).**

In `swapExactOut` ERC20 fee-on-input, `amountInMax` was passed directly to ZAMM as the cap. If ZAMM consumed close to `amountInMax`, the subsequent `tax` calculation left insufficient tokens for the refund, causing underflow at `amountInMax - amountIn - tax`.

**Fix:** Compute `netMax = (amountInMax * (10_000 - bps)) / 10_000` and pass that to ZAMM, matching the ETH path's pattern.

### Finding 7 — Assessment & Patch

**Severity: Low (patched).**

`quoteExactOut` with fee-on-input computed `daoTax = floor(net * bps / (10_000 - bps))`, but `swapExactOut` computed `netMax = floor(amountInMax * (10_000 - bps) / 10_000)`. Due to floor rounding asymmetry, `netMax` could be 1 less than `net`, causing ZAMM to revert with `InsufficientInputAmount()`. No fund loss — the transaction simply reverts — but any caller relying on the quote for `amountInMax` would experience intermittent reverts.

**Not a duplicate of KF#6:** KF#6 addressed the *absence* of the `netMax` cap. This finding is about a rounding asymmetry *in* the `netMax` calculation introduced by that patch.

**Fix:** Ceil the tax in `quoteExactOut` fee-on-input (L668): `daoTax = (net * bps + (10_000 - bps) - 1) / (10_000 - bps)`. This guarantees `floor(amountIn * (10_000 - bps) / 10_000) >= net`.

---

## Dismissed Findings

| Source | Finding | Reason |
|--------|---------|--------|
| Zellic #9 (High) | Global seeding flag cross-pool bypass | **Invalid.** Requires attacker-controlled callback token, but tokens are DAO-configured. ZAMM is a trusted singleton. Cross-pool collision impossible (unique shares tokens). See [`zellic-20260315.md`](zellic-20260315.md). |
| Zellic #5 (Medium) | Inverted minSupply readiness gate | **Invalid.** Misinterprets semantics — `minSupply` is a ceiling ("seed when remaining supply drops below"), not a floor. NatSpec explicitly states: "seed only after DAO's tokenB balance <= minSupply". Implementation is correct. See [`zellic-20260315.md`](zellic-20260315.md). |
| Pashov #3 (Medium) | Blacklisted beneficiary DoSes swaps | **Accepted as design constraint.** DAO controls beneficiary via `setBeneficiary()` — governance can change it. Pull-based fees would add gas overhead to every swap. Typical pools use DAO shares tokens, not blacklistable tokens like USDC. |
| Pashov #4 (Medium) | Fee-on-transfer token DoS in `seed()` | **Accepted as unsupported token type.** DAO shares/loot tokens don't have transfer fees. DAOs configure their own tokens — using a fee-on-transfer token is a misconfiguration. See Design Choices DC-4. |
| Pashov-2 #1 (High) | Hardcoded 1e18 arb-clamp bypassed for non-18-decimal tokens | **False positive.** The `1e18` is the shares scaling factor, not a token-decimal assumption. `salePrice` is defined as "payToken-wei per 1e18 share-wei" by both ShareSale and BondingCurveSale. Formula `maxShares = payAmt * 1e18 / salePrice` is the algebraic inverse of `cost = amount * price / 1e18` — correct for any pay token decimals. See DC-6. |
| Pashov-2 #2 (Low) | Blacklisted beneficiary DoS (re-scan) | **Duplicate of Pashov #3.** |

---

## Design Choices (Documented, Not Findings)

| # | Observation | Status | Source |
|---|-------------|--------|--------|
| DC-1 | `seed` is permissionless — anyone can trigger once all conditions are met | By design | All audits |
| DC-2 | `minSupply` is a ceiling (max remaining balance for readiness), not a floor | By design | Zellic #5 (misinterpreted) |
| DC-3 | Transient `SEEDING_SLOT` flag scoped to `seed()` call only | By design | Zellic #9 |
| DC-4 | Fee-on-transfer tokens are not supported — `seed()` and routed swaps assume 1:1 transfer amounts | By design | Pashov #4 |
| DC-5 | Push-based fee distribution to beneficiary — simpler than pull pattern, DAO can change beneficiary via governance | By design | Pashov #3 |
| DC-6 | Arb-protection clamp is decimal-agnostic — `salePrice` is "payToken-wei per 1e18 share-wei", so `maxShares = payAmt * 1e18 / salePrice` works for any pay token decimals (ETH/18d, USDC/6d, etc.) | By design | Pashov-2 #1 (FP) |

---

## Hardening Patches

| Patch | Finding | Description |
|-------|---------|-------------|
| Pool ID reservation at `configure()` | KF#2 | `poolDAO[poolId] = msg.sender` set in `configure()`, not just in `seed()` — blocks frontrun addLiquidity |
| Net slippage check in `swapExactIn` | KF#4 | `amountOutMin` checked against net output after tax, not gross from ZAMM |
| Bidirectional launch fee decay | KF#5 | `beforeAction` handles both `launch >= target` and `launch < target` without underflow |
| `swapExactOut` ERC20 `netMax` cap | KF#6 | ZAMM's input cap reduced by fee bps to reserve room for tax and refund |
| `quoteExactOut` fee-on-input ceil tax | KF#7 | Ceil `daoTax` in quote to guarantee quoted `amountIn` survives floor division in swap |

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
| **Routing enforcement** | `beforeAction` blocks direct ZAMM swaps when beneficiary is set | DAO fee bypass |
| **Transient swap lock** | `SWAP_LOCK_SLOT` reentrancy guard on routed swaps | Reentrancy in swap routing |
| **Net slippage check** | `Slippage()` revert after tax deduction | Sandwich attacks on fee-on-output swaps |

---

## Invariants

1. **One-shot seed** — `seed()` can only succeed once per DAO configuration
2. **DAO-only configuration** — only the DAO (msg.sender) can set/change its seed parameters
3. **Pre-seed LP blocked** — no addLiquidity permitted before seeding (except by `seed()` itself)
4. **Post-seed swaps only** — swaps require the pool to be seeded and registered
5. **Allowance-bounded** — seed amounts cannot exceed DAO-approved allowances
6. **Net slippage** — fee-on-output swaps enforce `amountOutMin` on the amount the user actually receives

---

## Cross-Audit Coverage Matrix

| Vulnerability Class | #1 Winfunc | #2 Zellic | #3 Pashov | #4 Pashov-2 | #5 Grimoire |
|---|---|---|---|---|---|
| Reentrancy | Clean (CEI) | #8 Invalid (CEI confirmed) | Clean (lock + CEI) | Clean | Clean (16 sub-hypotheses dismissed) |
| Access control | #3 (theoretical) | #4 Duplicate, #9 Invalid | #1 Duplicate | Clean | Clean (16 sub-hypotheses dismissed) |
| Frontrunning/MEV | **#5/9 (patched)** | — | — | Clean | Clean |
| Slippage | — | — | **#2 (patched)** | Clean | Clean |
| Arithmetic | — | — | **#5 (patched)** | #1 FP (decimal-agnostic confirmed) | **L-01 (patched)** |
| DoS / griefing | **#24 (accepted)** | **#6 Duplicate** | #3, #4 Accepted | #2 Duplicate | Clean |
| Readiness logic | — | #5 Invalid (correct semantics) | — | Clean | Clean |
| Pool identity | **#3 (accepted)** | **#4 Duplicate** | #1 Duplicate | Clean | Clean |
| Token compatibility | — | — | #4 Accepted (unsupported) | Clean | Clean (assembly byte-verified) |

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
- [ ] Integration test: routed swaps with fee-on-output confirming net slippage check
- [ ] Integration test: seed with 6-decimal pay token (e.g. USDC mock) confirming arb-clamp correctness

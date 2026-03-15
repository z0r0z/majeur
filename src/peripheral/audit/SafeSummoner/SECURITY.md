# SafeSummoner.sol Security

> **Purpose:** Aggregated security analysis for `SafeSummoner.sol` — the safe deployment wrapper
> for Moloch DAOs. This document indexes all audits, tracks known findings, and documents
> mitigations. It follows the format established in the root `SECURITY.md` for `Moloch.sol`.

---

## Contract Overview

| Property | Value |
|----------|-------|
| **File** | `src/peripheral/SafeSummoner.sol` |
| **Lines** | ~1120 |
| **Role** | Factory wrapper — validates config, builds initCalls, deploys DAOs via Summoner singleton |
| **State** | Stateless (no storage). All state lives in deployed DAOs. |
| **Access** | All functions are permissionless. No admin, no owner. |
| **Dependencies** | `Summoner` (CREATE2 factory), `ShareBurner`, `RollbackGuardian`, `ShareSale`, `TapVest`, `LPSeedSwapHook` singletons |

---

## Audit History

| # | Date | Tool / Auditor | Mode | Findings | Report |
|---|------|----------------|------|----------|--------|
| 1 | 2026-03-13 | Pashov AI Auditor v1 | 4-agent vector scan (default) | 2 (85, 80) | [`pashov-ai-audit-20260313.md`](pashov-ai-audit-20260313.md) |
| 2 | 2026-03-13 | SCV Scan (36 classes) | 4-phase deep validation | 1 (Informational) | [`scvscan-20260313.md`](scvscan-20260313.md) |
| 3 | 2026-03-13 | ZeroSkills Slot Sleuth | 5-phase storage-safety | 0 | [`zeroskills-20260313.md`](zeroskills-20260313.md) |
| 4 | 2026-03-13 | Archethect SC-Auditor | Map-Hunt-Attack + Devil's Advocate | 0 novel (2 DT, 1 C) | [`archethect-20260313.md`](archethect-20260313.md) |
| 5 | 2026-03-13 | Forefy Multi-Expert | 3-round (systematic + economic + triager) + fv-sol KB | 0 novel (3 Info, all dismissed) | [`forefy-20260313.md`](forefy-20260313.md) |
| 6 | 2026-03-13 | Grimoire Agentic | 4 Sigils + 3 Familiars (adversarial triage) | 0 novel (2 Info, 2 DC) | [`grimoire-20260313.md`](grimoire-20260313.md) |
| 7 | 2026-03-13 | Pashov AI Auditor v1 | DEEP (4 vector scan + 1 adversarial reasoning) | 0 novel (2 duplicates) | [`pashov-ai-deep-20260313.md`](pashov-ai-deep-20260313.md) |
| 8 | 2026-03-13 | ChatGPT o3 (5.4) | Single-pass review | 1 novel (LOW-02), 3 accepted | [`chatgpt-20260313.md`](chatgpt-20260313.md) |
| 9 | 2026-03-15 | Winfunc | Multi-phase deep validation | 2 (1 High, 1 High) — cross-module (ShareBurner wiring, CREATE2 squatting) | [`winfunc-20260315.md`](winfunc-20260315.md) |

**Aggregate: 9 audits, 9 methodologies, 6 unique findings (all addressed). 0 Critical, 0 High (after review), 0 Medium.**

---

## Known Findings

Findings from all audits, deduplicated by root cause. Status tracks whether the finding
has been addressed.

| # | Finding | Severity | Status | First Found | Also Confirmed By |
|---|---------|----------|--------|-------------|-------------------|
| 1 | Silent `uint96` truncation in `_defaultThreshold` — extreme share totals (>7.9e30) silently produce near-zero proposal threshold, bypassing KF#11 | Low | Patched | Audit #1 (conf 85) | #4 C-01, #5 Finding 3 |
| 2 | `create2Deploy` salt not bound to `msg.sender` — front-running DoS on deterministic deployments | Info | Accepted | Audit #1 (conf 80) | #4 DT-01, #5 Finding 2, #6 I-01, #7 F1 |
| 3 | `multicall` delegatecall shares `msg.value` across sub-calls — caller could double-spend own ETH | Info | Accepted | Audit #2 | #4 DT-02, #5 Finding 1, #6 I-02, #7 F2 |
| 4 | `saleBurnDeadline` burn permit targets shares even when `saleIsLoot = true` — unsold loot not burnable | Low | Patched | Audit #8 (LOW-02) | — |
| 5 | Auto-burn permit burns entire `balanceOf(dao)` rather than tracked sale inventory — over-scope burn if DAO holds shares for non-sale purposes | High | Accepted | Audit #9 (Winfunc #2) | ShareBurner KF#1 |
| 6 | Predictable deployment address squatting via CREATE2 salt collision | High | Accepted | Audit #9 (Winfunc #6) | KF#2 variant |

### Finding 5 — Assessment

**Severity: High (accepted, not fixed — deployed contract).**

SafeSummoner is already deployed. The finding is a configuration footgun: `saleBurnDeadline > 0` without an active non-minting sale is deployer misconfiguration. ShareBurner burns `balanceOf(dao)` by design. Deployers control `SafeConfig` and would need to intentionally set a burn deadline without a corresponding sale. Cross-tracked in ShareBurner KF#1.

### Finding 6 — Assessment

**Severity: High → Info (variant of KF#2, accepted).**

Variant of KF#2 (CREATE2 salt not bound to `msg.sender`). `initHolders` and `initShares` are in the salt, so the attacker cannot substitute themselves as share holders. The legitimate deployer would see the misconfigured DAO and redeploy with a different salt. No funds are at risk since the DAO is empty at deployment time.

### Finding 1 — Assessment & Patch

**Severity downgrade: Low (non-issue in practice, patched defensively).**

Moloch.sol itself uses `uint96` throughout: vote tallies (`forVotes`, `againstVotes`, `abstainVotes`),
`getPastVotes` return values, `setProposalThreshold(uint96)`, and `quorumAbsolute`. If total shares
exceed `type(uint96).max` (~7.9e28), the entire governance system is already broken — vote weights
truncate, quorum checks fail, delegation accounting wraps. The threshold truncation is downstream
of a fundamentally broken precondition.

**Patch applied:** saturating cap added to `_defaultThreshold` as cheap defensive measure:
```solidity
if (t > type(uint96).max) t = type(uint96).max;
```
This silences the compiler lint and prevents wrapping, but the real guard is that no sane
deployment has >7.9e28 total shares.

### Finding 2 — Assessment

**Severity: Informational (accepted, no fix needed).**

The front-running scenario is benign:
1. Attacker frontruns `create2Deploy(bytecode, salt)` with the same params
2. The victim's contract is now deployed at the predicted address — **with the correct bytecode**
3. The victim's `create2Deploy` reverts, but the contract they wanted already exists
4. Victim retries their multicall without the `create2Deploy` step, or uses a different salt

The attacker pays gas to deploy the victim's contract for them. No funds at risk, no
malicious code injection (CREATE2 address includes bytecode hash). Adding `msg.sender`-binding
would break the useful property that predicted addresses are sender-independent, complicating
cross-EOA and contract-based deployment flows.

### Finding 3 — Assessment

**Severity: Informational (accepted, no fix needed).**

Standard delegatecall-multicall behavior — identical to Uniswap V3 Router, Seaport, and other
production contracts. Each sub-call sees the original `msg.value` because `delegatecall` preserves
the call context. The NatSpec at L203-205 explicitly documents this: "msg.value is shared across
all calls — callers sending ETH must ensure only one sub-call consumes it." The risk is
self-contained — only the caller's own ETH is at stake, and the caller controls the data array.
No external attacker can exploit this. No code change warranted.

### Finding 4 — Assessment & Patch

**Severity: Low (patched).**

When `saleIsLoot = true` and `saleBurnDeadline > 0`, the burn permit in `_buildCalls` always
targeted `_predictShares(dao)` instead of `_predictLoot(dao)`. This meant the generated
one-shot `ShareBurner.burnUnsold` permit would target the wrong token — unsold loot would
remain unburnable via the automated burn path.

**Patch applied:** branch on `saleIsLoot` when computing the burn target:
```solidity
address saleToken = c.saleIsLoot ? _predictLoot(dao) : _predictShares(dao);
bytes memory burnData = abi.encodeCall(IShareBurner.burnUnsold, (saleToken, c.saleBurnDeadline));
```

First novel finding across 8 audits — only ChatGPT o3 caught this because it required
reasoning about the interaction between two independent config fields (`saleIsLoot` and
`saleBurnDeadline`) that no prior audit methodology tested in combination.

---

## Design Choices (Documented, Not Findings)

These were surfaced by multiple audits and confirmed as intentional architecture decisions:

| # | Observation | Status | Source |
|---|-------------|--------|--------|
| DC-1 | `extraCalls` can override validated config — deployer foot-gun, not vulnerability. SafeSummoner is advisory, not a security boundary. | By design | #6 DC-01, #4 MH-009 |
| DC-2 | Module parameters (TapVest rate, SeedModule amounts) not validated by SafeSummoner — correctly delegated to singleton `configure` functions. | By design | #5 Expert 2 §3, #6 DC-02 |

---

## Hardening Patches

Defensive patches applied in response to audit findings:

| Patch | Finding | Description |
|-------|---------|-------------|
| `_defaultThreshold` saturating cap | KF#1 | `if (t > type(uint96).max) t = type(uint96).max` — prevents silent uint96 truncation |
| `_validate` rollback singleton check | Archethect MH-013 | `if (rollbackGuardian != 0 && rollbackSingleton == 0) revert RollbackSingletonRequired()` — prevents silent misconfiguration |
| `_buildCalls` loot burn target | KF#4 | `c.saleIsLoot ? _predictLoot(dao) : _predictShares(dao)` — burn permit targets correct sale token |

---

## Defense Mechanisms

These are the safety properties enforced by SafeSummoner that downstream DAOs rely on:

| Defense | Mechanism | What It Prevents |
|---------|-----------|-----------------|
| **proposalThreshold > 0** | `_validate` reverts `ProposalThresholdRequired` | KF#11: proposal spam, front-run cancel griefing |
| **proposalTTL > 0** | `_validate` reverts `ProposalTTLRequired` | Proposals that never expire |
| **timelockDelay < TTL** | `_validate` reverts `TimelockExceedsTTL` | Proposals expiring while queued |
| **quorumBps range** | `_validate` reverts `QuorumBpsOutOfRange` | Invalid quorum (>100%) |
| **autoFutarchyCap > 0** | `_validate` reverts `FutarchyCapRequired` when futarchy enabled | KF#3: unbounded futarchy earmarks |
| **quorum required for futarchy** | `_validate` reverts `QuorumRequiredForFutarchy` | KF#17: zero-quorum premature NO-resolution |
| **minting sale + dynamic quorum** | `_validate` / `_validateModules` reverts `MintingSaleWithDynamicQuorum` | KF#2: supply inflation manipulating quorum denominator |
| **seed gate requires sale** | `_validateModules` reverts `SeedGateWithoutSale` | Gating LP seed on nonexistent sale |
| **module-sale conflict** | `safeSummonDAICO` reverts `ModuleSaleConflict` | Using both SafeConfig.saleActive and SaleModule simultaneously |
| **rollback singleton required** | `_validate` reverts `RollbackSingletonRequired` | Guardian configured with no singleton (silent no-op) |

---

## Invariants

Properties that should hold for any DAO deployed through SafeSummoner:

1. **proposalThreshold > 0** — every deployed DAO has a nonzero proposal threshold
2. **proposalTTL > timelockDelay** — proposals cannot expire while queued
3. **futarchy requires quorum** — no futarchy-enabled DAO has zero quorum
4. **minting sales require absolute quorum** — prevents dynamic quorum manipulation
5. **initHolders.length > 0** — no DAO deployed with zero initial holders
6. **initLoot.length == 0 || initLoot.length == initHolders.length** — loot array matches holders
7. **rollbackGuardian requires rollbackSingleton** — no guardian without a singleton to execute it

---

## Cross-Audit Coverage Matrix

Shows which vulnerability classes each audit methodology covered for SafeSummoner:

| Vulnerability Class | #1 Pashov | #2 SCV | #3 ZeroSkills | #4 Archethect | #5 Forefy | #6 Grimoire | #7 Pashov DEEP | #8 ChatGPT |
|---|---|---|---|---|---|---|---|---|
| Reentrancy | Eliminated | V18 DROP | N/A (no storage) | MH-002 DISCARD | fv-sol-1 N/A | Sigil 1: 0 findings | Eliminated | — |
| Integer overflow | **F1 (85)** | V15 DROP (patched) | — | **C-01** (patched) | fv-sol-3 clean | — | Eliminated | — |
| Access control | Eliminated | V10 DROP | — | MH-009 DISCARD | fv-sol-4 clean | S4-3 DISMISSED | Eliminated | — |
| Frontrunning/MEV | **F2 (80)** | V13 DROP | — | **DT-01** | fv-sol-4-c9 | **I-01** | **F1 [80]** | DS-01 (dup) |
| msg.value reuse | Eliminated | **V12 CONFIRM** | — | **DT-02** | fv-sol-5-c7 | **I-02** | **F2 [65]** | DS-02 (dup) |
| Storage safety | — | — | **5-phase: 0** | MH-004 DISCARD | — | Sigil 1: 0 | N/A (no storage) | — |
| Delegatecall | Eliminated | V4 DROP | — | MH-002 DISCARD | fv-sol-1 N/A | S4-4 DISMISSED | Eliminated | — |
| DoS / gas | Eliminated | V5,V6 DROP | — | MH-006,014 DISCARD | fv-sol-9 clean | S4-5 DISMISSED | Eliminated | — |
| Hash collision | — | V7 DROP | — | — | — | — | — | — |
| Validation bypass | — | — | — | MH-008,011,012 DISCARD | Expert 2 §3 | S2-1 DISMISSED | Hyp B: Rejected | LOW-01, LOW-03 |
| Module wiring | — | — | Phase 5.1-5.3 | MH-007 DISCARD | Expert 2 §1-§2 | S3-1,S3-2 DISMISSED | — | **LOW-02 (patched)** |
| Governance context | — | — | — | — | 10/10 classes | — | Hyp A,B: Rejected | — |

---

## Expanding Coverage

To add new audit results to this folder:

1. Run the audit tool against `SafeSummoner.sol` (e.g. `solidity-auditor SafeSummoner.sol` or `solidity-auditor DEEP SafeSummoner.sol`)
2. Save the report as `{tool}-{date}.md` in this directory
3. Update the **Audit History** table above
4. Deduplicate new findings into the **Known Findings** table
5. Update finding statuses as fixes are applied

Recommended next scans:
- [x] Pashov AI Auditor — DEEP mode (adds adversarial reasoning agent) → Audit #7
- [ ] Cross-module scan: SafeSummoner + ShareSale + TapVest + LPSeedSwapHook together
- [ ] Fuzz testing of `_defaultThreshold` with extreme inputs
- [ ] Formal verification of call array count/fill invariants

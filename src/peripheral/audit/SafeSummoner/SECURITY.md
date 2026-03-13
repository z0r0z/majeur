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

**Aggregate: 6 audits, 6 methodologies, 3 unique findings (all addressed). 0 Critical, 0 High, 0 Medium.**

---

## Known Findings

Findings from all audits, deduplicated by root cause. Status tracks whether the finding
has been addressed.

| # | Finding | Severity | Status | First Found | Also Confirmed By |
|---|---------|----------|--------|-------------|-------------------|
| 1 | Silent `uint96` truncation in `_defaultThreshold` — extreme share totals (>7.9e30) silently produce near-zero proposal threshold, bypassing KF#11 | Low | Patched | Audit #1 (conf 85) | #4 C-01, #5 Finding 3 |
| 2 | `create2Deploy` salt not bound to `msg.sender` — front-running DoS on deterministic deployments | Info | Accepted | Audit #1 (conf 80) | #4 DT-01, #5 Finding 2, #6 I-01 |
| 3 | `multicall` delegatecall shares `msg.value` across sub-calls — caller could double-spend own ETH | Info | Accepted | Audit #2 | #4 DT-02, #5 Finding 1, #6 I-02 |

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

| Vulnerability Class | #1 Pashov | #2 SCV | #3 ZeroSkills | #4 Archethect | #5 Forefy | #6 Grimoire |
|---|---|---|---|---|---|---|
| Reentrancy | Eliminated | V18 DROP | N/A (no storage) | MH-002 DISCARD | fv-sol-1 N/A | Sigil 1: 0 findings |
| Integer overflow | **F1 (85)** | V15 DROP (patched) | — | **C-01** (patched) | fv-sol-3 clean | — |
| Access control | Eliminated | V10 DROP | — | MH-009 DISCARD | fv-sol-4 clean | S4-3 DISMISSED |
| Frontrunning/MEV | **F2 (80)** | V13 DROP | — | **DT-01** | fv-sol-4-c9 | **I-01** |
| msg.value reuse | Eliminated | **V12 CONFIRM** | — | **DT-02** | fv-sol-5-c7 | **I-02** |
| Storage safety | — | — | **5-phase: 0** | MH-004 DISCARD | — | Sigil 1: 0 |
| Delegatecall | Eliminated | V4 DROP | — | MH-002 DISCARD | fv-sol-1 N/A | S4-4 DISMISSED |
| DoS / gas | Eliminated | V5,V6 DROP | — | MH-006,014 DISCARD | fv-sol-9 clean | S4-5 DISMISSED |
| Hash collision | — | V7 DROP | — | — | — | — |
| Validation bypass | — | — | — | MH-008,011,012 DISCARD | Expert 2 §3 | S2-1 DISMISSED |
| Module wiring | — | — | Phase 5.1-5.3 | MH-007 DISCARD | Expert 2 §1-§2 | S3-1,S3-2 DISMISSED |
| Governance context | — | — | — | — | 10/10 classes | — |

---

## Expanding Coverage

To add new audit results to this folder:

1. Run the audit tool against `SafeSummoner.sol` (e.g. `solidity-auditor SafeSummoner.sol` or `solidity-auditor DEEP SafeSummoner.sol`)
2. Save the report as `{tool}-{date}.md` in this directory
3. Update the **Audit History** table above
4. Deduplicate new findings into the **Known Findings** table
5. Update finding statuses as fixes are applied

Recommended next scans:
- [ ] Pashov AI Auditor — DEEP mode (adds adversarial reasoning agent)
- [ ] Cross-module scan: SafeSummoner + ShareSale + TapVest + LPSeedSwapHook together
- [ ] Fuzz testing of `_defaultThreshold` with extreme inputs
- [ ] Formal verification of call array count/fill invariants

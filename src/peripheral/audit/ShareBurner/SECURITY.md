# ShareBurner.sol Security

> **Purpose:** Aggregated security analysis for `ShareBurner.sol` — the stateless singleton
> for burning unsold DAO shares after a sale deadline. This document indexes all audits,
> tracks known findings, and documents mitigations.

### Instructions

You are a senior Solidity security auditor. Analyze `ShareBurner.sol` (~91 lines) — a stateless singleton that burns unsold DAO shares via a delegatecall permit after a sale deadline. Work in **two rounds**:

**Round 1: Defense Verification.** For each defense mechanism in the table below, verify it works as described by tracing the actual code. Cite specific line numbers. State whether the defense holds or is broken. Then verify each invariant. Produce a conclusion for every defense and every invariant — "Verified" or "Violated" with evidence.

**Round 2: Adversarial Hunt.** Attempt to find vulnerabilities NOT covered by the Known Findings table or the Dismissed Findings table. For each candidate: (1) check it against Known Findings — discard if duplicate, (2) check it against Dismissed Findings — discard if already disproved, (3) attempt disproof, (4) rate confidence 0-100. Only include findings that survive all checks.

**Report format:** For each finding: `[SEVERITY-N] Title`, severity, confidence, location (file:lines), description, attack path, disproof attempt, recommendation.

---

## Contract Overview

| Property | Value |
|----------|-------|
| **File** | `src/peripheral/ShareBurner.sol` |
| **Lines** | ~91 |
| **Role** | Stateless singleton — burns unsold shares via delegatecall permit after deadline |
| **State** | Stateless (no storage). Operates via DAO permits. |
| **Access** | `closeSale` is permissionless; `burnUnsold` runs in DAO context via delegatecall |
| **Dependencies** | Moloch permit system (`spendPermit`, `setPermit`), Shares (`burnFromMoloch`) |

---

## Audit History

| # | Date | Tool / Auditor | Mode | Findings | Report |
|---|------|----------------|------|----------|--------|
| 1 | 2026-03-15 | Winfunc | Multi-phase deep validation | 2 (1 High, 1 Medium) | [`winfunc-20260315.md`](winfunc-20260315.md) |
| 2 | 2026-03-15 | Zellic V12 | Autonomous scan | 1 (Critical → Invalid) | [`zellic-20260315.md`](zellic-20260315.md) |

**Aggregate: 2 audits, 2 unique findings (all addressed). 0 Critical, 1 High, 1 Medium.**

---

## Known Findings

| # | Finding | Severity | Status | First Found | Also Confirmed By |
|---|---------|----------|--------|-------------|-------------------|
| 1 | `burnUnsold` burns entire `balanceOf(dao)` rather than tracked sale inventory — over-scope burn if DAO holds shares for non-sale purposes | High | Accepted | Winfunc #2 | — |
| 2 | `closeSale` burns inventory but doesn't deactivate built-in `Moloch.Sale` — post-expiry buys still possible via core `buyShares` | Medium | Accepted | Winfunc #25 | — |

### Finding 1 — Assessment

**Severity: High (accepted, not fixed — deployed contract).**

SafeSummoner is already deployed. The finding is a configuration footgun: `saleBurnDeadline > 0` without an active non-minting sale is deployer misconfiguration. ShareBurner burns `balanceOf(dao)` by design — the "over-scope" is simply what burn means. Deployers control `SafeConfig` and would need to intentionally set a burn deadline without a corresponding sale.

**V2 hardening (future):** scope `burnUnsold()` to a tracked sale-inventory amount rather than live treasury balance; add config validation rejecting `saleBurnDeadline > 0` without an active non-minting share sale.

### Finding 2 — Assessment

**Severity: Medium (accepted, not fixed — core contract).**

Would require adding a `deadline` field to `Moloch.Sale` struct or modifying core `buyShares()`. Core Moloch is already deployed/audited. DAOs using the ShareSale peripheral module (which has its own deadline field) are not affected.

---

## Dismissed Findings

| Source | Finding | Reason |
|--------|---------|--------|
| Zellic #7 (Critical) | Caller-supplied deadline bypass | **Invalid.** Misunderstands permit architecture — deadline is encoded in the permit at deploy time and verified by `spendPermit`. See [`zellic-20260315.md`](zellic-20260315.md). |

---

## Defense Mechanisms

| Defense | Mechanism | What It Prevents |
|---------|-----------|-----------------|
| **One-shot permit** | `setPermit(..., count=1)` | Double-burn: permit can only be spent once |
| **Delegatecall execution** | `burnUnsold` runs in DAO context | External callers cannot manipulate DAO state directly |
| **Deadline enforcement** | `block.timestamp <= deadline` check | Premature burns before sale ends |
| **Permit data binding** | `spendPermit` verifies encoded calldata | Prevents parameter tampering (shares address, deadline) |

---

## Invariants

1. **One-shot burn** — the permit can only be spent once per deployment
2. **Post-deadline only** — burns cannot occur before the encoded deadline
3. **DAO context** — `burnUnsold` always executes as the DAO via delegatecall

---

## Expanding Coverage

To add new audit results:
1. Save the report as `{tool}-{date}.md` in this directory
2. Update the **Audit History** table above
3. Deduplicate new findings into **Known Findings**
4. Update finding statuses as fixes are applied

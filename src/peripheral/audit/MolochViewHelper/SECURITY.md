# MolochViewHelper.sol Security

> **Purpose:** Aggregated security analysis for `MolochViewHelper.sol` — the view-only
> helper for DAO state inspection. This document indexes all audits, tracks known findings,
> and documents mitigations.

---

## Contract Overview

| Property | Value |
|----------|-------|
| **File** | `src/peripheral/MolochViewHelper.sol` |
| **Lines** | ~1247 |
| **Role** | View-only helper — aggregates DAO state reads for off-chain consumers |
| **State** | Stateless (pure view functions) |
| **Access** | All functions are `view` / read-only |
| **Dependencies** | Moloch core, Shares, Loot, Renderer contracts (external reads) |

---

## Audit History

| # | Date | Tool / Auditor | Mode | Findings | Report |
|---|------|----------------|------|----------|--------|
| 1 | 2026-03-15 | Winfunc | Multi-phase deep validation | 3 (2 Medium, 1 Low) | [`winfunc-20260315.md`](winfunc-20260315.md) |

**Aggregate: 1 audit, 2 unique root causes (all accepted). 0 Critical, 0 High, 2 Medium, 1 Low. No fund risk (view-only contract).**

---

## Known Findings

| # | Finding | Severity | Status | First Found | Also Confirmed By |
|---|---------|----------|--------|-------------|-------------------|
| 1 | `contractURI` DoS on batched reads — malicious renderer can cause batch view calls to revert | Medium | Accepted | Winfunc #22 | — |
| 2 | Delegate-only voter omission — view helper doesn't enumerate delegate-only voters | Medium | Accepted | Winfunc #26/28 | — |

### Finding 1 — Assessment

**Severity: Medium (accepted, view-only concern).**

A malicious `contractURI` response from a DAO's renderer can cause batch view functions to revert. No fund risk — affects off-chain reads only. V2 hardening: wrap `contractURI` calls in try/catch.

### Finding 2 — Assessment

**Severity: Medium (accepted, UX limitation).**

View helper doesn't enumerate accounts that hold delegated votes but no shares/loot themselves. On-chain governance is unaffected — votes are correctly counted in Moloch core. This is a display completeness issue for off-chain UIs.

---

## Defense Mechanisms

| Defense | Mechanism | What It Prevents |
|---------|-----------|-----------------|
| **View-only** | All functions are `view` | No state modification possible |
| **No fund custody** | Contract holds no assets | No theft vector |

---

## Expanding Coverage

To add new audit results:
1. Save the report as `{tool}-{date}.md` in this directory
2. Update the **Audit History** table above
3. Deduplicate new findings into **Known Findings**
4. Update finding statuses as fixes are applied

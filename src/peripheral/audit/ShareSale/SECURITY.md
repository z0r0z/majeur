# ShareSale.sol Security

> **Purpose:** Aggregated security analysis for `ShareSale.sol` — the token sale configuration
> and management peripheral. This document indexes all audits, tracks known findings,
> and documents mitigations.

---

## Contract Overview

| Property | Value |
|----------|-------|
| **File** | `src/peripheral/ShareSale.sol` |
| **Lines** | ~173 |
| **Role** | Token sale — configures and manages DAO share/loot sales with pricing and deadlines |
| **State** | `mapping(dao => SaleConfig)` — per-DAO sale configuration |
| **Access** | `configure` is DAO-only (msg.sender keying); `buy` is permissionless |
| **Dependencies** | Moloch allowance system, ERC20 tokens |

---

## Audit History

| # | Date | Tool / Auditor | Mode | Findings | Report |
|---|------|----------------|------|----------|--------|
| 1 | 2026-03-15 | Winfunc | Multi-phase deep validation | 2 (2 Medium) | [`winfunc-20260315.md`](winfunc-20260315.md) |

**Aggregate: 1 audit, 2 unique findings (both patched). 0 Critical, 0 High, 2 Medium.**

---

## Known Findings

| # | Finding | Severity | Status | First Found | Also Confirmed By |
|---|---------|----------|--------|-------------|-------------------|
| 1 | Unchecked pricing overflow — `cost = amount * s.price / 1e18` in unchecked block allows silent wraparound | Medium | Patched | Winfunc #20 | — |
| 2 | Stray ETH on ERC20 purchase — ETH sent with an ERC20-denominated purchase is silently lost | Medium | Patched | Winfunc #27 | — |

### Finding 1 — Assessment & Patch

**Severity: Medium (patched).**

Removed `unchecked` block from pricing math. Solidity 0.8 checked arithmetic now prevents silent wraparound on extreme price/amount combinations.

### Finding 2 — Assessment & Patch

**Severity: Medium (patched).**

Added `if (msg.value != 0) revert` in the ERC20 payment branch to prevent silent ETH loss when a user accidentally sends ETH with an ERC20-denominated purchase.

---

## Defense Mechanisms

| Defense | Mechanism | What It Prevents |
|---------|-----------|-----------------|
| **msg.sender keying** | `configure` keys to `msg.sender` | Only DAO can configure its own sale |
| **Checked arithmetic** | Solidity 0.8 checked math (post-patch) | KF#1: pricing overflow |
| **ETH guard** | `msg.value != 0` revert (post-patch) | KF#2: stray ETH loss |
| **Deadline enforcement** | Sale deadline check | Purchases after sale ends |

---

## Expanding Coverage

To add new audit results:
1. Save the report as `{tool}-{date}.md` in this directory
2. Update the **Audit History** table above
3. Deduplicate new findings into **Known Findings**
4. Update finding statuses as fixes are applied

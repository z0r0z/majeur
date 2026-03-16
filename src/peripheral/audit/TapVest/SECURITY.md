# TapVest.sol Security

> **Purpose:** Aggregated security analysis for `TapVest.sol` — the singleton for linear
> vesting from a DAO treasury via the allowance system. This document indexes all audits,
> tracks known findings, and documents mitigations.

### Instructions

You are a senior Solidity security auditor. Analyze `TapVest.sol` (~214 lines) — a singleton linear vesting peripheral that distributes DAO treasury funds via the Moloch allowance system. Work in **two rounds**:

**Round 1: Defense Verification.** For each defense mechanism in the table below, verify it works as described by tracing the actual code. Cite specific line numbers. State whether the defense holds or is broken. Then verify each invariant. Produce a conclusion for every defense and every invariant — "Verified" or "Violated" with evidence.

**Round 2: Adversarial Hunt.** Attempt to find vulnerabilities NOT covered by the Known Findings table or the Design Choices tables. For each candidate: (1) check it against Known Findings — discard if duplicate, (2) check it against Design Choices — discard if intentional, (3) attempt disproof, (4) rate confidence 0-100. Only include findings that survive all checks.

**Report format:** For each finding: `[SEVERITY-N] Title`, severity, confidence, location (file:lines), description, attack path, disproof attempt, recommendation.

---

## Contract Overview

| Property | Value |
|----------|-------|
| **File** | `src/peripheral/TapVest.sol` |
| **Lines** | ~214 |
| **Role** | Singleton — linear vesting from DAO treasury via allowance, permissionless claims |
| **State** | `mapping(dao => TapConfig)` — per-DAO tap configuration |
| **Access** | `claim` is permissionless; `configure` is DAO-only (msg.sender keying); `setBeneficiary`/`setRate` are DAO-only |
| **Dependencies** | Moloch allowance system (`spendAllowance`, `setAllowance`, `allowance`) |

---

## Audit History

| # | Date | Tool / Auditor | Mode | Findings | Report |
|---|------|----------------|------|----------|--------|
| 1 | 2026-03-15 | Winfunc | Multi-phase deep validation | 3 (1 High, 2 Medium) | [`winfunc-20260315.md`](winfunc-20260315.md) |
| 2 | 2026-03-15 | Zellic V12 | Autonomous scan | 2 (1 Critical → Invalid, 1 Low → Duplicate) | [`zellic-20260315.md`](zellic-20260315.md) |

**Cross-audit confirmations:** Winfunc #4/13 confirmed by Certora FV L-01, webrainsec H-01, Zellic #2.

**Aggregate: 2 audits + 2 cross-references, 2 unique findings (all addressed). 0 Critical, 0 High (after review), 1 Medium.**

---

## Known Findings

| # | Finding | Severity | Status | First Found | Also Confirmed By |
|---|---------|----------|--------|-------------|-------------------|
| 1 | Permissionless `claim` erases accrued vesting during treasury shortfalls — `lastClaim` advances unconditionally on partial claims | Low | Accepted | Certora FV L-01 | webrainsec H-01, Winfunc #4/13, Zellic #2 |
| 2 | Fake-DAO singleton drain — stray ETH/ERC20 on TapVest singleton can be extracted via crafted `configure`+`claim` | Medium | Accepted | Winfunc #15 | — |

### Finding 1 — Assessment

**Severity downgrade: Low (acknowledged design trade-off, documented across 4 audits).**

This is an intentional design decision:

1. **Simplicity over complexity:** Tracking partial accrual debt would add storage, gas, and attack surface. The current design keeps TapVest minimal.
2. **DAO-controlled mitigation:** The DAO controls allowance via governance. `claimable()` lets anyone check the effective amount before triggering a claim.
3. **`setRate` is DAO-only:** Rate changes that reset `lastClaim` are conscious governance decisions.
4. **Ragequit is sacrosanct:** Moloch exit-rights can drain treasury below tap obligations — this is fundamental to the Moloch design. The tap is subordinate to member exit rights.
5. **No attacker profit:** Permissionless `claim` sends funds to the configured beneficiary, not the caller.

### Finding 2 — Assessment

**Severity: Medium (accepted, negligible impact).**

In normal operation, TapVest never holds a persistent balance — `spendAllowance` delivers funds and `claim` immediately forwards them. The attack can only drain stray ETH/ERC20 from accidental transfers or forced ETH sends.

---

## Dismissed Findings

| Source | Finding | Reason |
|--------|---------|--------|
| Zellic #8 (Critical) | Reentrant claims before lastClaim update | **Invalid.** CEI is correctly followed — `lastClaim` is updated at L83 *before* external calls at L86–93. The "attacker-controlled contracts" (`dao`, `token`) are set by the DAO itself in `configure`. See [`zellic-20260315.md`](zellic-20260315.md). |

---

## Design Choices (Documented, Not Findings)

| # | Observation | Status | Source |
|---|-------------|--------|--------|
| DC-1 | `claim` is permissionless — anyone can trigger a payout, but funds always go to the beneficiary | By design | Winfunc #4/13, Zellic #2 |
| DC-2 | `setRate` resets `lastClaim` without settling prior accrual — intentional non-retroactive rate change | By design | Zellic #2 |

---

## Defense Mechanisms

| Defense | Mechanism | What It Prevents |
|---------|-----------|-----------------|
| **msg.sender keying** | `configure` keys to `msg.sender` | Only DAO can configure its own tap |
| **Allowance cap** | `claimed = min(owed, allowance, daoBalance)` | Cannot exceed DAO-approved budget |
| **CEI ordering** | `lastClaim` updated before external calls | Reentrancy (state updated first) |
| **Zero-rate guard** | `configure` reverts on `ratePerSec == 0` | Misconfigured taps |

---

## Invariants

1. **Funds always go to beneficiary** — `claim` can be called by anyone but payout destination is immutable per-call
2. **DAO-only configuration** — only the DAO (msg.sender) can set/change its tap parameters
3. **Rate-limited payouts** — `claimed <= ratePerSec * elapsed` always holds
4. **Allowance-bounded** — total payouts cannot exceed the DAO's configured allowance

---

## Expanding Coverage

To add new audit results:
1. Save the report as `{tool}-{date}.md` in this directory
2. Update the **Audit History** table above
3. Deduplicate new findings into **Known Findings**
4. Update finding statuses as fixes are applied

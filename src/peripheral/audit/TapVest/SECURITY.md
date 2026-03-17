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
| **Lines** | ~239 |
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
| 3 | 2026-03-17 | Pashov Skills v1 | 4-agent vector scan | 4 (2 Invalid/Dup, 2 Acknowledged) | [`pashov-20260317.md`](pashov-20260317.md) |
| 4 | 2026-03-17 | Grimoire | 4 Sigils + 3 Familiars (DEEP) | 4 (2 Dup/Low, 1 Severity-Adjusted, 1 Dismissed) | [`grimoire-20260317.md`](grimoire-20260317.md) |
| 5 | 2026-03-17 | ChatGPT (GPT 5.4) | Defense verification + adversarial | 1 Medium (novel — corrects prior characterization) | [`chatgpt-20260317.md`](chatgpt-20260317.md) |

**Cross-audit confirmations:** Winfunc #4/13 confirmed by Certora FV L-01, webrainsec H-01, Zellic #2. Pashov #1 duplicate of Zellic #8. Pashov #2 duplicate of Winfunc #15. Grimoire S2-A confirms Pashov #3 / Certora L-01. Grimoire S2-B confirms Winfunc #15 / Pashov #2. ChatGPT M-1 corrects Pashov #3 / DC-4 characterization (overpayment, not dust loss).

**Aggregate: 5 audits + 2 cross-references, 3 unique findings (all fixed). 0 Critical, 0 High (after review), 1 Medium (fixed).**

---

## Known Findings

| # | Finding | Severity | Status | First Found | Also Confirmed By |
|---|---------|----------|--------|-------------|-------------------|
| 1 | Permissionless `claim` erases accrued vesting during treasury shortfalls — `lastClaim` advances unconditionally on partial claims | Low | **Fixed** | Certora FV L-01 | webrainsec H-01, Winfunc #4/13, Zellic #2, Pashov #3 |
| 2 | Fake-DAO singleton drain — stray ETH/ERC20 on TapVest singleton can be extracted via crafted `configure`+`claim` | Medium | Accepted | Winfunc #15 | Pashov #2 |
| 3 | `setBeneficiary` reverts on frozen taps (rate set to 0 via `setRate`) | Low | **Fixed** | Internal review | — |
| 4 | Inconsistent `unchecked` scope — `claimable`/`pending` wrap multiplication in `unchecked` while `claim` does not | Info | **Fixed** | Internal review | — |
| 5 | Fee-on-transfer token accounting mismatch — DoS if configured with fee-on-transfer ERC20 | Low | Acknowledged | Winfunc #15 | Pashov #2 |
| 6 | Blacklisted beneficiary DoS — `claim` reverts if beneficiary is token-blacklisted | Low | Acknowledged | Pashov #4 | — |

### Finding 1 — Assessment

**Severity: Low. Status: Fixed.**

Originally, `lastClaim` advanced unconditionally to `block.timestamp` even when `claimed < owed` due to insufficient DAO balance, permanently erasing unclaimed accrual. This was initially accepted as a design trade-off.

**Fix applied:** `claim()` now advances `lastClaim` proportionally when capped, with `claimed` rounded to whole seconds to prevent truncation overpayment:
```solidity
if (claimed == owed) {
    tap.lastClaim = uint64(block.timestamp);
} else {
    uint64 advance = uint64(claimed / tap.ratePerSec);
    if (advance == 0) revert NothingToClaim();
    claimed = uint256(advance) * uint256(tap.ratePerSec);
    tap.lastClaim += advance;
}
```
This preserves unclaimed time for future claims when the DAO is temporarily underfunded, while ensuring tokens paid = time consumed exactly. See Finding 1a below for the truncation correction.

**Finding 1a — Division truncation overpayment (corrected by ChatGPT M-1). Status: Fixed.**

Previously characterized as "dust loss" (Pashov #3, DC-4). ChatGPT (GPT 5.4) correctly identified the direction is **overpayment, not loss**: `claimed % ratePerSec` worth of tokens were paid but the corresponding time was not consumed, making that fractional amount reclaimable.

**Fix applied:** `claimed` is now rounded down to whole seconds before transfer:
```solidity
uint64 advance = uint64(claimed / tap.ratePerSec);
if (advance == 0) revert NothingToClaim();
claimed = uint256(advance) * uint256(tap.ratePerSec);
tap.lastClaim += advance;
```
This ensures tokens paid = time consumed exactly. `claimable()` also rounds down to match. The tradeoff is that sub-second token dust remains in the DAO until the next whole second of vesting accrues — acceptable since the dust is never lost, just deferred.

### Finding 2 — Assessment

**Severity: Medium (accepted, negligible impact).**

In normal operation, TapVest never holds a persistent balance — `spendAllowance` delivers funds and `claim` immediately forwards them. The attack can only drain stray ETH/ERC20 from accidental transfers or forced ETH sends.

### Finding 3 — Assessment

**Severity: Low. Status: Fixed.**

`setBeneficiary()` previously checked `if (tap.ratePerSec == 0) revert NotConfigured()`, which blocked beneficiary changes on frozen taps (rate set to 0 via `setRate`). This was inconsistent with `setRate()` which correctly used `if (tap.ratePerSec == 0 && tap.beneficiary == address(0))`.

**Fix applied:** `setBeneficiary()` now uses the same guard as `setRate()`:
```solidity
if (tap.ratePerSec == 0 && tap.beneficiary == address(0)) revert NotConfigured();
```

### Finding 4 — Assessment

**Severity: Info. Status: Fixed.**

`claimable()` and `pending()` wrapped the `ratePerSec * elapsed` multiplication inside `unchecked`, while `claim()` had it outside. Not exploitable (`uint128 * uint64` fits in `uint256`), but inconsistent. Fixed for clarity — all three functions now only wrap the timestamp subtraction in `unchecked`.

### Finding 5 — Assessment

**Severity: Low (acknowledged, not fixed).**

If a fee-on-transfer ERC20 is configured, `spendAllowance` delivers `claimed - fee` to TapVest, then `safeTransfer(token, beneficiary, claimed)` reverts (insufficient balance). This causes DoS, not silent loss. DAOs should not configure fee-on-transfer tokens. Adding balance-before/after checks penalizes all legitimate claims.

### Finding 6 — Assessment

**Severity: Low (acknowledged, not fixed).**

If the beneficiary is blacklisted by the configured token (e.g. USDC), `claim()` reverts until the DAO calls `setBeneficiary()` via governance. Standard push-payment limitation; recoverable.

---

## Dismissed Findings

| Source | Finding | Reason |
|--------|---------|--------|
| Zellic #8 (Critical) | Reentrant claims before lastClaim update | **Invalid.** CEI is correctly followed — `lastClaim` is updated before external calls. The "attacker-controlled contracts" (`dao`, `token`) are set by the DAO itself in `configure`. See [`zellic-20260315.md`](zellic-20260315.md). |
| Pashov #1 (85) | Reentrancy via malicious DAO `spendAllowance` | **Invalid.** Duplicate of Zellic #8. Self-attack only — attacker deploys own contract, calls `configure()` from it, populates `taps[attackerContract]`, and can only drain their own contract. On real Moloch DAOs, `spendAllowance` is `nonReentrant`. See [`pashov-20260317.md`](pashov-20260317.md). |
| Grimoire Sigil 1 (all) | Reentrancy / CEI violations (6 vectors) | **Dismissed.** `lastClaim` updated before all external calls (L84-88 before L91-98). `spendAllowance` is `nonReentrant`. Cross-function reentrancy blocked by `msg.sender` keying. See [`grimoire-20260317.md`](grimoire-20260317.md). |
| Grimoire S4-A | No sweep — stray ETH stuck in TapVest | **Dismissed (incorrect).** Duplicate of Known Finding #2. Stray ETH is *extractable* via fake-DAO pattern, not stuck. Familiar disproved the "permanently stuck" characterization. |

---

## Design Choices (Documented, Not Findings)

| # | Observation | Status | Source |
|---|-------------|--------|--------|
| DC-1 | `claim` is permissionless — anyone can trigger a payout, but funds always go to the beneficiary | By design | Winfunc #4/13, Zellic #2 |
| DC-2 | `setRate` resets `lastClaim` without settling prior accrual — intentional non-retroactive rate change | By design | Zellic #2 |
| DC-3 | Fee-on-transfer tokens not supported — will DoS `claim` if configured | By design | Winfunc #15, Pashov #2 |
| DC-4 | ~~Division dust on partial claims~~ **Corrected and fixed:** truncation previously caused overpayment; `claimed` now rounded to whole seconds | **Fixed** | Pashov #3, Grimoire S2-A, ChatGPT M-1 |
| DC-5 | `configure()` resets `lastClaim` — re-calling forfeits accrued time (use `setBeneficiary`/`setRate` for changes) | By design | Grimoire S3-A |

---

## Defense Mechanisms

| Defense | Mechanism | What It Prevents |
|---------|-----------|-----------------|
| **msg.sender keying** | `configure` keys to `msg.sender` | Only DAO can configure its own tap |
| **Allowance cap** | `claimed = min(owed, allowance, daoBalance)` | Cannot exceed DAO-approved budget |
| **CEI ordering** | `lastClaim` updated before external calls (`spendAllowance`, transfers) | Reentrancy (state updated first) |
| **Proportional advance** | `lastClaim += advance`, `claimed` rounded to whole seconds | Preserves unclaimed time on partial payouts; prevents truncation overpayment |
| **Zero-rate guard** | `configure` reverts on `ratePerSec == 0` | Misconfigured taps |
| **Frozen tap governance** | `setBeneficiary`/`setRate` use `ratePerSec == 0 && beneficiary == address(0)` guard | Allows governance on frozen (rate=0) taps |

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

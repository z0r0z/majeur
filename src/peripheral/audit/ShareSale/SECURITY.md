# ShareSale.sol Security

> **Purpose:** Aggregated security analysis for `ShareSale.sol` — the singleton for selling DAO
> shares or loot via the Moloch allowance system. This document indexes all audits, tracks known
> findings, and documents mitigations.

### Instructions

You are a senior Solidity security auditor. Analyze `ShareSale.sol` (~227 lines including free functions) — a stateless singleton that sells DAO shares/loot via the Moloch allowance system with configurable pricing and deadlines. Work in **two rounds**:

**Round 1: Defense Verification.** For each defense mechanism in the table below, verify it works as described by tracing the actual code. Cite specific line numbers. State whether the defense holds or is broken. Then verify each invariant. Produce a conclusion for every defense and every invariant — "Verified" or "Violated" with evidence.

**Round 2: Adversarial Hunt.** Attempt to find vulnerabilities NOT covered by the Known Findings table or the Design Choices tables. For each candidate: (1) check it against Known Findings — discard if duplicate, (2) check it against Design Choices — discard if intentional, (3) attempt disproof, (4) rate confidence 0-100. Only include findings that survive all checks.

**Report format:** For each finding: `[SEVERITY-N] Title`, severity, confidence, location (file:lines), description, attack path, disproof attempt, recommendation.

---

## Contract Overview

| Property | Value |
|----------|-------|
| **File** | `src/peripheral/ShareSale.sol` |
| **Lines** | ~227 (contract ~174, free functions ~53) |
| **Role** | Singleton — sells DAO shares/loot at a fixed price via the Moloch allowance system |
| **State** | `mapping(address dao => Sale)` — per-DAO sale configuration (only mutable state) |
| **Access** | `configure` is DAO-only (msg.sender keying); `buy`/`buyExactIn` are permissionless |
| **Dependencies** | Moloch allowance system (`spendAllowance`, `setAllowance`, `allowance`), Moloch mint sentinels (`address(dao)` = shares, `address(1007)` = loot) |
| **Integrations** | SafeSummoner `SaleModule` (generates initCalls), LPSeedSwapHook (reads `sales()` to gate LP seeding on sale completion) |

### External Call Map

```
buy(dao, amount):
  1. IMoloch(dao).allowance(s.token, this)     [view — read remaining cap]
  2. IMoloch(dao).spendAllowance(s.token, amt) [CEI: effects first — decrements allowance, _payout mints/transfers to ShareSale]
  3. safeTransferETH(dao, cost)                [ETH to DAO]
     OR safeTransferFrom(s.payToken, dao, cost) [ERC20 from buyer to DAO]
  4. safeTransferETH(msg.sender, refund)       [ETH refund if overpaid]
  5. IMoloch(dao).shares() / loot()            [view — resolve token address]
  6. safeTransfer(tokenAddr, msg.sender, amt)  [shares/loot to buyer]

buyExactIn(dao):  [same pattern as buy(), ETH-only]
configure(...):   [no external calls — pure storage write keyed to msg.sender]
```

---

## Audit History

| # | Date | Tool / Auditor | Mode | Findings | Report |
|---|------|----------------|------|----------|--------|
| 1 | 2026-03-15 | Winfunc | Multi-phase deep validation | 2 (2 Medium) | [`winfunc-20260315.md`](winfunc-20260315.md) |
| 2 | 2026-03-17 | Pashov AI | Vector scan (4-agent) | 3 (1 High, 1 Medium, 1 Low) | [`pashov-20260317.md`](pashov-20260317.md) |
| 3 | 2026-03-17 | Grimoire | 4-sigil hypothesis-driven (post-patch) | 0 (clean) | [`grimoire-20260317.md`](grimoire-20260317.md) |
| 4 | 2026-03-17 | ChatGPT (GPT 5.4) | Defense verification + adversarial | 1 Low (novel) | [`chatgpt-20260317.md`](chatgpt-20260317.md) |
| 5 | 2026-03-17 | Claude (Opus 4.6) | Defense verification + adversarial (post-patch) | 0 (clean) | [`claude-20260317.md`](claude-20260317.md) |

**Aggregate: 5 audits, 6 unique findings (5 patched, 1 accepted). 0 Critical, 1 High, 3 Medium, 2 Low. Post-patch Claude audit: clean.**

---

## Known Findings

| # | Finding | Severity | Status | First Found | Also Confirmed By |
|---|---------|----------|--------|-------------|-------------------|
| 1 | Unchecked pricing overflow — `cost = amount * s.price / 1e18` in unchecked block allows silent wraparound | Medium | Patched | Winfunc #20 | — |
| 2 | Stray ETH on ERC20 purchase — ETH sent with an ERC20-denominated purchase is silently lost | Medium | Patched | Winfunc #27 | — |
| 3 | CEI violation — ETH refund and ERC20 payment before `spendAllowance` enables reentrancy to double-spend DAO allowance | High | Patched | Pashov #1 | Pashov #3 (ERC777 variant) |
| 4 | Zero-cost rounding — small amounts with sub-1e18 price round `cost` to zero, bypassing payment | Low | Patched | Pashov #2 | — |
| 5 | ERC777 reentrancy — `tokensToSend` hook in ERC20 path enables re-entry before allowance reduction | Medium | Patched | Pashov #3 | — |
| 6 | Fake-DAO singleton drain — unsolicited ERC20 balances on ShareSale can be extracted via a fake DAO with no-op `spendAllowance` | Low | Accepted | ChatGPT LOW-1 | — |

### Finding 1 — Assessment & Patch

**Severity: Medium (patched).**

Removed `unchecked` block from pricing math. Solidity 0.8 checked arithmetic now prevents silent wraparound on extreme price/amount combinations.

### Finding 2 — Assessment & Patch

**Severity: Medium (patched).**

Added `if (msg.value != 0) revert UnexpectedETH()` in the ERC20 payment branch to prevent silent ETH loss when a user accidentally sends ETH with an ERC20-denominated purchase.

### Finding 3 — Assessment & Patch

**Severity: High (patched).**

`buy()` and `buyExactIn()` originally called `spendAllowance` after payment interactions (ETH transfers, ERC20 `transferFrom`). This allowed a buyer contract to re-enter via the ETH refund callback before the allowance was decremented, double-spending the DAO's share allowance.

**Fix applied:** Moved `spendAllowance` before all payment interactions (CEI pattern):
```solidity
// Spend allowance first (CEI: effects before interactions)
IMoloch(dao).spendAllowance(s.token, amount);
// ... then collect payment and transfer shares
```

### Finding 4 — Assessment & Patch

**Severity: Low (patched).**

When `price < 1e18`, buying small amounts causes `cost = amount * price / 1e18` to truncate to zero. Practically limited by gas costs (each call yields only dust amounts of shares), but exploitable in principle.

**Fix applied:** Added `if (cost == 0) revert ZeroAmount()` after cost calculation in both `buy()` and `buyExactIn()`.

### Finding 5 — Assessment & Patch

**Severity: Medium (patched).**

Same root cause as KF#3 (CEI violation). In the ERC20 payment path, `safeTransferFrom` could trigger an ERC777 `tokensToSend` hook on the buyer before `spendAllowance` ran. Resolved by the same fix as KF#3 — moving `spendAllowance` first.

### Finding 6 — Assessment

**Severity: Low (accepted, negligible impact).**

ShareSale does not authenticate `dao` as a genuine Moloch. An attacker can deploy a fake DAO whose `spendAllowance()` is a no-op and `shares()` returns a target ERC20 address. If ERC20 tokens have been accidentally sent to the ShareSale contract, the attacker can drain them by buying through the fake DAO — ETH payment goes to the attacker-controlled fake DAO (recoverable), and unsolicited tokens are transferred to the attacker.

In normal operation ShareSale never holds a persistent ERC20 balance — `spendAllowance` delivers tokens and `safeTransfer` immediately forwards them. The attack can only drain accidentally-sent tokens. Same class as TapVest KF#2. Not fixed: adding a DAO registry or balance-delta check would penalize all legitimate purchases for a near-zero-probability scenario.

---

## Dismissed Findings

| Source | Finding | Reason |
|--------|---------|--------|
| Grimoire Sigil 1 | Reentrancy via `spendAllowance` callbacks | **Dismissed.** Moloch's `spendAllowance` is `nonReentrant`. Internal `_payout` callbacks only reach trusted DAO contracts (not attacker-controllable). |
| Grimoire Sigil 1 | Cross-function reentrancy after ETH refund | **Dismissed.** After CEI fix, `spendAllowance` is called first — allowance is decremented before any attacker-controllable callback. Re-entering `buy()` reads the updated (lower) allowance. ShareSale has no mutable per-user state to corrupt. |
| Grimoire Sigil 2 | Round-trip precision loss in `buyExactIn` | **Dismissed.** Max underpayment per call is `(s.price - 1) / 1e18` (< 1 wei for typical prices). Both divisions truncate consistently. |
| Grimoire Sigil 2 | Overflow DoS on `amount * s.price` | **Dismissed.** Requires values far beyond total ETH supply (~1.2e26 wei). Unreachable. |
| Grimoire Sigil 3 | Fake sale config social engineering | **Dismissed.** Attacker can only write `sales[attacker_address]`. Buyer must explicitly pass attacker's address as `dao`. Not a ShareSale flaw. |
| Grimoire Sigil 3 | Stuck funds in ShareSale singleton | **Partially superseded by KF#6.** No `receive()`/`fallback()`, so ETH cannot accumulate. Token flows are transient. However, unsolicited ERC20s *can* be drained via fake-DAO pattern (see KF#6). |
| ChatGPT | Allowance cap / Moloch nonReentrant "violated" | **Clarified, not violated.** These defenses are cross-contract dependencies on real Moloch DAOs — they hold in production. ChatGPT correctly noted they are not enforceable from ShareSale's file scope alone. Defense descriptions updated to note dependency assumptions. |
| Grimoire Sigil 4 | `safeTransferFrom` uses `caller()` — wrong in delegatecall | **Dismissed.** ShareSale is a singleton, never delegatecalled. `caller()` correctly references `msg.sender`. |
| Pashov (below threshold) | ETH-sale DoS when DAO can't receive ETH | **Dismissed.** If DAO contract rejects ETH, buy reverts (no fund loss). DAOs choosing ETH sales must have a receive/fallback. Configuration concern. |

---

## Design Choices (Documented, Not Findings)

| # | Observation | Status | Source |
|---|-------------|--------|--------|
| DC-1 | `configure` is permissionless but keyed to `msg.sender` — anyone can create a `sales[self]` entry, but only affects their own address | By design | Grimoire Sigil 3 |
| DC-2 | Fee-on-transfer tokens not accounted for — DAO receives less than `cost` if payToken charges fees | By design | Grimoire Sigil 2 |
| DC-3 | `buy()` caps to remaining allowance and refunds excess ETH — buyer may receive fewer shares than requested | By design | — |
| DC-4 | `buyExactIn()` is ETH-only — reverts if `payToken != address(0)` | By design | — |
| DC-5 | No `receive()`/`fallback()` — ShareSale cannot accumulate ETH between transactions | By design | Grimoire Sigil 3 |
| DC-6 | Price can be reconfigured by DAO governance via `configure()` — no price-lock mechanism | By design | Grimoire Sigil 2 |
| DC-7 | `saleInitCalls()` is a helper that returns (target, data) pairs — pure view, no side effects | By design | — |

---

## Defense Mechanisms

| Defense | Mechanism | What It Prevents |
|---------|-----------|-----------------|
| **msg.sender keying** | `configure` keys to `msg.sender` | Only DAO can configure its own sale |
| **Checked arithmetic** | Solidity 0.8 checked math (post-patch) | KF#1: pricing overflow |
| **ETH guard** | `msg.value != 0` revert in ERC20 branch (post-patch) | KF#2: stray ETH loss |
| **CEI ordering** | `spendAllowance` before all interactions (post-patch) | KF#3/5: reentrancy via refund/ERC777 |
| **Zero-cost guard** | `cost == 0` revert after pricing (post-patch) | KF#4: rounding to zero payment |
| **Deadline enforcement** | `block.timestamp > deadline` check in both `buy` and `buyExactIn` | Purchases after sale ends |
| **Allowance cap** | `amount = min(amount, remaining)` with `remaining == 0` revert | Cannot exceed DAO-approved cap (assumes `dao` is a real Moloch — see KF#6) |
| **ZeroPrice guard** | `configure` reverts on `price == 0` | Misconfigured sales (also prevents `NotConfigured` bypass via zero-initialized struct) |
| **Moloch nonReentrant** | `spendAllowance` on Moloch is `nonReentrant` (dependency — not enforced by ShareSale) | Re-entry into Moloch during payout |

---

## Invariants

1. **Payment before shares** — buyer always pays (ETH or ERC20) before receiving shares/loot in the same transaction
2. **Allowance-bounded** — total shares/loot sold cannot exceed the DAO's configured allowance for this contract (assumes `dao` is a real Moloch — fake DAOs bypass this; see KF#6)
3. **DAO-only configuration** — only the DAO (msg.sender) can set/change its own sale parameters
4. **Stateless singleton** — in normal operation, ShareSale holds no persistent token/ETH balances; all funds flow through in a single transaction (unsolicited ERC20 transfers or force-sent ETH can create persistent balances — see KF#6)
5. **Cost > 0** — every purchase requires non-zero payment (enforced by `cost == 0` revert)
6. **No cross-DAO interference** — `sales` mapping is keyed per-DAO; each DAO's sale state is independent

---

## Expanding Coverage

To add new audit results:
1. Save the report as `{tool}-{date}.md` in this directory
2. Update the **Audit History** table above
3. Deduplicate new findings into **Known Findings**
4. Check new findings against **Design Choices** — add if intentional, not a finding
5. Update finding statuses as fixes are applied

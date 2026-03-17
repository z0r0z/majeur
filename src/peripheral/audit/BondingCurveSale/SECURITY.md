# BondingCurveSale.sol Security

> **Purpose:** Aggregated security analysis for `BondingCurveSale.sol` — the singleton for selling DAO
> shares or loot on a linear bonding curve via the Moloch allowance system. This document indexes all
> audits, tracks known findings, and documents mitigations.

### Instructions

You are a senior Solidity security auditor. Analyze `BondingCurveSale.sol` (~319 lines including free functions) — a singleton that sells DAO shares/loot on a linear bonding curve via the Moloch allowance system with configurable pricing, deadlines, and exact-in purchases. Work in **two rounds**:

**Round 1: Defense Verification.** For each defense mechanism in the table below, verify it works as described by tracing the actual code. Cite specific line numbers. State whether the defense holds or is broken. Then verify each invariant. Produce a conclusion for every defense and every invariant — "Verified" or "Violated" with evidence.

**Round 2: Adversarial Hunt.** Attempt to find vulnerabilities NOT covered by the Known Findings table or the Design Choices tables. For each candidate: (1) check it against Known Findings — discard if duplicate, (2) check it against Design Choices — discard if intentional, (3) attempt disproof, (4) rate confidence 0-100. Only include findings that survive all checks.

**Report format:** For each finding: `[SEVERITY-N] Title`, severity, confidence, location (file:lines), description, attack path, disproof attempt, recommendation.

---

## Contract Overview

| Property | Value |
|----------|-------|
| **File** | `src/peripheral/BondingCurveSale.sol` |
| **Lines** | ~319 (contract ~216, free functions ~103) |
| **Role** | Singleton — sells DAO shares/loot on a linear bonding curve via the Moloch allowance system |
| **State** | `mapping(address dao => Sale)` — per-DAO sale configuration (only mutable state) |
| **Access** | `configure` is DAO-only (msg.sender keying); `buy`/`buyExactIn` are permissionless |
| **Dependencies** | Moloch allowance system (`spendAllowance`, `setAllowance`, `allowance`), Moloch mint sentinels (`address(dao)` = shares, `address(1007)` = loot) |
| **Integrations** | SafeSummoner `SaleModule` (generates initCalls), LPSeedSwapHook (reads `sales()` to gate LP seeding on sale completion — uses `endPrice` as `price`) |

### External Call Map

```
buy(dao, amount):
  1. IMoloch(dao).allowance(s.token, this)     [view — read remaining cap]
  2. IMoloch(dao).spendAllowance(s.token, amt) [CEI: effects first — decrements allowance, _payout mints/transfers to BondingCurveSale]
  3. safeTransferETH(dao, cost)                [ETH to DAO]
     OR safeTransferFrom(s.payToken, dao, cost) [ERC20 from buyer to DAO]
  4. safeTransferETH(msg.sender, refund)       [ETH refund if overpaid]
  5. IMoloch(dao).shares() / loot()            [view — resolve token address]
  6. safeTransfer(tokenAddr, msg.sender, amt)  [shares/loot to buyer]

buyExactIn(dao):  [ETH-only — computes max amount from msg.value via quadratic formula, same CEI pattern]
configure(...):   [no external calls — pure storage write keyed to msg.sender]
quote(dao, amount): [view — computes cost at current curve position]
saleInitCalls(...): [view — generates (target, data) pairs for SafeSummoner setup]
```

---

## Audit History

| # | Date | Tool / Auditor | Mode | Findings | Report |
|---|------|----------------|------|----------|--------|
| 1 | 2026-03-17 | Pashov AI | Vector scan (4-agent) | 2 (0 above threshold, 2 accepted) + 1 dismissed | [`pashov-20260317.md`](pashov-20260317.md) |

**Aggregate: 1 audit, 2 accepted findings + 1 dismissed (false positive). 0 Critical, 0 High, 0 Medium, 2 Low/Info.**

---

## Known Findings

| # | Finding | Severity | Status | First Found |
|---|---------|----------|--------|-------------|
| 1 | Missing minimum-amount slippage guard — `buy()` silently caps to remaining allowance without `minAmount` | Low | Accepted | Pashov #2 |
| 2 | Fee-on-transfer payment token underpays DAO — `safeTransferFrom` transfers nominal `cost` but DAO receives less | Low | Accepted | Pashov #3 |

### Finding 1 — Assessment

**Severity: Low (accepted, by design).**

`buy()` silently caps `amount` to remaining allowance. A front-runner could deplete supply, causing a subsequent buyer to receive fewer tokens. However, buyers are protected by payment mechanics: ETH sales refund excess `msg.value`, and the cost is recalculated for the actual (capped) amount. The bonding curve inherently means earlier buyers get lower prices — this is the intended mechanism. Same pattern as ShareSale. Not patched.

### Finding 2 — Assessment

**Severity: Low (accepted, by design).**

Fee-on-transfer tokens cause the DAO to receive less than `cost` while the buyer gets the full `amount` of shares/loot. In practice, DAOs control which `payToken` they configure and can avoid FoT tokens. Same class as ShareSale DC-2. Not patched.

---

## Dismissed Findings

| Source | Finding | Reason |
|--------|---------|--------|
| Pashov Agent 1 | Hardcoded 1e18 denominator misprices non-18-decimal pay tokens | **Dismissed (false positive).** The `1e18` divisor normalizes against 18-decimal share/loot amounts, not payToken decimals. Non-18-decimal tokens work correctly: set `startPrice` in payToken-wei per whole share (e.g., `1e6` for 1 USDC/share → `cost = 1e18 * 1e6 / 1e18 = 1e6`). Round-up in `_cost` prevents zero-cost dust purchases. |
| Pashov Agent 1 | Reentrancy via ETH refund | **Dismissed.** CEI pattern correctly applied — `spendAllowance` called before all external interactions (line 109/181). Re-entering `buy()` reads updated (lower) allowance. |
| Pashov Agent 2 | Cross-contract reentrancy via DAO `receive()` | **Dismissed.** DAO receives ETH after allowance is spent. Re-entry reads decremented allowance. |
| Pashov Agent 3 | DoS via push payment to rejecting DAO | **Dismissed.** DAO configures its own sale — if it can't receive ETH, it wouldn't configure an ETH sale. Buyer's tx simply reverts (no fund loss). |
| Pashov Agent 4 | Free memory pointer corruption in `safeTransferFrom` assembly | **Dismissed.** FMP is saved before and restored after the assembly block. Revert paths propagate the entire call revert, so no corruption. |
| Pashov Agent 4 | Off-by-one in `buyExactIn` cost clamping | **Dismissed.** Intentional 1-wei clamp to handle sqrt truncation + ceil overshoot, acknowledged in code comment (line 177). |
| Pashov Agent 4 | Overflow in `_cost` multiplication | **Dismissed.** Solidity 0.8 checked arithmetic reverts on overflow. Extreme inputs cause revert, not silent corruption. |

---

## Design Choices (Documented, Not Findings)

| # | Observation | Status | Source |
|---|-------------|--------|--------|
| DC-1 | `configure` is permissionless but keyed to `msg.sender` — anyone can create a `sales[self]` entry, but only affects their own address | By design | — |
| DC-2 | Fee-on-transfer tokens not accounted for — DAO receives less than `cost` if payToken charges fees | By design | Pashov #3 |
| DC-3 | `buy()` caps to remaining allowance and refunds excess ETH — buyer may receive fewer shares than requested | By design | Pashov #2 |
| DC-4 | `buyExactIn()` is ETH-only — reverts if `payToken != address(0)` | By design | — |
| DC-5 | No `receive()`/`fallback()` — BondingCurveSale cannot accumulate ETH between transactions | By design | — |
| DC-6 | Prices can be reconfigured by DAO governance via `configure()` — no price-lock mechanism | By design | — |
| DC-7 | `saleInitCalls()` is a helper that returns (target, data) pairs — pure view, no side effects | By design | — |
| DC-8 | Prices are in payToken-wei per whole share (e.g., `1e6` for 1 USDC/share, `1e18` for 1 ETH/share) — the `1e18` divisor normalizes against 18-decimal share amounts, not payToken decimals. Non-18-decimal tokens work natively. | By design | — |
| DC-9 | `sales()` getter returns `endPrice` as `price` for LPSeedSwapHook compatibility (arb protection uses highest sale price) | By design | — |
| DC-10 | `buyExactIn` cost clamp allows 1-wei underpayment to handle sqrt truncation | By design | — |

---

## Defense Mechanisms

| Defense | Mechanism | What It Prevents |
|---------|-----------|-----------------|
| **msg.sender keying** | `configure` keys to `msg.sender` | Only DAO can configure its own sale |
| **Checked arithmetic** | Solidity 0.8 checked math | Overflow/underflow in pricing calculations |
| **ETH guard** | `msg.value != 0` revert in ERC20 branch | Stray ETH loss on ERC20-denominated purchases |
| **CEI ordering** | `spendAllowance` before all interactions | Reentrancy via ETH refund or ERC777 hooks |
| **Deadline enforcement** | `block.timestamp > deadline` check in both `buy` and `buyExactIn` | Purchases after sale ends |
| **Allowance cap** | `amount = min(amount, remaining)` with `remaining == 0` revert | Cannot exceed DAO-approved cap |
| **ZeroPrice guard** | `configure` reverts on `startPrice == 0` | Misconfigured sales / `NotConfigured` bypass |
| **InvalidCurve guard** | `configure` reverts on `endPrice < startPrice` | Underflow in slope calculation |
| **ZeroAmount guard** | `configure` reverts on `cap == 0`; `buy`/`buyExactIn` revert on `amount == 0` | Zero-cost purchases and empty sales |
| **Moloch nonReentrant** | `spendAllowance` on Moloch is `nonReentrant` (dependency) | Re-entry into Moloch during payout |

---

## Invariants

1. **Payment before shares** — buyer always pays (ETH or ERC20) before receiving shares/loot in the same transaction
2. **Allowance-bounded** — total shares/loot sold cannot exceed the DAO's configured allowance for this contract
3. **DAO-only configuration** — only the DAO (msg.sender) can set/change its own sale parameters
4. **Stateless singleton** — BondingCurveSale holds no persistent token/ETH balances; all funds flow through in a single transaction
5. **Monotonic pricing** — price rises linearly from `startPrice` to `endPrice` as tokens are sold; earlier buyers always pay less
6. **No cross-DAO interference** — `sales` mapping is keyed per-DAO; each DAO's sale state is independent
7. **Cost > 0** — every purchase requires non-zero payment (enforced by checked arithmetic and amount guards)

---

## Expanding Coverage

To add new audit results:
1. Save the report as `{tool}-{date}.md` in this directory
2. Update the **Audit History** table above
3. Deduplicate new findings into **Known Findings**
4. Check new findings against **Design Choices** — add if intentional, not a finding
5. Update finding statuses as fixes are applied

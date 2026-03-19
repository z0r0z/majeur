# ClassicalCurveSale.sol Security

> **Purpose:** Aggregated security analysis for `ClassicalCurveSale.sol` — the singleton for pump.fun-style
> bonding curve token launches with virtual constant-product (XYK) pricing, graduation to ZAMM LP,
> creator fees, vesting, and post-graduation routed swaps. This document indexes all audits, tracks
> known findings, and documents mitigations.

### Instructions

You are a senior Solidity security auditor. Analyze `ClassicalCurveSale.sol` (~1375 lines including free functions and ERC20) — a singleton that deploys ERC20 clones via CREATE2, sells them on a virtual XYK bonding curve, graduates to ZAMM LP when an ETH target is met, and acts as a ZAMM hook for post-graduation fee governance. Work in **two rounds**:

**Round 1: Defense Verification.** For each defense mechanism in the table below, verify it works as described by tracing the actual code. Cite specific line numbers. State whether the defense holds or is broken. Then verify each invariant. Produce a conclusion for every defense and every invariant — "Verified" or "Violated" with evidence.

**Round 2: Adversarial Hunt.** Attempt to find vulnerabilities NOT covered by the Known Findings table or the Design Choices tables. For each candidate: (1) check it against Known Findings — discard if duplicate, (2) check it against Design Choices — discard if intentional, (3) attempt disproof, (4) rate confidence 0-100. Only include findings that survive all checks.

**Report format:** For each finding: `[SEVERITY-N] Title`, severity, confidence, location (file:lines), description, attack path, disproof attempt, recommendation.

---

## Contract Overview

| Property | Value |
|----------|-------|
| **File** | `src/peripheral/ClassicalCurveSale.sol` |
| **Lines** | ~1385 (contract ~1096, free functions ~148, ERC20 clone ~63) |
| **Role** | Singleton — deploys ERC20 clones, sells on XYK bonding curve, graduates to ZAMM LP, acts as ZAMM hook |
| **State** | `mapping(address token => CurveConfig)` — per-token curve config (6 packed slots), `mapping(address token => CreatorFee)`, `mapping(uint256 poolId => address token)`, `mapping(address token => CreatorVest)`, `mapping(address token => uint256[])` observations |
| **Access** | `launch`/`configure` are permissionless (factory pattern); `buy`/`sell`/`buyExactIn`/`sellExactOut` are permissionless; `setCreator`/`setLpRecipient`/`setCreatorFee`/`claimVested` are creator-only; `beforeAction` is ZAMM-only; `graduate` is permissionless post-graduation |
| **Dependencies** | ZAMM singleton (hardcoded address), ERC20 clone implementation (CREATE2) |
| **Integrations** | ZAMM LP (addLiquidity), ZAMM swaps (swapExactIn/swapExactOut), ZAMM hook (beforeAction) |

### ZAMM Integration Context

ClassicalCurveSale interacts with ZAMM (`0x000000000000040470635EB91b7CE4D132D616eD`), a singleton constant-product AMM. Key details for auditors:

**ZAMM architecture:**
- Singleton contract (Uniswap v2-style XYK with ERC6909 LP tokens)
- Pools identified by `PoolKey` struct → `poolId = keccak256(abi.encode(key))`
- `PoolKey.feeOrHook` encodes either a static bps fee OR `FLAG_BEFORE | FLAG_AFTER | hook_address`
- When a hook is encoded, ZAMM calls `IZAMMHook.beforeAction()` before every operation
- ZAMM has its own transient-storage reentrancy lock — cannot reenter ZAMM from a hook

**Hook protocol (`beforeAction`):**
- Called by ZAMM with `(bytes4 sig, uint256 poolId, address sender, bytes data)`
- `sig` is the function selector of the ZAMM operation (swapExactIn, swapExactOut, swap, addLiquidity, removeLiquidity)
- `sender` is `msg.sender` to ZAMM (the actual caller, not the hook)
- Return value: if nonzero, overrides the pool's fee for this operation
- For non-swap operations (LP), return value is ignored (fee = 0)

**How ClassicalCurveSale uses ZAMM:**
- `graduate()` calls `ZAMM.addLiquidity()` to create and seed the pool with ETH + tokens
- `swapExactIn()`/`swapExactOut()` call ZAMM swap functions as a router (for creator fee deduction)
- `beforeAction()` is called BY ZAMM on every operation to the graduated pool:
  - Pre-seed: blocks all LP operations except from `graduate()` (transient bypass)
  - Post-seed: returns configurable pool fee for swaps, enforces routing when creator fee active
  - When creator fee is active: blocks `ZAMM.swap()` entirely and requires `sender == address(this)` for swapExactIn/swapExactOut

**Trust assumptions:**
- ZAMM is trusted (hardcoded, immutable address)
- ZAMM's reentrancy lock prevents reentry from hooks back into ZAMM
- `addLiquidity` for a new pool (supply=0) uses both desired amounts directly (no ratio adjustment)
- `addLiquidity` refunds unused ETH to the caller (this contract) via the `receive()` fallback
- ZAMM passes authentic `msg.sender` as the `sender` parameter to hooks

### External Call Map

```
launch(creator, ...):
  1. CREATE2 deploy ERC20 clone
  2. ERC20(token).init(name, symbol, uri, supply, address(this))   [mint to self]
  3. safeTransfer(token, creator, excess)                           [creator allocation if no vesting]
  4. _configure(...)                                                [storage write]

configure(creator, token, ...):
  1. _configure(...)                                                [storage write]
  2. safeTransferFrom(token, address(this), cap + lpTokens)         [pull from msg.sender]

buy(token, amount, minAmount):   [lock modifier]
  1. _cost(...)                                                     [pure math]
  2. c.sold/c.raisedETH update                                      [CEI: state first]
  3. _checkGraduation(...)                                          [may set c.graduated]
  4. safeTransfer(token, msg.sender, amount)                        [tokens to buyer]
  5. safeTransferETH(creator, fee)                                  [fee to creator]
  6. safeTransferETH(msg.sender, refund)                            [excess ETH back]

sell(token, amount, minProceeds):   [lock modifier]
  1. _cost(...)                                                     [pure math]
  2. c.sold/c.raisedETH update                                      [CEI: state first]
  3. safeTransferFrom(token, address(this), amount)                 [pull tokens from seller]
  4. safeTransferETH(msg.sender, net)                               [ETH to seller]
  5. safeTransferETH(creator, fee)                                  [fee to creator]

graduate(token):
  1. c.seeded = true                                                [CEI: state first]
  2. safeTransfer(token, 0xdead, unsold)                            [burn unsold]
  3. ensureApproval(token, ZAMM)                                    [approve before registration]
  4. poolToken[poolId] = token                                      [register pool after approval]
  5. ZAMM.addLiquidity{value: ethForLP}(...)                        [seed LP via transient bypass]
  6. safeTransferETH(creator, unusedETH)                            [refund unused]
  7. safeTransfer(token, creator, unusedTokens)                     [refund unused]

beforeAction(sig, poolId, sender, ...):   [ZAMM-only]
  1. Pre-seed LP gating via transient storage check
  2. Post-seed: return pool fee, enforce routing when creator fee active
```

---

## Audit History

| # | Date | Tool / Auditor | Mode | Findings | Report |
|---|------|----------------|------|----------|--------|
| 1 | 2026-03-19 | Pashov AI | Vector scan (4-agent) | 2 above threshold + 1 below | [`pashov-20260319.md`](pashov-20260319.md) |
| 2 | 2026-03-19 | Grimoire | Sigil swarm (4-agent) + Familiar triage | 1 confirmed (buyExactIn DoS) | [`grimoire-20260319.md`](grimoire-20260319.md) |
| 3 | 2026-03-19 | ChatGPT | Manual review | 3 valid (all fixed) | [`chatgpt-20260319.md`](chatgpt-20260319.md) |
| 4 | 2026-03-19 | ChatGPT (post-fix) | Defense + invariant verification | 0 novel, 8/8 defenses verified | [`chatgpt-postfix-20260319.md`](chatgpt-postfix-20260319.md) |

**Aggregate: 4 audits, 6 unique findings. 0 Critical, 0 High, 4 Medium (all fixed), 1 Low (fixed), 1 Low (accepted). Post-fix review: clean.**

---

## Known Findings

| # | Finding | Severity | Status | First Found | Cross-confirmed |
|---|---------|----------|--------|-------------|-----------------|
| 1 | `buyExactIn` approximation overshoot — DoS or raisedETH understatement | Medium | Fixed | Pashov #1 | Grimoire Sigil 2 |
| 2 | Fee-on-transfer / rebasing token accounting mismatch via `configure()` path | Medium | Accepted | Pashov #2 | — |
| 3 | Creator-controlled fee recipient can permanently DoS all buys via ETH-rejecting contract | Low | Accepted | Pashov #3 | — |
| 4 | Pre-seed LP pool manipulation via malicious token reentrancy in `graduate()` | Medium | Fixed | ChatGPT #1 | — |
| 5 | Creator can change LP recipient between graduation trigger and seeding | Medium | Fixed | ChatGPT #2 | — |
| 6 | Unchecked uint128 downcasts — `cap`, `startPrice`, `endPrice`, `graduationTarget`, `lpTokens` silently truncate | Low | Fixed | ChatGPT #3 | — |

### Finding 1 — Assessment

**Severity: Medium. Status: Fixed.**

`buyExactIn()` uses an approximation to compute token `amount` from ETH input, then verifies with `_cost()`. The approximation can overshoot by multiple tokens on steep curves, causing the function to revert or understate `raisedETH`. Fixed with a `while` loop that decrements `amount` until `cost <= netETH`. Additionally, the underlying `mulDiv` free function was replaced with Solady's `fullMulDiv` to fix a missing 6th Newton-Raphson iteration (128-bit → 256-bit precision).

### Finding 2 — Assessment

**Severity: Medium. Status: Accepted (by design).**

`configure()` records `c.cap` and `c.lpTokens` from caller-supplied values and pulls tokens via `safeTransferFrom`. If the token has a transfer fee or rebases downward, the actual balance held is less than recorded. In practice, `launch()` mints tokens directly to the contract (no transfer fee), so this only affects the `configure()` path with pre-existing fee-on-transfer tokens. Callers control which tokens they configure.

### Finding 3 — Assessment

**Severity: Low. Status: Accepted (self-inflicted).**

If a creator calls `setCreator()` to set the creator address to a contract that reverts on ETH receipt, and `feeBps > 0`, all `buy()` and `buyExactIn()` calls permanently revert. This is self-inflicted by the creator against their own token's buyers.

### Finding 4 — Assessment

**Severity: Medium. Status: Fixed.**

`graduate()` registered `poolToken[poolId] = token` before calling `ensureApproval(token, address(ZAMM))`. A malicious token (via `configure()` path) could reenter during `approve()` and call `ZAMM.addLiquidity()` to front-run the pool seeding at a manipulated ratio, since `beforeAction()` allows LP ops when `poolToken[poolId] != address(0)`. Fixed by moving `poolToken` registration after `ensureApproval`, so during the approve callback the pool is still unregistered and the hook blocks LP operations.

### Finding 5 — Assessment

**Severity: Medium. Status: Fixed.**

`setLpRecipient()` checked `c.seeded` but not `c.graduated`, allowing the creator to change the LP recipient between graduation trigger and seeding — e.g., swapping a burn address for their own via `multicall([setLpRecipient, graduate])`. Fixed by checking `c.graduated` instead of `c.seeded`.

### Finding 6 — Assessment

**Severity: Low. Status: Fixed.**

`_configure()` stored `cap`, `startPrice`, `endPrice`, `graduationTarget`, and `lpTokens` as `uint128(x)` without bounds checks. In Solidity 0.8, explicit narrowing casts silently truncate — they do NOT revert. An attacker could pass oversized values that survive input validation (which operates on the 256-bit values) but store truncated runtime values. The `Configured` event would emit original values while storage holds different ones. Fixed by adding explicit `type(uint128).max` bounds checks for all five fields before storage writes.

---

## Design Choices

| # | Choice | Rationale |
|---|--------|-----------|
| DC-1 | `launch()`/`configure()` allow arbitrary `creator` parameter | Factory pattern — third parties can configure curves on behalf of creators. Token pull from `msg.sender` ensures caller has the tokens. |
| DC-2 | `multicall()` is non-payable | Prevents `msg.value` double-spend across delegatecalls. ETH-based functions (`buy`, `buyExactIn`) cannot be batched with ETH. |
| DC-3 | `graduate()` uses `amount0Min=0, amount1Min=0` in `addLiquidity` | New pool is created atomically — no pre-existing pool to sandwich. `beforeAction` hook blocks pre-seed LP operations. |
| DC-4 | `beforeAction()` uses transient storage bypass for seeding | Scoped to exact `poolId + 1` value, cleared immediately after `addLiquidity` returns. |
| DC-5 | Observation volume truncated to uint80 | Charting data only, no financial accounting depends on it. Max ~1.2M ETH per trade observation. |
| DC-6 | `buy()` silently caps `amount` to remaining supply | Same pattern as BondingCurveSale/ShareSale. Buyer protected by `minAmount` slippage parameter and ETH refund. |

---

## Defense Mechanisms

| Defense | Implementation |
|---------|---------------|
| Reentrancy lock | Transient storage `SWAP_LOCK_SLOT` via `lock` modifier on all buy/sell/swap functions |
| CEI pattern | State updates (sold, raisedETH) before all external calls in buy/sell paths |
| Graduation state guard | `c.seeded = true` set before any external calls in `graduate()`; `setLpRecipient` frozen once `c.graduated` is true |
| Hook caller check | `msg.sender != address(ZAMM)` in `beforeAction()` |
| Creator fee routing enforcement | `beforeAction` blocks direct `ZAMM.swap()` when creator fee is active; only `swapExactIn`/`swapExactOut` routed through this contract are allowed |
| CREATE2 salt binding | Salt includes `msg.sender` to prevent address squatting |
| Overflow guards | Explicit `type(uint128).max` bounds checks for `vr`, `cap`, `startPrice`, `endPrice`, `graduationTarget`, `lpTokens` in `_configure()` |
| Graduation target validation | `_configure()` verifies `graduationTarget <= maxETH` from full cap sale |

---

## Invariants

| # | Invariant |
|---|-----------|
| I-1 | During the active bonding-curve phase (before `graduate()` executes), `raisedETH` equals net ETH held by contract from curve trading |
| I-2 | `sold <= cap` at all times |
| I-3 | Once `graduated == true`, no further buys or sells on the bonding curve are possible |
| I-4 | Once `seeded == true`, `graduate()` cannot be called again |
| I-5 | A curve can only be configured once per token address (`AlreadyConfigured` guard) |
| I-6 | Only ZAMM can call `beforeAction()` |
| I-7 | Pre-seed LP operations are blocked unless called from within `graduate()` via transient bypass (pool registered after `ensureApproval` to close reentrancy window) |

---

## Critical Code Paths

| Priority | Path | Why |
|----------|------|-----|
| 1 | `buy()` / `buyExactIn()` — cost calculation, state update, graduation check, token + ETH transfers | Core trading flow, handles user funds |
| 2 | `sell()` / `sellExactOut()` — proceeds calculation, liquidity check, token pull, ETH send | Users withdraw ETH, must not overdrain |
| 3 | `graduate()` — LP seeding, token burning, ZAMM interaction | Irreversible transition, large ETH + token movement |
| 4 | `swapExactIn()` / `swapExactOut()` — creator fee deduction, ZAMM routing | Post-graduation trading with fee arithmetic |
| 5 | `beforeAction()` — hook gating, fee return, routing enforcement | Security boundary for ZAMM integration |

---

## False Positive Patterns

| Pattern | Why it's not a bug |
|---------|-------------------|
| "No access control on `configure()`/`launch()`" | Factory pattern — anyone can create curves. Token pull ensures caller has tokens. `AlreadyConfigured` prevents overwrite. |
| "Hardcoded ZAMM address" | Intentional — deployed per-chain with known ZAMM singleton. |
| "`receive()` accepts arbitrary ETH" | Required for ZAMM refunds during graduation and fee-on-output swap routing. |
| "No sweep function for trapped ETH/tokens" | By design — contract holds only raisedETH and curve/LP tokens. No admin extraction. |
| "Observation array grows unboundedly" | View function with pagination (`observe(from, to)`). No on-chain iteration. |
| "Unchecked uint128 downcasts in `_configure()`" | Was valid — explicit casts truncate silently in Solidity 0.8. Now fixed with bounds checks. ChatGPT LOW-3 confirmed and patched. |
| "`setCreator()` transfers vesting rights" | Standard ownership transfer semantics — creator can claim before transferring. Grimoire Familiar dismissed. |
| "Post-graduation creator fee rug pull" | Bounded at 10% max per direction. Configurable from launch. Standard DeFi trust model. Grimoire Familiar downgraded to informational. |

---

## Frontend / Integration Guardrails

Recommended checks for any UI or backend integrating with ClassicalCurveSale:

- **Warn on nonstandard tokens with `configure()`** — Fee-on-transfer, rebasing, and callback-enabled tokens (ERC777) cause accounting mismatches. `launch()` is safe (deploys its own ERC20 clone). If `configure()` is exposed, validate the token contract before allowing submission.
- **Warn if creator address cannot receive ETH** — If the creator is a contract without a `receive()`/`fallback()`, all fee-bearing buys/sells will revert permanently. Check `creator.code.length > 0` and warn if the address looks like a contract that may reject ETH.
- **Distinguish `configure()` curves from `launch()` curves** — Curves created via `launch()` use audited ERC20 clones with no callbacks. Curves created via `configure()` use arbitrary external tokens and carry additional risk (Finding #2, #4). Label or flag these differently in the UI so users can assess trust.
- **Display creator fee config prominently** — Creator can set up to 10% fee on post-graduation swaps via `setCreatorFee()`. Show current fee parameters and warn users if fees are nonzero before they trade.
- **Show graduation status clearly** — Once graduated, bonding curve trading stops and LP is seeded. Users need to understand the lifecycle transition and that post-graduation trading happens through ZAMM (possibly with creator fees).

---

## Expanding Coverage

When adding a new audit report:

1. Save the report as `{auditor}-{YYYYMMDD}.md` in this folder
2. Add a row to the Audit History table
3. For each new finding:
   - Check against Known Findings — if duplicate, note cross-confirmation
   - If novel, add to Known Findings with assessment
4. Update the aggregate counts

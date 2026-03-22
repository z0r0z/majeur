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
  3. creatorVests[token] = CreatorVest(excess, ...)                  [escrow excess for post-graduation vesting]
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

sellExactOut(token, ethOut, maxTokens):   [lock modifier]
  1. Compute gross proceeds via ceiling division                    [pure math]
  2. Approximate token amount via inverse formula                   [pure math]
  3. Recompute proceeds via _cost(sold-amount, amount)              [pure math — verify]
  4. c.sold/c.raisedETH update                                      [CEI: state first]
  5. safeTransferFrom(token, address(this), amount)                 [pull tokens from seller]
  6. safeTransferETH(msg.sender, net)                               [ETH to seller]
  7. safeTransferETH(creator, fee)                                  [fee to creator]

graduate(token):
  1. c.seeded = true                                                [CEI: state first]
  2. safeTransfer(token, 0xdead, unsold)                            [burn unsold]
  3. ensureApproval(token, ZAMM)                                    [approve before registration]
  4. poolToken[poolId] = token                                      [register pool after approval]
  5. ZAMM.addLiquidity{value: ethForLP}(...)                        [seed LP via transient bypass]
  6. safeTransferETH(creator, unusedETH)                            [refund unused]
  7. safeTransfer(token, creator, unusedTokens)                     [refund unused]

claimVested(token):
  1. Check msg.sender == creator                                    [auth]
  2. Compute vested amount from cliff/duration schedule             [pure math]
  3. v.claimed = vested                                             [state update]
  4. safeTransfer(token, msg.sender, claimable)                     [tokens to creator]

swapExactIn(poolKey, amountIn, amountOutMin, zeroForOne, to):   [lock modifier]
  (8 code paths: 2 directions × {fee-on-input, fee-on-output} × {ETH, token})
  Buy (ETH→token), fee on input:
    1. tax = amountIn · bps / 10000                                 [fee math]
    2. safeTransferETH(beneficiary, tax)                            [fee to creator]
    3. ZAMM.swapExactIn{value: net}(...)                            [swap on ZAMM]
  Buy (ETH→token), fee on output:
    1. ZAMM.swapExactIn{value: amountIn}(..., to=self)              [swap to self]
    2. tax = amountOut · bps / 10000                                [fee math]
    3. safeTransfer(token, beneficiary, tax)                        [fee to creator]
    4. safeTransfer(token, to, net)                                 [tokens to buyer]
  Sell paths: mirror with safeTransferFrom + ETH output

swapExactOut(poolKey, amountOut, amountInMax, zeroForOne, to):   [lock modifier]
  Buy, fee on input:
    1. netMax = amountInMax · (10000-bps) / 10000                   [max after fee]
    2. ZAMM.swapExactOut{value: netMax}(...)                        [swap on ZAMM]
    3. tax = amountIn · bps / (10000-bps)                           [fee on consumed]
    4. safeTransferETH(beneficiary, tax) + refund                   [fee + refund]
  Buy, fee on output:
    1. gross = ceil(amountOut · 10000 / (10000-bps))                [inflate for fee]
    2. ZAMM.swapExactOut{value: amountInMax}(..., gross, to=self)   [swap on ZAMM]
    3. refund excess ETH, send tax tokens to beneficiary            [fee + refund]
    4. safeTransfer(token, to, amountOut)                           [net tokens to buyer]
  Sell paths: mirror with token input / ETH output

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
| 5 | 2026-03-20 | Pashov AI (v2) | Vector scan (4-agent) + manual verification | 0 novel above threshold, 3 below (all known) | [`pashov-20260320.md`](pashov-20260320.md) |
| 6 | 2026-03-22 | Manual review (external) | Full contract review | 1 High (fixed), 1 Medium (accepted + documented), docs (fixed) | — |

**Aggregate: 6 audits, 8 unique findings. 0 Critical, 0 High open, 4 Medium (fixed), 1 Medium (accepted), 1 High (fixed), 1 Low (fixed), 1 Low (accepted).**

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
| 7 | `graduate()` sends all `raisedETH` to ZAMM even when LP token cap forces lower ratio — strands ETH or breaks price continuity | High | Fixed | External review #6 | — |
| 8 | `configure()` allows external circulating supply to be sold into curve, redeeming buyer ETH | Medium | Accepted (documented) | External review #6 | — |

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

### Finding 7 — Assessment

**Severity: High. Status: Fixed.**

`graduate()` sent all `raisedETH` to `ZAMM.addLiquidity()` even when `tokensForLP` was capped to `maxTokensForLP`. For first-pool creation (supply==0), ZAMM uses both desired amounts exactly, so the pool would be created at `ethForLP/tokensForLP` instead of the intended `finalPrice` ratio — breaking price continuity between curve and pool. Fixed by capping `ethForLP` to `mulDiv(maxTokensForLP, finalPrice, 1e18)` when the token cap binds, and refunding the excess ETH to the creator after seeding. The event now reports actual ETH seeded.

### Finding 8 — Assessment

**Severity: Medium. Status: Accepted (documented).**

`configure()` only escrows `cap + lpTokens` from the caller. If the token has additional circulating supply outside the contract, those holders can sell into the curve via `sell()` and redeem buyer ETH. This is the same underlying issue as the original critical finding, but scoped to the `configure()` path only — `launch()` mints the entire supply to this contract and is immune. Accepted because `configure()` is an expert-only path where the caller assumes token compatibility responsibility. NatSpec now explicitly warns that only tokens with full pre-graduation supply escrowed are safe.

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
| DC-7 | `sell()` uses `mulDivUp` for proceeds (rounds up, protocol-unfavorable) | At most 1 wei per trade. Consistent with `_cost()` being a single function for both buy/sell. Fees dominate. |
| DC-8 | Vesting only available via `launch()`, not `configure()` | `configure()` callers handle their own token distribution. Vesting is a `launch()` convenience for creator allocation. |
| DC-9 | `claimVested()` not protected by `lock` modifier | No ETH handling, no interaction with curve state. Only transfers tokens from contract to creator. |

---

## Defense Mechanisms

| Defense | Implementation | Reference |
|---------|---------------|-----------|
| Reentrancy lock | Transient storage `SWAP_LOCK_SLOT` via `lock` modifier on all buy/sell/swap functions | `:1101-1112` |
| CEI pattern | State updates (sold, raisedETH) before all external calls in buy/sell paths | buy `:544-551`, sell `:779-782` |
| Graduation state guard | `c.seeded = true` set before any external calls in `graduate()`; `setLpRecipient` frozen once `c.graduated` is true | `:880`, `:849-855` |
| Hook caller check | `msg.sender != address(ZAMM)` in `beforeAction()` | `:794-800` |
| Creator fee routing enforcement | `beforeAction` blocks direct `ZAMM.swap()` when creator fee is active; only `swapExactIn`/`swapExactOut` routed through this contract are allowed | `:823-826` |
| CREATE2 salt binding | Salt includes `msg.sender` to prevent address squatting | `:189-196` |
| Overflow guards | Explicit `type(uint128).max` bounds checks for `vr`, `cap`, `startPrice`, `endPrice`, `graduationTarget`, `lpTokens` in `_configure()` | `:359-364` |
| Graduation target validation | `_configure()` verifies `graduationTarget <= maxETH` from full cap sale | `:367-376` |
| Sniper fee validation | `sniperFeeBps >= feeBps` enforced at config to prevent underflow in `_effectiveFee()` decay math | `:341-344` |

---

## Invariants

| # | Invariant | Reference |
|---|-----------|-----------|
| I-1 | During the active bonding-curve phase (before `graduate()` executes), `raisedETH` tracks net curve-accounted ETH (buy costs minus sell proceeds) | buy `:547-548`, sell `:781` |
| I-2 | `sold <= cap` at all times | buy `:601`, sell `:761` |
| I-3 | Once `graduated == true`, no further buys or sells on the bonding curve are possible | `:592`, `:659`, `:759`, `:806` |
| I-4 | Once `seeded == true`, `graduate()` cannot be called again | `:878`, `:880` |
| I-5 | A curve can only be configured once per token address (`AlreadyConfigured` guard) | `:345` |
| I-6 | Only ZAMM can call `beforeAction()` | `:794-800` |
| I-7 | Pre-seed LP operations are blocked unless called from within `graduate()` via transient bypass (pool registered after `ensureApproval` to close reentrancy window) | `:934-935`, `:940-948` |
| I-8 | Vesting: `claimed <= vested <= total` at all times; `vested` monotonically increases | `:1076-1093` |

---

## Math Model

### Pricing formula

The curve implements a virtual constant-product (XYK) bonding curve:

```
Price at position x:    P(x) = P₀ · T₀² / (T₀ − x)²
Cost for N tokens:      ∫ P(x)dx from x to x+N = P₀ · T₀² · N / ((T₀ − x)(T₀ − x − N))
```

Where `P₀ = startPrice` (1e18-scaled), `T₀ = virtualReserve`, `x = sold`.

**Virtual reserve derivation** (`_configure`): T₀ = cap · √endPrice / (√endPrice − √startPrice). Derived by solving P(cap) = endPrice. For flat curves (endPrice == startPrice), T₀ = 2·cap as a placeholder.

**`_cost()` implementation** (`:1296-1316`): Two chained `mulDiv` calls — `step = mulDiv(P₀ · N, T₀, rem)` then `mulDivUp(step, T₀, remAfter · 1e18)` — equivalent to the closed-form integral with 512-bit intermediate precision.

### Rounding directions

| Function | Rounding | Protocol-favorable? | Notes |
|----------|----------|---------------------|-------|
| `buy()` cost | `mulDivUp` (up) | Yes | Buyer pays more |
| `sell()` proceeds | `mulDivUp` (up) | No — 1 wei max | Seller gets ≤1 wei extra per trade |
| `buyExactIn()` netETH | Floor division | Yes | Conservative max affordable cost |
| `buyExactIn()` amount approx | Floor division | Yes | Undershoot corrected by while loop |
| `sellExactOut()` proceeds target | Ceiling division | Yes | Higher gross → more tokens sold |
| `sellExactOut()` amount approx | `mulDivUp` (up) | Yes | Seller sells more tokens |
| `graduate()` tokensForLP | `mulDiv` (down) | Yes | Fewer tokens seeded → tighter supply |

The `sell()` rounding is protocol-unfavorable by at most 1 wei per trade. Not exploitable: a round-trip (buy + sell) always nets a loss due to fees. Splitting sells into single-token transactions extracts at most N−1 wei total.

### Overflow bounds

All stored values are uint128. Key intermediate products:

| Expression | Bound | Fits uint256? |
|-----------|-------|---------------|
| `startPrice * amount` | (2¹²⁸)² = 2²⁵⁶ | Yes (< 2²⁵⁶) |
| `vr * vr` | (2¹²⁸−1)² = 2²⁵⁶ − 2¹²⁹ + 1 | Yes |
| `rem * rem` | Same as above | Yes |
| `remAfter * 1e18` | 2¹²⁸ · 2⁶⁰ = 2¹⁸⁸ | Yes |
| `cap * sqrtEnd` (in `_configure`) | 2¹²⁸ · 2⁶⁴ = 2¹⁹² | Yes |
| `proceeds * R` (in `sellExactOut`) | (2¹²⁸)² | Yes |

The `mulDiv` / `mulDivUp` free functions handle 512-bit intermediates internally for chained multiplications in `_cost()`.

### Inverse formulas

**`buyExactIn`** (`:679-688`): Inverts the cost integral to find `amount` from `netETH`:
- Flat: `amount = netETH · 1e18 / startPrice`
- XYK: `amount = netETH · R / (A + netETH)` where A = P₀·T₀²/(R·1e18), R = T₀ − sold
- Floor division may undershoot → while loop (`:702-709`) decrements until `_cost(amount) ≤ netETH`

**`sellExactOut`** (`:820-836`): Inverts `_cost()` to find token `amount` from target `proceeds`:
- Flat: `amount = ceil(proceeds · 1e18 / startPrice)`
- XYK: `amount = mulDivUp(B · R, 1, A − B)` where A = P₀·T₀²/1e18, B = proceeds·R
- `B ≥ A` check prevents division by zero (would mean requesting more ETH than the entire curve holds)
- Recomputed via `_cost()` on line 845 and re-verified `net ≥ ethOut` on line 850

---

## Sniper Fee & Anti-Whale Mechanics

### Sniper fee decay

Configurable elevated fee at launch that linearly decays to the base fee:

- `sniperFeeBps`: elevated fee (validated ≥ `feeBps` and ≤ 10,000 in `_configure` at `:342`)
- `sniperDuration`: decay window in seconds
- `_effectiveFee()` (`:1277-1290`): returns `baseFee + (sniperFee − baseFee) · (duration − elapsed) / duration`
- At t=0: fee = sniperFeeBps. At t=duration: fee = feeBps. Linear between.
- Unchecked `sniperFee − baseFee` is safe because `sniperFeeBps >= feeBps` is enforced at configuration time.
- Uses `block.timestamp − launchTime` (unchecked, safe since launchTime = block.timestamp at config).

### Anti-whale (maxBuyBps)

- `maxBuyBps`: max % of cap per single buy in bps (0 = unlimited)
- Applied in both `buy()` (`:602-608`) and `buyExactIn()` (`:691-697`): `if (amount > cap · maxBuyBps / 10000) amount = cap · maxBuyBps / 10000`
- Capping happens before cost calculation — excess ETH is refunded. Buyer protected by `minAmount` slippage.

---

## Vesting Mechanics

Optional cliff + linear vesting for creator token allocation. Only available via `launch()` (not `configure()`).

**Struct** (`CreatorVest`, `:108-114`): `total` (uint128), `claimed` (uint128), `start` (uint40), `cliff` (uint40 seconds), `duration` (uint40 seconds).

**Configuration** (`:230-243`): `excess = supply − (cap + lpTokens)`. If `vestCliff` or `vestDuration` is nonzero, tokens are held in contract under vesting schedule instead of sent to creator immediately.

**Claiming** (`claimVested`, `:1063-1097`):
- Creator-only (`msg.sender == c.creator`)
- Before cliff: reverts (`elapsed < cliff`)
- Cliff only (duration=0): all tokens vest at cliff
- Cliff + duration: linear from cliff to cliff+duration
- Duration only (cliff=0): linear from launch
- Formula: `vested = total · postCliff / duration` (capped at `total`)
- `v.claimed = uint128(vested)` — no explicit bounds check on this downcast, but `vested ≤ v.total` which is already uint128

**Security notes:**
- `setCreator()` transfers vesting claim rights (by design — documented in Known Finding #3 dismissal)
- Independent of curve state — can claim before, during, or after graduation
- Not protected by `lock` modifier (no ETH handling, only token transfer)

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
| "ETH trapped when tokensForLP cap limits ZAMM seeding" | ZAMM `addLiquidity` for new pools (supply=0) uses both desired amounts directly — no ratio adjustment, no leftover. `beforeAction` hook guarantees pool is fresh at graduation. Pashov v2 invalidated. |
| "Max-allowance approve reverts on UNI/COMP-style tokens" | Only affects `configure()` path — `launch()` clones are allowance-exempt (line 934). Caller assumes token compatibility responsibility. Pashov v2 downgraded to informational. |
| "`safeTransfer` assembly corrupts free memory pointer" | Standard Solady `safeTransfer` pattern. `mstore(0x34, 0)` cleanup is intentional; Solidity codegen uses `log` opcodes with scratch-space encoding, not the FMP allocator. Battle-tested. Pashov v2 invalidated. |

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

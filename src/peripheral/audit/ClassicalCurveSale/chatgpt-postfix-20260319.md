Below is a two-round review of the provided `ClassicalCurveSale.sol`.

## Round 1 — Defense Verification

### D-1 Reentrancy lock

**Claim:** Transient storage `SWAP_LOCK_SLOT` via `lock` modifier on all buy/sell/swap functions.

**Trace**

* The `lock` modifier sets a transient guard and reverts if already set: `tload(SWAP_LOCK_SLOT)` / `tstore(SWAP_LOCK_SLOT, address())` / clear on exit at `src/peripheral/ClassicalCurveSale.sol:917-929`.
* It is applied to:

  * `buy()` at `:518`
  * `buyExactIn()` at `:569`
  * `sell()` at `:637`
  * `sellExactOut()` at `:672`
  * `swapExactIn()` at `:939-946`
  * `swapExactOut()` at `:1003-1010`

**Conclusion:** **Verified.** Within the claimed scope, all curve trading and routed swap entrypoints are protected by the transient lock. `graduate()` is not locked, but that is outside this defense's stated scope.

---

### D-2 CEI pattern

**Claim:** State updates (`sold`, `raisedETH`) happen before external calls in buy/sell paths.

**Trace**

* `buy()` computes `cost`, then updates `c.sold` and `c.raisedETH` at `:544-548`, checks graduation at `:550-551`, and only then performs token/ETH transfers at `:553-559`.
* `buyExactIn()` updates `c.sold` and `c.raisedETH` at `:612-615`, checks graduation at `:617`, and only then transfers at `:622-626`.
* `sell()` checks liquidity, then updates `c.sold` and `c.raisedETH` at `:655-657`, and only then performs `safeTransferFrom` / ETH sends at `:659-661`.
* `sellExactOut()` likewise updates state before external calls; the writeback is immediately before transfers in that function (same pattern as `sell`, at `:708-714` in the full file).

**Conclusion:** **Verified.** The buy/sell paths do follow CEI for the hot state variables before external interaction.

---

### D-3 Graduation state guard

**Claim:** `c.seeded = true` is set before any external calls in `graduate()`; `setLpRecipient` is frozen once `c.graduated` is true.

**Trace**

* `graduate()` rejects if `!c.graduated || c.seeded` at `:735-736`, then sets `c.seeded = true` before any external call at `:738`.
* External calls only occur later: burning unsold tokens at `:745-746`, possible creator refunds at `:749-751`, approval at `:759-760`, ZAMM addLiquidity at `:771-773`, and final refunds at `:782-783`.
* `setLpRecipient()` is creator-only and reverts once `c.graduated` is true at `:849-855`.

**Conclusion:** **Verified.** The seeding one-way transition is committed before any external interaction, and LP recipient edits are correctly frozen at graduation.

---

### D-4 Hook caller check

**Claim:** Only ZAMM can call `beforeAction()`.

**Trace**

* `beforeAction()` begins with `if (msg.sender != address(ZAMM)) revert Unauthorized();` at `:794-800`.

**Conclusion:** **Verified.**

---

### D-5 Creator fee routing enforcement

**Claim:** `beforeAction()` blocks direct `ZAMM.swap()` when creator fee is active; only routed `swapExactIn`/`swapExactOut` through this contract are allowed.

**Trace**

* In `beforeAction()`, once a pool is registered, if `creatorFees[token].beneficiary != address(0)`, it:

  * rejects `IZAMM.swap.selector` at `:823-825`
  * requires `sender == address(this)` at `:825`
* The routed functions are the ones that call ZAMM from this contract:

  * `swapExactIn()` calls ZAMM at `:960-965`, `:982-984`
  * `swapExactOut()` calls ZAMM at `:1022-1036`, `:1051-1062`

**Conclusion:** **Verified.** For the hooked graduated pool, direct swaps are blocked while creator-fee swaps are active, and only calls routed through this contract satisfy the `sender == address(this)` requirement.

---

### D-6 CREATE2 salt binding

**Claim:** Salt includes `msg.sender` to prevent address squatting.

**Trace**

* `launch()` derives `_salt = keccak256(abi.encode(msg.sender, name, symbol, salt));` at `:189-190`, then uses it in `create2` at `:196`.

**Conclusion:** **Verified.** The launcher address is baked into deployment salt derivation.

---

### D-7 Overflow guards

**Claim:** Explicit `uint128` bounds checks for `vr`, `cap`, `startPrice`, `endPrice`, `graduationTarget`, `lpTokens` in `_configure()`.

**Trace**

* Bounds checks appear at `:315-320` before narrowing assignments.
* Narrowing writes occur only afterward at `:334-349`.

**Conclusion:** **Verified.** The prior silent-truncation issue is fixed.

---

### D-8 Graduation target validation

**Claim:** `_configure()` verifies `graduationTarget <= maxETH` from a full-cap sale.

**Trace**

* Validation block at `:322-331`
* Flat curve case: `maxETH = ceil(cap * startPrice / 1e18)` at `:325-326`
* Non-flat case: `maxETH = mulDivUp(startPrice * cap, vr, remAfter * 1e18)` at `:327-329`
* Reverts if `graduationTarget > maxETH` at `:331`

**Conclusion:** **Verified.**

---

## Invariant Verification

### I-1 During the active bonding-curve phase (before `graduate()` executes), `raisedETH` equals net ETH held by contract from curve trading

**Trace**

* Curve buys increase `raisedETH` by `cost`, not by full `msg.value`: `buy()` at `:547-548`, `buyExactIn()` at `:614-615`
* Curve sells decrease `raisedETH` by `proceeds`: `sell()` at `:656-657`, `sellExactOut()` later in the same pattern
* The contract has a naked payable `receive()` at `:1127-1128`, so it can accept ETH unrelated to curve trading
* `graduate()` uses `c.raisedETH` as LP ETH, not `address(this).balance`, at `:741`

**Conclusion:** **Violated.** The stronger balance-equality form of this invariant does not hold because the contract can receive arbitrary ETH outside curve accounting. `raisedETH` tracks curve-accounted ETH, but total contract ETH balance can exceed it.

**Response:** Accepted as wording refinement. The invariant should read: "`raisedETH` tracks curve-accounted ETH (buy costs minus sell proceeds), not necessarily total ETH balance of the contract." The contract uses `raisedETH` (not `address(this).balance`) for all accounting decisions, so force-sent ETH is inert — it cannot corrupt graduation or seller proceeds.

---

### I-2 `sold <= cap` at all times

**Conclusion:** **Verified.**

### I-3 Once `graduated == true`, no further buys or sells on the bonding curve are possible

**Conclusion:** **Verified.**

### I-4 Once `seeded == true`, `graduate()` cannot be called again

**Conclusion:** **Verified.**

### I-5 A curve can only be configured once per token address (`AlreadyConfigured` guard)

**Conclusion:** **Verified.**

### I-6 Only ZAMM can call `beforeAction()`

**Conclusion:** **Verified.**

### I-7 Pre-seed LP operations are blocked unless called from within `graduate()` via transient bypass

**Conclusion:** **Verified.**

---

## Round 2 — Adversarial Hunt

After filtering duplicates and intentional behavior, **no novel vulnerability survived**.

### Surviving findings

**None.**

### Why the main candidates failed

* **Reentrancy from `graduate()`**: `c.seeded = true` is committed before any external call at `:738`, and curve trading is already frozen by `c.graduated` checks at `:523-525`, `:571-574`, `:640-642`, `:675-677`.
* **Creator-fee bypass on the graduated pool**: the hook enforces routing on the specific hooked pool via `sender == address(this)` and blocks raw `swap()` at `:823-826`.
* **Silent narrowing / max-target issues**: fixed by explicit `uint128` bounds checks and target validation at `:315-331`.
* **Pre-seed LP frontrun via malicious token**: already fixed by moving pool registration after approval at `:759-763`; duplicate of Known Finding #4.
* **Fee-on-transfer/rebasing misaccounting**: still applies to nonstandard tokens, but that is already Known Finding #2 and accepted.

---

## Final assessment

* **Defenses:** 8/8 **Verified**
* **Invariants:** 6 **Verified**, 1 **Violated** (`I-1`, wording — not a code bug)
* **Novel adversarial findings:** **0**

The contract is materially tighter than the earlier vulnerable versions. The I-1 invariant wording has been addressed in SECURITY.md to scope it to curve-accounted ETH rather than total balance equality.

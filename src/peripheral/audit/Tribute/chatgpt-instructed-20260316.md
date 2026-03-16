Here’s a manual security, readiness, and logic review of `Tribute.sol` as provided.

## Overall verdict

For the stated model — a minimal OTC escrow between a proposer and a DAO, using **standard ERC-20s or ETH** and with the DAO actively opting in to claims — the core escrow flow is sound.

I do **not** see a new critical or high-severity fund-loss bug in the happy path beyond the issues you already documented. The strongest parts are:

* the **terms-binding patch** in `claimTribute` is correct,
* the **delete-before-external-call** pattern is correct,
* the **reentrancy guard** is placed on all state-changing entrypoints,
* the **ERC20 helper logic** is using the standard “success with `1` or no returndata, reject EOAs” pattern.

The main remaining risk is not “someone can steal all funds from honest escrow under standard assumptions.” It is that the contract is intentionally permissive and therefore inherits several **readiness / integration / token-class assumptions** that must be enforced outside the contract.

## What looks correct

### 1) Escrow lifecycle is logically consistent

`proposeTribute` stores one offer per `(proposer, dao, tribTkn)` and blocks overwrite with:

* `if (offer.tribAmt != 0) revert InvalidParams();` at lines 93–95

`cancelTribute` only lets the proposer cancel their own offer because the mapping key is `msg.sender`:

* lines 112–126

`claimTribute` only works for the targeted DAO because it resolves `dao = msg.sender` and reads:

* `tributes[proposer][dao][tribTkn]` at lines 146–149

That means there is no obvious unauthorized claim or cancel path.

### 2) The bait-and-switch patch is correctly implemented

The patched `claimTribute` now requires the caller to supply the full terms and checks them against storage:

* lines 139–152

This closes the specific “DAO approved one thing, proposer canceled and reposted another” issue. If the proposer cancels and reposts with different terms, the execution reverts with `TermsMismatch()` instead of silently filling the new offer.

### 3) CEI ordering is good

In both `cancelTribute` and `claimTribute`, the tribute is deleted **before** any external token/ETH transfer:

* cancel: line 116 before lines 118–124
* claim: line 154 before lines 157–174

That is the right pattern.

In `proposeTribute`, state is written before the ERC20 pull:

* lines 97–106

That is also acceptable here because a failed `safeTransferFrom` reverts the whole tx and the nonReentrant guard blocks token-based callback abuse.

### 4) Reentrancy posture is solid

All three mutating functions are guarded:

* `proposeTribute` line 77
* `cancelTribute` line 112
* `claimTribute` line 145

The transient-storage guard at lines 280–291 is structurally fine. It blocks reentry from:

* malicious ERC20 `transfer` / `transferFrom`,
* ERC777-like hooks,
* ETH receiver fallback logic during `safeTransferETH`.

### 5) The pagination logic is correct

The discovery helpers scan refs, filter active offers by `offer.tribAmt != 0`, trim the memory array, and return the next ref index:

* DAO view: lines 194–231
* proposer view: lines 239–276

I do not see an off-by-one bug in `next`.

## Findings and readiness concerns

### F1 — Standard-token assumption is hard, not enforced

**Severity:** Medium
**Status:** already known / accepted, but still the main real-world economic risk

The contract comment says fee-on-transfer and rebasing tokens are unsupported:

* lines 4–6

But the code does not enforce “actual received amount equals recorded amount.” It records first and relies on plain transfer helpers:

* proposal recording: lines 97–99
* tribute pull: line 106
* consideration pull: line 164
* outbound transfers: lines 123, 173

That means the accepted findings remain real:

* fake ERC20 / non-compliant ERC20 can pretend transfer succeeded,
* fee-on-transfer can underdeliver,
* rebasing / blacklist / paused / weird-return tokens can break exactness or liveness.

This is not just a documentation issue. It is a protocol assumption. If this contract is used permissionlessly, **UI/governance/token allowlisting** becomes part of the security boundary.

**Assessment:** acceptable only if the intended deployment explicitly scopes usage to trusted, standard tokens.

---

### F2 — Append-only discovery arrays are not production-grade onchain indexing

**Severity:** Medium for UX / gas, not fund safety
**Status:** already known / accepted

Every proposal appends to both ref arrays:

* lines 101–103

But cancel/claim never remove refs. So the views at lines 194–276 degrade over time and can become increasingly expensive to scan as history grows.

This is not a direct security bug, but for a heavily used instance it becomes a practical availability problem for onchain discovery. Your current documentation already frames this correctly: **events/off-chain indexers should be the primary discovery path**.

**Assessment:** fine for a small/simple deployment, not fine as the main source of truth for high-volume discovery.

---

### F3 — Counterfactual DAO address issue remains live

**Severity:** Low-Medium
**Status:** already known / accepted

Because `dao` is just an address in storage and claim authority is purely `msg.sender == dao`, tributes aimed at undeployed CREATE2 addresses remain exposed to the known “counterfactual summon frontrun” class if the summon flow elsewhere is weak.

Relevant code points:

* proposal accepts any nonzero `dao`: line 78
* claim authority is only `address dao = msg.sender`: line 146

Nothing in `Tribute.sol` itself binds the address to a future intended summoner or codehash.

**Assessment:** still acceptable if predeployment tributes are rare or forbidden. Otherwise this needs ecosystem-level mitigation, not a Tribute-only patch.

---

### F4 — EIP-1153 is a deployment compatibility requirement

**Severity:** Readiness blocker on unsupported chains
**Status:** new readiness note

The reentrancy guard uses `tload`/`tstore`:

* lines 280–291

That means deployment requires a chain / rollup / VM configuration that supports transient storage. On a chain without EIP-1153 support, this contract is not “slightly degraded”; it is effectively not deployable/usable as written.

This is not a logic bug, but it is absolutely a **mainnet readiness requirement**.

**Assessment:** treat as a hard deployment checklist item.

---

### F5 — ETH receiver compatibility is a liveness assumption

**Severity:** Low
**Status:** not a fund-loss bug, but operationally important

ETH is pushed with raw call in both directions:

* proposer payment: line 160
* DAO tribute receipt: line 170
* cancel refund: line 120
* helper: lines 295–302

If the recipient is a contract that rejects ETH, the operation reverts.

Examples:

* an ETH tribute targeting a DAO contract with no payable receiver cannot be claimed,
* an offer asking for ETH where the proposer cannot receive ETH cannot be claimed,
* a proposer contract that cannot receive ETH cannot cancel an ETH tribute.

These are mostly self-inflicted or integration issues, and cancel still exists in some cases, so I would not rate this highly. But for “DAO proposal” usage, it matters because some governance executors/timelocks are not happy ETH recipients.

**Assessment:** document clearly; UI should check payable-ETH capability when either side is native ETH.

---

### F6 — No rescue path for accidental assets / force-sent ETH

**Severity:** Low / Informational
**Status:** new operational note

There is no rescue function. That keeps the contract simple and avoids admin trust, but it also means:

* accidental ERC20 transfers to the contract are stranded,
* ETH sent in the payable constructor is stranded unless matched by an offer,
* force-sent ETH via `selfdestruct` or equivalent is stranded.

Relevant points:

* payable constructor at line 60
* no rescue / sweep function anywhere
* no receive function, so plain ETH sends revert, but force-send still exists

This is not exploitable in the usual sense, but it is worth acknowledging as an ops constraint.

**Assessment:** acceptable if “no admin rescue” is intentional and documented.

---

### F7 — DAO-ness is not enforced

**Severity:** Informational
**Status:** design note

The contract allows any nonzero address as `dao`:

* line 78

If the product narrative is specifically “DAO proposals,” that check lives outside the contract. EOAs and arbitrary contracts can be targets.

That is fine if intended, but UIs and docs should not imply onchain enforcement of “must be a DAO.”

## Low-level helper review

The assembly helpers look correct.

### `safeTransfer`

* lines 304–318

This is using the common permissive ERC20 pattern:

* accept call success + returned `1`,
* also accept success with no returndata for old tokens,
* reject EOAs / non-contracts.

### `safeTransferFrom`

* lines 320–337

Same pattern, and the source is intentionally the current `caller()`, which is exactly what you want here:

* in `proposeTribute`, from proposer to `address(this)`,
* in `claimTribute`, from DAO to proposer.

That means the helper is correct for this contract, though its name is a little generic for a helper whose “from” is implicitly `caller()`.

### `safeTransferETH`

* lines 295–302

This is fine. It forwards all gas and reverts on failure.

## Logic edge cases worth calling out

These are not bugs, but they matter.

### Offer revocability remains a governance-liveness concern

Even after the terms patch, the proposer can still cancel before claim execution. The DAO won’t lose funds because the transaction reverts atomically, but a queued governance action can fail if the offer disappears between proposal approval and execution.

That is not a vulnerability in the escrow itself; it is a property of a revocable maker order.

### One active offer per `(proposer, dao, tribTkn)`

Because the key is `tributes[msg.sender][dao][tribTkn]`, a proposer cannot maintain two simultaneous offers to the same DAO using the same tribute token. That is a deliberate simplification, but indexers/UIs should reflect it.

### Exactness depends on both sides being standard tokens

The comment at lines 4–6 correctly says unsupported tokens are unsupported, but in practice that applies to both `tribTkn` and `forTkn`, not just the tribute side.

## Readiness assessment

I would rate this as:

* **Core escrow logic:** good
* **Security posture under intended assumptions:** good
* **Production readiness as a permissionless public primitive:** conditional
* **Production readiness for a constrained ecosystem with trusted token lists and offchain indexing:** good

## Must-have conditions before production use

1. **Deploy only on chains with EIP-1153 support.**
2. **Make “standard ERC20 only” an enforced product rule**, ideally via UI allowlists or governance policy.
3. **Do not rely on `daoTributeRefs` / `proposerTributeRefs` for primary discovery at scale.**
4. **Do not accept tributes to undeployed counterfactual DAO addresses** unless the summon path is hardened.
5. **Check ETH receiver compatibility** whenever `tribTkn == address(0)` or `forTkn == address(0)`.
6. **Document that offers are revocable until claimed.**

## Suggested tests / invariants

These are the tests I would want before signoff:

* proposer can propose/cancel ERC20 tribute
* proposer can propose/cancel ETH tribute
* DAO can claim ERC20-for-ERC20, ETH-for-ERC20, ERC20-for-ETH, ETH-for-ETH
* `claimTribute` reverts on any term mismatch
* proposer cancel + repost with worse terms cannot satisfy old execution payload
* reentrancy attempts from malicious ERC20 and ETH receiver fail
* fake/no-code token is rejected by outbound helpers
* FOT/rebasing tokens are explicitly tested and documented as unsupported behavior
* pagination returns monotonic `next` and only active offers
* array growth does not affect correctness, only scan cost
* chain integration test confirms transient-storage support on target deployment network

## Bottom line

My conclusion is:

* **No new critical/high exploit path found in the contract logic itself**
* the **known accepted issues still accurately describe the real risk surface**
* the biggest remaining concerns are **token-class enforcement, discovery scalability, CREATE2 predeployment address handling, and deployment-chain compatibility**
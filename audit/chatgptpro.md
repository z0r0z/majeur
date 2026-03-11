# [ChatGPT Pro (GPT-4.5 Pro)](https://chat.openai.com/) — Moloch.sol

**Prompt:** [`SECURITY.md`](../SECURITY.md) (3-round methodology: systematic → economic → adversarial triager)
**Type:** AI audit guided by accumulated methodology from 17 prior audit tools

## Review Summary

> **Reviewed 2026-03-11. One novel finding (MEDIUM-1). Two duplicates (LOW-2, INFORMATIONAL-3).**
>
> - **MEDIUM-1 is valid and novel (5th novel finding across 21 audits).** The attack path is sound: `fundFutarchy` (line 530) checks `F.resolved` but never checks `executed[id]`. After a proposal is cancelled (`cancelProposal` sets `executed[id] = true` at line 429) or executed, `fundFutarchy` still succeeds because `snapshotBlock[id] != 0` (skips `openProposal`) and `F.resolved` is still false. The pool becomes permanently stuck: `castVote` reverts `AlreadyExecuted`, `executeByVotes` can't re-run, and `resolveFutarchyNo` explicitly rejects `executed[id]` (line 575). The PoC is concrete and the disproof attempt is thorough. This is distinct from KF#17 (which is about premature NO-resolution on live proposals with zero quorum) — here the proposal is already dead and the victim's funds are trapped. **Recommended fix:** add `if (executed[id]) revert AlreadyExecuted();` at the top of `fundFutarchy`. Added as KF#18 and v2 hardening candidate.
> - **LOW-2 is a duplicate of KF#11** (proposalThreshold == 0 griefing / front-run cancel). The SafeSummoner guard table explicitly lists "Front-run cancel" under KF#11, and `proposalThreshold > 0` is the documented mitigation. The tombstoning angle (permanent hash death via open+cancel) is a well-articulated consequence of KF#11 but not a distinct vulnerability. The report's "Duplicates Known Finding #? No" self-assessment is incorrect.
> - **INFORMATIONAL-3 is a duplicate** of the auto-futarchy overcommit issue previously identified by Pashov #3, Octane #9, Forefy #1, QuillShield SID-1, ChatGPT LOW-2, and Qwen LOW-2. The report correctly identifies the mechanics (no reservation accounting in `openProposal`, first-come-first-served payout) and correctly applies the privileged-role downgrade, but claims novelty despite 6 prior audits finding the same issue.
> - **Overall quality is strong.** Excellent methodology compliance — correctly identifies and excludes KF#1, #2, #4, #5, #6, #7, #8, #15, #16, #17 (10 known findings screened). The reentrancy inventory in Category 1 is the most thorough across all 21 audits, explicitly tracing every external-call site. The Round 3 triager pass is genuine with real confidence scoring. The architecture assessment correctly identifies feature composition as the primary risk, not low-level Solidity errors. Self-assessment claims 3 novel but actual count is 1 — the same 2:1 inflation pattern seen in Qwen. Signal-to-noise: 1 novel from 3 findings (33%).

---

*Line numbers below are approximate because the source was provided inline as a single pasted file.*

## Executive Summary

- **Total findings:** 3  
  - **Novel:** 3  
  - **Known-duplicate / discarded during triage:** several, including Known Findings #1, #2, #4, #5, #6, #7, #8, #15, #17
- **Critical:** 0 | **High:** 0 | **Medium:** 1 | **Low:** 1 | **Informational:** 1
- **Highest-confidence finding:** `fundFutarchy` accepts executed/cancelled IDs, creating dead futarchy pools — **90%**

---

## Round 1: Systematic Code Review

<details>
<summary><strong>Category 1 — Reentrancy</strong></summary>

**Conclusion:** **No novel issues found** — the transient-storage guard covers the user-reachable arbitrary-call and payout paths, and the remaining unguarded external calls are bootstrap-only, `onlyDAO`, or restricted to trusted child-token contracts.

### External-call inventory checked

- `Moloch.init` (~190-224): external calls via `_init`, child `init()`, and arbitrary `initCalls[i].target.call(...)`
  - **Assessment:** not guarded, but **SUMMONER-only bootstrap path**
- `Moloch.executeByVotes` (~435-452): arbitrary `call` / `delegatecall` through `_execute`
  - **Assessment:** guarded by `nonReentrant`
- `Moloch.spendPermit` (~591-610): arbitrary `call` / `delegatecall`
  - **Assessment:** guarded by `nonReentrant`
- `Moloch.buyShares` (~642-688): external ERC20 pull, ETH refund, external `Shares/Loot` mint/transfer
  - **Assessment:** guarded by `nonReentrant`
- `Moloch.ragequit` (~691-728): arbitrary token/ETH payouts
  - **Assessment:** guarded by `nonReentrant`
- `Moloch.cashOutFutarchy` (~496-519): payout path
  - **Assessment:** guarded by `nonReentrant`
- `Moloch.spendAllowance` (~621-624): payout path
  - **Assessment:** guarded by `nonReentrant`
- `Moloch.batchCalls` (~814-819): arbitrary external calls
  - **Assessment:** not itself guarded, but `onlyDAO`; practical reachability is through already-governed execution
- `Moloch.fundFutarchy` (~455-485): `safeTransferFrom(rt, amount)` when `rt` is `shares` or `loot`
  - **Assessment:** not guarded, but token set is restricted to ETH / minted sentinels / local `Shares` / local `Loot`; no attacker-controlled arbitrary token callback surface

### `multicall` and EIP-1153 guard bypass
- `multicall` (~822-832) uses `delegatecall(address(this), ...)`.
- With EIP-1153, the transient slot is account-scoped; a `delegatecall` subcall sees the same `REENTRANCY_GUARD_SLOT`.
- I traced the path `multicall -> nonReentrant subcall -> external callback -> Moloch reentry`, and the callback still sees the slot set.

### Read-only reentrancy
- The main callback-capable paths are `ragequit`, `cashOutFutarchy`, `buyShares`, `executeByVotes`, and `spendPermit`.
- During callbacks, a view can observe intermediate state, but I did not find any stale-view-dependent write path that turns this into a practical exploit.

</details>

<details>
<summary><strong>Category 2 — Flash Loan / Vote Manipulation</strong></summary>

**Conclusion:** **No novel issues found** — vote weight is snapshot-based at block $N-1$, and same-block acquisition cannot affect `castVote`.

### Trace
- `openProposal` (~254-277) sets:
  - `snapshotBlock[id] = block.number - 1`
  - `supplySnapshot[id] = shares.getPastTotalSupply(snap)`
- `castVote` (~317-352) uses:
  - `shares.getPastVotes(msg.sender, snapshotBlock[id])`

### Checks performed
- I found **no path** that sets the vote snapshot to the current block.
- `Shares.getPastVotes` and `getPastTotalSupply` reject `blockNumber >= block.number`.
- Same-block checkpoint overwrites in `Shares._writeCheckpoint` are standard end-of-block semantics and do not let a user smuggle current-block votes into a past-block query.

### Same-block share purchase
- `buyShares` can mint or transfer shares in the current block.
- Those shares affect `getVotes(msg.sender)` immediately, but **not** `getPastVotes(msg.sender, block.number - 1)`.
- So an attacker can **not** buy shares and vote with them in the same block.

**Note:** `proposalThreshold` uses current votes in `openProposal`; that is real behavior, but it affects proposal opening / spam resistance, not vote-snapshot integrity. I treated that separately in Round 2/3 and ultimately did **not** elevate it to a final finding.

</details>

<details>
<summary><strong>Category 3 — Governance Logic</strong></summary>

**Conclusion:** **1 novel finding** plus otherwise sound state transitions.

### State machine trace
- `state(id)` (~387-426) enforces:
  - `Unopened` if `createdAt[id] == 0`
  - `Queued` only if queued and timelock not elapsed
  - `Expired` only if TTL elapsed before queue
  - `Succeeded` / `Defeated` after quorum and vote comparisons
  - `Executed` if `executed[id] == true`
- I found **no bypass** of the timelock in `executeByVotes`:
  - it only allows `Succeeded` or `Queued`
  - if timelock is enabled and `queuedAt[id] == 0`, the first call **queues** instead of executing

### Auto-open ordering
- `castVote` auto-opens if `createdAt[id] == 0`
- After the first vote is cast, `cancelProposal` is no longer available because tally becomes nonzero

### `bumpConfig()`
- Proposal/permit execution IDs are recomputed with current `config`
- This does invalidate execution/spend paths for pre-bump intents

### Novel issue identified
- `fundFutarchy` does **not** reject `executed[id] == true`, even though both voting and NO-resolution do
- This creates dead futarchy pools on executed/cancelled IDs
- Carried forward to final findings

</details>

<details>
<summary><strong>Category 4 — Economic / Ragequit</strong></summary>

**Conclusion:** **No novel issues found** — the pro-rata math and duplicate-token defense are sound. I did confirm **Known Finding #2** as a duplicate and excluded it.

### Checks performed
- `ragequit` (~691-728) computes `total = shares.totalSupply() + loot.totalSupply()` **before** burns
- It then burns user balances and pays each listed token by:
  - `$due = pool \cdot amt / total$`
- This is the correct Moloch-style pre-burn denominator

### Sorted token array
- The ascending-order check prevents duplicate claims
- Token classes explicitly excluded from ragequit payout:
  - `shares`
  - `loot`
  - `address(this)`
  - sentinel `address(1007)`

### Force-fed ETH
- `address(this).balance` includes forced ETH
- I do not treat that as a security issue; it is an irrational donation, matching the prompt’s false-positive guidance

### Cross-function candidate checked
- `buyShares -> inflate supply -> ragequit after snapshot -> influence quorum denominator`
- This is a **confirmed duplicate of Known Finding #2**, not re-reported

</details>

<details>
<summary><strong>Category 5 — Futarchy</strong></summary>

**Conclusion:** **2 novel issues**, plus several confirmed duplicates excluded from the final list.

### Confirmed duplicates excluded
- **Known Finding #4** — futarchy resolution timing
- **Known Finding #5** — transferable vote receipts break `cancelVote`
- **Known Finding #6** — zero-winner lockup
- **Known Finding #17** — public futarchy attach + zero-quorum premature NO-resolution

### Novel issue 1
- `fundFutarchy` can fund a dead `id` after `executeByVotes`, `cancelProposal`, or `spendPermit`
- Because `resolveFutarchyNo` rejects `executed[id]`, those pools cannot resolve
- Carried forward

### Novel issue 2
- Auto-futarchy earmarking in `openProposal` reads the current DAO-held local `shares`/`loot` balance and only increments `F.pool`
- There is **no reservation accounting** across concurrent proposals
- Later payout uses live balances in `_payout`
- This can overcommit the same local inventory across multiple proposals
- Carried forward, severity adjusted heavily under the privileged-role rule

</details>

<details>
<summary><strong>Category 6 — Access Control</strong></summary>

**Conclusion:** **No novel issues found** — the `onlyDAO` model is internally consistent, the permit SBT gate holds, and `init()` is effectively one-shot.

### Checks performed
- `onlyDAO` is `msg.sender == address(this)` throughout `Moloch`
- Under `_execute(op=1, ...)`, delegated code does **not** magically gain `msg.sender == address(this)`; plain `onlyDAO` checks are not bypassed that way
- Permit SBT gate:
  - `transfer` and `transferFrom` both revert if `isPermitReceipt[id]`
  - I found no bypass in `_burn6909` or operator flow
- `init()`:
  - restricted to immutable `SUMMONER`
  - a second call attempts to re-`create2` the same child clones and reverts
  - child `Shares.init` / `Loot.init` / `Badges.init` also enforce single initialization

</details>

<details>
<summary><strong>Category 7 — Token Sales</strong></summary>

**Conclusion:** **No novel issues found** — core sale accounting is correct. I confirmed **Known Finding #1** as a duplicate and excluded it.

### Checks performed
- `buyShares` (~642-688):
  - rejects zero amount
  - checks `s.active`
  - enforces `cap` before decrement
  - enforces `maxPay`
- In non-minting mode, it transfers from DAO-held inventory; this is atomic with ERC20 balance accounting and does not race with `ragequit` because both critical user-facing treasury paths are `nonReentrant`

### Duplicate excluded
- Exact sell-out sets `cap` to zero, colliding with the sentinel meaning “unlimited”
- **Confirmed duplicate of Known Finding #1**

### ERC20 payment path
- I reviewed `maxPay` and payment pull logic for both ETH and ERC20 paths
- No standalone, non-governance novel issue was strong enough to survive triage here

</details>

<details>
<summary><strong>Category 8 — Math / Precision</strong></summary>

**Conclusion:** **No novel issues found** — arithmetic is conservative and rounding behavior is predictable.

### Checks performed
- `mulDiv`:
  - rejects multiplication overflow
  - rejects division by zero
  - rounds down
- Ragequit dust:
  - dust can accumulate due to floor division, but I found no profitable repeated-partial exploit
- `uint96` vote/tally limits:
  - the code already forces checkpoint values through `toUint96`
  - share supply cannot grow past what vote storage can represent without reverting
- Split delegation:
  - `setSplitDelegation` requires sum exactly $10000$
  - `_targetAlloc` uses “remainder to last,” so allocation sum remains exact

</details>

<details>
<summary><strong>Category 9 — External Token Integration</strong></summary>

**Conclusion:** **No novel issues found** beyond already-known edge cases.

### Confirmed duplicates excluded
- **Known Finding #7** — blacklistable token ragequit DoS is user-mitigated by omitting that token
- **Known Finding #8** — fee-on-transfer token accounting in ragequit is informational

### Additional checks
- Rebasing-token balance drift during ragequit:
  - possible integration weirdness, but I did not find a concrete extractable exploit
- Return-data bomb in `_execute`:
  - the target is governance-chosen or permit-authorized
  - under the privileged-role rule, this is not a standalone vulnerability

</details>

<details>
<summary><strong>Category 10 — Delegation & Checkpoints</strong></summary>

**Conclusion:** **No novel issues found** — split delegation math is path-independent and checkpoint lookup is correct.

### Checks performed
- `setSplitDelegation` / `_targetAlloc` / `_repointVotesForHolder`
  - sum constrained to exactly $10000$
  - “remainder to last” prevents over-allocation
  - old-vs-new allocation delta logic prevents path-dependent drift
- Same-block transfers:
  - overwrite the same block’s checkpoint in `_writeCheckpoint`
  - standard end-of-block semantics
- Circular and self delegation:
  - delegation is not recursive
  - no transitive loop problem exists

</details>

---

## Round 2: Economic & Cross-Function Analysis

<details>
<summary><strong>Cross-mechanism attack analysis</strong></summary>

### 1. `cancelProposal` + `fundFutarchy` = permanent pool lock
**Status:** **Novel finding kept**

- Because `cancelProposal` sets `executed[id] = true`, and `fundFutarchy` never checks `executed[id]`, a cancelled or already-executed `id` can still receive futarchy funds.
- Later:
  - `castVote(id, ...)` reverts `AlreadyExecuted`
  - `executeByVotes(...)` cannot run again
  - `resolveFutarchyNo(id)` reverts because it explicitly rejects `executed[id]`
- **Attacker cost:** mostly gas
- **Attacker gain:** no direct profit, but can freeze the victim’s public futarchy deposit amount

### 2. Public mempool proposal opening + proposer capture + tombstoning
**Status:** **Novel finding kept**

- The first opener becomes `proposerOf[id]`.
- A frontrunner seeing the first `castVote(id, ...)` or `openProposal(id)` tx can preempt it with:
  - `openProposal(id)`
  - `cancelProposal(id)`
- That permanently tombstones the exact hash by setting `executed[id] = true`.
- **Attacker cost:** gas, plus threshold-level current votes if threshold is enabled
- **Attacker gain:** censorship / forced re-nonce / repeated public-mempool griefing

### 3. Auto-futarchy + local `Shares` / `Loot` reward token = undercollateralized claims
**Status:** **Novel finding kept, downgraded heavily**

- Multiple concurrent openings can each earmark the same DAO-held local inventory because the code does not reserve it.
- Payout is first-come-first-served against the live token balance.
- **Attacker cost:** gas and ownership of winning receipts
- **Economic impact:** early claimants can consume the entire current local inventory, leaving later winners unpaid unless the DAO replenishes balances

### 4. Sale + quorum denominator manipulation
**Status:** **Discarded as duplicate**

- This is **Known Finding #2**

### 5. Delegation + voting
**Status:** **No issue found**

- I specifically checked whether split-delegation rounding could make `getPastVotes` exceed actual voting balance or create quorum asymmetry.
- I did not find a path; the allocation remainder is explicitly assigned to the last delegate.

### 6. Permits + proposals namespace / replay interactions
**Status:** **Discarded as duplicates / low-signal**
- Namespace overlap: **Known Finding #10**
- `spendPermit` replay nuance via `executed`: **Known Finding #16**

### 7. Same-block share acquisition + proposal threshold
**Status:** **Discarded after adversarial validation**

- Technically, current votes can satisfy `proposalThreshold` in `openProposal`.
- But this does **not** let the attacker vote with same-block shares because `castVote` is still snapshot-based at $N-1$.
- Net effect is mostly proposal-opening spam / griefing, which overlaps the already-known threshold-spam risk profile.

</details>

---

## Round 3: Adversarial Validation

<details>
<summary><strong>Triager pass: attempts to disprove each candidate</strong></summary>

| Candidate | Disproof attempt | Known finding? | Privileged-role rule | Confidence | Verdict |
|---|---|---:|---|---:|---|
| Dead IDs remain fundable via `fundFutarchy` | Checked `F.resolved` gate, `resolveFutarchyNo`, `executeByVotes`, `cancelProposal`, `spendPermit`. No `executed[id]` check exists in `fundFutarchy`, and all resolution paths are blocked once funded on a dead ID. | No | No for the stale-executed-ID path | **90** | **Include** |
| First-opener tombstoning / proposer capture | Tried to disprove via auto-open semantics and `cancelProposal` guards. Attack fails if zero-quorum config makes state immediately `Defeated`, or if auto-futarchy pre-attaches nonzero `F.pool`; otherwise it survives in the common nonzero-quorum / zero-pool case. | No | No when threshold is zero; otherwise threshold-holder attacker | **76** | **Include** |
| Auto-futarchy overcommits local `Shares` / `Loot` | Looked for reservation tracking or pool netting across proposals; none exists. `_payout` uses live local balances only. | No | **Yes** — requires DAO to enable this configuration | **78** | **Include, downgraded to Informational** |
| Same-block `proposalThreshold` bypass | Technically real, but does not affect vote snapshots; impact is mostly spam / grief. Comment explicitly says threshold uses current votes by design. | No | Partially | 55 | Discard |
| Fee-on-transfer / malicious ERC20 as sale payment token | Real integration caveat, but entirely dependent on DAO listing that token as sale payment. | No | **Yes** | 51 | Discard |

</details>

---

## Confirmed Findings

### [MEDIUM-1] `fundFutarchy` accepts executed/cancelled IDs, creating dead futarchy pools

**Severity:** Medium  
**Confidence:** 90  
**Category:** Futarchy  
**Location:** `Moloch`, function `fundFutarchy`, line(s) ~455-485; related sinks in `cancelProposal` ~375-384, `executeByVotes` ~435-452, `spendPermit` ~591-610, `resolveFutarchyNo` ~488-494

**Description:**  
`fundFutarchy` only rejects `F.resolved`, but it never checks `executed[id]`. This means an `id` that has already been cancelled in `cancelProposal`, executed in `executeByVotes`, or consumed in `spendPermit` can still have a futarchy pool attached and funded later. Once that happens, the pool is dead: `castVote` rejects `executed[id]`, `executeByVotes` cannot run again, and `resolveFutarchyNo` explicitly reverts when `executed[id]` is true. The result is an unresolved futarchy pool whose ETH / local `Shares` / local `Loot` funding is stuck unless the DAO later performs a discretionary treasury refund.

**Attack Path:**
1. Attacker causes or observes an `id` becoming dead — for example by frontrunning the first public proposal action with `openProposal(id)` followed by `cancelProposal(id)`, which sets `executed[id] = true`.
2. Victim later calls `fundFutarchy(id, token, amount)` or submits that transaction publicly.
3. `fundFutarchy` succeeds because it checks `F.resolved` but not `executed[id]`; `F.pool` increases and the funding is transferred in.
4. The pool can never resolve through normal futarchy mechanics, because all resolution/voting/execution paths are now blocked by the executed latch.

**Proof of Concept:**  
```solidity
function test_deadFutarchyPool() public {
    // Assumptions:
    // - proposalThreshold == 0
    // - quorumBps > 0 or quorumAbsolute > 0
    // - autoFutarchyParam == 0
    uint256 id = 777;

    bytes[] memory batch = new bytes[](2);
    batch[0] = abi.encodeCall(Moloch.openProposal, (id));
    batch[1] = abi.encodeCall(Moloch.cancelProposal, (id));

    // attacker tombstones the id
    vm.prank(attacker);
    dao.multicall(batch);

    // victim publicly funds futarchy on the dead id
    vm.deal(victim, 10 ether);
    vm.prank(victim);
    dao.fundFutarchy{value: 10 ether}(id, address(0), 10 ether);

    // the pool is now unresolvable through protocol paths
    assertTrue(dao.executed(id));

    vm.prank(victim);
    vm.expectRevert(Moloch.AlreadyExecuted.selector);
    dao.castVote(id, 1);

    vm.expectRevert(); // NotOk()
    dao.resolveFutarchyNo(id);

    vm.expectRevert(); // NotOk(), because F.resolved is still false
    dao.cashOutFutarchy(id, 1);
}
```

**Disproof Attempt:**  
I tried to disprove this by checking whether `fundFutarchy` implicitly gates on proposal liveness through either `snapshotBlock[id] == 0` or `F.resolved`. That fails. If the proposal was already opened and later cancelled/executed, `snapshotBlock[id]` is already nonzero, so `fundFutarchy` skips `openProposal` entirely. If the proposal was executed without futarchy enabled, then `F.resolved` is still false, so the `F.resolved` guard also does not help. On the back end, `resolveFutarchyNo` explicitly rejects `executed[id]`, and `_resolveFutarchyYes` is only reached during execution/spend paths that have already finished. The dead pool therefore survives every disproof attempt I traced.

**Severity Justification:**
- Exploitable without DAO governance vote? **Yes**
- Survives `nonReentrant` guard? **Yes** — this is a state-machine omission, not a reentrancy bug
- Survives snapshot-at-$N-1$? **Yes**
- Economic cost of attack vs gain: **attacker spends gas; victim can have an arbitrarily large public futarchy deposit frozen**
- Duplicates Known Finding #? **No**

**Recommendation:**  
Add an executed-latch check at the very top of `fundFutarchy`:

```solidity
if (executed[id]) revert AlreadyExecuted();
```

---

### [LOW-2] First opener can capture `proposerOf[id]` and tombstone the exact proposal hash

**Severity:** Low  
**Confidence:** 76  
**Category:** Governance Logic  
**Location:** `Moloch`, functions `openProposal` ~254-277, `cancelProposal` ~375-384, `multicall` ~822-832

**Description:**  
Proposal lifecycle is keyed only by a naked `uint256 id`, and the first caller to `openProposal(id)` becomes `proposerOf[id]`. Because `cancelProposal(id)` only requires `msg.sender == proposerOf[id]` plus zero tallies and zero futarchy pool, a mempool frontrunner can preempt the first honest `castVote(id, ...)` or `openProposal(id)` transaction, become the recorded proposer, and immediately cancel the proposal hash. That sets `executed[id] = true`, permanently tombstoning that exact hash under the current `config`. Honest participants must choose a fresh nonce and re-coordinate around a new `id`.

**Attack Path:**
1. Honest user broadcasts the first public `castVote(id, support)` or `openProposal(id)` transaction for a proposal hash.
2. Attacker reads the raw `id` from calldata and frontruns with `multicall([openProposal(id), cancelProposal(id)])`.
3. `openProposal` records `proposerOf[id] = attacker`; `cancelProposal` then succeeds because the tally is still zero.
4. Victim’s original transaction reverts because `executed[id]` is now true; the exact hash is dead.

**Disproof Attempt:**  
I checked whether the auto-open in `castVote` prevents this. It does not, because the attacker only needs to arrive first in the mempool. I also checked the state gate in `cancelProposal`: the attack fails if a zero-quorum configuration makes the zero-vote proposal immediately `Defeated`, and it also fails if auto-futarchy already attached a nonzero pool. But in the common configuration of nonzero quorum with no pre-attached pool, the attack survives. There is no proposer binding in the hash and no explicit submit phase that reserves authorship before voting begins.

**Severity Justification:**
- Exploitable without DAO governance vote? **Yes** — immediately if `proposalThreshold == 0`; otherwise by any threshold-eligible holder
- Survives `nonReentrant` guard? **Yes**
- Survives snapshot-at-$N-1$? **Yes**
- Economic cost of attack vs gain: **gas-only censorship / forced re-nonce; no direct profit**
- Duplicates Known Finding #? **No**

**Recommendation:**  
Bind proposal authorship into the proposal identity, e.g. compute proposal IDs from `(proposer, op, to, value, dataHash, nonce, config)` and require voting/opening against that proposer-bound hash.

---

### [INFORMATIONAL-3] Auto-futarchy can overcommit DAO-held local `Shares` / `Loot` across concurrent proposals

**Severity:** Informational  
**Confidence:** 78  
**Category:** Futarchy  
**Location:** `Moloch`, function `openProposal`, line(s) ~280-311; `cashOutFutarchy` ~496-519; `_payout` ~920-930

**Description:**  
When auto-futarchy is enabled and `rewardToken` is configured as the local `Shares` or `Loot` contract address, `openProposal` calculates `amt` from the DAO’s current local-token balance and increments `futarchy[id].pool`. However, it does not reserve that inventory globally. If several proposals are opened while the DAO still holds the same local token balance, each proposal can independently promise the same units. Later, `cashOutFutarchy` pays winners via `_payout`, which transfers against the live local token balance. This makes payouts effectively first-come-first-served: early claimants can consume the inventory, while later winning claimants revert until the DAO replenishes balances.

**Attack Path:**
1. DAO governance enables auto-futarchy and sets `rewardToken` to `address(shares)` or `address(loot)`.
2. Multiple proposals are opened before any claims are paid; each opening reads the same current DAO-held local balance and credits a separate `F.pool`.
3. Earlier proposals resolve and their winners claim first, draining the actual local token inventory.
4. Later winners call `cashOutFutarchy` and revert in `_payout` because the live balance is lower than the promised per-proposal pools.

**Disproof Attempt:**  
I tried to find any reservation accounting that would net already-promised local balances out of later auto-earmarks. I found none. `F.pool` is per-proposal only. There is also no debit of a global available balance when a proposal opens, and no distinction in `_payout` between earmarked and unearmarked local inventory. The issue therefore survives disproof. I did, however, apply the privileged-role rule: this mode only exists if DAO governance explicitly enables auto-futarchy with local `Shares`/`Loot`, so the final severity is heavily downgraded.

**Severity Justification:**
- Exploitable without DAO governance vote? **No**
- Survives `nonReentrant` guard? **Yes** — accounting issue, not reentrancy
- Survives snapshot-at-$N-1$? **N/A**
- Economic cost of attack vs gain: **early claimants can consume up to the DAO’s currently held local reward inventory; later winners face payout failure**
- Duplicates Known Finding #? **No**

**Recommendation:**  
Do not auto-earmark against live local `Shares` / `Loot` balances without reservation tracking. The minimal safe fix is to skip auto-futarchy earmarks when `rewardToken` is `address(shares)` or `address(loot)`.

---

## Category Coverage Matrix

| Category | Result | Defense Verified |
|---|---|---|
| 1. Reentrancy | No novel issues | EIP-1153 transient guard; `multicall` shares the same transient slot |
| 2. Flash Loan / Vote Manipulation | No novel issues | Snapshot fixed at block $N-1$; `getPastVotes` / `getPastTotalSupply` |
| 3. Governance Logic | **1 Low finding** | Timelock/state machine otherwise sound |
| 4. Economic / Ragequit | No novel issues | Sorted token array; pre-burn denominator; duplicate KF#2 excluded |
| 5. Futarchy | **1 Medium + 1 Informational finding** | Resolution math immutable; duplicates KF#4/#5/#6/#17 excluded |
| 6. Access Control | No novel issues | `onlyDAO`, permit SBT gate, effective one-shot init |
| 7. Token Sales | No novel issues | Cap/maxPay logic correct; duplicate KF#1 excluded |
| 8. Math / Precision | No novel issues | Conservative `mulDiv`; exact BPS sum enforcement |
| 9. External Token Integration | No novel issues | Safe transfer wrappers; duplicates KF#7/#8 excluded |
| 10. Delegation & Checkpoints | No novel issues | Exact split math, standard same-block checkpoint semantics |

---

## Invariant Verification

| Invariant | Result | Evidence |
|---|---|---|
| `Shares.totalSupply == sum(balanceOf)` | **Verified** | `Shares._mint`, `burnFromMoloch`, and `_moveTokens` update supply/balances consistently |
| ERC-6909 `totalSupply[id] == sum(balanceOf[*][id])` | **Verified** | `_mint6909` / `_burn6909` are balanced; transfers conserve supply |
| Proposal state machine monotonicity | **Verified** | `state()` transitions are one-way; no state reversal found |
| `executed[id]` is one-way | **Verified** | Only assignments found set it to `true`; never reset |
| Ragequit pro-rata conservation | **Verified** | Uses pre-burn denominator and per-token `$pool \cdot amt / total$` math |
| Futarchy payout immutability | **Verified** | `payoutPerUnit` is only written in `_finalizeFutarchy` while unresolved |
| No admin keys post-init | **Verified** | `onlyDAO` self-call model; `init` restricted to immutable `SUMMONER` |
| `supplySnapshot[id]` written once | **Verified** | Only assigned in `openProposal`, guarded by `snapshotBlock[id] == 0` |

---

## Architecture Assessment

This is a **stronger-than-average governance codebase** from a security-engineering perspective. The major fundamentals are good: vote snapshots are correctly anchored at block $N-1$, the transient-storage reentrancy guard is properly applied to the dangerous treasury/execution paths, the ragequit math is conservative, and the split-delegation checkpoint implementation is substantially cleaner than many bespoke governance forks.

The main residual risk comes from **feature composition**, not from low-level Solidity mistakes. In particular, the combination of hash-only proposal identities, public pre-vote opening, cancellability by first opener, and optional futarchy funding creates edge cases that ordinary Governor-style systems do not have. Relative to other governance frameworks, the core execution model is solid, but the futarchy and intent-hash flexibility expand the state space enough that a few lifecycle gaps remain.
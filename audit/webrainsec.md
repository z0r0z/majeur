# webrainsec: Moloch Majeur Security Audit

**Auditor:** webrainsec

**Date:** 2026-03-14

**Scope:** 
  * Moloch.sol (2,110 LOC)
  * DAICO.sol (1,425 LOC)
  * Tribute.sol (281 LOC)
  * SafeSummoner.sol (298 LOC)
  * MolochViewHelper.sol (1,247 LOC)
  * Renderer.sol (891 LOC)

**Compiler:** Solidity 0.8.30, Foundry, via_ir, Cancun EVM

## Review Summary

> **Reviewed 2026-03-15. No production blockers identified. Zero novel findings — all 20 findings are duplicates of known Moloch.sol core findings or previously identified peripheral contract issues.**
>
> - **20 findings total:** 2 High, 7 Medium, 11 Low. Scope covers Moloch.sol core plus DAICO.sol, Tribute.sol, SafeSummoner.sol, MolochViewHelper.sol, Renderer.sol.
> - **Moloch.sol core: 0 novel findings.** H-02 is KF#2 (dynamic quorum + minting sale + ragequit). M-01 is a new observation about `executeByVotes` return value semantics but is informational (callers are expected to call twice for timelocked proposals). M-02 is KF#16 (shared `executed[]` namespace). M-03 is KF#5 (vote receipt transferability breaks `cancelVote`). M-05 is a sharper framing of KF#3/KF#11 (auto-futarchy blocks cancel). M-06 compounds M-02 + M-05 (no novel root cause). M-07 is KF#21 (permit IDs enter proposal lifecycle). All Lows are duplicates of known findings.
> - **DAICO.sol findings (H-01, M-04, L-06, L-07):** H-01 (tap forfeiture) is a duplicate of Certora FV L-01, acknowledged as intentional Moloch exit-rights design. M-04 (USDT re-approval) targets the obsolete DAICO.sol contract (removed, replaced by modular peripherals). L-06 and L-07 also target obsolete DAICO.sol.
> - **Peripheral findings (L-05):** Tribute discovery array growth is a duplicate of Certora I-02.
> - **Report quality is strong.** Clear root-cause analysis, well-constructed PoCs with concrete output, and honest acknowledgment of prior art (H-01 note references Certora acknowledgment). The cross-feature interaction analysis (M-05, M-06) demonstrates good compositional reasoning. Severity calibration is reasonable — H-01 and H-02 are arguable but the auditor provides clear rationale.
> - **DAICO.sol is obsolete.** 4 of 20 findings target DAICO.sol, which has been removed and replaced by modular `SafeSummoner` + `ShareSale` + `TapVest` + `LPSeedSwapHook` peripherals. These findings are historically accurate but no longer applicable to the current codebase.

## Executive Summary

- Moloch Majeur has correct reentrancy protection (EIP-1153 transient storage), safe CEI ordering, and sound arithmetic. The risk surface is in economic interactions between features: ragequit + tap claims, share sales + ragequit, and shared state between permits and governance.
- The most critical finding is a permanent fund forfeiture bug in `DAICO.claimTap` that destroys unclaimed ops compensation with no recovery mechanism. Proven with Foundry PoC (25 ETH lost in test scenario).
- Most findings involve cross-feature interactions. Individually safe components produce unsafe outcomes when composed. The minting sale + ragequit treasury extraction (H-02), the permit/proposal shared namespace (M-02, M-06, M-07), and the auto-futarchy cancel deadlock (M-05) are the highest-priority fixes.

## Findings

| ID | Title | Severity |
|----|-------|----------|
| H-01 | `claimTap` forfeits unclaimed funds on partial claims | High |
| H-02 | Underpriced minting sale enables buy-ragequit treasury extraction | High |
| M-01 | `executeByVotes` returns success without executing on first timelock call | Medium |
| M-02 | Shared `executed[]` namespace lets permits preempt governance proposals | Medium |
| M-03 | Vote receipt transfer permanently locks voter's tally entry | Medium |
| M-04 | `ensureApproval` breaks for USDT-style tokens on re-approval | Medium |
| M-05 | `cancelProposal` permanently blocked when auto-futarchy is active | Medium |
| M-06 | Auto-futarchy + permit execution creates unresolvable governance bypass | Medium |
| M-07 | Proposal lifecycle accepts permit IDs without domain separation | Medium |
| L-01 | Auto-futarchy earmarks create unbounded dilution promises across proposals | Low |
| L-02 | `fundFutarchy` accepts funding after proposal is defeated | Low |
| L-03 | `buyShares` checked overflow reverts all purchases at extreme prices | Low |
| L-04 | Proposal state non-monotonicity: Succeeded can retroactively flip to Defeated | Low |
| L-05 | Tribute discovery arrays grow unboundedly, DoS on view calls | Low |
| L-06 | DAICO `buy()`/`buyExactOut()` excess ETH stuck in ZAMM on partial LP usage | Low |
| L-07 | `setupDAICO` validates caller against its own `dao` parameter, any address can self-authorize | Low |
| L-08 | Split delegation rounding concentrates extra voting power on last delegate | Low |
| L-09 | Checkpoint `uint96` caps total supply at ~79.2B shares, bricks minting on overflow | Low |
| L-10 | Zero `proposalThreshold` lets anyone spam proposals | Low |
| L-11 | Auto-earmarked futarchy funds stuck when proposal expires unfunded | Low |

**Total: 2 High, 7 Medium, 11 Low**

---

## H-01: `claimTap` forfeits unclaimed funds on partial claims, no recovery path

> **Review: Duplicate of Certora FV L-01 (tap forfeiture class). Severity adjusted to Low (acknowledged by-design behavior). Targets obsolete DAICO.sol.** The tap forfeiture root cause — `lastClaim` advances unconditionally on partial claims — was first identified by Certora FV (L-01) and independently confirmed by Winfunc (#4/#13) and Grimoire. The project team acknowledged this as intentional Moloch exit-rights design: ragequit is sacrosanct and can drain treasury below tap obligations. The auditor's own note (line 127) correctly references the Certora acknowledgment. The PoC is well-constructed and the economic reasoning is sound, but the behavior is documented and accepted. Additionally, **DAICO.sol has been removed** — replaced by modular `TapVest.sol` which shares the same design choice. The `TapVest` equivalent is documented as a V2 hardening candidate (add `unpaidAccrual` carry field). **Severity: Low (acknowledged design tradeoff, obsolete contract).**

**Target:** `DAICO.claimTap`
**Location:** `src/peripheral/DAICO.sol:806-811`

`claimTap` computes `owed = ratePerSec * elapsed`, then caps the payout to `min(owed, allowance, daoBalance)`. But `lastClaim` always advances to `block.timestamp` regardless of how much was actually paid:

```solidity
claimed = owed < allowance ? owed : allowance;
if (claimed > daoBalance) claimed = daoBalance;
if (claimed == 0) revert NothingToClaim();

tap.lastClaim = uint64(block.timestamp); // jumps forward even on partial claim
```

The difference `owed - claimed` is permanently destroyed. There is no accumulator, no deficit tracker, no mechanism to recover it.

**Root Cause**

`lastClaim` is a time cursor, not an accounting variable. It always advances to `block.timestamp`, so the next `claimTap` call computes `owed` only from the new baseline. Any unclaimed amount from the previous period is erased from the system. The `Tap` struct contains only `ops`, `tribTkn`, `ratePerSec`, and `lastClaim`, with no cumulative tracking.

**Reasoning**

1. DAICO tap is configured at 1 ETH/day for the ops team. Over 30 days, ops accrues ~30 ETH.
2. DAO members coordinate a ragequit, draining treasury from 100 ETH to 5 ETH.
3. `claimTap` is called: `owed = 30 ETH`, `daoBalance = 5 ETH`, so `claimed = 5 ETH`. `lastClaim` jumps 30 days forward.
4. Even if treasury recovers (new members join a share sale, donations), the 25 ETH gap is gone. The next `claimTap` only accrues from the jump point.

A majority coalition can ragequit before ops claims, destroying the ops team's accrued compensation while receiving their own full pro-rata treasury share. The same forfeiture occurs when the DAO's allowance to the DAICO contract is temporarily insufficient, a scenario the NatSpec does not document. `setTapRate` also forfeits accrued amounts, but that is an explicit governance action. The `claimTap` forfeiture requires no governance decision. It happens silently whenever `claimed < owed`.

**Impact**

Ops team loses accrued compensation permanently. In the PoC below, 25 ETH (83% of owed funds) is destroyed after a coordinated ragequit. The loss scales linearly with the claim gap and the treasury drawdown.

**PoC**

```solidity
// test/foundry/H01_TapForfeiture.t.sol // forge test --match-test test_H01 -vv
function test_H01_TapForfeiture_PermanentLoss() public {
    // Phase 1: Accrue 30 days of tap (~30 ETH owed)
    vm.warp(block.timestamp + 30 days);
    uint256 pendingBefore = daico.pendingTap(address(moloch)); // ~30 ETH

    // Phase 2: Bob + Alice ragequit, draining treasury from 100 ETH to ~5 ETH
    address[] memory tokens = new address[](1);
    tokens[0] = address(0);
    vm.prank(bob);
    moloch.ragequit(tokens, 40e18, 0);   // Bob takes 40 ETH
    vm.prank(alice);
    moloch.ragequit(tokens, 55e18, 0);   // Alice takes 55 ETH

    // Phase 3: Ops claims, gets 5 ETH instead of 30 ETH
    uint256 opsBefore = ops.balance;
    daico.claimTap(address(moloch));
    uint256 opsClaimed = ops.balance - opsBefore; // ~5 ETH

    // Phase 4: Replenish treasury, wait 1 day, only NEW accrual is claimable
    vm.deal(address(moloch), 100 ether);
    vm.warp(block.timestamp + 1 days);
    daico.claimTap(address(moloch)); // ~1 ETH (not 26 ETH)
    // PERMANENT LOSS: ~25 ETH
}
```

**Output**
```
Owed to ops:       29999999999999808000 (~30 ETH)
Actually claimed:   5000000000000000000 (5 ETH)
FORFEITED:         24999999999999808000 (~25 ETH)
Second claim:       999999999999993600  (~1 ETH)
PERMANENT LOSS:    24999999999999814400 (~25 ETH)
```

**Limitations:** The PoC uses a clean treasury drain via ragequit. In practice, treasury drawdowns can also come from proposal execution, other allowance spending, or LP operations. The forfeiture mechanism is the same regardless of the cause.

**Note:** The project team acknowledged this behavior as intentional in their Certora audit response (`audit/certora.md`, status: "Will not fix"), framing forfeiture as a Moloch exit-rights design property. The `setTapRate` NatSpec (L287) documents rate-change forfeiture as "non-retroactive." But the `claimTap` NatSpec itself does not disclose that partial claims permanently destroy the difference, and the forfeiture at `claimTap` is not a governance-initiated action. We maintain this as High because the loss is silent, irreversible, and requires no attacker.

**Fix**

Replace time-based tracking with a cumulative accumulator:

```diff
- claimed = owed < allowance ? owed : allowance;
- if (claimed > daoBalance) claimed = daoBalance;
- if (claimed == 0) revert NothingToClaim();
- tap.lastClaim = uint64(block.timestamp);
+ uint256 totalOwed = tap.totalOwed + owed;
+ uint256 claimable = totalOwed - tap.totalClaimed;
+ claimed = claimable < allowance ? claimable : allowance;
+ if (claimed > daoBalance) claimed = daoBalance;
+ if (claimed == 0) revert NothingToClaim();
+ tap.totalOwed = totalOwed;
+ tap.totalClaimed += claimed;
+ tap.lastClaim = uint64(block.timestamp);
```

**Affected files:** `src/peripheral/DAICO.sol`

---

## H-02: Underpriced minting sale enables buy-ragequit treasury extraction

> **Review: Duplicate of KF#2 (dynamic quorum + minting sale + ragequit). Severity adjusted to Low (governance-configured, economically constrained).** KF#2 documents this class: "Supply inflation via `buyShares` → ragequit after snapshot → quorum denominator manipulation. Economically constrained." The auditor's framing focuses on treasury extraction rather than quorum manipulation, but the root cause is identical — minting shares below NAV and ragequitting for pro-rata treasury. The privileged-role rule applies: governance sets both `pricePerShare` and `ragequittable`. A DAO voting to sell shares below NAV is a governance decision. SafeSummoner blocks the quorum variant (`MintingSaleWithDynamicQuorum`). The PoC assumes a 10x price discount — a scenario that requires governance to deliberately underprice shares. The auditor correctly notes this in limitations: "Requires `ragequittable == true` and a minting sale priced below NAV. Both are governance-controlled parameters." **Severity: Low (per KF#2, privileged-role rule).**

**Target:** `Moloch.buyShares`, `Moloch.ragequit`
**Location:** `src/Moloch.sol:706-756`, `src/Moloch.sol:759-797`

When `ragequittable == true` and a minting share sale has `pricePerShare < treasury_value / totalSupply`, an attacker buys shares at the sale price and ragequits for proportional treasury. No cooldown exists between buying and ragequitting.

**Root Cause**

`buyShares` (minting mode) creates new shares at a fixed price set by governance. `ragequit` distributes proportional treasury based on current share supply. When sale price is below net asset value per share, the gap is extractable. There is no lock period between share acquisition and ragequit eligibility.

**Reasoning**

1. Treasury: 1,000 ETH. Supply: 100e18. NAV: 10 ETH/share. Sale: 1 ETH/share (minting).
2. Attacker buys 100e18 shares for 100 ETH. Treasury: 1,100 ETH. Supply: 200e18.
3. Attacker ragequits 100e18 shares. Payout: `100/200 * 1,100 = 550 ETH`.
4. Profit: 550 - 100 = 450 ETH. Alice's remaining treasury: 550 ETH (was 1,000).

SafeSummoner blocks the quorum manipulation variant (`MintingSaleWithDynamicQuorum`) but not this economic extraction.

**Impact**

Attacker extracts 450 ETH from a 1,000 ETH treasury in a single block. Existing members (Alice) lose 45% of their treasury value. The attack scales linearly with the price discount. DAOs routinely run discounted share sales for fundraising, so every such sale becomes an extraction opportunity.

**PoC**

```solidity
// test/foundry/M04_BuyRagequitArb.t.sol // forge test --match-test test_M04 -vv
function test_M04_BuyRagequitArbitrage() public {
    // Treasury: 1000 ETH, Supply: 100e18, NAV: 10 ETH/share
    // Sale: 1 wei/unit = 1 ETH per 1e18 shares (10x below NAV)

    // Step 1: Buy 100e18 shares for 100 ETH
    vm.prank(attacker);
    moloch.buyShares{value: 100 ether}(address(0), 100e18, 0);
    // Treasury: 1100 ETH, Supply: 200e18

    // Step 2: Ragequit immediately, same block
    address[] memory tokens = new address[](1);
    tokens[0] = address(0);
    vm.prank(attacker);
    moloch.ragequit(tokens, 100e18, 0);
    // Attacker gets 550 ETH. Profit: 450 ETH.
}
```

**Output**
```
Treasury:          1000 ETH → 1100 ETH → 550 ETH
Attacker ETH:      1000 ETH → 900 ETH  → 1450 ETH
PROFIT:            450 ETH
Alice loss:        450 ETH (treasury dropped from 1000 to 550)
```

**Limitations:** Requires `ragequittable == true` and a minting sale priced below NAV. Both are governance-controlled parameters. The attack does not work for non-minting sales (DAO holds the shares, ragequit can't exceed treasury).

**Severity rationale (elevated from Medium):** `ragequittable = true` is the default Moloch configuration. Discounted minting sales are standard DAO fundraising practice. No cooldown exists between `buyShares` and `ragequit`, so the attack executes atomically in one transaction. `SafeSummoner` blocks the quorum manipulation variant (`MintingSaleWithDynamicQuorum`) but has no price-vs-NAV validation. `setSale` only checks `pricePerShare != 0`. The entire treasury can be drained proportionally to the discount in a single block with no MEV competition or oracle manipulation required.

**Fix**

Add a cooldown between share acquisition and ragequit eligibility:

```diff
+ mapping(address => uint256) public lastShareAcquisition;

  function buyShares(...) {
      ...
+     lastShareAcquisition[msg.sender] = block.number;
      ...
  }

  function ragequit(...) {
+     require(block.number > lastShareAcquisition[msg.sender], "cooldown");
      ...
  }
```

Or validate `pricePerShare >= ragequitValue` in `buyShares` when minting mode is active.

**Affected files:** `src/Moloch.sol`

---

## M-01: `executeByVotes` returns success without executing on first timelock call

> **Review: Valid observation. Severity adjusted to Informational.** The `return (true, "")` on queue is a reasonable observation about API semantics. However, the two-call pattern (queue then execute) is the documented behavior of timelocked governance — integrators are expected to call `executeByVotes` twice. The `Queued` event emitted on line 246 signals the queue action to callers. Changing to `return (false, "queued")` would break integrators that correctly interpret the first call as "queued successfully" vs "failed." The risk is limited to naive integrators who don't handle the timelock lifecycle. No fund loss, no governance bypass. **Severity: Informational (API semantics, not exploitable).**

**Target:** `Moloch.executeByVotes`
**Location:** `src/Moloch.sol:509-513`

When `timelockDelay != 0` and a Succeeded proposal is called for the first time, `executeByVotes` queues the proposal and returns `(true, "")` without executing:

```solidity
if (timelockDelay != 0) {
    if (queuedAt[id] == 0) {
        queuedAt[id] = uint64(block.timestamp);
        emit Queued(id, queuedAt[id]);
        return (true, ""); // success signal, but nothing executed
    }
```

**Root Cause**

The queuing branch returns `true` as the first element of the tuple. The return variable is named `ok` in the function signature. Any caller checking `(bool ok, ) = moloch.executeByVotes(...)` interprets this as successful execution.

**Reasoning**

1. A meta-governance contract (multisig, DAO-of-DAOs, automated keeper) calls `executeByVotes` and checks `ok == true`.
2. The call returns `(true, "")` because it only queued the proposal.
3. The integrator marks the action as complete. It never calls `executeByVotes` again after the timelock expires.
4. The proposal sits in the queue permanently, never executed. It could be a critical treasury operation, a config change, or a security patch that never takes effect.

**Impact**

Integrating contracts that rely on the boolean return value to determine execution status will misinterpret queue-only calls as successful execution. The proposal never runs.

**Fix**

```diff
- return (true, "");
+ return (false, "queued");
```

Or split into `queueProposal()` and `executeProposal()`.

**Affected files:** `src/Moloch.sol`

---

## M-02: Shared `executed[]` namespace lets permits preempt governance proposals

> **Review: Duplicate of KF#16 + KF#10. Severity accepted as Low.** KF#16: "`spendPermit` doesn't check `executed` flag — allows double-execution if DAO creates both proposal and permit with identical params. Requires two governance votes. `_burn6909` is the actual replay guard." KF#10: "Permit/proposal ID namespace overlap." The auditor correctly identifies the timelock bypass angle, but the precondition — the DAO creating both a proposal and a permit for the same intent — requires two separate governance votes. The `_burn6909` receipt burn is the real replay guard. V2 fix: use separate namespaces. **Severity: Low (per KF#16, requires two governance votes).**

**Target:** `Moloch.spendPermit`, `Moloch.executeByVotes`
**Location:** `src/Moloch.sol:668` vs `src/Moloch.sol:502`

Proposals and permits share the same `executed[]` mapping, keyed by `_intentHashId(op, to, value, data, nonce)`. `spendPermit` sets `executed[tokenId] = true` at L668 without checking the flag first. `executeByVotes` checks `if (executed[id]) revert AlreadyExecuted()` at L502:

```solidity
// spendPermit: sets executed, no AlreadyExecuted check
executed[tokenId] = true;
_burn6909(msg.sender, tokenId, 1);
(ok, retData) = _execute(op, to, value, data);

// executeByVotes: blocked if already executed
if (executed[id]) revert AlreadyExecuted();
```

**Root Cause**

Permits and proposals use the same namespace (`executed[]`) with the same key derivation (`_intentHashId`). A permit execution permanently blocks the governance path for the same intent.

**Reasoning**

1. Governance passes a proposal to send 100 ETH to address X with a 2-day timelock.
2. The same intent hash exists as a permit held by an authorized spender (`setPermit` is `onlyDAO`, so the DAO must have created both).
3. The spender calls `spendPermit` during the timelock period. `executed[id]` is set to `true`. The action executes immediately.
4. When the timelock expires, `executeByVotes` reverts with `AlreadyExecuted`. The governance path is permanently blocked for this intent.

The DAO created both the proposal and the permit. The permit holder is using an authorized path. But the timelock guarantee is violated: members expected a ragequit window, and the permit path bypasses it.

**Impact**

When a DAO creates both a timelocked proposal and a permit for the same intent, the permit holder can execute immediately, eliminating the ragequit window that the timelock was designed to provide. The risk is highest when the DAO governance creates permits and proposals through separate processes, e.g., an ops team requests permits while governance independently proposes the same action.

**Fix**

```diff
+ if (executed[tokenId]) revert AlreadyExecuted();
  executed[tokenId] = true;
  _burn6909(msg.sender, tokenId, 1);
```

Or use separate namespaces: `executedProposal[id]` and `executedPermit[id]`.

**Affected files:** `src/Moloch.sol`

---

## M-03: Vote receipt transfer permanently locks voter's tally entry

> **Review: Duplicate of KF#5. Severity accepted as Low.** KF#5: "Vote receipt transferability breaks `cancelVote` — transferred receipts → original voter can't cancel (underflow). Voluntary user action." First identified by Pashov Skills as a novel finding. The key defense: this is a voluntary user action — the voter chose to transfer their receipts. Receipt transferability is intentional for futarchy (receipts are prediction market claim tokens). **Severity: Low (per KF#5, voluntary user action).**

**Target:** `Moloch.cancelVote`, `Moloch.transfer`
**Location:** `src/Moloch.sol:394-416`, `src/Moloch.sol:915-923`

Vote receipts (ERC6909 tokens) are transferable. Only permit receipts have SBT restrictions. When a voter transfers their receipts to another address, `cancelVote` reverts because `_burn6909(msg.sender, rid, weight)` underflows. The voter's tally entry (`hasVoted`, `voteWeight`, tally counts) is permanently locked.

**Root Cause**

`cancelVote` burns receipts from `msg.sender`, but if the voter transferred them, the burn underflows. The tally entry has no alternative cleanup path.

**Reasoning**

1. Alice votes FOR a proposal, receiving receipt tokens.
2. Alice transfers her receipts to Bob (valid ERC6909 transfer).
3. Alice calls `cancelVote`. `_burn6909(alice, rid, weight)` reverts because alice's balance is 0.
4. Alice's FOR vote is permanently locked in the tally. She cannot undo it.

**Impact**

Voters who transfer receipts lose the ability to cancel their votes. The vote weight remains in the tally permanently. Receipt transferability is intentional for futarchy (receipts function as prediction market claim tokens). But transferring receipts breaks `cancelVote`, and this interaction is undocumented.

**Fix**

Document that transferring vote receipts forfeits cancel rights. Or allow partial cancellation proportional to remaining receipt balance.

**Affected files:** `src/Moloch.sol`

---

## M-04: `ensureApproval` breaks for USDT-style tokens on re-approval

> **Review: Not a real bug even on the obsolete DAICO.sol. Severity: Not applicable.** The re-approval path requires the allowance to drop below `type(uint128).max`, but `ensureApproval` sets it to `type(uint256).max` on the first call. Since `type(uint256).max` is astronomically large, normal `transferFrom` consumption cannot realistically reduce it below the `uint128.max` threshold — it would take 2^128 individual max-amount transfers. The re-approval branch is dead code in practice: once the allowance is set to max, it stays above the threshold permanently. The auditor's trigger scenario ("external `approve` resets it") would require a separate governance action that doesn't exist in the DAICO code path. Additionally, **DAICO.sol has been removed** from the codebase. **Severity: Not applicable (unreachable code path, obsolete contract).**

**Target:** `DAICO.ensureApproval`
**Location:** `src/peripheral/DAICO.sol:1400-1425`

`ensureApproval` checks if the current allowance is below `type(uint128).max` and calls `approve(spender, type(uint256).max)` directly. The code comment at L1395 claims USDT compatibility, but USDT reverts on `approve(spender, newAmount)` when the current allowance is non-zero and `newAmount` is non-zero. The function does not reset to zero first:

```solidity
// Sets max approval directly, no zero-first reset
mstore(0x14, spender)
mstore(0x34, not(0)) // type(uint256).max
mstore(0x00, 0x095ea7b3000000000000000000000000)
success := call(gas(), token, 0, 0x10, 0x44, 0x00, 0x20)
```

**Root Cause**

The function skips the `approve(spender, 0)` step required by USDT-style tokens before setting a new non-zero approval.

**Reasoning**

1. DAICO's LP integration calls `ensureApproval(usdtToken, zammAddress)`. First call succeeds (allowance was 0 → max).
2. ZAMM consumes allowance via `transferFrom`, reducing it. For most scenarios, it stays above `uint128.max` and `ensureApproval` is a no-op.
3. If allowance drops below `uint128.max` (e.g., external `approve` resets it, or a governance action changes the threshold), `ensureApproval` calls `approve(zamm, max)` with current allowance > 0. USDT reverts.
4. All subsequent DAICO LP buys revert. The LP path is bricked for that token.

**Impact**

DAICO's LP functionality breaks permanently for USDT and similar tokens if the re-approval path is triggered. The code comment at L1395 explicitly claims USDT compatibility, misleading deployers into using USDT with the LP integration.

**Fix**

```diff
+ // Zero-first approval for USDT compatibility
+ mstore(0x14, spender)
+ mstore(0x34, 0)
+ mstore(0x00, 0x095ea7b3000000000000000000000000)
+ pop(call(gas(), token, 0, 0x10, 0x44, 0x00, 0x20))
+
  mstore(0x14, spender)
  mstore(0x34, not(0))
  mstore(0x00, 0x095ea7b3000000000000000000000000)
  success := call(gas(), token, 0, 0x10, 0x44, 0x00, 0x20)
```

Or use Solady's `safeApproveWithRetry`.

**Affected files:** `src/peripheral/DAICO.sol`

---

## M-05: `cancelProposal` permanently blocked when auto-futarchy is active

> **Review: Variant of KF#3 + KF#11. Severity adjusted to Low.** This is a sharper framing of a known interaction: auto-futarchy earmarks (`F.pool > 0`) block `cancelProposal`. The auditor correctly identifies that the cancel window is eliminated when auto-futarchy is active. However, the cancel guard (`F.pool != 0`) is intentional — it prevents cancellation of proposals that have attracted real futarchy investment. The auto-futarchy earmark is a governance-configured feature (`autoFutarchyParam` set via `onlyDAO`). Proposers can use `multicall` to batch `openProposal` + `castVote` atomically, which effectively replaces cancel-before-vote as a safety mechanism. The proposer can also resubmit with a different nonce. **Severity: Low (design tradeoff, governance-configured).**

**Target:** `Moloch.cancelProposal`
**Location:** `src/Moloch.sol:419-431`

`cancelProposal` requires `F.pool == 0` (L428). But `openProposal` auto-earmarks futarchy funds when `autoFutarchyParam != 0` (L336: `F.pool += amt`). Since `castVote` auto-opens proposals, and auto-futarchy immediately sets `pool > 0`, no proposal can be cancelled once auto-futarchy is configured:

```solidity
// cancelProposal: requires zero pool
FutarchyConfig memory F = futarchy[id];
if (F.enabled && F.pool != 0) revert NotOk();

// openProposal: auto-earmarks on open
if (amt != 0) {
    F.pool += amt; // pool > 0 from the moment a proposal is opened
}
```

**Root Cause**

The `pool == 0` guard was designed for manually-funded futarchy. Auto-futarchy bypasses it by funding at open time, before the proposer has any window to cancel. Even batching `openProposal` + `cancelProposal` via `multicall` fails because the earmark runs synchronously during `openProposal`.

**Impact**

Proposers lose their safety valve. They cannot withdraw a flawed or accidentally submitted proposal even when zero votes have been cast. The proposal runs to completion (or expiry) regardless. With auto-futarchy active, this affects every proposal in the DAO.

**Fix**

Allow cancellation when no votes have been cast, regardless of futarchy pool. Return earmarked funds on cancellation:

```diff
- if (F.enabled && F.pool != 0) revert NotOk();
+ // Allow cancel if no votes cast, return auto-earmarked funds
  executed[id] = true;
+ if (F.enabled && F.pool != 0) {
+     futarchy[id].pool = 0; // write to storage, not memory copy
+ }
```

**Affected files:** `src/Moloch.sol`

---

## M-06: Auto-futarchy + permit execution creates unresolvable governance bypass

> **Review: Compound of M-02 + M-05 (no novel root cause). Severity adjusted to Low.** This chains KF#16 (shared `executed[]` namespace) with M-05 (auto-futarchy blocks cancel) to show a stranded futarchy pool scenario. The composition is valid but requires the same precondition as M-02: the DAO must create both a proposal and a permit for the same intent via two separate governance votes. The stranded futarchy pool remains in the DAO treasury — no fund loss, just bookkeeping. **Severity: Low (compound of known findings, no novel root cause).**

**Target:** `Moloch.spendPermit`, `Moloch.cancelProposal`, futarchy resolution
**Location:** `src/Moloch.sol:659-676`, `src/Moloch.sol:306-341`, `src/Moloch.sol:419-431`

Three issues compound: (a) permits preempt governance via shared `executed[]` (M-02), (b) proposals can't be cancelled with auto-futarchy (M-05), (c) futarchy pools strand when the permit path short-circuits governance.

**Root Cause**

When a permit holder executes via `spendPermit`, `_resolveFutarchyYes` is called (L674). But the governance path (which would have resolved futarchy normally) is now blocked by `AlreadyExecuted`. The futarchy pool sits in limbo: resolved (if futarchy was enabled on the permit) or permanently unresolvable (if the governance proposal had futarchy but the permit path did not trigger it).

**Reasoning**

1. DAO has `autoFutarchyParam != 0` and `timelockDelay = 2 days`.
2. Governance passes a proposal. Auto-futarchy earmarks reward tokens. Members vote, creating futarchy receipts.
3. During the 2-day timelock, a permit holder calls `spendPermit` with the same intent hash. The action executes. `executed[id] = true`.
4. After timelock expires, `executeByVotes` reverts (`AlreadyExecuted`). `_resolveFutarchyYes` from the governance path never runs.
5. If the permit-side futarchy resolution differs from the governance-side (different `enabled` state), the governance futarchy pool is stranded. Winners on the governance futarchy cannot cash out.

**Impact**

Futarchy participants lose their expected payouts. Members lose their ragequit window (the permit bypasses the timelock). The compound of M-02 + M-05 makes this worse: the proposal can't be cancelled (M-05) and can't be executed via governance (M-02).

**Fix**

Use separate execution namespaces for proposals and permits. Or check and resolve futarchy in `spendPermit` for the governance proposal's futarchy config when the intent hashes match.

**Affected files:** `src/Moloch.sol`

---

## M-07: Proposal lifecycle accepts permit IDs without domain separation

> **Review: Duplicate of KF#21 (Cantina MAJEUR-21). Severity accepted as Medium.** KF#21: "Permit IDs enter proposal/futarchy lifecycle — `openProposal`, `castVote`, `fundFutarchy`, `resolveFutarchyNo` never check `isPermitReceipt[id]`." First discovered by Cantina Apex. The V1.5 assessment documents containment: bounded by `autoFutarchyCap`, requires `proposalThreshold` worth of shares, one-shot per permit ID. V2 fix: add `if (isPermitReceipt[id]) revert` guards. **Severity: Medium (per KF#21).**

**Target:** `Moloch.openProposal`, `Moloch.castVote`, `Moloch.fundFutarchy`, `Moloch.resolveFutarchyNo`
**Location:** `src/Moloch.sol:278`, `src/Moloch.sol:347`, `src/Moloch.sol:530`, `src/Moloch.sol:573`

`openProposal`, `castVote`, `fundFutarchy`, and `resolveFutarchyNo` accept raw `uint256` IDs without checking `isPermitReceipt[id]`. Permit token IDs (derived from `_intentHashId`) can be fed into the proposal lifecycle, creating cross-domain state overlap between two governance mechanisms that should be independent.

**Root Cause**

Proposals and permits share the `_intentHashId` namespace. Only `setPermit` (L630) and `spendPermit` (L666) check `isPermitReceipt[id]`. The proposal lifecycle functions assume all IDs are proposals.

**Reasoning**

1. DAO creates a permit via `setPermit(spender, op, to, value, data, nonce, count)`. The permit's tokenId is `_intentHashId(op, to, value, data, nonce)`.
2. Any shareholder calls `openProposal(tokenId)`. Proposal state (`snapshotBlock`, `createdAt`, `proposerOf`) is written to the permit's ID.
3. Votes are cast on the permit ID via `castVote(tokenId, support)`. Futarchy can be attached via `fundFutarchy`.
4. The permit and proposal lifecycles now share state under the same ID. `spendPermit` can still execute (it doesn't check proposal state), and `executeByVotes` re-derives the same ID.
5. Both governance execution and permit execution can fire on the same ID, so the underlying action executes twice.

**Impact**

Cross-domain state contamination between permits and proposals. Futarchy pools attached to permit IDs become unresolvable through normal governance paths. The action behind the shared ID can be double-executed: once via `executeByVotes` (if the "proposal" passes) and once via `spendPermit`.

**Fix**

Add `isPermitReceipt[id]` checks to proposal lifecycle functions:

```diff
  function openProposal(uint256 id) public {
+     require(!isPermitReceipt[id], NotOk());
      ...

  function castVote(uint256 id, uint8 support) public {
+     require(!isPermitReceipt[id], NotOk());
      ...

  function fundFutarchy(uint256 id, address token, uint256 amount) public payable {
+     require(!isPermitReceipt[id], NotOk());
      ...
```

**Affected files:** `src/Moloch.sol`

---

## Low Findings

### L-01: Auto-futarchy earmarks create unbounded dilution promises across proposals

> **Review: Duplicate — auto-futarchy overcommit pattern found by 9+ prior audits (Octane, Pashov, Forefy, QuillShield, ChatGPT, ChatGPT Pro, Qwen, Archethect V2, Almanax, Grimoire, Solarizer, Ackee, Winfunc). KF#3 documents this as Design.** Mitigated by `autoFutarchyCap` (per-proposal bound) and minted-token path which mints on demand. **Severity: Low (per KF#3).**

**Target:** `Moloch.openProposal`
**Location:** `src/Moloch.sol:306-341`

When `rewardToken = address(this)` or `address(1007)` (mint-based rewards), auto-futarchy earmarks pool amounts from `balanceOf(address(this))` without locking tokens. Each new proposal earmarks the same pool. If multiple proposals resolve, only the first claimants succeed and later ones revert on insufficient balance. The `autoFutarchyCap` bounds per-proposal amounts but not the total outstanding.

### L-02: `fundFutarchy` accepts funding after proposal is defeated

> **Review: Duplicate of KF#18. Severity accepted as Low.** KF#18: "`fundFutarchy` accepts executed/cancelled proposal IDs." The L-02 variant (funding after Defeated but before `resolveFutarchyNo`) is a subset of the same root cause. Funds are not permanently lost — they remain in the DAO contract. V2 fix: add `if (executed[id]) revert`. **Severity: Low (per KF#18).**

**Target:** `Moloch.fundFutarchy`
**Location:** `src/Moloch.sol`

Between a proposal being Defeated (per `state()`) and `resolveFutarchyNo` being called, `fundFutarchy` still accepts contributions. Funders contribute to a pool that will resolve to the losing side. The funds are not lost (returned via `cashOutFutarchy`) but the contributor wasted gas and locked capital unnecessarily.

### L-03: `buyShares` checked overflow reverts all purchases at extreme prices

> **Review: Valid observation. Severity accepted as Low.** Checked arithmetic overflow on extreme `pricePerShare` is a governance-configured edge case. The privileged-role rule applies — governance sets the price. Similar to Winfunc #20 (ShareSale pricing overflow). **Severity: Low (governance-configured).**

**Target:** `Moloch.buyShares`
**Location:** `src/Moloch.sol:719`

`cost = shareAmount * price` uses checked arithmetic. A DAO that sets `pricePerShare` to a very large value inadvertently DoS-es all share purchases because every call reverts on overflow.

### L-04: Proposal state non-monotonicity: Succeeded can flip to Defeated

> **Review: Duplicate of KF#15 (post-queue voting, by design). Severity accepted as Low.** The non-monotonic state transition is the intended last-objection window documented in KF#15. First identified by Claude (Opus 4.6). The auditor correctly notes "This is by design." **Severity: Low (per KF#15, design tradeoff).**

**Target:** `Moloch.state`
**Location:** `src/Moloch.sol:433+`

If `quorumAbsolute` or `minYesVotesAbsolute` is increased via governance while a proposal is Active/Succeeded, the proposal retroactively becomes Defeated. This is by design (governance config bump invalidates stale proposals) but integrators checking `state()` in sequential blocks will see a non-monotonic transition.

### L-05: Tribute discovery arrays grow unboundedly

> **Review: Duplicate of Certora I-02 (unbounded Tribute arrays). Severity accepted as Low.** Previously identified by Certora FV as Informational. View-layer only — no state-changing function iterates these arrays. Also related to Winfunc #21/#23 (Tribute discovery spam). **Severity: Low (per Certora I-02, view-layer DoS).**

**Target:** `Tribute` contract
**Location:** `src/peripheral/Tribute.sol:100-102`

`daoTributeRefs` and `proposerTributeRefs` are push-only. Cancelled and claimed tributes leave stale entries. `getActiveDaoTributes` iterates all entries, causing gas DoS on view calls over time. No state-changing function iterates these arrays, so this is view-layer only.

### L-06: DAICO `buy()`/`buyExactOut()` excess ETH stuck in ZAMM

> **Review: Targets obsolete DAICO.sol. Severity: Informational.** DAICO.sol has been removed from the codebase. The modular replacement (`LPSeedSwapHook`) does not share this code path. **Severity: Informational (obsolete contract).**

**Target:** `DAICO.buy`, `DAICO.buyExactOut`
**Location:** `src/peripheral/DAICO.sol`

If `ZAMM.addLiquidity` uses less ETH than sent via `{value: ethValue}`, the excess depends on ZAMM's refund behavior. If ZAMM does not refund, ETH is trapped in the ZAMM contract with no recovery path from DAICO.

### L-07: `setupDAICO` access check is self-referential

> **Review: Targets obsolete DAICO.sol. Severity: Informational.** DAICO.sol has been removed. The auditor correctly notes the impact is limited because the DAO must separately approve token spending. **Severity: Informational (obsolete contract).**

**Target:** `DAICO.setupDAICO`
**Location:** `src/peripheral/DAICO.sol`

The function checks `require(msg.sender == dao)` where `dao` is a parameter. Any address can call `setupDAICO(theirOwnAddress, ...)` and pass the check. The impact is limited because the DAO must separately approve token spending for the configuration to be usable, but it pollutes storage with arbitrary sale configs.

### L-08: Split delegation rounding concentrates extra voting power on last delegate

> **Review: Related to KF#24 (Auron — split delegation rounding). Severity accepted as Low.** The "remainder to last delegate" behavior is the same `_targetAlloc` rounding mechanism documented in KF#24. The bias is deterministic but sub-wei in magnitude with 18-decimal tokens. **Severity: Low (per KF#24, dust-level impact).**

**Target:** `Moloch._targetAlloc`
**Location:** `src/Moloch.sol`

`_targetAlloc` gives the division remainder to the last delegate in the array. With 4 delegates at 25% each and 100 tokens, the last delegate gets the dust from 3 rounding operations. The bias is deterministic and always favors the same position.

### L-09: Checkpoint `uint96` caps total supply at ~79.2B shares

> **Review: Related to SafeSummoner KF#1 (uint96 truncation). Severity accepted as Low.** The `uint96` cap is a known architectural constraint. SafeSummoner's `_defaultThreshold` saturating cap (patched) addresses the downstream threshold truncation. The 79.2B share ceiling is sufficient for all realistic deployments. **Severity: Low (known constraint).**

**Target:** `Moloch._writeCheckpoint`
**Location:** `src/Moloch.sol:1543`, `src/Moloch.sol:1974-1977`

All voting power is stored as `uint96` (max ~7.9e28). The `toUint96` safe cast reverts on overflow. Any share mint pushing `totalSupply` past `type(uint96).max` bricks all share operations. With 18-decimal shares, the cap is ~79.2 billion shares. Sufficient for most DAOs but reachable by aggressive minting sales or auto-futarchy mint rewards.

### L-10: Zero `proposalThreshold` lets anyone spam proposals

> **Review: Duplicate of KF#11. Severity accepted as Low.** KF#11: "`proposalThreshold == 0` griefing." The most widely confirmed finding across all audits. SafeSummoner enforces `proposalThreshold > 0`. The auditor correctly notes SafeSummoner protection. **Severity: Low (per KF#11, configuration-dependent).**

**Target:** `Moloch.openProposal`
**Location:** `src/Moloch.sol:283-286`

`openProposal` only checks voting power when `proposalThreshold != 0`:

```solidity
uint96 threshold = proposalThreshold;
if (threshold != 0) {
    require(_shares.getVotes(msg.sender) >= threshold, Unauthorized());
}
```

When the threshold is zero, any address can create proposals without holding shares. SafeSummoner validates `proposalThreshold > 0` at deployment (`src/SafeSummoner.sol:166`), so DAOs deployed through the standard path are protected. DAOs deployed via direct `init()` calls or that later call `setProposalThreshold(0)` lose this guard and become vulnerable to proposal spam that wastes voter attention and gas.

### L-11: Auto-earmarked futarchy funds stuck when proposal expires unfunded

> **Review: Duplicate of KF#6 (zero-winner futarchy lockup). Severity accepted as Low.** KF#6: "If no one votes for winning side, pool tokens are permanently inaccessible via `cashOutFutarchy`. Funds remain in DAO treasury." The auto-earmark variant is the same outcome — funds stay in the DAO contract and can be recovered via governance. First identified by Pashov Skills. **Severity: Low (per KF#6, funds remain in DAO treasury).**

**Target:** `Moloch.openProposal`, `Moloch.resolveFutarchyNo`, `Moloch.cashOutFutarchy`
**Location:** `src/Moloch.sol:335-336`, `src/Moloch.sol:573-580`

When a proposal with `autoFutarchy = true` is created, `openProposal` earmarks funds into the futarchy pool at line 336 (`F.pool += amt`) but creates no funder record or receipt tokens for the auto-earmarked portion. If the proposal is defeated or expires without reaching quorum, `resolveFutarchyNo` resolves the pool but the auto-earmarked portion has no claimant because `cashOutFutarchy` requires burning receipt tokens to withdraw, and no tokens were minted for the auto portion. SafeSummoner mitigates the most common trigger (premature defeat from low quorum) by enforcing non-zero quorum at deployment, but the funds remain permanently stuck for proposals that expire after the voting period.

---

*webrainsec.io / @webrainsec*

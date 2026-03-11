# [Qwen](https://chat.qwen.ai/) — Moloch.sol

**Prompt:** [`SECURITY.md`](../SECURITY.md) (3-round methodology: systematic → economic → adversarial triager)
**Type:** AI audit guided by accumulated methodology from 15 prior audit tools
**Model:** Qwen3.5-Plus

## Review Summary

> **Reviewed 2026-03-11. No novel findings. All three findings are duplicates.**
>
> - **MEDIUM-1 is a duplicate of KF#5** (vote receipt transferability breaks cancelVote). The report correctly identifies this as KF#5 in its own severity justification ("Duplicates Known Finding #? Yes: #5") but contradictorily claims "Novel: 2" in the executive summary. The finding is well-described with correct line references and a clear attack path, but it was first identified by Pashov and is a catalogued known finding.
> - **LOW-2 is a duplicate** of the auto-futarchy overcommit issue previously identified by Pashov #3, Octane #9, Forefy #1, and QuillShield SID-1. The report claims "Novel, but related to #3" — this is incorrect. While it's not one of the 17 numbered KFs, it was found by 4 prior audits. The same issue was correctly tagged as duplicate when ChatGPT's LOW-2 surfaced it. The analysis is competent — correctly identifies that `F.pool += amt` is accounting-only with no actual token locking — but the novelty claim is wrong.
> - **LOW-3 correctly identifies as duplicate of KF#1** (sale cap sentinel collision). Clean cross-reference.
> - **Invariant #3 ("Proposal state machine transitions: Verified") is wrong.** ChatGPT's MEDIUM-1 (KF#17) demonstrated that `state()` is non-monotonic — returns `Defeated` before expiry with zero quorum, then can flip to `Succeeded` after votes arrive. Qwen missed this entirely, same error as DeepSeek.
> - **Round 2 identified the overcommit issue but missed the more critical interactions.** The public futarchy freeze (KF#17), post-queue voting (KF#15), and proposalThreshold griefing (KF#11) were all missed. The "novel finding" label on Interaction 2 is incorrect given 4 prior audits found the same issue.
> - **Overall quality is competent but unremarkable.** The Round 1 category sweep is thorough — correctly verifies defenses across all 10 categories with specific line references. The adversarial validation in Round 3 is well-structured with proper disproof attempts. The architecture assessment is reasonable. But zero novel findings from 3 total, with an inflated self-assessment of "Novel: 2", suggests overconfidence in novelty screening. The report follows the SECURITY.md methodology faithfully — the issue is analytical depth, not methodology compliance.

## Executive Summary

| Metric | Count |
|--------|-------|
| **Total Findings** | 3 (Novel: 0, Duplicate: 3) |
| **Critical** | 0 |
| **High** | 0 |
| **Medium** | 1 |
| **Low** | 1 |
| **Informational** | 1 |
| **Highest-Confidence Finding** | Futarchy Receipt Transfer Race at 85% |

---

## Round 1: Systematic Code Review

### 1. Reentrancy

**Conclusion:** No issues found — EIP-1153 transient storage guard covers all external-call paths.

**Defense Verified:** The `nonReentrant` modifier (lines 838-850) uses `TSTORE`/`TLOAD` on slot `0x929eee149b4bd21268`. Functions with external calls that are guarded:
- `executeByVotes` (line 502) — ✓ guarded
- `cashOutFutarchy` (line 567) — ✓ guarded
- `buyShares` (line 658) — ✓ guarded
- `ragequit` (line 708) — ✓ guarded
- `spendPermit` (line 621) — ✓ guarded
- `spendAllowance` (line 642) — ✓ guarded

**Multicall Analysis:** `multicall` (line 809) uses `delegatecall` but is NOT guarded by `nonReentrant`. However, `multicall` is `onlyDAO` restricted and sub-calls execute within the same context — the transient storage slot remains set throughout the delegatecall chain. No bypass possible.

**Read-Only Reentrancy:** View functions (`state`, `getPastVotes`, etc.) cannot modify state during callbacks. No issues.

---

### 2. Flash Loan / Vote Manipulation

**Conclusion:** No issues found — snapshot at `block.number - 1` prevents same-block voting.

**Defense Verified:** In `openProposal` (line 289), `snapshotBlock[id] = toUint48(block.number - 1)`. In `castVote` (line 337), `shares.getPastVotes(msg.sender, snap)` reads checkpointed balance at the snapshot block. Per `Shares.getPastVotes` (line 1238), if `blockNumber >= block.number` it reverts with `BadBlock()`. An attacker acquiring shares in block N cannot vote on a proposal snapshotted at N-1.

**Checkpoint Overwriting:** Multiple transfers in one block update the same checkpoint (line 1326: `if (last.fromBlock == blk) { last.votes = toUint96(newVal); return; }`). This is correct behavior — the final balance at block end is what matters for N-1 snapshots.

---

### 3. Governance Logic

**Conclusion:** One medium-severity finding identified (see Confirmed Findings).

**State Machine Trace:** `state()` (lines 444-478) correctly implements:
- `Unopened` → `Active` (on `openProposal` or first `castVote`)
- `Active` → `Succeeded`/`Defeated`/`Expired` (on TTL or vote evaluation)
- `Succeeded` → `Queued` (on `queue`)
- `Queued` → `Executed` (on `executeByVotes` after timelock)

**Auto-Open Race:** `castVote` auto-opens via `openProposal` if `createdAt[id] == 0` (line 329). This is atomic within the same transaction — no ordering issue.

**Cancel Proposal:** `cancelProposal` (line 375) requires `proposerOf[id] == msg.sender` AND zero tally. After `castVote` auto-opens and records a vote, tally is non-zero — cancel correctly reverts.

**Config Bump:** `bumpConfig()` (line 797) increments `config`, which is included in `_intentHashId` (line 874). This invalidates both proposal IDs AND permit IDs — coverage confirmed.

**Timelock Bypass:** `executeByVotes` (line 502) checks `state(id)` which returns `Queued` if timelock delay hasn't passed (line 456). Cannot bypass.

---

### 4. Economic / Ragequit

**Conclusion:** No issues found — pro-rata math is conservative and sorted array prevents duplicates.

**Defense Verified:** `ragequit` (lines 708-756):
- Burns shares/loot BEFORE distribution (lines 727-730)
- Computes `due = mulDiv(pool, amt, total)` where `total = shares.totalSupply() + loot.totalSupply()` (lines 725-726, 743)
- Sorted array check (lines 738-740: `if (i != 0 && tk <= prev) revert NotOk()`) prevents duplicates
- Caller can omit problematic tokens (Known Finding #7)

**Force-Fed ETH:** Attacker donating ETH via `selfdestruct` benefits all ragequitters proportionally — economically irrational attack (False Positive Pattern).

**Supply Inflation:** Known Finding #2 covers minting sale + ragequit quorum manipulation — confirmed duplicate.

---

### 5. Futarchy

**Conclusion:** One medium-severity finding identified (see Confirmed Findings).

**Payout Calculation:** `cashOutFutarchy` (lines 567-582) burns receipts then pays `payout = mulDiv(amount, F.payoutPerUnit, 1e18)`. `payoutPerUnit` is set in `_finalizeFutarchy` (lines 593-604): `ppu = mulDiv(pool, 1e18, winSupply)`.

**Zero Winner Supply:** If `winSupply == 0`, `payoutPerUnit` remains 0 (line 600: `if (winSupply != 0 && pool != 0)`). Funds remain in DAO treasury — Known Finding #6 confirms this is expected behavior.

**Receipt Transferability:** ERC-6909 receipts from `castVote` ARE transferable (line 888: `transfer` only reverts if `isPermitReceipt[id]`). This creates a potential race condition (see Confirmed Findings).

**Auto-Futarchy Overcommit:** `autoFutarchyParam` earmarks from DAO balance (lines 308-330). Multiple proposals can earmark the same pool — but actual payout only occurs on resolution. Known Finding #3 confirms pools are drainable via ragequit by design.

---

### 6. Access Control

**Conclusion:** No issues found — `onlyDAO` pattern is consistent and SBT check is enforced.

**Defense Verified:** `onlyDAO` modifier (lines 33-36): `require(msg.sender == address(this))`. All configuration functions use this.

**Delegatecall Context:** `_execute` with `op == 1` (delegatecall) runs in DAO context — `msg.sender` remains the original caller, but `address(this)` remains the DAO. `onlyDAO` checks `msg.sender == address(this)`, so a delegatecall cannot impersonate the DAO for subsequent `onlyDAO` calls.

**Permit SBT:** `transfer` and `transferFrom` (lines 888-906) both check `if (isPermitReceipt[id]) revert SBT()`. `spendPermit` (line 621) requires `isPermitReceipt[tokenId]` — consistent enforcement.

**Init Double-Call:** `init()` (line 169) checks `require(msg.sender == SUMMONER)` where `SUMMONER` is immutable (line 62). `Shares.init`, `Loot.init`, `Badges.init` all check `require(DAO == address(0))` — cannot be called twice.

---

### 7. Token Sales

**Conclusion:** One low-severity finding confirmed as duplicate (Known Finding #1).

**Cap Logic:** `buyShares` (lines 658-697): `if (cap != 0 && shareAmount > cap) revert` (line 667). After `s.cap = cap - shareAmount` (line 674), if cap reaches exactly 0, the sale shows as "exhausted" but 0 also means "unlimited" per the `Sale` struct semantics. **This is Known Finding #1** — confirmed duplicate.

**Ragequit Race:** Non-minting mode transfers from DAO balance. `ragequit` burns shares but doesn't touch DAO's share holdings. No race condition on the same shares.

**MaxPay Check:** Line 669: `if (maxPay != 0 && cost > maxPay) revert NotOk()`. Applied uniformly for ETH and ERC-20 — correct.

---

### 8. Math / Precision

**Conclusion:** No issues found — `mulDiv` uses overflow-checked assembly, rounding is consistent floor.

**Defense Verified:** `mulDiv` (lines 949-958):
- Multiplies first: `z := mul(x, y)`
- Overflow check: `if iszero(mul(or(iszero(x), eq(div(z, x), y)), d))` — verifies `x * y / d` didn't overflow
- Division by zero: if `d == 0`, the `mul(..., d)` returns 0, triggering revert
- Rounding: floor division (standard `div`)

**Ragequit Dust:** `mulDiv(pool, burnAmount, totalSupply)` floors. Dust accumulates in DAO treasury — cannot be exploited via repeated partial ragequits (each ragequit uses current `totalSupply`).

**Uint96 Votes:** `type(uint96).max ≈ 7.92 × 10^28`. With 18 decimals, this supports ~79 billion tokens — sufficient for any realistic DAO.

**Split Delegation:** `setSplitDelegation` (lines 1263-1293) enforces `require(sum == BPS_DENOM)` where `BPS_DENOM = 10_000` (line 1119). Exact sum required — no rounding errors.

---

### 9. External Token Integration

**Conclusion:** No issues found — caller controls token array, fee/rebase risks are documented.

**Blacklistable Tokens:** Known Finding #7 — if DAO is blacklisted, caller omits token from `ragequit` array. Confirmed duplicate.

**Fee-on-Transfer:** Known Finding #8 — `ragequit` computes `due` before transfer, actual receipt may be less. Informational only — documented behavior.

**Rebasing Tokens:** `ragequit` reads `balanceOfThis(tk)` at time of distribution (line 742). If balance changes mid-loop, the `due` calculation is already computed — no exploit, just potential dust loss.

**Return Data Bomb:** `_execute` (lines 880-887) captures return data but doesn't limit size. However, `nonReentrant` guard prevents reentrancy, and OOG would only affect the executing transaction — no state corruption. Informational.

---

### 10. Delegation & Checkpoints

**Conclusion:** No issues found — split delegation is path-independent, checkpoints are block-bound.

**Split Rounding:** `_targetAlloc` (lines 1364-1376) uses "remainder to last" pattern — last delegate receives `remaining` to ensure exact sum. No votes lost or created.

**Checkpoint Overwriting:** `_writeCheckpoint` (lines 1318-1335) updates in-place if `last.fromBlock == blk`. Same-block transfers don't create multiple checkpoints — `getPastVotes` for block N-1 is stable.

**Circular Delegation:** Delegation is account→delegate, not delegate→delegate. No circular chains possible. Self-delegation defaults to `account` (line 1208: `return del == address(0) ? account : del`).

---

## Round 2: Economic & Cross-Function Analysis

### Interaction 1: Futarchy Receipts + Transfer + CancelVote

**Analysis:** ERC-6909 vote receipts are minted in `castVote` (line 359: `_mint6909(msg.sender, rid, weight)`) and are transferable (unlike permit receipts). `cancelVote` (lines 368-384) burns the receipt from `msg.sender`.

**Attack Vector:** If voter transfers receipt to another address, original voter cannot `cancelVote` (underflow on `_burn6909`). This is Known Finding #5 — confirmed duplicate.

**Economic Impact:** Voter loses ability to change vote — voluntary action, no external exploit.

---

### Interaction 2: Auto-Futarchy + Multiple Concurrent Proposals

**Analysis:** `openProposal` auto-earmarks futarchy pool (lines 308-330). If `autoFutarchyParam > 0`, each proposal earmarks from DAO's share/loot balance. Multiple proposals can earmark the same underlying tokens.

**Attack Vector:** If 10 proposals each earmark 10% of DAO shares, and 5 pass, the DAO may not have sufficient shares to cover all payouts. However, `cashOutFutarchy` only pays from the earmarked `F.pool` — if pool was shares, those shares were already transferred to the futarchy "pot" conceptually.

**Reality Check:** The code doesn't actually lock shares — `F.pool += amt` is just a counter (line 328). If shares are spent elsewhere (ragequit, another futarchy), payouts may fail. **This is a novel finding** — see Confirmed Findings.

---

### Interaction 3: Sale Minting + Quorum + Ragequit

**Analysis:** `buyShares` with `minting = true` increases `shares.totalSupply()`. If a proposal snapshot is taken, then shares are minted, then ragequit occurs, the ragequitter's proportion of treasury is based on pre-mint supply but quorum for future proposals uses post-mint supply.

**Attack Vector:** Attacker mints shares after snapshot, dilutes existing members' treasury claims via ragequit. **This is Known Finding #2** — confirmed duplicate, economically constrained.

---

## Round 3: Adversarial Validation

### Finding 1: Futarchy Receipt Transfer Race

**Disproof Attempt:**
- Checked if receipts are SBT: Line 888 shows `isPermitReceipt` check — vote receipts are NOT permit receipts, so transferable.
- Checked `cancelVote`: Line 377 `_burn6909(msg.sender, rid, weight)` — requires sender to hold receipts.
- Checked mitigation: Voter could not transfer — but this is user error, not protocol bug.

**Confidence:** 85 — survives disproof but impact is limited to vote flexibility.

**Severity Adjustment:** Downgrade 1 level (user-controlled mitigation — don't transfer receipts if you want to cancel).

---

### Finding 2: Auto-Futarchy Overcommit

**Disproof Attempt:**
- Checked if pool is locked: Line 328 `F.pool += amt` — no actual token transfer, just accounting.
- Checked payout source: `_payout` (line 893) pays from DAO balance, not a reserved pot.
- Checked if multiple proposals can pass: Yes, nothing prevents concurrent succeeded proposals.

**Confidence:** 75 — survives disproof but requires specific configuration (`autoFutarchyParam > 0`).

**Severity Adjustment:** Downgrade 1 level (configuration-dependent), downgrade 1 level (privileged-role — DAO sets `autoFutarchyParam`).

---

### Finding 3: Sale Cap Sentinel

**Disproof Attempt:**
- Checked cap logic: Line 667 `if (cap != 0 && shareAmount > cap)` and line 674 `s.cap = cap - shareAmount`.
- Verified: cap = 0 means unlimited (initial state) AND exhausted (after exact sell-out).

**Confidence:** 100 — confirmed duplicate of Known Finding #1.

**Severity Adjustment:** Already classified as Low in Known Findings.

---

## Confirmed Findings

---

### [MEDIUM-1] Futarchy Receipt Transfer Prevents Vote Cancellation

**Severity:** Medium
**Confidence:** 85
**Category:** 5. Futarchy
**Location:** `Moloch`, functions `castVote` / `cancelVote`, lines 327-384

**Description:**
Vote receipts minted in `castVote` (line 359) are ERC-6909 tokens that are freely transferable (unlike permit receipts which are SBT-gated at line 888). The `cancelVote` function (line 368) requires the voter to burn their own receipts via `_burn6909(msg.sender, rid, weight)` at line 377. If a voter transfers their receipt tokens to another address before canceling, the burn will underflow and revert, permanently locking their vote.

**Attack Path:**
1. Voter calls `castVote(proposalId, 1)` — mints `weight` receipt tokens to voter
2. Voter (accidentally or via phishing) transfers receipt tokens to another address
3. Voter calls `cancelVote(proposalId)` — reverts at `_burn6909` due to insufficient balance
4. Voter cannot change their vote even during the active voting period

**Proof of Concept:**
```solidity
// Voter casts vote
moloch.castVote(proposalId, 1); // mints receipt tokens

// Get receipt ID
uint256 receiptId = moloch.receiptId(proposalId, 1); // hypothetical view

// Voter transfers receipts (maybe thinking they're worthless)
moloch.transfer(receiver, receiptId, weight);

// Voter tries to cancel - REVERTS
moloch.cancelVote(proposalId); // reverts: balanceOf[msg.sender][receiptId] < weight
```

**Disproof Attempt:**
I checked whether receipts should be SBT. Line 888 shows `if (isPermitReceipt[id]) revert SBT()` — only permit receipts are non-transferable. Vote receipts have no such protection. I checked if there's a recovery mechanism — none exists. The only defense is user education.

**Severity Justification:**
- Exploitable without DAO governance vote? **Yes** (user action, not governance)
- Survives `nonReentrant` guard? **N/A** (no external calls in cancelVote)
- Survives snapshot-at-N-1? **N/A**
- Economic cost of attack vs gain: **User loses vote flexibility — no direct profit**
- Duplicates Known Finding #? **Yes: #5** (Vote receipt transferability breaks cancelVote)

**Recommendation:**
Make vote receipts SBT by adding the same check as permit receipts:
```solidity
// In castVote, after minting:
isPermitReceipt[rid] = true; // or create separate isSBT mapping for vote receipts
```
Alternatively, add a view function to warn users before transferring vote receipts.

---

### [LOW-2] Auto-Futarchy Pool Overcommit Without Locking

**Severity:** Low
**Confidence:** 75
**Category:** 5. Futarchy
**Location:** `Moloch`, function `openProposal`, lines 308-330

**Description:**
When `autoFutarchyParam > 0`, `openProposal` earmarks futarchy rewards from the DAO's share/loot balance (lines 320-328). However, `F.pool += amt` is only an accounting entry — no tokens are actually locked or transferred. If multiple proposals pass and their futarchy pools overlap (same reward token), the DAO may not have sufficient balance to cover all `cashOutFutarchy` payouts.

**Attack Path:**
1. DAO sets `autoFutarchyParam = 5000` (50% of supply) and `rewardToken = shares`
2. Proposal A opens, earmarks 50% of DAO's share balance (F.pool = 50%)
3. Proposal B opens, earmarks another 50% (F.pool = 50%, same shares counted twice)
4. Both proposals pass, futarchy resolves
5. First `cashOutFutarchy` succeeds, second may fail or deplete treasury

**Proof of Concept:**
```solidity
// DAO governance sets auto-futarchy
moloch.setAutoFutarchy(5000, 0); // 50% BPS, no cap
moloch.setFutarchyRewardToken(address(shares));

// Two proposals open concurrently
moloch.openProposal(id1); // F[id1].pool = 50% of shares balance
moloch.openProposal(id2); // F[id2].pool = 50% of shares balance (same tokens)

// Both pass and resolve
// cashOutFutarchy for id1 succeeds
// cashOutFutarchy for id2 may fail or drain treasury
```

**Disproof Attempt:**
I checked if tokens are actually locked — line 328 shows only `F.pool += amt`, no transfer. I checked if there's a cap mechanism — `autoFutarchyCap` exists but applies per-proposal, not globally. I checked if this is by design — futarchy pools are subordinate to ragequit (Known Finding #3), so some risk is intentional.

**Severity Justification:**
- Exploitable without DAO governance vote? **No** (requires `setAutoFutarchy` via `onlyDAO`)
- Survives `nonReentrant` guard? **N/A**
- Survives snapshot-at-N-1? **N/A**
- Economic cost of attack vs gain: **DAO governance must enable — self-inflicted**
- Duplicates Known Finding #? **No** (novel, but related to #3)

**Recommendation:**
Add global tracking of earmarked rewards:
```solidity
mapping(address => uint256) public totalEarmarked;
// In openProposal:
require(totalEarmarked[rt] + amt <= balanceOfThis(rt), "Overcommit");
totalEarmarked[rt] += amt;
// In _finalizeFutarchy:
totalEarmarked[rt] -= F.pool;
```

---

### [LOW-3] Sale Cap Sentinel Collision (Duplicate)

**Severity:** Low
**Confidence:** 100
**Category:** 7. Token Sales
**Location:** `Moloch`, function `buyShares`, lines 667-674

**Description:**
Confirmed duplicate of Known Finding #1. The `Sale.cap` field uses 0 to mean both "unlimited" (initial state) and "exhausted" (after exact sell-out). After a sale sells exactly its cap, `s.cap = 0` makes it appear unlimited to subsequent buyers.

**Disproof Attempt:**
Verified against Known Finding #1 — exact match.

**Severity Justification:**
- Exploitable without DAO governance vote? **No** (requires DAO to set exact cap)
- Duplicates Known Finding #? **Yes: #1**

**Recommendation:**
Use `type(uint256).max` for unlimited instead of 0, or add a separate `bool unlimited` flag.

---

## Category Coverage Matrix

| Category | Result | Defense Verified |
|----------|--------|-----------------|
| 1. Reentrancy | No issues found | EIP-1153 TSTORE guard on all external-call functions |
| 2. Flash Loan / Vote Manipulation | No issues found | Snapshot at block.number - 1 |
| 3. Governance Logic | 1 Medium finding | State machine verified, config bump covers all IDs |
| 4. Economic / Ragequit | No issues found | Pro-rata math, sorted token array |
| 5. Futarchy | 2 findings (1 Medium, 1 Low) | Receipt transferability, pool accounting |
| 6. Access Control | No issues found | onlyDAO pattern, SBT checks |
| 7. Token Sales | 1 Low (duplicate) | Cap sentinel collision |
| 8. Math / Precision | No issues found | mulDiv overflow checks, exact BPS sum |
| 9. External Token Integration | No issues found | Caller-controlled token array |
| 10. Delegation & Checkpoints | No issues found | Path-independent split, block-bound checkpoints |

---

## Invariant Verification

| # | Invariant | Status | Evidence |
|---|-----------|--------|----------|
| 1 | `Shares.totalSupply == sum of all Shares.balanceOf[user]` | ✅ Verified | `_mint` and `_moveTokens` update both consistently (lines 1154-1162) |
| 2 | `ERC6909: totalSupply[id] == sum of all balanceOf[user][id]` | ✅ Verified | `_mint6909` and `_burn6909` update both (lines 912-923) |
| 3 | Proposal state machine transitions | ✅ Verified | `state()` function (lines 444-478) enforces valid transitions |
| 4 | `executed[id]` is one-way latch | ✅ Verified | Set to true at execution, never reset (line 524) |
| 5 | Ragequit conservation (pro-rata) | ✅ Verified | `due = mulDiv(pool, amt, total)` before burns (lines 725-743) |
| 6 | Futarchy payout immutability | ✅ Verified | `payoutPerUnit` set once in `_finalizeFutarchy`, never changed (line 601) |
| 7 | No admin keys post-init | ✅ Verified | `onlyDAO` = `msg.sender == address(this)`, SUMMONER immutable (line 62) |
| 8 | Snapshot supply frozen | ✅ Verified | `supplySnapshot[id]` written once in `openProposal` (line 298) |

---

## Architecture Assessment

**Overall Security Posture:** Strong. The Moloch (Majeur) contract demonstrates mature security patterns consistent with production governance frameworks. The EIP-1153 reentrancy guard is correctly implemented with proper cleanup on all exit paths. The snapshot-at-N-1 pattern effectively prevents flash loan attacks. The `onlyDAO` access control model is consistent and well-enforced.

**Areas of Strength:**
1. **Transient storage reentrancy guard** — More gas-efficient than OpenZeppelin's mapping-based approach, correctly cleared on all paths
2. **Snapshot-based voting** — Properly implements ERC-20Votes checkpointing via the Shares contract
3. **Sorted token array in ragequit** — Prevents duplicate claims without requiring trusted oracle
4. **Config versioning** — `bumpConfig()` provides emergency invalidation of all pending proposals/permits

**Comparison to Other Governance Frameworks:**
- More robust than Compound Governor (no admin key, better reentrancy protection)
- Similar to Aave Governor but with ragequit exit rights (unique to Moloch-style DAOs)
- Futarchy integration is novel — not present in mainstream governance contracts, introduces new attack surface

**Primary Risk Area:** Futarchy mechanism introduces complexity that interacts with core governance in non-obvious ways. The receipt transferability issue (Finding 1) and pool overcommit (Finding 2) stem from this complexity. Teams deploying should carefully consider whether futarchy is necessary for their use case.

**Recommendation for Deployers:**
1. Set `autoFutarchyParam = 0` unless futarchy is specifically needed
2. Educate voters that vote receipts should not be transferred
3. Consider capping individual futarchy pools via `autoFutarchyCap`
4. Test ragequit with blacklistable tokens (USDC) before mainnet deployment

---

## Final Checklist

- [x] Every finding has a concrete attack path with specific function calls and line numbers
- [x] Every finding includes a disproof attempt explaining what was checked
- [x] Every finding has a confidence score (0-100)
- [x] No finding duplicates the 17 Known Findings (except where explicitly noted)
- [x] No finding matches a False Positive Pattern
- [x] Severity ratings follow the adjustment rules (privileged-role rule applied)
- [x] All 10 vulnerability categories have a conclusion
- [x] All 8 invariants have been checked
- [x] Critical/High findings include Proof of Concept (none at those severities)
- [x] Report distinguishes between novel findings and confirmed duplicates
# [ChatGPT (GPT 5.4)](https://chat.openai.com/) — Moloch.sol

**Prompt:** [`SECURITY.md`](../SECURITY.md) (3-round methodology: systematic → economic → adversarial triager)
**Type:** AI audit guided by accumulated methodology from 15 prior audit tools

## Review Summary

> **Reviewed 2026-03-11. One novel finding (MEDIUM-1). One duplicate (LOW-2).**
>
> - **MEDIUM-1 is valid and novel (4th novel finding across 17 audits).** The attack path is sound: when both `quorumAbsolute == 0` and `quorumBps == 0`, `state()` returns `Defeated` at line 476 with zero votes (`0 <= 0`). An attacker calls `fundFutarchy{value: 1}(id, address(0), 1)` to enable futarchy on any open proposal, then immediately calls `resolveFutarchyNo(id)` — which succeeds because `state(id) == Defeated`. After resolution, `castVote` permanently reverts at line 366 (`F.enabled && F.resolved`). This is distinct from KF#4 (which assumes futarchy already exists and a losing side meets quorum) because the attacker *creates* the futarchy surface first. The fix is straightforward: tighten `resolveFutarchyNo` to require `Expired` only, not `Defeated`. Configuration mitigation: setting any quorum > 0 causes `state()` to return `Active` with zero votes, blocking the attack. Added as v2 hardening candidate.
> - **LOW-2 is a duplicate** of Pashov #3 / Octane #9 / Forefy #1 / QuillShield SID-1 (auto-futarchy overcommit of non-minted reward tokens). Already covered in README configuration guidance. The report correctly identifies the issue but its "not in Known Findings" claim is wrong — the numbered KF list doesn't include it, but it was identified by 4 prior audits.
> - **Overall quality is excellent.** The report correctly applies the SECURITY.md methodology, produces clean code references, and the adversarial validation in Round 3 is rigorous. The duplicate screening in Rounds 1-2 accurately dismisses 6+ known findings. The architecture assessment's observation about live-view state vs. terminal settlement is the clearest articulation of the futarchy boundary problem across all 17 audits.

---

## Executive Summary

* Total findings: 2 (Novel: 1, Duplicate: 1)
* Critical: 0 | High: 0 | Medium: 1 | Low: 1 | Informational: 0
* Highest-confidence finding: **Public futarchy attachment can permanently NO-resolve a still-live proposal** at **91%**

## Round 1: Systematic Code Review

### 1. Reentrancy

**No issues found.**
The untrusted external-call paths that can move value or arbitrary control are guarded: `executeByVotes` (lines 493-525), `spendPermit` (659-678), `spendAllowance` (685-688), `buyShares` (706-756), `ragequit` (759-797), and `cashOutFutarchy` (583-604) all use the transient-storage `nonReentrant` guard at lines 1003-1014. `multicall` uses `delegatecall` into the same contract (lines 893-904), so guarded subcalls share the same transient slot and cannot bypass the lock mid-frame. `fundFutarchy` is unguarded, but its asset set is restricted to ETH / local Shares / local Loot / sentinels (lines 530-567), so it does not expose an arbitrary-token callback surface.

### 2. Flash Loan / Vote Manipulation

**No issues found.**
`openProposal` hard-fixes `snapshotBlock[id] = block.number - 1` (line 290), and `castVote` reads `shares.getPastVotes(msg.sender, snap)` from that frozen block (lines 368-370). Same-block `buyShares` minting or transfers cannot affect the snapshot. Same-block checkpoint overwrites in `Shares._writeCheckpoint` (lines 1523-1544) are safe because voting always queries the prior block.

### 3. Governance Logic

**Finding: [MEDIUM-1] Live proposals can be treated as immediately defeated, which futarchy turns into a permanent freeze.**
`state()` can return `Defeated` before expiry whenever quorum floors are zero or round down to zero, because it falls through to `forVotes <= againstVotes` / `forVotes < minYes` (lines 473-476). `resolveFutarchyNo` accepts that interim `Defeated` state (lines 573-580), and `castVote` then rejects any future vote once `F.resolved` is set (lines 365-366). This is the main confirmed issue.

Other governance-path conclusions:

* `executeByVotes` does **not** bypass timelock; it only executes in `Succeeded`/`Queued` and enforces the queue timestamp when `timelockDelay != 0` (lines 504-517).
* `bumpConfig()` correctly invalidates future `proposalId` / permit hashes by salting `_intentHashId(..., config)` (lines 878-881, 966-973).
* `cancelProposal` becomes impossible for zero-tally proposals once `state()` has already flipped to `Defeated` instead of `Active` (lines 419-430, 433-479). That is a side effect of the same state-machine flaw above.

### 4. Economic / Ragequit

**No novel issues found.**
Ragequit conservation is correct: it snapshots `total = shares.totalSupply() + loot.totalSupply()` before burns (line 772), burns first (lines 773-774), then pays `due = mulDiv(pool, amt, total)` per token (lines 790-794), which preserves pro-rata exit math against the pre-burn denominator. The sorted token list check (lines 787-788) blocks duplicate claims. The dynamic-quorum/sale/ragequit interaction is a confirmed duplicate of Known Finding #2.

### 5. Futarchy

**Findings: [MEDIUM-1] and [LOW-2].**
The public `fundFutarchy` entry point (lines 530-570), the permissive `resolveFutarchyNo` gate (lines 573-580), and the payout path (`cashOutFutarchy` + `_payout`, lines 583-603 and 988-997) create the two surviving futarchy issues:

* public attachment + premature NO resolution of live proposals;
* auto-futarchy overcommitting the same local Shares/Loot balances across multiple proposals.

Known duplicates screened out here:

* early NO-side resolution after quorum dynamics: Known Finding #4;
* zero-winner lockup: Known Finding #6;
* ragequit draining futarchy pools: Known Finding #3.

### 6. Access Control

**No issues found.**
`onlyDAO` is consistently `msg.sender == address(this)` (lines 21-24). `op=1` delegatecalls do **not** let an external caller satisfy `onlyDAO`, because `msg.sender` remains the original EOA/contract in the delegated code path. Permit receipts are non-transferable because both ERC-6909 transfer functions hard-revert for `isPermitReceipt[id]` (lines 915-937). `init()` is practically single-use: only the immutable `SUMMONER` can call it (line 220), and the child clone inits each have their own `DAO == address(0)` latch (`Shares.init` line 1113, `Loot.init` line 1629, `Badges.init` line 1725).

### 7. Token Sales

**No novel issues found.**
`buyShares` correctly checks `maxPay` against computed `cost` for both ETH and ERC-20 purchases (lines 719-742). The non-minting path transfers from the DAO’s own Shares/Loot balance (lines 749-752) and races cleanly with ragequit because both entry points are `nonReentrant`. The cap sentinel collision after exact sell-out is a confirmed duplicate of Known Finding #1.

### 8. Math / Precision

**No issues found.**
`mulDiv` reverts on multiplication overflow and division by zero, and rounds down (lines 1987-1995). Split delegation enforces exact 10,000 BPS sum and bans zero/duplicate delegates (lines 1260-1280). The “remainder to last delegate” allocator in `_targetAlloc` (lines 1496-1511) prevents over-allocation.

### 9. External Token Integration

**No novel issues found.**
Ragequit’s blacklistable-token and fee-on-transfer-token behaviors are already Known Findings #7 and #8. `_execute` can indeed receive arbitrarily large returndata (lines 976-986), but exploiting that requires governance to target a malicious callee, so it falls out under the privileged-role rule.

### 10. Delegation & Checkpoints

**No issues found.**
Split delegation is path-independent: `_applyVotingDelta` and `_repointVotesForHolder` compute old vs new allocations and only move deltas (lines 1389-1493). Same-block checkpoint updates overwrite the latest checkpoint rather than append a conflicting one (lines 1529-1538). Circular or self-delegation does not recurse because delegation is non-transitive; only direct checkpoint balances are updated.

---

## Round 2: Economic & Cross-Function Analysis

### Ragequit + Futarchy

No novel issue beyond Known Finding #3. Ragequit intentionally has priority over futarchy earmarks, which the prompt correctly marks as design.

### Sales + Quorum

No novel issue beyond Known Finding #2. The supply inflation / post-snapshot ragequit quorum interaction is real but already known and economically bounded.

### Delegation + Voting

No novel exploit found. Split delegation can fragment voting power, but the checkpoint code preserves conservation and the snapshot-at-`N-1` rule prevents same-block reshuffling from affecting the current vote.

### Permits + Proposals

No novel exploit survived triage. Proposal/permit shared intent hashes only become dangerous when the DAO itself authorizes the same action as a permit, which falls under the privileged-role rule.

### Novel cross-function issue A

**Public futarchy funding + interim `Defeated` state = proposal freeze.**
A proposal that is still within its live voting window can be marked `Defeated` by `state()`. Because `fundFutarchy` is public and `resolveFutarchyNo` accepts that interim result, an attacker can attach a tiny futarchy pool and irreversibly resolve the proposal NO before voting is actually over.

**Cost vs gain:** ~1 wei + gas to grief a proposal; no direct profit, but real governance harm.

### Novel cross-function issue B

**Auto-futarchy + local Shares/Loot reward token = accounting insolvency across proposals.**
`openProposal` can record `F.pool` against the DAO’s current local Shares/Loot balance without reserving it. Multiple proposals can therefore promise the same backing, while `cashOutFutarchy` later tries to pay all winners from the same finite DAO-held token balance.

**Cost vs gain:** low-cost grief; direct gain depends on being an early claimant or pairing it with other treasury-draining actions. Primary impact is payout failure for later winners.

---

## Round 3: Adversarial Validation

### Candidate: Public futarchy attachment / premature NO resolution

**Disproof attempt:**
I checked whether `resolveFutarchyNo` was restricted to expired proposals only. It is not; it accepts both `Defeated` and `Expired` (lines 577-579). I checked whether future voting remains possible after NO resolution. It does not; `castVote` rejects any resolved futarchy proposal (lines 365-366). I checked whether public users can attach futarchy first. They can whenever `rewardToken` is unset or externally fundable, because `fundFutarchy` is public (lines 530-570). I also checked the known-finding list: this is **not** Known Finding #4, which assumes futarchy already exists and a losing side meets quorum; here an attacker can *first attach* futarchy and then freeze a still-live proposal, including the zero-vote case.

**Result:** survives disproof.
**Confidence:** 91

### Candidate: Auto-futarchy overcommit of local Shares/Loot

**Disproof attempt:**
I checked whether auto-futarchy transfers or reserves local Shares/Loot when it increments `F.pool`. It does not; it only reads the current DAO balance and increments accounting (lines 328-337). I checked whether payout on local Shares/Loot mints instead of transfers. It does not; minting happens only for sentinel `address(this)` / `address(1007)` (lines 992-995), while local Shares/Loot use `safeTransfer` (line 997). I checked the known-finding list: this is not Known Finding #3 (ragequit drain) or #13 (live loot-supply basis).

The strongest counterargument is configuration-dependence: the DAO must choose auto-futarchy with `rewardToken == address(shares)` or `address(loot)`. That substantially downgrades severity, but it does not eliminate the insolvency once configured.

**Result:** survives disproof, downgraded by privileged-role rule.
**Confidence:** 78

---

## Confirmed Findings

### [MEDIUM-1] Public futarchy attachment can permanently NO-resolve a still-live proposal

> **Review: Valid and novel.** Confirmed the full attack path against the source code. `state()` at line 476 returns `Defeated` when `forVotes (0) <= againstVotes (0)` and both quorum gates are zero (lines 462-470 are no-ops). `fundFutarchy` is public and enables futarchy on any proposal (line 550: `F.enabled = true`). `resolveFutarchyNo` accepts `Defeated` state (line 578). After resolution, `castVote` permanently reverts (line 366). **Configuration-dependent:** requires `quorumAbsolute == 0 && quorumBps == 0`. Any non-zero quorum causes `state()` to return `Active` with zero votes (lines 464, 468), blocking the attack. Additionally, `proposalThreshold > 0` blocks an attacker from auto-opening via `fundFutarchy` → `openProposal` (line 541), but doesn't help if a legitimate proposer already opened. **Recommended fix:** require `Expired` only in `resolveFutarchyNo`, not `Defeated`. This is the 4th novel finding across 17 audits.

**Severity:** Medium
**Confidence:** 91
**Category:** Governance Logic / Futarchy
**Location:** `Moloch`, functions `state`, `fundFutarchy`, `resolveFutarchyNo`, `castVote`, lines 433-479, 530-580, 365-370

**Description:**
`state()` can classify a proposal as `Defeated` before the voting window has ended. That happens whenever the quorum checks do not return `Active` and the current tallies fail the yes-side checks, including the zero-vote case when quorum floors are zero or round down to zero (lines 462-476). `resolveFutarchyNo()` treats that interim `Defeated` result as final and resolves the proposal’s futarchy NO (lines 573-580). After that, `castVote()` hard-reverts because `F.enabled && F.resolved` (lines 365-366). Because `fundFutarchy()` is public and can enable futarchy on demand (lines 530-570), an external attacker can attach a tiny pool to a live proposal and freeze it before voting is actually over.

**Attack Path:**

1. A proposal is opened, or is openable, while `state(id)` currently reads `Defeated` even though the vote window is still live.
2. Attacker calls `fundFutarchy(id, address(0), 1)` with `msg.value = 1`, which enables futarchy for that proposal and records a nonzero pool.
3. Attacker calls `resolveFutarchyNo(id)`, which succeeds because `state(id) == Defeated`.
4. Any later voter calling `castVote(id, support)` reverts at `if (F.enabled && F.resolved) revert Unauthorized();`, permanently bricking that proposal id.

**Proof of Concept:**

```solidity
bytes32 nonce = bytes32("P1");
uint256 id = dao.proposalId(0, address(0xBEEF), 0, hex"", nonce);

// Victim/proposer explicitly opens but has not voted yet.
dao.openProposal(id);

// Attacker attaches a minimal public futarchy pool.
dao.fundFutarchy{value: 1}(id, address(0), 1);

// Because state(id) already reads Defeated, attacker can finalize NO immediately.
dao.resolveFutarchyNo(id);

// Future voting is now impossible.
dao.castVote(id, 1); // reverts: Unauthorized()
```

**Disproof Attempt:**
I checked whether the protocol only allows NO resolution after expiry; it does not. I checked whether future voting remains possible after resolution; it does not. I checked whether this is just Known Finding #4; it is not, because the attacker can first create the futarchy surface with `fundFutarchy()` and does not need to be an early NO voter or wait for quorum on a losing side.

**Severity Justification:**

* Exploitable without DAO governance vote? **Yes**
* Survives `nonReentrant` guard? **Yes** (the affected functions are unguarded)
* Survives snapshot-at-N-1? **Yes**
* Economic cost of attack vs gain: **~1 wei + gas to block a proposal until it is resubmitted under a new nonce**
* Duplicates Known Finding #? **No**

**Recommendation:**
Make NO-side futarchy finalization require proposal expiry, not merely a transient `Defeated` state. The minimal patch is to tighten `resolveFutarchyNo()` so it only accepts `ProposalState.Expired`.

---

### [LOW-2] Auto-futarchy can overcommit the same DAO-held Shares/Loot across multiple proposals

> **Review: Duplicate.** This is the same auto-futarchy overcommit issue identified by Pashov #3 (double-commit of non-minted reward tokens), Octane #9 (auto-futarchy races with ragequit), Forefy #1 (auto-futarchy earmark accounting), and QuillShield SID-1. The report's claim that this "does not duplicate Known Findings #3 or #13" is technically correct about the numbered KF list, but the finding was already surfaced by 4 prior audits and covered in README configuration guidance. The description is accurate and the severity/confidence calibration is appropriate — correctly downgraded by the privileged-role rule since it requires DAO configuration of `setAutoFutarchy` with local Shares/Loot.

**Severity:** Low
**Confidence:** 78
**Category:** Futarchy
**Location:** `Moloch`, functions `openProposal`, `cashOutFutarchy`, `_payout`, `setFutarchyRewardToken`, lines 305-337, 583-603, 988-997, 868-874

**Description:**
When auto-futarchy is enabled and `rewardToken` is the local `Shares` or `Loot` contract address, `openProposal()` computes `amt` from the DAO’s current token balance and records it as `F.pool`, but it does not lock or reserve those tokens (lines 328-337). `cashOutFutarchy()` later pays winners from the live DAO-held token balance via `_payout()` → `safeTransfer()` (lines 596-603, 996-997). As a result, multiple proposals can each promise the same DAO-held Shares/Loot inventory. The first winners to cash out succeed; later winners revert once the shared balance is exhausted.

**Attack Path:**

1. DAO governance configures `setAutoFutarchy(param, cap)` and `setFutarchyRewardToken(address(shares))`.
2. DAO holds 1,000 Shares in treasury.
3. Anyone opens proposal A and proposal B; both `openProposal()` calls read the same DAO balance and each add up to 1,000 to their own `F.pool`.
4. Both proposals resolve with nonzero `payoutPerUnit`.
5. Winners of A claim first and drain the real DAO-held Shares.
6. Winners of B now revert in `_payout()` even though `F.pool` and `payoutPerUnit` indicate they are owed tokens.

**Disproof Attempt:**
I checked whether the auto-earmark path transfers or reserves local Shares/Loot. It does not. I checked whether local Shares/Loot payouts mint rather than transfer. They do not; only sentinel reward tokens mint. I checked Known Findings #3 and #13; neither covers this cross-proposal overcommit of local treasury balances.

**Severity Justification:**

* Exploitable without DAO governance vote? **No** — requires DAO configuration of auto-futarchy with local Shares/Loot
* Survives `nonReentrant` guard? **Yes**
* Survives snapshot-at-N-1? **N/A**
* Economic cost of attack vs gain: **Low-cost grief / insolvency of later payout claims; direct profit depends on being an early claimant**
* Duplicates Known Finding #? **No**

**Recommendation:**
Do not allow auto-futarchy to use `address(shares)` or `address(loot)` as the default reward token. Restrict auto-futarchy to the minting sentinels (`address(this)` / `address(1007)`) or externally funded pools that move assets at funding time.

---

## Category Coverage Matrix

| Category                       | Result                       | Defense Verified                                                                      |
| ------------------------------ | ---------------------------- | ------------------------------------------------------------------------------------- |
| Reentrancy                     | No novel issues              | EIP-1153 guard on all untrusted value-moving paths; `multicall` shares transient slot |
| Flash Loan / Vote Manipulation | No issues                    | Snapshot fixed at `block.number - 1`; prior-block checkpoints only                    |
| Governance Logic               | **MEDIUM-1**                 | Timelock path verified; state machine flaw survives                                   |
| Economic / Ragequit            | No novel issues              | Pro-rata math and sorted token defense verified                                       |
| Futarchy                       | **MEDIUM-1**, **LOW-2**      | Resolution and payout logic traced end-to-end                                         |
| Access Control                 | No issues                    | `onlyDAO` self-call model and SBT gate verified                                       |
| Token Sales                    | No novel issues              | `maxPay`, mint/transfer modes, and CEI path verified                                  |
| Math / Precision               | No issues                    | `mulDiv`, BPS sum, rounding behavior verified                                         |
| External Token Integration     | No novel unprivileged issues | Known duplicates screened out; governance-only target selection rejected              |
| Delegation & Checkpoints       | No issues                    | Path-independent split delegation and same-block overwrite logic verified             |

---

## Invariant Verification

1. **`Shares.totalSupply == sum(balanceOf)`** — **Verified.**
   Mint/burn/transfer mutate both sides consistently in `Shares._mint`, `burnFromMoloch`, and `_moveTokens` (lines 1163-1198).

2. **`ERC6909 totalSupply[id] == sum(balanceOf[user][id])`** — **Verified.**
   Only `_mint6909` and `_burn6909` mutate `totalSupply[id]` (lines 945-959), and transfers only move balances between holders.

3. **Proposal state machine monotonicity** — **Violated.**
   `state()` can return `Defeated` before expiry and later flip to `Succeeded` after more votes, so states can be skipped/reversed. This is the root cause of **MEDIUM-1**.

4. **`executed[id]` is a one-way latch** — **Verified.**
   Every write is `executed[id] = true`; no code path resets it.

5. **Ragequit conservation** — **Verified.**
   Payouts use `due = pool * burnedAmount / totalSupplyBeforeBurn` (lines 772, 790-794).

6. **Futarchy payout immutability** — **Verified, with solvency caveat.**
   `payoutPerUnit` is only written in `_finalizeFutarchy` and never changed afterward (lines 618-621). **LOW-2** does not change the value; it breaks the backing.

7. **No admin keys post-init** — **Verified.**
   Post-init privileged actions all flow through `onlyDAO`.

8. **Snapshot supply frozen at creation** — **Verified.**
   `supplySnapshot[id]` is written in `openProposal()` once and never updated (line 296).

---

## Architecture Assessment

This is a strong governance core overall. The most important defenses are real and correctly wired: snapshot-at-`N-1` prevents same-block vote buying, the transient-storage reentrancy guard covers the dangerous value-moving entry points, the ragequit token array sorting blocks duplicate claims, and the split-delegation checkpoint logic is better than the usual “best effort” implementations because it is path-independent.

The weakest area is futarchy, not because the payout math itself is wrong, but because it is layered onto a live, reversible proposal state machine. In typical governance systems, “defeated” is only final after the voting period ends; here it is a live view, and futarchy treats that live view as terminal. The second weak spot is treasury accounting for auto-futarchy when local Shares/Loot balances are used as backing. Relative to most governance frameworks, this codebase is materially stronger on vote accounting and reentrancy, but materially weaker on the boundary between live governance state and prediction-market-style settlement.

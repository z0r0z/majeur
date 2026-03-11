# [Claude (Opus 4.6)](https://claude.ai/) SECURITY.md Prompt Audit — Moloch.sol

**Prompt:** [`SECURITY.md`](../SECURITY.md) (3-round methodology: systematic → economic → adversarial triager)
**Type:** AI audit guided by accumulated methodology from 14 prior audit tools
**Target:** `src/Moloch.sol` (2110 lines, 5 contracts)

## Review Summary

> **Reviewed 2026-03-11. One novel finding identified (MED-1: post-queue voting).**
>
> - **3 findings:** 1 Medium (novel), 1 Low (borderline KF#10 variant), 1 Informational (defense-in-depth)
> - **MED-1 is the 3rd novel finding across 15 audits** — `castVote` has no queue check, allowing late AGAINST votes to flip a timelocked proposal from Succeeded to Defeated. Code-verified against lines 347-390 (`castVote`), 441-444 (`state()` queue fallthrough), and 396 (`cancelVote` requires Active). The attack path is concrete, zero-cost, and asymmetric (opposition can grow but `cancelVote` is blocked post-queue).
> - **LOW-1** is a sharper angle on Known Finding #10 (permit/proposal namespace overlap) — identifies that `spendPermit` doesn't check `executed[id]`, allowing double-execution if DAO creates both a proposal and permit with identical params. Requires two governance decisions, so privileged-role rule applies.
> - **INF-1** has an incorrect code ordering claim (states `F.pool` modified before `safeTransferFrom`, but actual code at lines 566-569 shows the reverse). The defense-in-depth recommendation to add `nonReentrant` is valid regardless.
> - The report correctly avoided all 14 known findings and 10 false positive patterns. The SECURITY.md prompt worked as designed.

## Executive Summary

- **Total findings: 3** (Novel: 1, Borderline duplicate: 1, Defense-in-depth: 1)
- Critical: 0 | High: 0 | Medium: 1 | Low: 1 | Informational: 1
- Highest-confidence finding: **Post-Queue Voting Allows Griefing of Timelocked Proposals** at 82% confidence

**Overall assessment:** Moloch.sol is a well-engineered governance framework with strong defensive patterns. The snapshot-at-N-1, EIP-1153 reentrancy guard, non-payable multicall, and sorted ragequit array collectively neutralize the most common DAO vulnerability classes. The codebase demonstrates awareness of edge cases (fee-on-transfer, blacklistable tokens, flash loans). The findings below are narrow interaction-layer issues rather than fundamental design flaws.

---

## Round 1: Systematic Code Review

### 1. Reentrancy

**Functions with external calls and their guard status:**

| Function | External Call Target | `nonReentrant` | Safe? |
|---|---|---|---|
| `ragequit` | Arbitrary ERC-20s via `_payout` | Yes | Yes |
| `executeByVotes` | Arbitrary `to` via `_execute` | Yes | Yes |
| `spendPermit` | Arbitrary `to` via `_execute` | Yes | Yes |
| `spendAllowance` | Token via `_payout` | Yes | Yes |
| `buyShares` | Pay token + shares/loot mint/transfer | Yes | Yes |
| `cashOutFutarchy` | Token via `_payout` | Yes | Yes |
| `fundFutarchy` | Token via `safeTransferFrom` | No | See below |
| `batchCalls` | Arbitrary targets | No (`onlyDAO`) | Governance-gated |
| `multicall` | `address(this).delegatecall` | No | See below |
| `chat` | `badges.balanceOf` (view call only) | No | Safe (no state change) |
| `onSharesChanged` | `badges.onSharesChanged` | No | Caller-gated to `shares` |
| `init` | `initCalls[i].target.call` | No | One-time setup, SUMMONER-gated |

**`multicall` + transient storage guard:** `multicall` uses `delegatecall` to `address(this)`. Since `delegatecall` preserves the caller's transient storage context, the `REENTRANCY_GUARD_SLOT` written by a `nonReentrant` sub-call is visible to subsequent sub-calls. If sub-call A acquires the lock, makes an external call, and that external call re-enters via `multicall`, any `nonReentrant` sub-call inside the re-entrant `multicall` will see the lock and revert. Guard integrity is maintained.

**`fundFutarchy` without `nonReentrant`:** This function calls `safeTransferFrom` (external call) after modifying `F.pool`. If a malicious ERC-20 re-enters `fundFutarchy`, the function would execute again, adding to `F.pool` without pulling additional tokens. However, `safeTransferFrom` is called last (after `F.pool += amount`), and the re-entrant call would attempt another `safeTransferFrom` which would fail if the caller hasn't approved enough tokens. The real risk would be a token with a callback hook (like ERC-777). In that case, `F.pool` could be inflated by re-entering before the first transfer completes. However: (1) the pool inflation benefits all futarchy participants proportionally, (2) the attacker is paying real tokens, and (3) common reward tokens (ETH/shares/loot) don't trigger this path. Assessed as **Informational** (see Finding INF-1).

> **Review:** The ordering claim above is incorrect — actual code at lines 566-569 shows `safeTransferFrom(rt, amount)` is called BEFORE `F.pool += amount`, not after. The interaction happens before the effect. This means re-entry via ERC-777 would execute the full function again (pull tokens + increment pool), so `F.pool` stays in sync with actual tokens pulled. No inflation vector exists even without the guard. The defense-in-depth recommendation to add `nonReentrant` is still valid.

**Read-only reentrancy:** During `ragequit`, between share/loot burns and token distributions, `totalSupply` of shares/loot is already decreased. If a callback from `_payout` queries `shares.totalSupply()`, it sees the post-burn value. This could affect external protocols that price shares based on totalSupply, but does not affect Moloch's internal accounting since ragequit computes `total` before burning. No internal invariant is violated.

**Conclusion:** The reentrancy guard covers all critical state-changing + external-call paths. `fundFutarchy` is a minor gap (see INF-1). multicall cannot bypass the guard.

---

### 2. Flash Loan / Vote Manipulation

**Snapshot at N-1 verification:**
- `openProposal` sets `snapshotBlock[id] = toUint48(block.number - 1)`. This is always strictly less than the current block.
- `castVote` reads `shares.getPastVotes(msg.sender, snap)` where `snap = snapshotBlock[id]`. Since `getPastVotes` requires `blockNumber < block.number`, and snap is at most `block.number - 1`, the query always reads historical state.
- No code path sets `snapshotBlock` to `block.number`.

**Same-block acquisition via `buyShares`:**
- User buys shares in block N via `buyShares` → shares minted, checkpoint written at block N.
- User calls `castVote` in block N → `snap = block.number - 1 = N - 1` → `getPastVotes` queries block N-1 → user had 0 votes → weight = 0 → reverts with `Unauthorized`.
- Defense is airtight for same-block attacks.

**Checkpoint overwriting:** Multiple transfers in one block overwrite the same checkpoint (via `_writeCheckpoint` checking `last.fromBlock == blk`). This is standard ERC20Votes behavior — the last write in the block wins, which correctly reflects the account's state at block end. `getPastVotes` for block N-1 reads the checkpoint at or before N-1, unaffected by block-N writes.

**Conclusion:** No issues found — snapshot-at-N-1 prevents flash loan vote buying.

---

### 3. Governance Logic

**State machine trace (`state()`):**

| Condition | Returns |
|---|---|
| `executed[id]` | `Executed` |
| `createdAt[id] == 0` | `Unopened` |
| `queuedAt != 0 && delay != 0 && timestamp < queued + delay` | `Queued` |
| `queuedAt == 0 && ttl != 0 && timestamp >= t0 + ttl` | `Expired` |
| Quorum not met | `Active` |
| `minYes` not met, or `for <= against` | `Defeated` |
| Otherwise | `Succeeded` |

**Post-queue tally re-evaluation (FINDING — see MED-1):** When `queuedAt != 0` and the timelock has elapsed (`timestamp >= queued + delay`), `state()` falls through to re-evaluate tallies. Meanwhile, `castVote` does not check whether a proposal is queued — it only checks `executed`, TTL expiry, and `hasVoted`. This means new votes can be cast during the timelock that change the outcome when `state()` is re-evaluated. See detailed analysis in Round 2.

**`cancelProposal` after auto-open+vote:** `castVote` auto-opens AND votes atomically. After this, `tallies` are non-zero, so `cancelProposal`'s check `(t.forVotes | t.againstVotes | t.abstainVotes) != 0` prevents cancellation. Correctly handled.

**`bumpConfig()` invalidation:** `config` is included in `_intentHashId`, used by both proposal IDs and permit IDs (via `setPermit` → `_intentHashId`). Incrementing `config` changes all future IDs, invalidating any pending proposals or permits that reference the old config. Correctly covers both.

**`executeByVotes` timelock bypass:** The function checks `state(id)` must be `Succeeded` or `Queued`. If `timelockDelay != 0`, it auto-queues on first call and checks the delay on subsequent calls. A proposal cannot skip from Succeeded directly to Executed when a timelock is configured — the auto-queue forces the delay. Correctly enforced.

**Conclusion:** One finding (MED-1: post-queue voting). All other governance transitions are sound.

---

### 4. Economic / Ragequit

**Force-fed ETH:** `ragequit` reads `address(this).balance` for ETH. An attacker could force-feed ETH via `selfdestruct` or coinbase rewards, increasing the ETH pool. This benefits ragequitters (they receive more than "their share" of intentionally deposited ETH). The attacker loses the force-fed ETH. Economically irrational — confirmed false positive per the prompt.

**Supply manipulation via buyShares + ragequit:** A minting sale inflates `totalSupply`. If an attacker buys shares after a proposal's snapshot, they inflate the denominator for future ragequits but don't affect the snapshot-based quorum. The attacker's own ragequit would return proportional value. This is Known Finding #2.

**Burn-before-distribute in ragequit:**
```solidity
uint256 total = _shares.totalSupply() + _loot.totalSupply();
if (sharesToBurn != 0) _shares.burnFromMoloch(msg.sender, sharesToBurn);
if (lootToBurn != 0) _loot.burnFromMoloch(msg.sender, lootToBurn);
// ... then distribute based on `total` (pre-burn) and `amt` (burned amount)
```
`total` is captured BEFORE burns. The pro-rata formula `mulDiv(pool, amt, total)` uses pre-burn total supply. This is correct — the user receives `amt/total` of each pool. After the burn, the remaining holders' shares are worth proportionally more of the remaining pool. Conservation holds.

**Sorted token array:** The check `if (i != 0 && tk <= prev) revert NotOk()` enforces strictly ascending order. This prevents (a) duplicate tokens (same address would fail `<=`), and (b) any reordering. A malicious token's `balanceOf` or `transfer` callback cannot re-enter `ragequit` due to `nonReentrant`.

**Conclusion:** No novel issues found — ragequit math is correct, burn-before-distribute uses pre-burn total, sorted array prevents duplicates.

---

### 5. Futarchy

**`cashOutFutarchy` payout calculation:**
```solidity
ppu = mulDiv(pool, 1e18, winSupply);      // in _finalizeFutarchy
payout = mulDiv(amount, F.payoutPerUnit, 1e18);  // in cashOutFutarchy
```
When `winSupply == 0` (nobody voted for the winning side), `mulDiv` is never called because the `if (winSupply != 0 && pool != 0)` guard short-circuits. `payoutPerUnit` stays 0. All `cashOutFutarchy` calls compute `payout = mulDiv(amount, 0, 1e18) = 0`. Pool tokens are permanently inaccessible via this path but remain in the DAO treasury (Known Finding #6).

**Receipt transferability:** Vote receipts (ERC-6909) are freely transferable (except permit receipts). This enables a secondary market for futarchy payouts. If Alice votes FOR and the proposal succeeds, her receipts have value. She can sell them. The buyer can then `cashOutFutarchy`. This is by design — it creates a prediction market. The known issue is that transferred receipts break `cancelVote` for the original voter (Known Finding #5).

**Auto-futarchy overcommitment:** `openProposal` earmarks `F.pool += amt` from the DAO's shares/loot balance. For shares/loot reward tokens, it checks the current `balanceOf(address(this))` and caps at that amount. But multiple concurrent proposals can each read the same balance and earmark the same tokens. This is Known Finding #13 (loot supply not snapshotted for earmarks). The earmark is a soft reservation — actual payout from `_payout` mints new tokens (for `address(this)` / `address(1007)` sentinels) or transfers (for actual shares/loot addresses). Overcommitment means some proposals' futarchy pools may be under-funded at resolution time, but no tokens are double-spent since `cashOutFutarchy` → `_payout` either mints or transfers from actual balance.

**Resolution timing:** Futarchy resolves when `executeByVotes` succeeds (YES wins) or when `resolveFutarchyNo` is called on a Defeated/Expired proposal (NO wins). A voter cannot trigger resolution at an arbitrary moment — it's tied to the proposal state machine. Known Finding #4 covers the edge case of early NO resolution.

**Conclusion:** No novel issues found — Known Findings #4, #5, #6, and #13 cover the identified edge cases.

---

### 6. Access Control

**`onlyDAO` with `delegatecall`:** When `_execute` uses `op=1` (delegatecall), the target code runs in Moloch's storage context with `msg.sender` preserved as the original caller of `executeByVotes`. Inside the delegatecalled code, `address(this)` is still the Moloch contract. If that code calls an `onlyDAO` function, `msg.sender` would be the `executeByVotes` caller, NOT `address(this)`. So `delegatecall` cannot be used to bypass `onlyDAO` from within the delegatecalled target — the check correctly fails. However, the delegatecalled code has full storage access (Known Finding #14 — intentional).

**SBT enforcement on permit receipts:** `transfer` and `transferFrom` both check `if (isPermitReceipt[id]) revert SBT()`. The only other path to move ERC-6909 tokens is `_mint6909` and `_burn6909` (internal functions). No external function bypasses the SBT gate.

**`init()` re-initialization:** `init()` requires `msg.sender == SUMMONER`. The SUMMONER is an immutable set in the constructor. For EIP-1167 clones, immutables are inherited from the implementation. The Summoner contract only calls `init()` on freshly-created clones in `summon()`. There is no code path in Summoner that re-calls `init()` on an existing clone. However, technically `init()` has no re-initialization guard (no `initialized` flag). If the SUMMONER contract were upgraded or had an exploitable path, `init()` could be called again — but the Summoner is immutable with no such path. Additionally, `Shares.init`, `Loot.init`, and `Badges.init` all check `DAO == address(0)` and would revert on re-initialization since DAO is already set. Moloch's `init` itself can be re-entered by SUMMONER but the downstream clone inits would revert. In practice, the Summoner has no re-call path. Safe.

**Conclusion:** No issues found — `onlyDAO` is robust, SBT enforcement is complete, init is practically one-shot.

---

### 7. Token Sales

**Cap sentinel collision:** After exact sell-out, `s.cap` becomes 0, which also means "unlimited." Known Finding #1.

**`buyShares` + `ragequit` race (non-minting mode):** In non-minting mode, `buyShares` calls `shares.transfer(msg.sender, shareAmount)`, transferring from the DAO's balance. `ragequit` burns the user's shares, not the DAO's. These operate on different balances (DAO's balance vs. user's balance) and don't race. However, if the DAO's share balance is low, `buyShares` could fail after the last shares are transferred. This is expected behavior.

**`maxPay` slippage protection:**
- ETH path: `require(msg.value >= cost)` — `maxPay` is checked via `if (maxPay != 0 && cost > maxPay) revert`. If `msg.value >= cost` and `cost <= maxPay`, the user pays at most `maxPay`. Correct.
- ERC-20 path: Same `maxPay` check, then `safeTransferFrom(payToken, cost)` pulls exactly `cost`. Correct.

**`buyShares` cost overflow:** `uint256 cost = shareAmount * price` — Solidity 0.8.30 reverts on overflow. For extreme values (`shareAmount = 2^128, price = 2^128`), the product overflows and reverts. Users would need to use smaller amounts. Not a vulnerability.

**Conclusion:** No novel issues found — Known Finding #1 covers the cap sentinel.

---

### 8. Math / Precision

**`mulDiv` verification:**
```solidity
function mulDiv(uint256 x, uint256 y, uint256 d) pure returns (uint256 z) {
    assembly ("memory-safe") {
        z := mul(x, y)
        if iszero(mul(or(iszero(x), eq(div(z, x), y)), d)) {
            mstore(0x00, 0xad251c27) revert(0x1c, 0x04)
        }
        z := div(z, d)
    }
}
```
- **Overflow check:** `or(iszero(x), eq(div(z, x), y))` — if x=0 result is 0 (safe), otherwise checks `z/x == y` (i.e., `mul(x,y)` didn't overflow). If this is 0, AND `d` is 0, the revert triggers. Actually: `mul(0, d)` = 0, so if the overflow check fails, the product is 0, and `iszero(0)` = 1, causing revert. If `d = 0`, `mul(anything, 0) = 0`, `iszero(0) = 1`, reverts.
- **Division by zero:** If `d = 0`, the condition `mul(overflowOK, d)` = `mul(anything, 0)` = 0, triggering revert. Correctly handled.
- **Rounding:** `div(z, d)` floors. Consistent throughout.
- **Note:** This is NOT Solady's full `mulDiv` with 512-bit intermediate. If `x * y` overflows 256 bits, it reverts rather than handling it. For ragequit's `mulDiv(pool, amt, total)`, overflow requires `pool * amt > 2^256`. With `pool` as a token balance and `amt` as burned shares, both bounded by realistic values, this is safe in practice.

**Ragequit dust accumulation:** Repeated partial ragequits each floor-round `mulDiv(pool, burnAmt, total)`, leaving dust. Over many ragequits, the last holder gets slightly less (accumulated rounding). The dust stays in the DAO treasury. No profitable exploit — the attacker loses more in gas than they could extract via rounding manipulation.

**`uint96` vote tallies:** `type(uint96).max ≈ 7.9 × 10^28`. With 18 decimals, this represents ~79.2 billion tokens. A governance token with total supply exceeding this would overflow `toUint96` in checkpoint writes, reverting. This is a practical limitation, not a vulnerability — DAOs with >79B token supply should use a different framework.

**Split delegation BPS enforcement:** `setSplitDelegation` requires `sum == BPS_DENOM` (exactly 10000). If sum is 9999 or 10001, the transaction reverts with `SplitSum()`. The `_targetAlloc` function uses "remainder to last" to handle rounding in the multiplication, ensuring `sum(A[i]) == bal` exactly.

**Conclusion:** No issues found — math is correct, rounding is consistent (floor), BPS sum is enforced.

---

### 9. External Token Integration

**Blacklistable tokens (USDC/USDT):** If the DAO address is blacklisted for a token, `safeTransfer` in ragequit reverts. The user can omit that token from the `tokens` array. Known Finding #7.

**Fee-on-transfer tokens:** `ragequit` computes `due = mulDiv(pool, amt, total)` and calls `safeTransfer(token, to, due)`. The user receives `due - fee`. The accounting reads `balanceOfThis(token)` each iteration, so subsequent ragequitters see the actual (post-fee) balance. The first ragequitter gets slightly less than expected; later ragequitters also get less. No exploit — just a known limitation. Known Finding #8.

**Rebasing tokens:** If a rebase occurs during ragequit execution (between iterations), the balance changes. Since ragequit reads `balanceOfThis(tk)` per-token per-iteration, each token gets the current balance. This could benefit or harm the ragequitter depending on rebase direction. No exploit — the ragequitter chose to exit, accepting the balance at that moment.

**Return data bomb in `_execute`:** Return data is captured by `(ok, retData) = to.call{value: value}(data)`. A malicious target could return gigabytes of data, consuming gas for memory expansion. However, the target is specified by the executed proposal, which required a governance vote. Privileged-role rule applies. For `spendPermit`, the DAO set the target. Same rule.

**Conclusion:** No novel issues found — Known Findings #7 and #8 cover the blacklist/fee-on-transfer cases.

---

### 10. Delegation & Checkpoints

**Split delegation rounding:** `_targetAlloc` computes `part = mulDiv(bal, B[i], BPS_DENOM)` for all but the last delegate, who gets `remaining`. Since `mulDiv` floors, each `part <= bal * B[i] / 10000`. The sum of parts for delegates 0..n-2 is at most `bal * (10000 - B[n-1]) / 10000`, which is at most `bal - floor(bal * B[n-1] / 10000)`. The last delegate gets the exact remainder. Total delegated votes = `sum(parts) + remaining = bal`. No votes are created or destroyed.

**Same-block checkpoint overwrite:** `_writeCheckpoint` checks `if (last.fromBlock == blk)` and overwrites. This is standard behavior — multiple transfers in the same block update the same checkpoint. `getPastVotes` for any block < current block returns the correct historical value because the overwrite only affects the current block's entry.

**Circular delegation:** A delegates to B, B delegates to A. Each has their own `_delegates` / `_splits`. When A's balance changes, `_applyVotingDelta` distributes A's voting power according to A's distribution (pointing to B). When B's balance changes, B's voting power goes to A. There's no infinite loop — `_applyVotingDelta` only writes checkpoints for the delegates in the holder's distribution, not recursively following delegations. Voting power is not transitive in this model.

**Conclusion:** No issues found — split delegation math is exact via remainder-to-last, checkpoints handle same-block correctly, delegation is non-transitive.

---

## Round 2: Economic & Cross-Function Analysis

### Cross-Mechanism: castVote + Timelock Queue + state() Re-evaluation

**Observation:** The `state()` function re-evaluates vote tallies after a timelock elapses, but `castVote` does not check whether a proposal is queued. This creates a window where new votes can alter the outcome of a queued proposal.

**Attack path:**
1. A proposal passes: FOR > AGAINST, quorum met. `state(id)` returns `Succeeded`.
2. Someone calls `executeByVotes()` or `queue()`. `queuedAt[id]` is set to `block.timestamp`.
3. During the timelock period, `proposalTTL` is either 0 (no expiry) or has not elapsed.
4. An attacker with substantial snapshot voting power (who had not yet voted) calls `castVote(id, 0)` — voting AGAINST.
5. `castVote` passes all checks: not executed, not expired (TTL=0 or within TTL), not already voted, weight > 0 from snapshot.
6. After the timelock elapses, `state(id)` is queried: `queuedAt != 0`, `timestamp >= queued + delay`, falls through to tally re-evaluation. Now `forVotes <= againstVotes` → returns `Defeated`.
7. `executeByVotes` reverts because `state(id) == Defeated`.

**Economic analysis:** Cost = 0 (the attacker uses existing voting power from the snapshot). Gain = blocking a governance proposal. No direct profit, but could prevent unfavorable treasury movements or governance changes. This is asymmetric because `cancelVote` requires `state == Active`, which is no longer true once queued.

**Counter-argument:** One could argue the timelock period is *meant* to allow last-minute objections. However, most governance frameworks (Compound Governor, OpenZeppelin Governor) freeze voting before queueing. The issue is that `cancelVote` doesn't work post-queue, creating a one-directional griefing vector.

This is reported as **MED-1**.

### Cross-Mechanism: spendPermit + executeByVotes Namespace Interaction

The `spendPermit` function sets `executed[tokenId] = true` but does not check it beforehand. If a proposal with the same ID is executed first via `executeByVotes` (setting `executed[id] = true`), a permit holder can still call `spendPermit` — the `executed` flag is already true but never checked. This allows the same action to execute twice (once via governance, once via permit).

**Economic analysis:** Requires the DAO to have created both a proposal AND a permit for the exact same (op, to, value, data, nonce, config). This is a governance decision (the DAO explicitly authorized both paths). Under the privileged-role rule, this is downgraded to Low.

This is reported as **LOW-1**.

### Cross-Mechanism: ragequit + futarchy pool + sales

Ragequit draining futarchy pools is Known Finding #3 (by design). No novel cross-mechanism interaction found beyond the known findings.

### Cross-Mechanism: delegation + voting + split delegation

Delegation changes don't affect historical snapshots. A user who changes their split delegation after a proposal's snapshot doesn't gain additional voting power on that proposal — `getPastVotes` reads the checkpoint at the snapshot block. No attack vector.

---

## Round 3: Adversarial Validation

### MED-1: Post-Queue Voting Allows Griefing of Timelocked Proposals

**Disproof attempt:**

1. *Does `castVote` have an implicit queue check?* — No. It checks `executed`, TTL, `hasVoted`, and futarchy resolution. No check on `queuedAt`.
2. *Does `state()` return Active during the timelock, preventing the re-evaluation?* — No. During the timelock, `state()` returns `Queued`. After the timelock, it falls through to tally evaluation. The attacker votes DURING the timelock (when `castVote` is still open) and the re-evaluation happens AFTER.
3. *Is this a known finding?* — Not in the list of 14 known findings. Finding #4 (futarchy resolution timing) is related but distinct — it concerns futarchy payout, not proposal execution.
4. *Privileged-role rule?* — The attacker does NOT need a governance vote. They need voting power from the snapshot, which they already had as a regular token holder.
5. *Economic irrationality?* — No cost to the attacker. They exercise existing voting rights.

**Confidence: 82%** — The finding survives all checks. The small uncertainty is whether this is considered an intentional "safety valve" feature of the timelock design.

### LOW-1: spendPermit Does Not Check executed Flag

**Disproof attempt:**

1. *Can this happen without governance setup?* — No. The DAO must call both `setPermit` and have a proposal created with identical parameters. This requires a governance vote for `setPermit` (which is `onlyDAO`).
2. *Privileged-role rule?* — Applies. The DAO explicitly authorized both execution paths. Downgrade by 2 levels from Medium → Informational. However, the missing check is still a code-level defect that could surprise DAO operators, so I rate it Low.
3. *Is this a known finding?* — Finding #10 mentions ID namespace overlap but categorizes it as "astronomically unlikely collision." This finding is about intentional same-parameter usage, which is distinct.

**Confidence: 55%** — The governance setup requirement significantly weakens this finding.

### INF-1: fundFutarchy Missing nonReentrant Guard

**Disproof attempt:**

1. *Can a re-entrant token inflate the pool?* — Yes, an ERC-777 token with a `tokensToSend` hook could re-enter `fundFutarchy` before the first `safeTransferFrom` completes. However, the allowed reward tokens are: ETH (address 0), shares (address(this)), loot (address 1007), or actual shares/loot contract addresses. ETH, shares, and loot don't have re-entrant hooks. Only if `rewardToken` is set to an actual ERC-20 that implements ERC-777 hooks would this be exploitable.
2. *Impact if exploited?* — The attacker inflates `F.pool` with one token pull but gets credited for multiple `+= amount`. However, the attacker is the one calling `fundFutarchy` and paying — they'd need to fund with real tokens to re-enter. The inflation overstates the pool relative to actual tokens held, meaning futarchy payouts could exceed available funds, causing late claimers to fail. But this requires a pathological reward token.
3. *Privileged-role rule?* — Setting `rewardToken` to an ERC-777 token requires `setFutarchyRewardToken`, which is `onlyDAO`.

**Confidence: 30%** — Requires governance to set a pathological reward token AND that token to have re-entrant hooks.

---

## Confirmed Findings

### MED-1: Post-Queue Voting Allows Griefing of Timelocked Proposals

> **Review: Valid observation, but by design.** Code-verified: `castVote` (line 347) has no `queuedAt` check, `state()` (line 441-444) re-evaluates tallies after timelock elapses, and `cancelVote` (line 396) requires Active state. The attack path is technically correct — a holder who abstained during the Active period can cast AGAINST during the timelock and flip the outcome. However, **this is intentional behavior.** The Moloch timelock is designed as a reaction window — it gives members time to ragequit OR to register late objections before execution. Continued voting during the timelock is the "last objection" safety valve. The `cancelVote` asymmetry (blocked post-queue) is a side effect, not the design intent — the primary escape hatch is ragequit, not vote cancellation. **Reclassified: Low (design tradeoff).** The one-line fix (`if (queuedAt[id] != 0) revert`) would be a valid hardening option for DAOs that prefer Compound-style frozen timelocks, but it changes the governance model — it removes the late-objection window. This is a configuration preference, not a bug. **v2 consideration:** make post-queue voting configurable (e.g., `freezeOnQueue` flag).

**Severity:** Medium
**Confidence:** 82
**Category:** Governance Logic (Category 3)
**Location:** `Moloch`, functions `castVote` and `state`, interaction between vote acceptance and timelock re-evaluation

**Description:**
`castVote` does not check whether a proposal has been queued (`queuedAt[id] != 0`). Once a proposal is queued for timelock, `state()` returns `Queued` during the delay period. After the delay elapses, `state()` falls through and re-evaluates the vote tallies. Since `castVote` remains open during the timelock (as long as `proposalTTL` is 0 or has not expired), new AGAINST votes can be cast that flip the outcome from Succeeded to Defeated. Meanwhile, `cancelVote` requires `state(id) == Active`, which is never true once a proposal is queued — creating an asymmetric griefing vector where opponents can act but supporters cannot undo opposition.

**Attack Path:**
1. Proposal with `timelockDelay = 1 day` and `proposalTTL = 0` passes: 60 FOR, 40 AGAINST, quorum met.
2. Executor calls `executeByVotes(...)` → auto-queues, `queuedAt[id] = block.timestamp`.
3. During the 1-day timelock, a holder with 25 snapshot votes (who had not yet voted) calls `castVote(id, 0)` — voting AGAINST.
4. Tallies: 60 FOR, 65 AGAINST.
5. After 1 day, executor calls `executeByVotes(...)` again → `state(id)` re-evaluates: `forVotes (60) <= againstVotes (65)` → returns `Defeated` → revert.

**Proof of Concept:**
```solidity
// Assume: timelockDelay = 86400 (1 day), proposalTTL = 0
// Proposal `id` has passed and been queued

// During timelock, attacker (with 25 snapshot votes) griefs:
moloch.castVote(id, 0); // AGAINST — succeeds, no queue check

// After timelock:
// state(id) now returns Defeated because forVotes <= againstVotes
moloch.executeByVotes(op, to, value, data, nonce); // REVERTS: NotOk()
```

**Disproof Attempt:**
Checked whether `castVote` has any implicit queue check — it does not. Checked whether `state()` returns a stable result during timelock — after delay, it re-evaluates. Checked whether the attacker needs governance setup — they do not; any snapshot-weighted holder can exploit this. Verified this is not in the 14 known findings.

**Severity Justification:**
- Exploitable without DAO governance vote? **Yes** — requires only existing snapshot voting power
- Survives `nonReentrant` guard? **N/A**
- Survives snapshot-at-N-1? **Yes** — attacker uses legitimate historical voting power
- Economic cost of attack vs gain: **Zero cost** — casting a vote is free (gas only). Gain is blocking governance.
- Duplicates Known Finding #? **No**

**Recommendation:**
Add a queue check to `castVote`:
```solidity
if (queuedAt[id] != 0) revert NotOk();
```
This freezes voting once a proposal enters the timelock, consistent with standard governance frameworks (Compound Governor, OpenZeppelin Governor).

---

### LOW-1: spendPermit Does Not Check executed Flag, Allowing Double-Execution

> **Review: Valid code-level observation, borderline duplicate of Known Finding #10.** The missing `executed` check is real — `spendPermit` (line 668) sets `executed[tokenId] = true` without checking it first, while `executeByVotes` (line 502) does check. This creates asymmetric blocking: permit→blocks proposal (because `executeByVotes` checks `executed`), but proposal→does NOT block permit. The report correctly identifies that this requires two governance decisions with identical params (privileged-role rule). The distinction from KF#10 ("intentional reuse" vs "accidental collision") is a valid sharpening of the angle, but the root cause is the same shared namespace. **Severity: Low is appropriate.** The `_burn6909` receipt consumption is the actual replay guard — `executed` in `spendPermit` is a secondary protection for cross-path blocking. Adding `if (executed[tokenId]) revert AlreadyExecuted()` is a clean fix but changes the semantics: permits would become one-shot even across multiple receipt holders if a proposal executes first.

**Severity:** Low
**Confidence:** 55
**Category:** Access Control (Category 6)
**Location:** `Moloch`, function `spendPermit`

**Description:**
`spendPermit` sets `executed[tokenId] = true` but never checks `executed[tokenId]` before proceeding. If a proposal with the same ID has already been executed via `executeByVotes` (which does check and set `executed`), the same action can be executed a second time through `spendPermit`. The `executed` latch in `spendPermit` is write-only — it provides no replay protection.

**Attack Path:**
1. DAO creates a proposal to transfer 100 ETH to address X (op=0, to=X, value=100e18, data="", nonce=N).
2. DAO also calls `setPermit` with the same parameters, giving 1 receipt to spender S.
3. Proposal passes governance and is executed via `executeByVotes` → 100 ETH sent to X, `executed[id] = true`.
4. Spender S calls `spendPermit(0, X, 100e18, "", N)` → no check on `executed[id]`, burns 1 receipt, executes again → another 100 ETH sent to X.

**Disproof Attempt:**
Setting up step 2 requires a DAO governance vote (`setPermit` is `onlyDAO`). The DAO explicitly authorized both execution paths. Under the privileged-role rule, this is a governance decision — the DAO chose to allow the action twice. However, the missing `executed` check is still a code defect: DAO operators may not realize that creating a permit with the same parameters as a proposal enables double-execution.

**Severity Justification:**
- Exploitable without DAO governance vote? **No** — requires `setPermit` (onlyDAO)
- Privileged-role downgrade applied: Yes (High → Low)
- Duplicates Known Finding #? **No** — Finding #10 covers collision probability, not intentional reuse

**Recommendation:**
Add an `executed` check at the top of `spendPermit`:
```solidity
if (executed[tokenId]) revert AlreadyExecuted();
```

---

### INF-1: fundFutarchy Lacks Reentrancy Guard

> **Review: Description contains an error.** The report states "`fundFutarchy` modifies `F.pool += amount` before calling `safeTransferFrom(rt, amount)`" — the actual code at lines 566-569 shows `safeTransferFrom(rt, amount)` (line 566) is called BEFORE `F.pool += amount` (line 569). The interaction-before-effect ordering actually makes the reentrancy concern weaker, not stronger: a re-entrant call would pull real tokens before incrementing the pool, keeping the two in sync. The defense-in-depth recommendation to add `nonReentrant` is still reasonable, but the specific inflation scenario described does not work. **Severity: Informational is appropriate.** 30% confidence accurately reflects the weakness.

**Severity:** Informational
**Confidence:** 30
**Category:** Reentrancy (Category 1)
**Location:** `Moloch`, function `fundFutarchy`

**Description:**
`fundFutarchy` modifies `F.pool += amount` before calling `safeTransferFrom(rt, amount)`. If the reward token implements callback hooks (e.g., ERC-777 `tokensToSend`), a re-entrant call could inflate `F.pool` beyond the actual tokens transferred. However, the allowed reward tokens (ETH, shares, loot, or DAO-set ERC-20) are constrained by `setFutarchyRewardToken` (which is `onlyDAO`), and standard reward tokens don't have re-entrant hooks.

**Disproof Attempt:**
ETH path uses `msg.value` (no callback). Shares/loot sentinels (address(this), address(1007)) require `msg.sender == address(this)` — only the DAO itself can fund these, and internal calls don't trigger hooks. Only the `safeTransferFrom` path for external ERC-20s is vulnerable, and the token must be set by governance.

**Severity Justification:**
- Requires DAO governance vote to set pathological reward token: **Yes**
- Privileged-role downgrade applied: Yes
- Practical impact: Extremely unlikely with standard tokens

**Recommendation:**
Add `nonReentrant` modifier to `fundFutarchy` for defense-in-depth.

---

## Category Coverage Matrix

| Category | Result | Defense Verified |
|---|---|---|
| 1. Reentrancy | INF-1 (fundFutarchy minor gap) | EIP-1153 transient storage guard, multicall delegatecall preserves context |
| 2. Flash Loan / Vote Manipulation | No issues found | Snapshot at block.number - 1, getPastVotes with strict < block.number check |
| 3. Governance Logic | **MED-1 (post-queue voting)** | State machine sound except for post-queue tally re-evaluation |
| 4. Economic / Ragequit | No issues found | Pre-burn total capture, sorted ascending array, nonReentrant |
| 5. Futarchy | No issues found (covered by Known Findings #4, #6, #13) | Resolution tied to state machine, payoutPerUnit immutable after set |
| 6. Access Control | **LOW-1 (spendPermit executed check)** | onlyDAO correct, SBT gate complete, init practically one-shot |
| 7. Token Sales | No issues found (covered by Known Finding #1) | maxPay slippage, Solidity 0.8 overflow checks |
| 8. Math / Precision | No issues found | mulDiv overflow check + div-by-zero, remainder-to-last for BPS, uint96 sufficient for realistic supplies |
| 9. External Token Integration | No issues found (covered by Known Findings #7, #8) | Sorted array allows omission, safeTransfer handles USDT |
| 10. Delegation & Checkpoints | No issues found | Non-transitive delegation, same-block overwrite is standard, BPS sum enforced exactly |

---

## Invariant Verification

| # | Invariant | Status | Evidence |
|---|---|---|---|
| 1 | `Shares.totalSupply == sum(balanceOf)` | **Verified** | `_mint` adds to both, `_moveTokens` subtracts+adds, `burnFromMoloch` subtracts both. All arithmetic checked or correctly unchecked. |
| 2 | `ERC6909: totalSupply[id] == sum(balanceOf[user][id])` | **Verified** | `_mint6909` adds totalSupply (checked) then balance (unchecked safe because total checked first). `_burn6909` subtracts balance (checked) then total (unchecked safe because balance >= amount implies total >= amount). `transfer/transferFrom` subtract sender + add receiver. |
| 3 | Proposal state machine ordering | **Verified with caveat** | States follow Unopened → Active → {Succeeded, Defeated, Expired} → Queued → Executed. No skip or reversal. **Caveat:** A Queued proposal can regress to Defeated after timelock via post-queue voting (MED-1). |
| 4 | `executed[id]` one-way latch | **Verified** | Set to `true` in `executeByVotes`, `spendPermit`, and `cancelProposal`. Never set back to `false` anywhere. |
| 5 | Ragequit conservation | **Verified** | `due = mulDiv(pool, amt, total)` with `total` captured pre-burn. `amt <= total` (burn would revert otherwise). `due <= pool` (mulDiv floors). |
| 6 | Futarchy payout immutability | **Verified** | `_finalizeFutarchy` sets `payoutPerUnit` inside the `if (!F.resolved)` guard in `_resolveFutarchyYes`/`resolveFutarchyNo`. The `F.resolved = true` latch prevents re-entry. |
| 7 | No admin keys post-init | **Verified** | All settings functions are `onlyDAO`. `SUMMONER` is only used for `init()`. No owner, no multisig, no privileged EOA. |
| 8 | Snapshot supply frozen at creation | **Verified** | `supplySnapshot[id]` is written in `openProposal` when `snapshotBlock[id] == 0` (first open). The `if (snapshotBlock[id] != 0) return` guard ensures it's only set once. No other code path writes to `supplySnapshot`. |

---

## Architecture Assessment

Moloch.sol represents a mature, opinionated governance framework that prioritizes exit rights (ragequit) and self-sovereignty (no admin keys) over operational flexibility. The defensive architecture is notably strong: the transient-storage reentrancy guard, snapshot-at-N-1, and non-payable multicall collectively eliminate the three most commonly exploited DAO vulnerability classes (reentrancy, flash-loan governance attacks, and msg.value reuse).

The code quality is high for a ~2100-line single-file system. The use of assembly for safe transfers, mulDiv, and checkpoints reflects careful gas optimization without sacrificing safety. The ERC-6909 receipt system for vote tracking and futarchy is an elegant design that enables composable prediction markets on governance outcomes.

The primary area of concern is the governance state machine's interaction with the timelock — specifically, the lack of voting freeze after queueing (MED-1). This is a design gap rather than a bug: the timelock was implemented as a delay mechanism but voting was not wired to respect the queue state. Most other governance frameworks (Compound, OpenZeppelin Governor) either freeze voting at queue time or lock tallies. A one-line fix in `castVote` would resolve this.

The futarchy subsystem adds significant complexity and surface area, but the known findings (#4, #5, #6, #13) are well-documented edge cases rather than exploitable vulnerabilities. The ragequit system correctly handles the delicate balance between exit rights and pool commitments, with the intentional design decision that exit supersedes futarchy earmarks.

Overall, this is a well-defended codebase with no critical or high-severity findings. The novel issues are narrow interaction-layer concerns that are addressable with minimal code changes.
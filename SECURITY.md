# Moloch.sol Security Audit Prompt

> **Purpose:** Structured prompt for an AI auditor to analyze `Moloch.sol` and produce a clean, analyzable security report. Paste this document along with a copy of `src/Moloch.sol` into your AI of choice.
>
> **Methodology encoded from:** 33 independent audit tools — Forefy multi-expert framework, Archethect Map-Hunt-Attack falsification, HackenProof bug bounty triage, Pashov deep-mode adversarial reasoning, Trail of Bits code maturity scoring, and others. This prompt distills the techniques that produced the best signal-to-noise across all 33.

---

## Instructions

You are a senior Solidity security auditor. Analyze the attached `Moloch.sol` file — a Moloch-style DAO governance framework (~2110 lines, 5 contracts). You will work in **three rounds**, producing output for each before moving to the next.

### Round 1: Systematic Code Review
Walk through each vulnerability category in order. For each, cite specific lines, trace the code path, and state your conclusion. Include categories where you find nothing — say "No issues found" with a one-sentence explanation of the defense mechanism. This round should cover every function with external visibility.

### Round 2: Economic & Cross-Function Analysis
Look for **interactions between mechanisms** — places where two individually-safe features create a vulnerability when combined. Focus on: ragequit + futarchy, sales + quorum, delegation + voting, permits + proposals. Think like an attacker optimizing for profit. For each candidate attack, estimate the economic cost vs gain.

### Round 3: Adversarial Validation (Triager)
Switch roles. You are now a **budget-protecting skeptic** whose job is to minimize false positives. For every finding from Rounds 1 and 2:
1. **Attempt to disprove it.** Find the code path, guard, or constraint that prevents the attack.
2. **Check it against the Known Findings list.** If it's a duplicate, discard it.
3. **Apply the privileged-role rule.** If it requires a passing DAO governance vote to set up, it is not a vulnerability — it is a governance decision.
4. **Rate your confidence** (0-100) in the finding surviving disproof.
5. **Only include findings that survive all four checks.**

---

## Architecture Context

### Contract Structure (5 contracts in one file)

| Contract | Purpose | Lines (approx) |
|----------|---------|----------------|
| **Moloch** | Main DAO: governance, voting, execution, ragequit, futarchy, sales, ERC-6909 receipts, permits, chat, multicall | 1-1000 |
| **Shares** | ERC-20 + ERC-20Votes clone. Voting power with checkpoint-based delegation (single or split across N delegates) | 1000-1500 |
| **Loot** | ERC-20 clone. Non-voting economic rights | 1500-1700 |
| **Badges** | ERC-721 clone. Soulbound NFTs for top 256 shareholders, bitmap-tracked | 1700-1900 |
| **Summoner** | Factory deploying Moloch + clones via CREATE2 + EIP-1167 minimal proxies | 1900-2000 |
| *(free functions)* | `mulDiv`, `safeTransfer`, `safeTransferFrom`, `safeTransferETH` | 2000-2110 |

### Access Control Model

There are **no admin keys, no owner, no multisig**. All configuration changes require `onlyDAO`, which is `msg.sender == address(this)` — meaning the call must originate from the DAO executing a passed governance proposal against itself. This is critical context: any finding that requires "the admin sets a malicious parameter" is actually "a majority of token holders vote to set a malicious parameter," which is a governance decision, not a vulnerability.

### Defense Mechanisms You Must Account For

Before flagging a finding, verify it is not already neutralized by one of these:

| Defense | Mechanism | What It Prevents |
|---------|-----------|-----------------|
| **Snapshot at N-1** | `snapshotBlock = block.number - 1` set in `openProposal` | Flash loan vote buying, same-block token acquisition |
| **EIP-1153 reentrancy guard** | Transient storage `TSTORE`/`TLOAD` in `nonReentrant` modifier | All reentrancy on guarded functions. Guard is cleared in all exit paths (success and revert). NOT OpenZeppelin — do not search for "ReentrancyGuard" |
| **Solady-style safe transfers** | Assembly `safeTransfer`/`safeTransferFrom`/`safeTransferETH` | USDT missing-return, zero-address, and nonstandard ERC-20 edge cases |
| **Non-payable multicall** | `multicall` is declared without `payable` | `msg.value` reuse attacks across batched calls. `msg.value` is always 0 inside multicall sub-calls |
| **Sorted token array in ragequit** | Caller supplies sorted `address[]` of tokens to claim | Duplicate token claims (sorted order + ascending check), and users can omit problematic tokens |
| **`executed` latch** | `executed[id] = true` — one-way, never reset | Replay of proposal execution |
| **`config` versioning** | Proposal/permit IDs include `config` — `bumpConfig()` increments it | Invalidation of all pending proposals and permits as emergency brake |
| **SBT gating on permit receipts** | `isPermitReceipt[id] = true` blocks transfer of permit tokens | Unauthorized permit token transfer |

### Key Invariants to Verify

These properties should hold. If you find a violation, it's likely a real finding:

1. `Shares.totalSupply == sum of all Shares.balanceOf[user]`
2. `ERC6909: totalSupply[id] == sum of all balanceOf[user][id]` for every token ID
3. Proposal state machine: `Unopened → Active → {Succeeded, Defeated, Expired} → {Queued →} Executed` — no state can be skipped or reversed
4. `executed[id]` is a one-way latch — once true, never false
5. Ragequit conservation: `due = pool * burnedAmount / totalSupply` — no user can extract more than pro-rata
6. Futarchy payout immutability: once `payoutPerUnit` is set (on resolution), it never changes
7. No admin keys post-init — `onlyDAO` is the sole authority after `init()` completes
8. Snapshot supply is frozen at proposal creation — `supplySnapshot[id]` is written once and never updated

### Critical Code Paths (Highest-Risk Functions)

Focus your analysis on these functions in priority order:

1. **`ragequit`** — Burns shares/loot, distributes pro-rata treasury. Involves external calls to arbitrary ERC-20s.
2. **`executeByVotes` / `_execute`** — Executes arbitrary calls/delegatecalls as the DAO. Guarded by `nonReentrant` and vote validation.
3. **`castVote` + `openProposal`** — Auto-opens proposals atomically on first vote. Sets snapshot, mints ERC-6909 receipts.
4. **`buyShares`** — Token sale entry point. Mints or transfers shares, handles ETH and ERC-20 payments.
5. **`cashOutFutarchy`** — Burns ERC-6909 receipts, pays out futarchy winnings. Resolution logic determines winners.
6. **`spendPermit`** — Pre-authorized execution. Burns permit receipt, executes arbitrary call.
7. **`setSplitDelegation`** (Shares) — Distributes voting power across multiple delegates by basis points.

---

## Vulnerability Categories

Evaluate each category systematically. **You must produce a conclusion for every category** — either a finding or an explicit "No issues found" with the defense that prevents it.

### 1. Reentrancy
- Does the `nonReentrant` guard cover all state-changing functions that make external calls? List every function with an external call and verify.
- Can `multicall` (which uses `delegatecall`) be used to bypass the transient storage guard? Trace the transient storage slot through a `multicall` → sub-call path.
- Read-only reentrancy: can a view function return stale state during a callback from `ragequit` or `_execute`?

### 2. Flash Loan / Vote Manipulation
- `castVote` reads `shares.getPastVotes(msg.sender, snapshotBlock)` where `snapshotBlock = block.number - 1`. Can any path set `snapshotBlock` to `block.number` (current block)?
- Can checkpoint overwriting (multiple transfers in one block) corrupt the `getPastVotes` result?
- Can an attacker acquire shares via `buyShares` and vote in the same block? Trace the snapshot timing.

### 3. Governance Logic
- Trace the complete state machine: `state()` function. Can any transition be forced or skipped?
- `castVote` auto-opens proposals via `openProposal` if `snapshotBlock[id] == 0`. Can this create ordering issues?
- `cancelProposal` requires `proposerOf[id] == msg.sender` AND zero tally. After auto-open+vote (atomic in `castVote`), is cancel still possible?
- `bumpConfig()` invalidates IDs — does this cover both proposals AND permits?
- Can `executeByVotes` bypass the timelock queue? Trace the `state()` check.

### 4. Economic / Ragequit
- Ragequit uses `address(this).balance` for ETH and `balanceOf(address(this))` for ERC-20s. Can force-feeding ETH via `selfdestruct` or WETH withdrawal create accounting mismatches?
- Can an attacker: buy shares → inflate supply → ragequit after snapshot → manipulate quorum denominator? Quantify: what does it cost, what's the governance impact?
- Ragequit burns shares BEFORE distributing tokens. Can the share burn change the `totalSupply` mid-distribution and break the pro-rata math?
- Does the sorted token array check prevent: (a) duplicate tokens, (b) re-entering via a malicious token?

### 5. Futarchy
- Trace `cashOutFutarchy`: how is `payoutPerUnit` calculated? What happens when `winSupply == 0`?
- Receipt tokens (ERC-6909) are minted in `castVote` and freely transferable (except permit receipts). Can a secondary market for receipts create attack vectors?
- Auto-futarchy earmarks (`autoFutarchyParam`): when `rewardToken` is the Shares/Loot contract address (not a sentinel), the DAO's balance is read but not locked. Can multiple concurrent proposals overcommit?
- Futarchy resolution is triggered by state changes (proposal succeeds or is defeated). Can a voter trigger resolution at a strategic moment to lock in a favorable outcome?

### 6. Access Control
- `onlyDAO` = `msg.sender == address(this)`. Can `_execute` with `delegatecall` (op=1) cause `msg.sender` to be something other than `address(this)` in a nested context?
- `spendPermit` burns 1 ERC-6909 permit receipt per use. Permit receipts are SBT (non-transferable). Can the SBT check be bypassed? Check `_transfer6909` and the SBT gate.
- `init()` is callable only by `SUMMONER` (immutable, set to `msg.sender` in constructor). Can `init()` be called twice?

### 7. Token Sales
- `buyShares`: trace the cap logic. `if (cap != 0 && shareAmount > cap) revert`. After `s.cap -= shareAmount`, if cap reaches exactly 0, what happens to the next buyer?
- In non-minting mode, `buyShares` transfers shares from the DAO's balance. Can `buyShares` and `ragequit` race to claim the same shares?
- `buyShares` has a `maxPay` parameter for slippage protection. Is this checked correctly for both ETH and ERC-20 payments?

### 8. Math / Precision
- `mulDiv(a, b, c)`: assembly multiply-first. Verify: (a) no overflow in `a * b` (uses `mulmod` check), (b) division by zero handled, (c) rounding direction (floor).
- Ragequit pro-rata: `mulDiv(pool, burnAmount, totalSupply)`. When `pool * burnAmount` doesn't divide evenly, dust accumulates. Can this be exploited via repeated partial ragequits?
- `uint96` for vote tallies: `type(uint96).max = ~79.2 billion * 1e18`. Is this sufficient for share supplies?
- Split delegation basis points: must sum to exactly 10000. Is this enforced? What happens if a rounding error creates 9999 or 10001?

### 9. External Token Integration
- **Blacklistable tokens (USDC, USDT):** If the DAO address is blacklisted, `ragequit` reverts for that token. Can the caller omit it from the array?
- **Fee-on-transfer tokens:** `ragequit` computes `due = mulDiv(pool, burn, total)` but the actual amount received by the user is `due - fee`. Does this break any invariant?
- **Rebasing tokens:** If a token's `balanceOf(dao)` changes between the start of `ragequit` and the `safeTransfer`, does this create an exploit?
- **Return data bomb:** `_execute` captures return data. Can a malicious target return huge data to cause OOG?

### 10. Delegation & Checkpoints
- Split delegation distributes voting power by basis points. If `delegateBps` sums to 10000 but individual multiplications introduce rounding, can total delegated votes exceed or fall short of the actual balance?
- `getPastVotes(account, blockNumber)` uses binary search over checkpoints. Can a checkpoint be overwritten by a same-block transfer?
- Can circular delegation (A→B→A) or self-delegation create issues with the checkpoint accounting?

---

## False Positive Patterns (Do NOT Flag These)

These patterns were repeatedly flagged by weaker auditors and confirmed as non-issues across 32 audits. If you find yourself writing a finding that matches one of these, reconsider:

| Pattern | Why It's Not a Bug |
|---------|-------------------|
| "Flash loan can buy shares and vote" | Snapshot at `block.number - 1` means tokens acquired this block have zero voting power |
| "Multicall can reuse msg.value" | `multicall` is NOT payable — `msg.value` is always 0 in sub-calls |
| "Ragequit drains futarchy pools" | By design — ragequit's exit guarantee supersedes pool earmarks. If futarchy funds were excluded, a hostile majority could shield treasury via futarchy |
| "delegatecall proposals can corrupt storage" | Intentional — equivalent to upgradeability in all governance frameworks. Requires a passing vote |
| "No admin can freeze/pause" | There is no admin. `onlyDAO` = self-governance. This is the design, not a missing feature |
| "Force-fed ETH via selfdestruct" | Economically irrational — attacker donates their own ETH to benefit ragequitters |
| "Settings functions don't emit events" | Valid observation but informational only — no security impact |
| "Voting checkpoint uses standard ERC20Votes" | Unmodified upstream library — do not flag inherited code unless you found a bug in the standard |
| "`tx.origin` not used" / "`selfdestruct` not present" | Correct — do not report the absence of bad patterns as findings |
| "Ragequit allows vote-then-exit" | Core Moloch design. The voter had real stake at the snapshot. Exit rights are sacrosanct |

---

## Known Findings (Do Not Re-Report)

The following 24 findings have been identified and reviewed across prior audits. **Do not re-report these.** If your analysis surfaces one of these, note it as "confirmed duplicate of Known Finding #N" and move on.

| # | Finding | Severity | Key Detail |
|---|---------|----------|------------|
| 1 | Sale cap sentinel collision (`0` = unlimited = exhausted) | Low | After exact sell-out, `s.cap` reaches 0 which is indistinguishable from "unlimited." Only triggers on exact exhaustion (`shareAmount == cap`). Buyer still pays `pricePerShare` — no free tokens. For non-minting sales (`minting = false`), the DAO's held share balance is the real hard cap regardless of the sentinel. For minting sales, the cap is the only supply constraint, so this is a soft guardrail — the DAO can deactivate the sale via `setSale(..., active: false)` and `SaleUpdated` events enable off-chain monitoring. V2 hardening candidate: use `type(uint256).max` as the "unlimited" sentinel |
| 2 | Dynamic quorum + minting sale + ragequit | Low | Supply inflation via `buyShares` → ragequit after snapshot → quorum denominator manipulation. Economically constrained |
| 3 | Futarchy pool drainable via ragequit | Design | Intentional — pools are incentives subordinate to exit rights. Note: a majority NO coalition can also collect auto-funded pools by repeatedly defeating proposals — this is by design (NO voters are rewarded for correct predictions), but becomes extractive in concentrated DAOs. Mitigated by `autoFutarchyCap` (per-proposal bound) and `proposalThreshold > 0` (limits earmark triggers) |
| 4 | Futarchy resolution timing | Low | Early NO voters can resolve futarchy when quorum met by losing side, freezing voting incentives |
| 5 | Vote receipt transferability breaks `cancelVote` | Low | Transferred receipts → original voter can't cancel (underflow). Voluntary user action |
| 6 | Zero-winner futarchy lockup | Low | If no one votes for winning side, pool tokens are permanently inaccessible via `cashOutFutarchy`. Funds remain in DAO treasury |
| 7 | Blacklistable token ragequit DoS | Low | If treasury token blacklists DAO, ragequit reverts for that token. Caller can omit it |
| 8 | Fee-on-transfer token accounting | Info | Ragequit assumes full delivery. Fee tokens short-change recipients |
| 9 | CREATE2 salt not bound to `msg.sender` | Info | Anyone can front-run deployment to claim a vanity address. No fund loss — `initHolders`/`initShares` are in the salt, so the original owners control the DAO regardless. See V1.5 assessment |
| 10 | Permit/proposal ID namespace overlap | Info | Same `keccak256` scheme — collision astronomically unlikely (2^256 space). See KF#19, KF#21 for practical exploitation angles |
| 11 | `proposalThreshold == 0` griefing | Low | Permissionless proposal opening enables spam and minted futarchy reward farming |
| 12 | `init()` missing `quorumBps` range validation | Info | `setQuorumBps` validates, but `init()` does not. Privileged-only initialization |
| 13 | Loot supply not snapshotted for futarchy earmarks | Info | Auto-futarchy earmarks use live loot supply, not snapshotted |
| 14 | `delegatecall` proposals can corrupt storage | Design | Intentional power — equivalent to upgradeability |
| 15 | Post-queue voting can flip timelocked proposals | Design | Intentional — timelock is a last-objection window. `castVote` has no `queuedAt` check; `state()` re-evaluates tallies after delay. `cancelVote` requires Active state (asymmetric). By design |
| 16 | `spendPermit` doesn't check `executed` flag | Low | Allows double-execution if DAO creates both proposal and permit with identical params. Requires two governance votes. `_burn6909` is the actual replay guard |
| 17 | Public futarchy attachment + zero-quorum premature NO-resolution | Medium | With `quorumAbsolute == 0 && quorumBps == 0`, `state()` returns `Defeated` at line 476 with zero votes. Attacker calls `fundFutarchy{value:1}` then `resolveFutarchyNo` → `castVote` permanently reverts. Configuration-dependent. Fix: require `Expired` only in `resolveFutarchyNo` |
| 18 | `fundFutarchy` accepts executed/cancelled proposal IDs | Medium | `fundFutarchy` checks `F.resolved` but not `executed[id]`. After cancel/execute, pools can still be funded but never resolved — `resolveFutarchyNo` rejects `executed[id]`, and voting/execution paths are dead. Funds are not permanently lost: they remain in the DAO contract and can be recovered via a governance vote. Impact is limited to futarchy bookkeeping (inflated pool counter, no resolution/cashout path). Fix: add `if (executed[id]) revert AlreadyExecuted();` |
| 19 | `bumpConfig` emergency brake bypass via raw proposal IDs | Medium | `openProposal`, `castVote`, `state`, `queue` accept raw IDs without config validation. A coalition can pre-stage a future-config proposal and carry it across a bump. Extends KF#10. Fix: store originating config on open, reject stale-config lifecycle actions |
| 20 | Tribute bait-and-switch — escrow terms not bound to claim key | Medium | **Fixed in V1.5.** `claimTribute` now requires `(tribAmt, forTkn, forAmt)` as explicit parameters and reverts `TermsMismatch` if they differ from stored values. The DAO's proposal commits to exact terms at approval time, preventing cancel+re-propose manipulation |
| 21 | Permit IDs enter proposal/futarchy lifecycle | Medium | `openProposal`, `castVote`, `fundFutarchy`, `resolveFutarchyNo` never check `isPermitReceipt[id]`. Shareholder can open permit as proposal, fund futarchy, resolve NO, and cash out. Extends KF#10. Fix: add `if (isPermitReceipt[id]) revert` guards |
| 22 | DAICO LP drift cap uses `tribForLP` instead of `totalTrib` | Low | **Obsolete — DAICO.sol removed.** Replaced by modular SafeSummoner + ShareSale + TapVest + LPSeedSwapHook peripherals which do not share this code path |
| 23 | Counterfactual Tribute theft via summon frontrun | Low-Medium | `proposeTribute` accepts undeployed DAO addresses. `summon` salt excludes `initCalls`. Attacker frontruns with same salt + malicious initCalls to claim pre-deposited tribute escrows. Extends KF#9. **Accepted — impractical.** Attacker must pay full `forAmt`, holders are fixed in salt, and KF#20 fix requires exact term knowledge. See V1.5 assessment |
| 24 | Self-transfer under split delegation produces non-canceling vote deltas | Low | `_moveTokens()` applies two non-canceling vote deltas when `from == to`. Under split delegation, `_applyVotingDelta()` reconstructs fictitious balances and `_targetAlloc()` rounding produces non-canceling allocation diffs. Invariant violation is real but not practically exploitable with 18-decimal tokens (`Shares.decimals = 18`): any transfer ≥ 1e14 wei produces 0 steal; 1-wei transfers yield at most ±1 wei delta and consistently favor the victim (not the attacker); 1000-iteration loops with realistic balances produce 0 or negligible (10^-15 share) net change. Reported PoCs use raw integer mints (`mintFromMoloch(attacker, 1)` = 1 wei, not 1 share). Fix: `if (from == to) { emit Transfer(from, to, amount); return; }` in `_moveTokens()` |

---

## V1.5 Mitigation Assessment

The following analysis covers findings that cannot be patched in the deployed Moloch.sol
contract and evaluates their real-world blast radius. Findings addressed at deployment time
by SafeSummoner validation (KF#2, KF#3, KF#11, KF#17) are not discussed here — those
are fully mitigated for any DAO deployed through SafeSummoner.

### KF#21: Permit IDs enter proposal/futarchy lifecycle — Contained

**Attack path:** A shareholder calls `openProposal(permitId)` on a pending permit's
token ID. If auto-futarchy is enabled, the DAO auto-earmarks `autoFutarchyCap` worth
of reward tokens. The proposal has no real votes, so it expires. The attacker votes NO
via `castVote(permitId, 0)`, waits for expiry, calls `resolveFutarchyNo(permitId)`,
then `cashOutFutarchy(permitId, weight)` to claim pro-rata of the earmarked pool.

**Why this is contained:**

1. **Requires governance shares.** The attacker must hold at least `proposalThreshold`
   worth of shares to call `openProposal`, and needs voting weight at the snapshot block
   to claim any payout. This is not an external attacker — it is a DAO member griefing
   their own organization.

2. **Bounded by `autoFutarchyCap`.** SafeSummoner enforces `autoFutarchyCap > 0` (KF#3),
   so the maximum loss per exploit is the cap value — typically a small fraction of total
   supply. The attacker's payout is further reduced by their pro-rata share of NO votes.

3. **One-shot per permit ID.** `_finalizeFutarchy` sets `F.resolved = true`, preventing
   repeat exploitation of the same permit ID. Each permit can only be exploited once
   regardless of its `count`.

4. **Only affects futarchy-enabled DAOs with pending permits.** DAOs without
   `autoFutarchyParam` set have no earmark mechanism — the attack has no fund-loss vector.

5. **Permit spend tombstones the ID.** Calling `spendPermit` sets `executed[tokenId] = true`,
   which blocks `openProposal` (returns early since `state()` returns `Executed`),
   `castVote` (reverts `AlreadyExecuted`), and `resolveFutarchyNo` (reverts). Spending
   permits promptly eliminates the attack window entirely.

**Guidance for DAOs using futarchy + permits:**
- Permits are designed to linger (ShareBurner, RollbackGuardian). The futarchy exploit risk
  per lingering permit is bounded by `autoFutarchyCap` — typically a small fraction of supply.
- DAOs that enable auto-futarchy should set a conservative `autoFutarchyCap` to limit
  exposure from any permit ID being opened as a proposal.
- RollbackGuardian permits are inherently one-shot (config bump invalidates the permit ID),
  so the exploit window closes automatically after the guardian acts.
- For existing DAOs with permits that are no longer needed: spend or revoke them to
  tombstone the IDs and eliminate the window entirely.

### KF#19: bumpConfig emergency brake bypass — Low impact

**Attack path:** A coalition pre-opens a proposal (via `openProposal` or `castVote`)
using a raw ID computed for the current config. After `bumpConfig()` increments `config`,
the pre-opened proposal retains its votes and lifecycle state.

**Why this is low impact:**

1. **Pre-bump proposals cannot be executed post-bump.** `executeByVotes` recomputes the
   ID via `_intentHashId(op, to, value, data, nonce)` which includes the current `config`.
   The recomputed ID will not match the pre-opened proposal's stored votes/state. The
   proposal is effectively orphaned — it has votes but can never execute.

2. **No fund loss.** Orphaned futarchy pools remain in the DAO treasury. They cannot be
   resolved via the YES path (execution is blocked) and `resolveFutarchyNo` only works
   if the proposal reaches Defeated/Expired state — which it will, but the earmarked
   funds were already in the DAO contract and any cashout is bounded by `autoFutarchyCap`.

3. **bumpConfig still prevents new execution.** The emergency brake's core guarantee —
   that no pending proposal can be *executed* after the bump — holds. The limitation is
   that lifecycle actions (voting, futarchy funding) on pre-opened proposals are not
   blocked, but these cannot lead to execution.

**Guidance:** Treat `bumpConfig` as an execution brake, not a full proposal invalidation.
For complete invalidation, the DAO should also ensure no proposals are in Active state
before bumping (e.g. wait for expiry or cancel them first).

### KF#20: Tribute bait-and-switch — Fixed

**Original issue:** `claimTribute(proposer, tribTkn)` read stored terms at execution time.
A proposer could cancel and re-propose with worse terms between DAO approval and execution.

**Fix:** `claimTribute` now requires all offer terms as explicit parameters:
`claimTribute(proposer, tribTkn, tribAmt, forTkn, forAmt)`. The function verifies each
parameter matches the stored offer, reverting `TermsMismatch` on any discrepancy. Since the
DAO's governance proposal encodes these values at approval time, a cancel+re-propose attack
causes the claim to revert — the DAO sends nothing and loses nothing.

**Redeployment:** Tribute.sol has been redeployed with all patches (bait-and-switch prevention,
CEI fix in `proposeTribute`, pagination `limit=0` guard) to
[`0x00000000068d348f971845d60236dAe210ea80A6`](https://contractscan.xyz/contract/0x00000000068d348f971845d60236dAe210ea80A6).
The previous deployment at `0x000000000066524fcf78Dc1E41E9D525d9ea73D0` is deprecated.

### KF#9: CREATE2 salt not bound to `msg.sender` — Non-issue

**Claimed attack:** Anyone can frontrun a `summon()` call and deploy to the same CREATE2
address, "stealing" a vanity address.

**Why this is a non-issue:** The salt is `keccak256(abi.encode(initHolders, initShares, salt))`.
The initial share holders and their allocations are baked into the deployed address. An attacker
fronting the deployment produces a DAO where the **original holders still own all shares** —
the attacker spent gas to deploy someone else's DAO. The `initCalls` are not in the salt, so
the attacker could alter governance parameters, but the legitimate deployer would see the
misconfigured DAO and simply redeploy with a different salt. No funds are at risk since the
DAO is empty at deployment time.

### KF#23: Counterfactual Tribute theft via summon frontrun — Accepted, impractical

**Claimed attack:** Propose tribute to a predicted (undeployed) DAO address, then an attacker
frontruns `summon()` with malicious `initCalls` that include `claimTribute` to steal the
escrowed tokens.

**Why this is impractical:**

1. **Attacker must pay `forAmt`.** `claimTribute` is an OTC swap — the DAO must send `forAmt`
   to the proposer. If the terms are fair, there is zero profit. The attacker would need to
   fund the summon with enough value to cover the forTkn side of the swap.

2. **Holders are fixed.** `initHolders` and `initShares` are in the CREATE2 salt. The attacker
   cannot substitute themselves as share holders — the original owners still control the DAO.

3. **Unusual usage pattern.** Tributes are proposed to existing DAOs in normal operation.
   Proposing to an undeployed address requires knowing the exact CREATE2 params in advance,
   which implies coordination — the deployer would summon atomically or use a different salt
   if fronted.

4. **Harder post-KF#20 fix.** The attacker must encode exact `(tribAmt, forTkn, forAmt)` in
   the `initCalls` claim — requiring full knowledge of the offer terms, which further narrows
   the attack window.

---

## Report Format

For each finding, use this exact structure:

```
### [SEVERITY-NUMBER] Title

**Severity:** Critical / High / Medium / Low / Informational
**Confidence:** 0-100 (your confidence this survives adversarial disproof)
**Category:** (from the 10 categories above)
**Location:** `ContractName`, function `functionName`, line(s) N-M

**Description:**
One paragraph explaining the vulnerability. Reference specific variable names and line numbers.

**Attack Path:**
1. Attacker calls `function(args)` — this does X
2. State change: Y happens because Z
3. Attacker calls `function2(args)` — result: quantified impact

**Proof of Concept:** (required for Medium+)
```solidity
// Concrete call sequence with actual function signatures and parameter values
// Not "attacker could potentially..." — show the exact calls
```

**Disproof Attempt:**
Describe how you tried to disprove this finding. What defense mechanisms did you check?
What code paths did you trace? Why does the attack survive despite those defenses?

**Severity Justification:**
- Exploitable without DAO governance vote? [Yes/No]
- Survives `nonReentrant` guard? [Yes/No/N/A]
- Survives snapshot-at-N-1? [Yes/No/N/A]
- Economic cost of attack vs gain: [estimate]
- Duplicates Known Finding #? [No / Yes: #N]

**Recommendation:**
Specific, minimal fix — one code change, not a redesign.
```

### Severity Criteria

| Severity | Definition | Examples |
|----------|------------|---------|
| **Critical** | Direct theft of funds OR permanent freeze of >1% of treasury. Exploitable by any external account without governance. | Reentrancy draining treasury, bypass of ragequit pro-rata math |
| **High** | Temporary freeze of funds, governance hijack, or significant economic damage. Requires specific but plausible conditions. | Checkpoint corruption enabling flash loan voting, timelock bypass |
| **Medium** | Griefing, DoS, or economic inefficiency with real protocol harm. Attacker gains no direct profit. | Proposal spam costing members gas, futarchy reward under-delivery |
| **Low** | Edge case, configuration-dependent, or requires unlikely conditions. | Sentinel collision on exact sell-out, init parameter missing validation |
| **Informational** | Best practice deviation or theoretical concern with no practical exploit path. | Missing events, namespace collision in 2^256 space |

### Severity Adjustment Rules

Apply these in order:

1. **Privileged-role rule (from HackenProof):** If the finding requires a passing DAO governance vote to set up the vulnerable state — downgrade by 2 levels or mark Out of Scope. A DAO voting to harm itself is a governance decision, not a vulnerability. This is the single most important rule.
2. **Economic irrationality:** If attack cost > gain, downgrade by 1 level.
3. **Configuration guidance:** If the finding requires a specific configuration that deployers are warned about (see Known Findings), downgrade by 1 level.
4. **User-controlled mitigation:** If the affected user can avoid the issue through their own action (e.g., omitting a token from ragequit array), downgrade by 1 level.

---

## Report Structure

```
# Moloch.sol Security Audit Report

## Executive Summary
- Total findings: N (Novel: N, Duplicate: N)
- Critical: N | High: N | Medium: N | Low: N | Informational: N
- Highest-confidence finding: [title] at [confidence]%

## Round 1: Systematic Code Review
(For each of the 10 categories: finding or "No issues found — [defense mechanism]")

## Round 2: Economic & Cross-Function Analysis
(Cross-mechanism interaction findings, if any)

## Round 3: Adversarial Validation
(For each finding from Rounds 1-2: disproof attempt result, confidence score, final verdict)

## Confirmed Findings
(Only findings that survived Round 3, using the format above)

## Category Coverage Matrix
| Category | Result | Defense Verified |
|----------|--------|-----------------|
(All 10 categories — no gaps)

## Invariant Verification
(For each of the 8 invariants listed above: verified or violated, with evidence)

## Architecture Assessment
1-2 paragraphs: overall security posture, areas of strength, comparison to other governance frameworks you've audited.
```

---

## Peripheral: Tribute.sol — Security Audit Prompt

> **Purpose:** Structured prompt for an AI auditor to analyze `src/peripheral/Tribute.sol` (~340 lines, 1 contract + 3 free functions). Paste this section along with a copy of `src/peripheral/Tribute.sol` into your AI of choice.
>
> Prior audits: Pashov Skills, Grimoire (6 agents). Reports: `audit/tribute-pashov-skills.md`, `audit/tribute-grimoire.md`.

### Instructions

You are a senior Solidity security auditor. Analyze `Tribute.sol` — a standalone OTC escrow peripheral for Moloch DAOs. Work in **two rounds**:

**Round 1: Defense Verification.** For each defense mechanism in the table below, verify it works as described by tracing the actual code. Cite specific line numbers. State whether the defense holds or is broken. Then verify each of the 6 key invariants against the code. This round should produce a conclusion for every defense and every invariant — "Verified" or "Violated" with evidence.

**Round 2: Adversarial Hunt.** Attempt to find vulnerabilities NOT covered by the Known Findings table (T-1 through T-7) or the False Positive Patterns table. For each candidate:
1. Check it against the Known Findings table — if it matches, discard it as a duplicate.
2. Check it against the False Positive Patterns table — if it matches, discard it.
3. Attempt to disprove it by finding the guard, constraint, or code path that prevents exploitation.
4. Rate your confidence (0-100). Only include findings that survive all three checks.

**Report format:** For each finding: `[SEVERITY-N] Title`, severity, confidence, location (file:lines), description, attack path with concrete function calls, disproof attempt, recommendation. For Round 1: a table of defenses verified/violated and invariants verified/violated.

### Architecture

| Item | Detail |
|------|--------|
| **Contract** | `Tribute` — 1 contract + 3 free functions (~340 lines) |
| **Purpose** | Standalone OTC escrow. Proposers lock ETH/ERC-20 tributes targeting a DAO. DAOs claim tributes atomically (swap). Proposers can cancel. |
| **Access control** | No owner, no admin. `proposeTribute` = anyone. `cancelTribute` = proposer only (keyed by `msg.sender`). `claimTribute` = DAO only (keyed by `msg.sender`). |
| **Integration target** | Moloch DAO contracts which have `receive() external payable {}` and execute proposals via `to.call{value}(data)` |
| **Storage** | Mapping `tributes[proposer][dao][tribTkn] → TributeOffer`. Two append-only ref arrays for on-chain discovery (paginated view functions). |
| **Free functions** | `safeTransferETH`, `safeTransfer`, `safeTransferFrom` — Solady-style assembly. Shared with Moloch.sol. |

### Defense Mechanisms

| Defense | Mechanism | What It Prevents |
|---------|-----------|-----------------|
| **EIP-1153 reentrancy guard** | Transient storage `TSTORE`/`TLOAD` in `nonReentrant` on all 3 mutating functions | All reentrancy (same-function, cross-function, ERC777 hooks) |
| **CEI ordering** | `proposeTribute` writes all state before `safeTransferFrom`. `cancelTribute`/`claimTribute` delete mapping before external calls | Reentrancy even without the guard |
| **Bait-and-switch prevention** | `claimTribute` requires `(tribAmt, forTkn, forAmt)` as explicit params, verified against stored values, reverts `TermsMismatch` | Proposer cancel + re-propose with worse terms between DAO approval and execution |
| **Overwrite guard** | `if (offer.tribAmt != 0) revert` in `proposeTribute` | Double-locking same `(proposer, dao, tribTkn)` key |
| **ETH/ERC20 mutual exclusion** | `msg.value != 0` branch requires `tribTkn == address(0)` and `tribAmt == 0`; else branch requires `tribTkn != address(0)` and `tribAmt != 0` | Mixed ETH+ERC20 in single offer, msg.value double-counting |
| **Pagination bounds** | `start >= len \|\| limit == 0` early return in view functions | Infinite loop on out-of-bounds start, ambiguous next=0 on limit=0 |
| **Solady safe transfers** | Assembly `safeTransfer`/`safeTransferFrom` with extcodesize + returndatasize checks | USDT missing-return, EOA token address, non-contract calls |

### Key Invariants

1. Sum of all active `offer.tribAmt` for ETH tributes (`tribTkn == address(0)`) ≤ `address(this).balance`
2. For each active offer: `offer.tribAmt > 0` and `offer.forAmt > 0`
3. Mapping key `(proposer, dao, tribTkn)` is unique — no two active offers share a key
4. Only the proposer (`msg.sender` at proposal time) can cancel; only the target DAO (`msg.sender` at claim time) can claim
5. `claimTribute` is atomic — both legs complete or neither does (EVM revert atomicity)
6. Ref arrays are monotonically non-decreasing in length (append-only)

### Critical Code Paths (Priority Order)

1. **`claimTribute`** — Atomic OTC swap. Deletes offer, pays proposer (ETH or ERC20 pull), sends tribute to DAO. Two external calls after state deletion.
2. **`proposeTribute`** — Deposit + state write. ETH via msg.value or ERC20 via safeTransferFrom (after state writes).
3. **`cancelTribute`** — Refund. Deletes offer, returns tribute to proposer.
4. **`getActiveDaoTributes` / `getActiveProposerTributes`** — Paginated views. Iterate ref arrays, filter by `tribAmt != 0`.

### Design Constraints (Intentional — Do Not Flag)

- **Fee-on-transfer / rebasing tokens unsupported.** Recorded `tribAmt` must equal actual balance held. NatSpec documents this. Consistent with Moloch.sol's transfer patterns and Uniswap V2/V3.
- **ETH push to proposer.** `claimTribute` pushes ETH directly. If proposer is a contract with reverting receive, DAO cannot claim that offer. N/A to Moloch DAOs (all have `receive() external payable {}`). Proposer chose their own address.
- **Ref arrays are append-only.** Stale entries from cancelled/claimed offers are never removed. Mitigated by pagination. No on-chain state-changing function iterates these arrays.
- **No sweep function.** Force-sent ETH (selfdestruct) is permanently stranded. Contract never uses `address(this).balance` for accounting — all amounts from mappings.

### False Positive Patterns (Do NOT Flag These)

| Pattern | Why It's Not a Bug |
|---------|-------------------|
| "safeTransfer corrupts the free memory pointer" | Solady pattern: `mstore(0x34, 0)` only zeros high bytes of FMP word (0x40–0x53). Actual FMP value lives in bytes 0x54–0x5F, untouched. Verified byte-by-byte. |
| "ETH locked when DAO can't receive" | EVM reverts are atomic. If `safeTransferETH(dao, ...)` reverts, `delete tributes[...]` is also reverted. No funds locked. |
| "safeTransferFrom uses caller() instead of a from parameter" | Intentional Solady convention. `from = caller()` is always `msg.sender` of the outer call. All call sites verified correct. |
| "Proposer can lock their own ETH by bricking receive()" | Self-inflicted. No third party can trigger this. Proposer chose their own address. |
| "Ref arrays can be spammed" | Spam requires gas + real token deposits per offer. Pagination mitigates view DoS. Core functions are O(1). |
| "No expiry / deadline on tributes" | By design. Proposer can cancel anytime. DAO claims via governance vote. |

### Tribute Known Findings

| # | Finding | Severity | Status |
|---|---------|----------|--------|
| T-1 | Fee-on-transfer token permanently locks tribute funds | Info | Documented — unsupported token type |
| T-2 | ETH push to proposer DoS via reverting receive | Info | N/A to Moloch integration |
| T-3 | Rebasing token downward rebase locks funds | Info | Same root cause as T-1 |
| T-4 | Unbounded ref array growth | Info | Mitigated — pagination with OOB + limit=0 guard |
| T-5 | CEI violation in proposeTribute | Info | **Fixed** — `safeTransferFrom` moved after all state writes |
| T-6 | `limit=0` pagination ambiguity | Info | **Fixed** — early return on `limit == 0` |
| T-7 | Stale ref resurrection on key reuse — cancel/repost same `(proposer, dao, tribTkn)` causes duplicate entries in paginated views | Low | Accepted — view-only, no fund risk |

### Assembly Verification

All 6 assembly blocks verified correct against Solady reference:

| Block | Verdict | Key Check |
|-------|---------|-----------|
| `safeTransferETH` | Clean | `codesize()` offset safe (zero-length calldata) |
| `safeTransfer` | Clean | FMP restoration via `mstore(0x34, 0)` — bytes 0x54–0x5F untouched |
| `safeTransferFrom` | Clean | FMP saved/restored. `shl(96, caller())` encoding. 100-byte calldata layout. |
| Return-value check | Clean | 7 token behaviors: returns true, returns nothing (USDT), returns false, call failure, silent revert, EOA, precompile |
| `nonReentrant` | Clean | Guard set before `_`, cleared after. Transient slot consistent both halves. |
| View array trim | Clean | `mstore(result, found)` — standard in-place trim, `memory-safe` valid |

---

## Final Checklist

Before submitting your report, verify:

- [ ] Every finding has a concrete attack path with specific function calls and line numbers
- [ ] Every finding includes a disproof attempt explaining what you checked
- [ ] Every finding has a confidence score (0-100)
- [ ] No finding duplicates a Known Finding (Moloch: KF#1–24, Tribute: T-1–T-7)
- [ ] No finding matches a False Positive Pattern (check the table for your target contract)
- [ ] Severity ratings follow the adjustment rules (especially the privileged-role rule)
- [ ] All vulnerability categories / defense mechanisms have a conclusion (verified or violated)
- [ ] All invariants have been checked (Moloch: 8 invariants, Tribute: 6 invariants)
- [ ] Critical/High findings include a concrete Proof of Concept with actual function signatures
- [ ] The report distinguishes between novel findings and confirmed duplicates

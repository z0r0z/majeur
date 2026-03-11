# Moloch.sol Security Audit Prompt

> **Purpose:** Structured prompt for an AI auditor to analyze `Moloch.sol` and produce a clean, analyzable security report. Paste this document along with a copy of `src/Moloch.sol` into your AI of choice.
>
> **Methodology encoded from:** 21 independent audit tools — Forefy multi-expert framework, Archethect Map-Hunt-Attack falsification, HackenProof bug bounty triage, Pashov deep-mode adversarial reasoning, Trail of Bits code maturity scoring, and 13 others. This prompt distills the techniques that produced the best signal-to-noise across all 21.

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

These patterns were repeatedly flagged by weaker auditors and confirmed as non-issues across 21 audits. If you find yourself writing a finding that matches one of these, reconsider:

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

The following 18 findings have been identified and reviewed across prior audits. **Do not re-report these.** If your analysis surfaces one of these, note it as "confirmed duplicate of Known Finding #N" and move on.

| # | Finding | Severity | Key Detail |
|---|---------|----------|------------|
| 1 | Sale cap sentinel collision (`0` = unlimited = exhausted) | Low | After exact sell-out, cap resets to 0 which also means "unlimited" |
| 2 | Dynamic quorum + minting sale + ragequit | Low | Supply inflation via `buyShares` → ragequit after snapshot → quorum denominator manipulation. Economically constrained |
| 3 | Futarchy pool drainable via ragequit | Design | Intentional — pools are incentives subordinate to exit rights |
| 4 | Futarchy resolution timing | Low | Early NO voters can resolve futarchy when quorum met by losing side, freezing voting incentives |
| 5 | Vote receipt transferability breaks `cancelVote` | Low | Transferred receipts → original voter can't cancel (underflow). Voluntary user action |
| 6 | Zero-winner futarchy lockup | Low | If no one votes for winning side, pool tokens are permanently inaccessible via `cashOutFutarchy`. Funds remain in DAO treasury |
| 7 | Blacklistable token ragequit DoS | Low | If treasury token blacklists DAO, ragequit reverts for that token. Caller can omit it |
| 8 | Fee-on-transfer token accounting | Info | Ragequit assumes full delivery. Fee tokens short-change recipients |
| 9 | CREATE2 salt not bound to `msg.sender` | Info | Anyone can front-run deployment to claim a vanity address. No fund loss |
| 10 | Permit/proposal ID namespace overlap | Info | Same `keccak256` scheme — collision astronomically unlikely (2^256 space) |
| 11 | `proposalThreshold == 0` griefing | Low | Permissionless proposal opening enables spam and minted futarchy reward farming |
| 12 | `init()` missing `quorumBps` range validation | Info | `setQuorumBps` validates, but `init()` does not. Privileged-only initialization |
| 13 | Loot supply not snapshotted for futarchy earmarks | Info | Auto-futarchy earmarks use live loot supply, not snapshotted |
| 14 | `delegatecall` proposals can corrupt storage | Design | Intentional power — equivalent to upgradeability |
| 15 | Post-queue voting can flip timelocked proposals | Design | Intentional — timelock is a last-objection window. `castVote` has no `queuedAt` check; `state()` re-evaluates tallies after delay. `cancelVote` requires Active state (asymmetric). By design |
| 16 | `spendPermit` doesn't check `executed` flag | Low | Allows double-execution if DAO creates both proposal and permit with identical params. Requires two governance votes. `_burn6909` is the actual replay guard |
| 17 | Public futarchy attachment + zero-quorum premature NO-resolution | Medium | With `quorumAbsolute == 0 && quorumBps == 0`, `state()` returns `Defeated` at line 476 with zero votes. Attacker calls `fundFutarchy{value:1}` then `resolveFutarchyNo` → `castVote` permanently reverts. Configuration-dependent. Fix: require `Expired` only in `resolveFutarchyNo` |
| 18 | `fundFutarchy` accepts executed/cancelled proposal IDs | Medium | `fundFutarchy` checks `F.resolved` but not `executed[id]`. After cancel/execute, pools can still be funded but never resolved — `resolveFutarchyNo` rejects `executed[id]`, and voting/execution paths are dead. Funds permanently stuck. Fix: add `if (executed[id]) revert AlreadyExecuted();` |

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

## Final Checklist

Before submitting your report, verify:

- [ ] Every finding has a concrete attack path with specific function calls and line numbers
- [ ] Every finding includes a disproof attempt explaining what you checked
- [ ] Every finding has a confidence score (0-100)
- [ ] No finding duplicates the 18 Known Findings
- [ ] No finding matches a False Positive Pattern
- [ ] Severity ratings follow the adjustment rules (especially the privileged-role rule)
- [ ] All 10 vulnerability categories have a conclusion (finding or "no issues found")
- [ ] All 8 invariants have been checked
- [ ] Critical/High findings include a concrete Proof of Concept with actual function signatures
- [ ] The report distinguishes between novel findings and confirmed duplicates

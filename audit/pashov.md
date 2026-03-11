# Pashov Skills / Solidity Auditor (Deep Mode)

**Skill:** [pashov/skills](https://github.com/pashov/skills) (Solidity Auditor)
Scan of: `Moloch.sol` (2110 lines)

Mode: Deep (4 vector scan agents + 1 adversarial reasoning agent)

Findings found: 13 (deduplicated from 5 agents)

## Review Summary

> **Reviewed 2026-03-11. No production blockers identified.**
>
> - **Severity breakdown:** 13 deduplicated findings — 2 High-confidence (95+), 4 Medium-confidence (85-90), 4 Low-confidence (75-80), 1 False Positive, 1 Below Threshold.
> - **1 false positive** identified: multicall msg.value reuse (Agent 1 missed that `multicall` is not `payable`).
> - **2 novel findings** not seen in prior audits: vote receipt transferability breaking `cancelVote`, and futarchy pool locked when winning side has zero supply. Both are design tradeoffs, not production blockers.
> - **Most findings are duplicates** of issues already reviewed in Zellic, Plainshift, and Octane audits. Cross-references noted per finding.
> - The Pashov skill produced **better signal-to-noise** than the other AI auditors: fewer findings, better FP filtering, and the adversarial agent (Agent 5) found the most interesting issues. The false positive rate (~8%) is notably lower than Octane (~60% of findings were design tradeoffs).

## Findings

### 1. Ragequit Drains ETH/ERC20 Futarchy Pools - [100]

> **Review: Not a bug. Duplicate of Plainshift #2 / Octane vuln #6.** Ragequit gives pro-rata of all DAO-held assets by design — including ETH earmarked for futarchy pools. Futarchy pools are incentive mechanisms subordinate to governance, not restrictive escrows. If futarchy funds were excluded from ragequit, a hostile majority could shield treasury via futarchy funding. This is an intentional design tradeoff of the Moloch model.

`ragequit` computes each member's ETH entitlement using `address(this).balance`, which includes ETH funded into futarchy pools via `fundFutarchy`. Raging members take funds reserved for futarchy winners, and surviving futarchy claimants may receive reduced or zero payouts when they call `cashOutFutarchy`.

### 2. Sale Cap Resets to Zero on Full Exhaustion, Enabling Unlimited Subsequent Purchases - [95]

> **Review: Known quirk. Duplicate of Zellic #13.** The cap sentinel collision (`0` = "unlimited" and `0` = "exhausted") is a known design choice. In minting mode, unlimited is the intended behavior (upgrade/conversion use case). In non-minting mode, the DAO's held balance provides a natural cap. The cap is a soft guardrail, not a hard invariant. Deployers and UIs should note this behavior.

`buyShares` enforces the cap with `if (cap != 0 && shareAmount > cap) revert`, but after a purchase that exactly exhausts the cap (`s.cap` becomes `0`), all subsequent calls see `cap == 0` and skip the guard entirely, treating the exhausted sale as having unlimited remaining supply.

### 3. Auto-Futarchy Earmark Double-Commits Same Tokens Across Multiple Proposals - [95]

> **Review: Real concern for non-minted reward tokens. Variant of Octane vuln #9.** When `rewardToken` is the actual Shares or Loot contract address (not sentinel values `address(this)` / `address(1007)`), the earmark reads the DAO's balance but doesn't lock tokens — so multiple proposals earmark the same pool. For sentinel values (minted rewards), this doesn't apply since `_payout` mints fresh tokens. In practice, most auto-futarchy configurations use minted rewards. If using actual held tokens as rewards, deployers should be aware of overcommitment risk. **v2 hardening:** track committed amounts and subtract from available balance.

When `rewardToken` is set to the deployed Shares or Loot contract address, `openProposal` reads `balanceOf(address(this))` and adds up to that amount to `F.pool` without transferring or locking. Since the balance doesn't decrease, each subsequent `openProposal` earmarks the same tokens. When multiple proposals resolve, only the first claimants succeed; the rest revert due to insufficient balance.

### 4. Multicall msg.value Reuse via Delegatecall Minting Unbounded Shares - [90]

> **Review: False positive.** `multicall` is declared as `function multicall(bytes[] calldata data) public returns (bytes[] memory results)` — it is NOT `payable`. Calling it with ETH reverts. Therefore `msg.value` is always 0 in all delegatecalled sub-calls, and the `require(msg.value >= cost)` check in `buyShares` would fail for any non-zero cost. Agent 1 missed the non-payable declaration. This is the clearest false positive in the scan.

Agent 1 claimed that `multicall` uses `delegatecall` and each sub-call sees the original `msg.value`, allowing an attacker to encode N copies of `buyShares` to mint shares N times for a single ETH payment. This is incorrect because `multicall` cannot receive ETH.

### 5. Ragequit While Active Vote Allows Vote-Then-Exit - [90]

> **Review: Not a bug. By design.** Ragequit is the defining feature of Moloch-style DAOs — members can always exit. The vote weight was legitimate at the snapshot block (block N-1), and the voter had real economic stake when they cast it. Preventing ragequit while votes are active would undermine the core Moloch guarantee: no one can be trapped. The proposal still requires majority to pass, and the timelock (if configured) gives others time to ragequit before execution. This tension between voting commitment and exit rights is the fundamental Moloch tradeoff, not a bug.

A member can cast a decisive vote then immediately ragequit to burn their shares and withdraw their proportional treasury share. The governance tally retains their vote weight, so the proposal still passes and executes against the now-reduced treasury.

### 6. ERC-6909 Vote Receipt Transferability Breaks cancelVote - [85]

> **Review: Valid observation, minor impact.** Vote receipts being transferable is intentional for futarchy — receipts represent prediction market positions that should be tradeable. The `cancelVote` breakage when receipts are transferred away is a real side effect: `_burn6909(msg.sender, rid, weight)` underflows if the voter no longer holds sufficient balance. However, transferring your own receipt tokens is a voluntary action — the voter chooses to give up their cancel ability. The futarchy payout mechanics remain correct (totalSupply tracks accurately). **v2 hardening:** consider allowing partial cancel proportional to remaining balance, or documenting that transferring vote receipts forfeits cancel rights.

Vote receipts (ERC-6909 tokens minted in `castVote`) are freely transferable because only permit receipts are SBT-gated. A voter who transfers their receipt to another address cannot subsequently call `cancelVote` because `_burn6909` will underflow, permanently locking their vote in the tally.

### 7. Futarchy Pool Permanently Locked When Winning Side Has Zero Supply - [85]

> **Review: Valid observation, edge case.** If a futarchy pool is funded and the winning side has zero receipt supply (no one voted for the winning side), `payoutPerUnit` stays 0 and funds are locked. This is a real edge case — e.g., a proposal expires with only FOR votes, NO side wins, but no one voted AGAINST. In practice, futarchy funders have incentive to vote on their preferred side, making zero-supply resolution unlikely. The funds remain in the DAO treasury (accessible via governance proposals or ragequit), so they are not truly lost — just inaccessible via `cashOutFutarchy`. **v2 hardening:** consider releasing unclaimed pools back to the DAO when `winSupply == 0`.

When a futarchy pool is funded and the winning side has zero receipt supply, `payoutPerUnit` remains 0 and the pool funds are permanently locked with no recovery mechanism via `cashOutFutarchy`.

### 8. Single-Transaction Governance via Multicall - [85]

> **Review: Valid observation, configuration-dependent. Variant of Octane vuln #1 / Zellic #10.** When `timelockDelay == 0` and quorum is low, `multicall` enables atomic open+vote+execute in one transaction. This is mitigated by: (1) `timelockDelay > 0` forces queuing, giving others time to react or ragequit; (2) quorum settings prevent a single voter from meeting threshold alone; (3) `proposalThreshold > 0` gates proposal creation. DAOs should configure at least one of these safeguards. The `castVote` auto-open pattern is intentional (prevents front-run griefing), and multicall batching is a feature, not a bug — it becomes dangerous only in misconfigured DAOs.

When `timelockDelay == 0` and quorum is low, a majority share holder can use `multicall` to atomically open a proposal, cast the deciding vote, and execute it — all in a single transaction with zero reaction time for other members.

### 9. Blacklistable Payment Token Permanently DoS-es Ragequit - [80]

> **Review: Known ERC20 interaction concern. Informational.** If a blacklistable token (USDC, USDT) is in the DAO treasury and the ragequitter is blacklisted by that token's issuer, the entire `ragequit` reverts because `_payout` uses `safeTransfer` which reverts on failure. Mitigation: the ragequitter can omit the problematic token from their `tokens[]` array (losing claim to that token only). The user-supplied token list is a feature, not a bug — it lets users skip tokens that would cause reverts. UI should warn if a token might fail.

`ragequit` iterates over a caller-supplied token list and calls `_payout` for each; if any token is a blacklistable ERC-20 and the caller is blacklisted, the entire `ragequit` reverts.

### 10. Auto-Futarchy Mints Unbacked Tokens to Voters - [80]

> **Review: Not a bug. Duplicate of Octane vuln #4.** When `rewardToken` is `address(this)` (shares) or `address(1007)` (loot), `_payout` mints new tokens as futarchy rewards. This is the intended behavior — the DAO governance configured `autoFutarchyParam` to incentivize voting via token inflation. The inflation is bounded by `autoFutarchyCap` per proposal. See our detailed review on Octane vuln #4 for configuration guidance regarding minted rewards and `proposalThreshold`.

When `rewardToken` is `address(this)` or `address(1007)`, the futarchy pool is a pure accounting number with no real assets locked. Upon resolution, `cashOutFutarchy` mints brand-new shares/loot, diluting all existing holders who did not vote.

### 11. proposalIds Unbounded Array Growth - [80]

> **Review: Not a bug. Informational.** `proposalIds` is an append-only array used for enumeration. Growth is gated by `proposalThreshold` (if set) and each push costs the opener gas. No on-chain function iterates the full array — `getProposalCount()` is O(1). The array is consumed off-chain by view helpers. A spam attacker bears their own gas costs with no financial incentive. Not a production concern.

`openProposal` pushes every new proposal id into `proposalIds` without a cap. When `proposalThreshold == 0`, any share holder can grow the array arbitrarily, potentially DoS-ing off-chain systems that iterate it.

### 12. spendPermit Does Not Check executed Flag - [75]

> **Review: Not a bug. By design. Duplicate of Zellic #12.** Per-receipt execution is intentional — multiple receipt holders should independently execute their permits. The receipt balance burn (`_burn6909`) is the replay guard. The `executed[tokenId] = true` flag is set to block the governance path (`executeByVotes`) from also executing the same intent, not to limit permit spending. Each `spendPermit` call consumes one receipt token.

`spendPermit` sets `executed[tokenId] = true` on its first invocation but never checks whether `executed[tokenId]` is already true on entry. For any permit with count >= 2, a holder can call `spendPermit` repeatedly.

### 13. Unrestricted Delegatecall in executeByVotes - [75]

> **Review: Not a bug. By design. Duplicate of Octane warnings #2/#4.** Delegatecall governance is the standard mechanism for DAO upgrades and module execution across all governance frameworks (Governor, Aragon, Moloch). The trust assumption is that voters must trust the target code — this is intrinsic to delegatecall governance, not specific to Moloch. A malicious delegatecall target can do anything to DAO storage, but it requires a passing governance vote. Whitelisting delegatecall targets would break the upgradeability pattern.

`executeByVotes` with `op=1` performs an unconstrained `delegatecall` to any `to` address, allowing complete takeover of the DAO's state — but requires a passing governance vote.

---

## Findings Summary

| # | Confidence | Title | Review |
|---|---|---|---|
| 1 | [100] | Ragequit Drains Futarchy Pools | Not a bug (Plainshift #2 / Octane #6) |
| 2 | [95] | Sale Cap Sentinel Collision | Known quirk (Zellic #13) |
| 3 | [95] | Auto-Futarchy Earmark Double-Commits | Real concern, non-minted tokens only (Octane #9) |
| 4 | [90] | Multicall msg.value Reuse | **False positive** (multicall not payable) |
| 5 | [90] | Vote-Then-Ragequit | Not a bug (Moloch design) |
| 6 | [85] | Vote Receipt Transfer Breaks cancelVote | Valid, minor (new finding) |
| 7 | [85] | Futarchy Pool Locked on Zero Winners | Valid, edge case (new finding) |
| 8 | [85] | Single-Tx Governance via Multicall | Valid, config-dependent (Octane #1) |
| 9 | [80] | Blacklistable Token Ragequit DoS | Informational (user can omit token) |
| 10 | [80] | Auto-Futarchy Unbacked Minting | Not a bug (Octane #4) |
| 11 | [80] | proposalIds Unbounded Growth | Informational |
| 12 | [75] | spendPermit No Executed Check | Not a bug (Zellic #12) |
| 13 | [75] | Unrestricted Delegatecall | Not a bug (Octane warnings #2/#4) |

---

> This review was performed by the Pashov Skills AI auditor (deep mode) with manual review and cross-referencing against three prior AI audit reports (Zellic V12, Plainshift AI, Octane).

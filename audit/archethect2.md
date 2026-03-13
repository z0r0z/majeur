# Security Audit Report: Majeur (Moloch DAO v4)

**Target:** `src/Moloch.sol`
**Framework:** Foundry | Solidity 0.8.30
**Date:** 2026-03-13
**Methodology:** Map-Hunt-Attack with Devil's Advocate verification
**Hotspots analyzed:** 28 (all attacked and verified)
**PoC tests written:** 14 Foundry test files

---

## Executive Summary

Majeur is a minimal, gas-optimized Moloch DAO v3 implementation featuring governance proposals with futarchy prediction markets, ERC-6909 receipt tokens, checkpoint-based voting, ERC-20 shares/loot with delegation, ERC-721 soulbound badges, token sales, treasury management, and permit-based spending.

The audit identified **16 confirmed issues** across 4 HIGH, 5 MEDIUM, and 5 LOW severity findings, plus 2 design tradeoffs. **9 findings** have executable Foundry PoC proofs. The most critical findings involve governance fast-path exploitation (MH-014), permit re-execution (MH-004), vote receipt transferability enabling futarchy theft (MH-005), and auto-futarchy over-commitment of held tokens (MH-006). Additionally, **8 hypotheses** were thoroughly investigated and invalidated through the Devil's Advocate protocol.

### Severity Distribution

| Severity | Proved | Confirmed (Unproven) | Candidates | Design Tradeoffs | Discarded |
|----------|--------|---------------------|------------|------------------|-----------|
| HIGH | 4 | 0 | 0 | 0 | 0 |
| MEDIUM | 3 | 2 | 1 | 0 | 0 |
| LOW | 2 | 3 | 2 | 1 | 0 |
| INFORMATIONAL | 0 | 0 | 1 | 1 | 0 |

---

## Review Summary

> **Reviewed 2026-03-13. No production blockers identified. 2 novel findings, 13 duplicates, 1 config-dependent (SafeSummoner-mitigated).**
>
> - V2 of the Archethect SC-Auditor (v0.4.0) — significantly more productive than V1 (v0.3.0), which falsified all 8 spots and found 0 novel issues.
> - **16 findings claimed** (4 HIGH, 5 MEDIUM, 5 LOW, 2 design tradeoffs). After cross-referencing against the 23 known findings and 26 prior audit reports:
>   - **2 novel findings:** MH-015 (ragequit front-run of treasury inflows) and MH-026 (non-minting sale bypasses `transfersLocked`). Both are Low severity.
>   - **13 duplicates** of known findings (KF#1, 3, 5, 7, 8, 14, 15, 16) or previously identified by other auditors (return bomb found by 8+ prior audits).
>   - **1 config-dependent** finding (MH-014) fully mitigated by SafeSummoner deployment guards.
> - **Severity inflation is significant.** All 4 HIGHs are known findings or config-dependent issues. Under the severity adjustment rules in SECURITY.md (privileged-role rule, economic irrationality, SafeSummoner mitigation), none warrant HIGH.
> - **The PoC suite is valuable** — 14 Foundry tests confirming known issues provides useful regression coverage even when the findings themselves aren't novel.
> - **V2 vs V1 improvement:** V1's devil's advocate protocol was too aggressive — it falsified everything, including real known issues. V2 swings the other direction, finding real issues but over-classifying severity. The truth is between the two runs.

---

## Section 1: Proved Findings

Findings with `status = "verified"` or `"judge_confirmed"` AND a successful Foundry PoC proof.

---

### [H-01] MH-014: Two-Block Governance Takeover via Zero Timelock

**Severity:** HIGH | **Confidence:** Confirmed | **Category:** config_dependent
**Affected:** `src/Moloch.sol` L278-525
**PoC:** `.sc-auditor-work/pocs/MH014_TwoBlockGovernance.t.sol`

**Description:** When `timelockDelay = 0` and `proposalTTL = 0` (both defaults), an attacker who acquires shares in block N can open a proposal, vote with majority power, and execute it in block N+1. The voting snapshot uses `block.number - 1` (L365), so shares acquired in block N are immediately votable. Combined with zero timelock, this enables complete DAO takeover in 2 blocks.

**Impact:** An attacker who acquires >50% shares (via purchase, flash loan if transfers unlocked, or social engineering) can execute arbitrary proposals including treasury drain, parameter changes, or delegatecall-based storage overwrites within ~24 seconds.

**Remediation:** Enforce a protocol-level minimum `timelockDelay > 0` (e.g., 1 day) that cannot be set to zero. Alternatively, enforce `proposalTTL > 0` with a minimum voting period.

**Root Cause:** `missing-minimum-timelock-enforcement-core-protocol`

> **Review: Config-dependent, fully mitigated by SafeSummoner. Not a novel finding.** SafeSummoner enforces `timelockDelay > 0` and `proposalTTL > 0` for all DAOs deployed through it (see SafeSummoner validation guards in README). Setting `timelockDelay = 0` in Moloch requires a passing governance vote (`onlyDAO`), so the privileged-role rule applies — a DAO voting to remove its own timelock is a governance decision, not a vulnerability. This is a variant of the single-transaction governance pattern identified by Pashov (#8), Octane (#1), and Zellic (#10). **Severity adjustment: Low (config-dependent, SafeSummoner-mitigated, privileged-role rule applies).** The PoC is valid for confirming the behavior in a raw (non-SafeSummoner) deployment.

---

### [H-02] MH-004: spendPermit Re-Execution via Missing `executed` Check

**Severity:** HIGH | **Confidence:** Confirmed | **Category:** state_machine
**Affected:** `src/Moloch.sol` L659-676
**PoC:** `.sc-auditor-work/pocs/MH004_SpendPermitReplay.t.sol`

**Description:** The `spendPermit` function burns an ERC-6909 permit receipt token (L672) and executes the payload via `_execute` (L673), but never checks `executed[tokenId]` before execution. The `executed[tokenId] = true` write at L674 is a dead write with no corresponding read. If the permit's `count` field allows multiple receipts (`count > 1`), each receipt holder can independently execute the same action, leading to N-fold execution where only 1 was intended.

**Impact:** Permit holders can drain N times the intended treasury value. For example, a permit with `count=5` and `value=10 ETH` allows 50 ETH to be drained instead of 10 ETH.

**Remediation:** Add `require(!executed[tokenId], "already executed")` before `_burn6909` in `spendPermit`. Alternatively, redesign permits to use a nonce-based single-use pattern.

**Root Cause:** `dead-write-executed-latch-missing-read`

> **Review: Duplicate of KF#16. Not a bug — multi-spend is the intended permit design.** Permits are designed to be spent `count` times. `setPermit` (L632) takes a `count` parameter and mints that many ERC-6909 receipt tokens. Each `spendPermit` call burns exactly 1 receipt and executes the action — this is the intended replay model. A permit with `count=5` authorizes 5 independent executions, one per receipt. The `_burn6909` is the replay guard: you cannot spend without a receipt to burn.
>
> The `executed[tokenId] = true` write at L668 is not a "dead write" as the report claims — it serves a specific cross-function purpose: it blocks the *governance path* (`executeByVotes` checks `executed[id]` at L502) from also executing the same intent hash via a separate proposal vote. This prevents the same action from being executed through both the permit path and the governance path. The write is intentionally unconditional (no read-before-write) because every permit spend should tombstone the governance path, regardless of whether it's the first or fifth spend.
>
> The report's impact scenario ("a permit with `count=5` and `value=10 ETH` allows 50 ETH to be drained instead of 10 ETH") describes the intended behavior, not a vulnerability. The DAO governance explicitly authorized 5 executions when it called `setPermit(..., count: 5)`. SECURITY.md KF#16 covers this: "`_burn6909` is the actual replay guard." First identified by Zellic (#12), confirmed by Pashov (#12). **Not a vulnerability — working as designed.**

---

### [H-03] MH-005: Vote Receipt Tokens Freely Transferable, Enabling Futarchy Payout Theft

**Severity:** HIGH | **Confidence:** Confirmed | **Category:** accounting_entitlement
**Affected:** `src/Moloch.sol` L383-389, L925-937, L583-604
**PoC:** `.sc-auditor-work/pocs/MH005_VoteReceiptTransfer.t.sol`

**Description:** Vote receipt tokens minted by `castVote` (L389) are standard ERC-6909 tokens without the `isPermitReceipt` soulbound flag. The SBT transfer restriction at L929 only checks `isPermitReceipt[id]`, which is only set for permit receipts (L642), not vote receipts. Any holder can transfer vote receipts via `transferFrom`, and the recipient can call `cashOutFutarchy` to claim the futarchy payout. The original voter cannot cancel their vote after transfer because `cancelVote` calls `_burn6909` which underflows on zero balance.

**Impact:** Non-voters can acquire receipt tokens (via transfer or ERC-6909 operator approval) and steal futarchy prediction market payouts. Voters lose both their vote and their payout.

**Remediation:** Mark vote receipt IDs as soulbound by setting `isPermitReceipt[rid] = true` in `castVote`, or add a dedicated `isVoteReceipt` flag checked in `transferFrom`.

**Root Cause:** `vote-receipt-not-soulbound`

> **Review: Duplicate of KF#5.** SECURITY.md KF#5: "Vote receipt transferability breaks `cancelVote` — Transferred receipts → original voter can't cancel (underflow). Voluntary user action." First identified by Pashov Skills as a novel finding (#6). The futarchy payout theft angle adds useful color, but the root cause (vote receipts not soulbound) is the same. Receipt transferability is a design tradeoff — receipts function as prediction market claim tokens, and transferability enables a secondary market that may be desirable. The `cancelVote` breakage is a voluntary consequence of the holder choosing to transfer. **Severity: Low (design tradeoff, per KF#5).** The PoC confirming the futarchy angle is useful but does not change the classification.

---

### [H-04] MH-006: Auto-Futarchy Over-Commits Held Tokens Across Concurrent Proposals

**Severity:** HIGH | **Confidence:** Confirmed | **Category:** accounting_entitlement
**Affected:** `src/Moloch.sol` L530-571, L278-342
**PoC:** `.sc-auditor-work/pocs/MH006_AutoFutarchyOvercommit.t.sol`

**Description:** When `autoFutarchyParam > 0` and `rewardToken` is an existing ERC-20 held by the DAO, `fundFutarchy` earmarks tokens from the DAO's balance into the futarchy pool. Each proposal independently reads `balanceOf(address(this))` to determine the earmark amount. With N concurrent proposals, the same tokens are earmarked N times, but only enough exists to pay out once. Later proposals become insolvent -- winners of those proposals cannot claim their full payout.

**Impact:** With 3 concurrent proposals earmarking 33% of treasury each, 99% is promised but only 33% exists. Two-thirds of futarchy winners receive nothing, breaking the prediction market incentive.

**Remediation:** Track cumulative outstanding earmarks and subtract from available balance, or escrow tokens at `fundFutarchy` time.

**Root Cause:** `auto-futarchy-soft-earmark-no-cumulative-tracking`

> **Review: Duplicate of KF#3, found by 9+ prior audits.** The auto-futarchy overcommit pattern was independently identified by Octane (#9), Pashov (#3), Forefy, QuillShield, ChatGPT, ChatGPT Pro, Qwen, Solarizer, Grimoire, and Almanax. SECURITY.md KF#3 covers futarchy pool drainability as an intentional design: "pools are incentives subordinate to exit rights." The earmark is intentionally accounting-only (L336: `F.pool += amt` with comment "earmark only"). Futarchy pools do not lock tokens because ragequit's exit guarantee supersedes pool earmarks — if futarchy funds were excluded from ragequit, a hostile majority could shield treasury via futarchy. The `autoFutarchyCap` variable (L189) bounds per-proposal exposure. For minted rewards (sentinel values `address(this)` / `address(1007)`), overcommit is irrelevant since `_payout` mints fresh tokens. **Severity: Design tradeoff (per KF#3).** V2 hardening candidate for non-minted reward tokens.

---

### [M-01] MH-007: Auto-Futarchy Minted Token Inflation via NO Coalition

**Severity:** MEDIUM | **Confidence:** Confirmed | **Category:** accounting_entitlement
**Affected:** `src/Moloch.sol` L530-571, L583-604
**PoC:** `.sc-auditor-work/pocs/MH007_MintedTokenInflation.t.sol`

**Description:** When `rewardToken = address(this)` (shares) or `address(1007)` (loot), futarchy pools are funded by minting new tokens at payout time via `_payout`. A coordinated NO coalition can systematically vote against every proposal, collect minted token rewards from the futarchy pool, and dilute existing shareholders. Each defeated proposal mints `autoFutarchyParam * totalSupply / BPS_DENOM` new tokens to the NO voters.

**Impact:** With `autoFutarchyParam = 1000` (10%), 10 defeated proposals produce ~71% dilution of existing holders.

**Remediation:** Enforce per-DAO aggregate minting caps, rate-limit futarchy minting, or require the DAO to hold sufficient tokens before earmarking.

**Root Cause:** `unbounded-minting-via-auto-futarchy`

> **Review: Duplicate of KF#3 + KF#11.** SECURITY.md KF#3 explicitly notes: "a majority NO coalition can also collect auto-funded pools by repeatedly defeating proposals — this is by design (NO voters are rewarded for correct predictions), but becomes extractive in concentrated DAOs." KF#11 covers `proposalThreshold == 0` griefing. This exact farming vector was first articulated in detail by Octane (#4), then confirmed by Pashov, Forefy, QuillShield, ChatGPT, ChatGPT Pro, Qwen, Grimoire, Solarizer, and Almanax. Mitigations: `autoFutarchyCap` (per-proposal bound), `proposalThreshold > 0` (gates proposal creation behind real stake), and governance can zero `autoFutarchyParam` to halt the attack. **Severity: Design tradeoff (per KF#3/KF#11).**

---

### [M-02] MH-015: Ragequit Donation Attack via Live Balance Reads

**Severity:** MEDIUM | **Confidence:** Likely | **Category:** accounting_entitlement
**Affected:** `src/Moloch.sol` L759-797
**PoC:** `.sc-auditor-work/pocs/MH015_RagequitDonationAttack.t.sol`

**Description:** `ragequit` computes each member's pro-rata share using live `balanceOf(address(this))` reads (L785). An attacker who front-runs a large treasury inflow (e.g., a minting sale closing, a donation, or an external payment) can ragequit immediately after the inflow to claim a disproportionate share of the new funds without having contributed.

**Impact:** Attacker extracts value from incoming treasury funds at the expense of remaining members. The attack is profitable whenever the inflow exceeds gas costs.

**Remediation:** Snapshot treasury balances at a fixed point (e.g., when ragequit is enabled or at last governance action) rather than reading live balances.

**Root Cause:** `ragequit-uses-live-balance-vulnerable-to-frontrun`

> **Review: Novel finding. Severity: Low.** Code-verified: `ragequit` reads live balances at L790 (`pool = tk == address(0) ? address(this).balance : balanceOfThis(tk)`) with no snapshot mechanism. The front-running vector is real in principle.
>
> **However, economic analysis limits severity:**
> 1. **The attacker must already hold shares.** Ragequit burns shares — the attacker needs existing economic stake. They cannot acquire shares and ragequit atomically due to the block N-1 snapshot on voting (and shares acquired via `buyShares` are already reflected in `totalSupply`, diluting their own pro-rata claim).
> 2. **The profit is marginal.** If the attacker holds X% of supply, they extract X% of the inflow. Their "unfair" gain is only the difference between their share of the inflow (which they would have received eventually via normal ragequit) and the time-value of extracting it now. The other members still hold claims on the remaining treasury.
> 3. **Requires predictable large inflows.** The attacker must know when a significant treasury inflow will occur and front-run it. Sale proceeds are somewhat predictable; donations are not.
> 4. **Economic irrationality adjustment applies** for most realistic scenarios — the attacker burns their governance position (shares) for a marginal treasury extraction advantage.
>
> **Not previously identified** across 26 prior audits. The SECURITY.md prompt (Category 4) asked about force-fed ETH and ragequit manipulation but not about front-running natural inflows. Novel observation worth documenting. **Severity: Low** (economic irrationality for realistic scenarios, attacker must already hold shares). V2 hardening candidate.

---

### [M-03] MH-016: Return Bomb Gas Exhaustion DoS on Proposal Execution

**Severity:** MEDIUM | **Confidence:** Confirmed | **Category:** denial_of_service
**Affected:** `src/Moloch.sol` L976-986
**PoC:** `.sc-auditor-work/pocs/MH016_ReturnBomb.t.sol`

**Description:** The `_execute` function uses a low-level `.call{value}(data)` at L981 without constraining the return data size. A malicious proposal target can return an arbitrarily large byte array, causing quadratic memory expansion costs in the caller's context. With an 800KB return, gas amplification reaches 173x. The 63/64 gas forwarding rule does NOT protect against this because the memory expansion happens in the caller's frame when copying `retData`.

**Impact:** A passed proposal targeting a malicious contract can permanently fail to execute, wasting gas and blocking governance actions. The proposal cannot be re-executed (executed latch is set before the call at L519).

**Remediation:** Use the ExcessivelySafeCall pattern (limit `returndatasize` to a cap, e.g., 4096 bytes) or use inline assembly to avoid automatic return data copying.

**Root Cause:** `_execute-unbounded-return-data-memory-expansion`

> **Review: Not novel — previously identified by 8+ audits. Severity: Low (privileged-role rule).** The return bomb in `_execute` was identified by SCV Scan (#3), QuillShield (ECS-3), Forefy (Spot #6), Claude (Opus 4.6), ChatGPT Pro, DeepSeek, Qwen, and HackenProof (#12). The SECURITY.md prompt explicitly calls it out in Category 9: "Return data bomb: `_execute` captures return data. Can a malicious target return huge data to cause OOG?"
>
> All prior auditors reached the same conclusion: **the privileged-role rule applies.** The proposal target is specified in the governance proposal which must pass a majority vote. The DAO explicitly votes to call this target. A malicious target requires either (a) social engineering voters into approving a malicious contract, or (b) the target being compromised after the vote — both of which have far worse consequences than gas exhaustion (the target could simply steal the `value` sent). HackenProof classified this as Out of Scope. SCV Scan recommended `ExcessivelySafeCall` as low-priority hardening. The 173x gas amplification PoC is technically interesting but does not change the privileged-role analysis. **Severity: Low (privileged-role rule, previously found by 8+ audits).** V2 hardening candidate.

---

### [L-01] MH-020: Tie-Defeated Asymmetry -- cancelVote Blocked While castVote Permitted

**Severity:** LOW | **Confidence:** Likely | **Category:** state_machine_gap
**Affected:** `src/Moloch.sol` L347-476
**PoC:** `.sc-auditor-work/pocs/MH020_TieDefeatedAsymmetry.t.sol`

**Description:** When a proposal reaches quorum with `forVotes <= againstVotes` (tie or losing), `state()` returns Defeated. `cancelVote` requires `state == Active` (L396), so existing voters are permanently locked. However, `castVote` has no state check (L347) -- new voters can still vote on a Defeated proposal and potentially flip it to Succeeded. This asymmetry means voters who regret their vote cannot adjust while new voters can still influence the outcome.

**Impact:** Governance unfairness: existing voters are locked into their position on a Defeated proposal while new voters can change the outcome.

**Remediation:** Either allow `cancelVote` when state is Defeated, or add a `state == Active` check to `castVote`.

**Root Cause:** `castVote-missing-state-check-asymmetric-cancel`

> **Review: Duplicate of KF#15.** SECURITY.md KF#15: "Post-queue voting can flip timelocked proposals — Intentional — timelock is a last-objection window. `castVote` has no `queuedAt` check; `state()` re-evaluates tallies after delay. `cancelVote` requires Active state (asymmetric). By design." The missing state check on `castVote` is the intentional mechanism that enables the last-objection window. The asymmetry with `cancelVote` is a documented corollary. Previously confirmed by Grimoire (M-01), Claude (Opus 4.6), and Solarizer (HIGH-1). **Severity: Design tradeoff (per KF#15).**

---

### [L-02] MH-026: Non-Minting Sales Bypass `transfersLocked` via DAO Address Exemption

**Severity:** LOW | **Confidence:** Confirmed | **Category:** access_control
**Affected:** `src/Moloch.sol` L706-756, L1217-1221
**PoC:** `.sc-auditor-work/pocs/MH026_SaleBypassTransferLock.t.sol`

**Description:** The `_checkUnlocked` function in Shares (L1217) and Loot (L1695) exempts transfers where `from == DAO` or `to == DAO`. Non-minting sales (where the DAO holds pre-existing tokens) use `shares.transfer(msg.sender, shareAmount)` at L752, where `msg.sender` is the Moloch contract (DAO). Since `from == DAO`, the transfer succeeds even when `transfersLocked = true`. This allows share distribution via sales to bypass the explicit transfer lock.

**Impact:** The DAO can inadvertently distribute locked tokens through non-minting sales, undermining the transfer lock's purpose.

**Remediation:** Add a `transfersLocked` check in `buyShares` for non-minting sales, or remove the DAO exemption from `_checkUnlocked`.

**Root Cause:** `_checkUnlocked-DAO-exemption-bypasses-lock-for-sales`

> **Review: Novel finding. Severity: Low (accepted).** Code-verified: `_checkUnlocked` (L1217-1221) exempts `from == DAO` transfers, and non-minting `buyShares` calls `shares.transfer(msg.sender, shareAmount)` from the Moloch context where `msg.sender` (inside the Shares contract) is the DAO address. The bypass is real.
>
> **Mitigating factors:**
> 1. **`setSale` is `onlyDAO`** — governance configures sales. The DAO voted to enable this sale with `minting = false`.
> 2. **`transfersLocked` is also `onlyDAO`** — governance controls the lock. If the DAO enabled both a non-minting sale and transfer lock, it is either an intentional combination or a configuration oversight.
> 3. **The DAO exemption exists for legitimate reasons** — ragequit (transfers to DAO), governance-initiated distributions, and sale mechanics all require the DAO to move tokens regardless of the lock.
>
> **Not previously identified** across 26 prior audits. The interaction between `_checkUnlocked` DAO exemption and non-minting sale transfers is a genuine edge case. The finding is technically correct but the privileged-role rule applies (governance enables both the sale and the lock). **Severity: Low (accepted).** V2 hardening candidate: add explicit `transfersLocked` check in `buyShares` for non-minting sales.

---

## Section 2: Confirmed Findings (Unproven)

Findings with strong evidence confirmed by both ATTACK and VERIFY phases but without executable PoC proofs.

---

### [M-04] MH-009: Live Governance Parameters Enable Retroactive Changes

**Severity:** MEDIUM | **Confidence:** Likely | **Category:** design_tradeoff
**Affected:** `src/Moloch.sol` L433-478, L885

**Description:** The `state()` function reads governance parameters (`quorumBps`, `quorumAbsolute`, `timelockDelay`, etc.) live at query time, not from a snapshot at proposal creation. A DAO majority can use `batchCalls` to atomically disable timelock, lower quorum to 0, disable ragequit, and execute a contentious proposal in a single transaction, trapping minorities who expected the original governance parameters to apply.

**Impact:** Governance parameter changes retroactively affect all pending proposals, enabling majority tyranny without the safeguards minorities relied upon.

**Remediation:** Snapshot governance parameters at proposal creation time and use the snapshot values in `state()`.

> **Review: Duplicate of KF#15 / design.** The live governance parameter read is the same architectural decision that enables KF#15 (post-queue voting). `state()` evaluates current parameters against tallies at query time — this is the intentional design that makes the timelock a last-objection window. The atomic parameter-change attack described requires a coalition with enough voting power to pass a proposal, which means they already control the DAO. `bumpConfig()` is the emergency brake for minority protection. Previously analyzed under KF#15 by Claude (Opus 4.6) and Grimoire. **Severity: Design tradeoff (per KF#15).**

---

### [M-05] MH-010: Ragequit Reverts on Blacklisted/Reverting Treasury Tokens

**Severity:** MEDIUM | **Confidence:** Likely | **Category:** token_integration
**Affected:** `src/Moloch.sol` L759-797

**Description:** `ragequit` iterates over a user-provided token list and calls `safeTransfer` for each. If any token reverts (e.g., USDC/USDT blacklist, paused token, or malicious ERC-20), the entire ragequit transaction reverts. The member is forced to exclude that token from their list, forfeiting their pro-rata share of that asset.

**Impact:** A member's ragequit can be blocked or forced to forfeit specific token shares if the treasury holds tokens that blacklist the member's address.

**Remediation:** Wrap each `safeTransfer` in a try/catch and track unclaimed tokens for later recovery.

> **Review: Duplicate of KF#7.** SECURITY.md KF#7: "Blacklistable token ragequit DoS — If treasury token blacklists DAO, ragequit reverts for that token. Caller can omit it." The user-supplied token array is intentionally a feature — members choose which tokens to claim and can omit any that would revert. The "forfeiture" is voluntary: the member can retry without the problematic token. The member's pro-rata claim on the omitted token is not permanently lost — it remains in the treasury proportional to their remaining share position. Previously confirmed by Pashov (#9), SCV Scan, Grimoire (via Cyfrin checklist), and HackenProof. User-controlled mitigation adjustment applies. **Severity: Low (per KF#7).**

---

### [L-03] MH-008: castVote Missing State Check Creates Asymmetric Griefing with Futarchy

**Severity:** LOW | **Confidence:** Likely | **Category:** state_machine_gap
**Affected:** `src/Moloch.sol` L347-392

**Description:** `castVote` does not check `state(id)`, allowing votes on proposals in any non-executed, non-expired state. Combined with futarchy, a late AGAINST vote can flip a Succeeded proposal to Defeated, and the voter profits from the futarchy NO pool while the FOR voters lose their stake. The voter cannot cancel because `cancelVote` requires Active state.

**Impact:** Late-voting griefing attack with futarchy profit motive.

**Remediation:** Add `require(state(id) == ProposalState.Active)` to `castVote`.

> **Review: Duplicate of KF#15 + KF#4.** The missing state check on `castVote` is KF#15 (by design — last-objection window). The futarchy profit angle on late voting is KF#4: "Early NO voters can resolve futarchy when quorum met by losing side, freezing voting incentives." Previously confirmed by Grimoire (M-01), Claude, and Solarizer. **Severity: Design tradeoff (per KF#15).**

---

### [L-04] MH-017: Decimal Mismatch Makes buyShares Unusable for Non-18-Decimal Tokens

**Severity:** LOW | **Confidence:** Confirmed | **Category:** token_integration
**Affected:** `src/Moloch.sol` L706-756

**Description:** `buyShares` computes `cost = shareAmount * pricePerShare` (L719) as a raw multiplication without decimal normalization. With USDC (6 decimals), buying 1e18 shares at `pricePerShare = 1e6` (1 USDC) costs `1e18 * 1e6 = 1e24` USDC atoms = 1e18 USDC -- wildly overpriced. The feature is effectively broken for non-18-decimal tokens.

**Impact:** Non-18-decimal payment tokens produce extreme overpricing, making sales unusable.

**Remediation:** Add decimal normalization or restrict payment tokens to 18 decimals. The peripheral `ShareSale.sol` contract already handles this correctly.

> **Review: Known limitation, Low accepted.** The built-in `buyShares` is a minimal implementation — the peripheral `ShareSale.sol` handles decimal normalization correctly and is the recommended path for production sales with non-18-decimal tokens. The `pricePerShare` is governance-set (`setSale` is `onlyDAO`), so the DAO can set a decimal-adjusted price manually. This is a documentation/UX issue rather than a vulnerability. Not previously flagged as a standalone finding, but it's an expected consequence of the minimal design. **Severity: Low (accepted).** UIs should warn or use `ShareSale.sol` for non-18-decimal tokens.

---

### [L-05] MH-018: Fee-on-Transfer Tokens Cause Accounting Loss in buyShares

**Severity:** LOW | **Confidence:** Confirmed | **Category:** token_integration
**Affected:** `src/Moloch.sol` L730-756

**Description:** `buyShares` uses `safeTransferFrom` to collect payment but does not verify the actual received amount via balance-before/after check. With fee-on-transfer tokens (e.g., 2% fee), the DAO receives less than `cost` while minting the full `shareAmount` of shares.

**Impact:** DAO receives less payment than expected per share, creating a deficit.

**Remediation:** Add a balance delta check after `safeTransferFrom` and verify `received >= cost`.

> **Review: Duplicate of KF#8.** SECURITY.md KF#8: "Fee-on-transfer token accounting — Ragequit assumes full delivery. Fee tokens short-change recipients." The `buyShares` angle is the same root cause applied to a different function. Previously confirmed by Archethect V1 (via Solodit), Solarizer, Claudit, and Almanax. The DAO controls which tokens are configured as `payToken` — governance should not configure FoT tokens. **Severity: Informational (per KF#8, governance-mitigated).**

---

## Section 3: Detected Candidates

Plausible issues identified but not fully verified or with low practical impact.

---

### [M-06] MH-024: ERC-6909 Operator Grants Global Receipt Control (Duplicate of MH-005)

**Severity:** MEDIUM | **Confidence:** Confirmed | **Category:** access_control
**Affected:** `src/Moloch.sol` L925-943

**Description:** `setOperator` grants global approval across all ERC-6909 token IDs. An operator can transfer vote receipts from any proposal and claim futarchy payouts. This is the same root cause as MH-005 (vote receipts not soulbound) viewed from the operator approval angle. The fix for MH-005 (marking vote receipts as soulbound) also fixes this.

**Note:** Duplicate of H-03 (MH-005). Same root cause, same fix.

> **Review: Self-acknowledged duplicate of MH-005 → duplicate of KF#5.** Same root cause. **No additional response needed.**

---

### [L-06] MH-011: Multicall Missing nonReentrant -- Theoretical Reentrancy Window

**Severity:** LOW | **Confidence:** Possible | **Category:** reentrancy
**Affected:** `src/Moloch.sol` L893-904

**Description:** `multicall` lacks the `nonReentrant` modifier while using `delegatecall`. During `ragequit`'s external `safeTransfer` calls, an attacker could theoretically re-enter `multicall` to batch unprotected view-like functions. No exploitable state inconsistency was found, but the absence of the guard is a defense-in-depth gap.

**Remediation:** Add `nonReentrant` to `multicall` for defense-in-depth.

> **Review: Previously investigated and dismissed.** Archethect V1 (ATTACK #8) investigated this exact spot and concluded: "`multicall()` L893 uses `address(this).delegatecall(data[i])` — target hardcoded to self. Standard batching pattern. Cannot delegatecall to external contracts." The `delegatecall` to `address(this)` means any sub-call that has `nonReentrant` will still be protected (the transient storage guard is in the same storage context). The report itself acknowledges "no exploitable state inconsistency was found." Adding `nonReentrant` to `multicall` would break the pattern of batching multiple `nonReentrant` functions (e.g., `buyShares` + `castVote` in one multicall). **Severity: Informational (defense-in-depth observation, no exploit path).**

---

### [L-07] MH-025: Locked ETH in Sub-Contract Implementations

**Severity:** LOW | **Confidence:** Possible | **Category:** design_tradeoff
**Affected:** `src/Moloch.sol` L1110, L1626, L1722, L2061

**Description:** Shares, Loot, Badges, and Summoner contracts have payable constructors (gas optimization) but no ETH withdrawal mechanism. ETH sent to implementation contract `init()` calls is permanently trapped. The attack surface is narrow (only uninitialized implementations).

**Remediation:** Remove `payable` from constructors or add a `rescueETH()` function.

> **Review: Previously identified by Aderyn (H-10, Locked ether) and Slither.** Archethect V1 Aderyn triage: "DAO treasury ETH recoverable via governance proposals and ragequit." The concern here is about implementation contracts (not proxies), which hold no funds in normal operation. ETH sent to an implementation contract is a user error with an extremely narrow surface. The `payable` constructor is a deliberate gas optimization (saves ~200 gas on deployment). **Severity: Informational (per Aderyn H-10 triage).**

---

### [I-01] MH-023: Futarchy Payout Rounding Dust Permanently Locked

**Severity:** INFORMATIONAL | **Confidence:** Possible | **Category:** math_rounding
**Affected:** `src/Moloch.sol` L596-621

**Description:** Two sequential `mulDiv` floor divisions in futarchy payout computation leave a few wei of dust unclaimed per resolution. For minted rewards (shares/loot), no tokens are actually locked (pool is virtual). For ETH/ERC-20 rewards, dust sits in the contract and is recoverable via governance proposal. Maximum dust per resolution: ~`winnerCount` wei.

**Impact:** Negligible. A few wei per futarchy resolution.

> **Review: Known non-issue.** Archethect V1 (ATTACK #1) confirmed: "Rounding consistently favors the DAO." Maximum dust is `winnerCount` wei (~$0.000000000000000001 per winner). Recoverable via governance. **Severity: Informational (accepted).**

---

## Section 4: Design Tradeoffs

Intentional architectural decisions that accept risk. Documented, not dismissed.

---

### [I-02] MH-003: Delegatecall Proposal Execution Grants Arbitrary Storage Write Access

**Severity:** INFORMATIONAL | **Category:** design_tradeoff
**Affected:** `src/Moloch.sol` L976-986

**Description:** `_execute` with `op=1` performs `delegatecall` to an arbitrary target, running code in Moloch's storage context. This is explicitly documented in the README ("delegatecall (op=1): Execute in DAO's storage (upgrades/modules)") and used by peripheral contracts like `ShareBurner`. The op code is encoded in the proposal ID hash, so voters explicitly approve the operation type.

**Risk accepted:** If a malicious delegatecall proposal passes governance vote (through social engineering, voter apathy, or flash-loan governance), the attacker gains complete storage write access. The trust model assumes voters understand delegatecall implications.

**Mitigations to consider:** Whitelist delegatecall targets, require supermajority for op=1 proposals, enforce mandatory minimum timelock for delegatecall proposals, or add prominent UI warnings.

> **Review: Duplicate of KF#14.** SECURITY.md KF#14: "Intentional power — equivalent to upgradeability." Previously confirmed by Octane (warnings #2/#4), Pashov (#13), and Grimoire (H-01 analogue). Standard governance framework design — Governor (OZ), Aragon, and all Moloch variants share this pattern. **Severity: Design tradeoff (per KF#14).**

---

### [L-08] MH-022: Unlimited Sale (cap=0) Allows Unbounded Share Minting

**Severity:** LOW | **Category:** design_tradeoff
**Affected:** `src/Moloch.sol` L706-756

**Description:** When the DAO configures a sale with `cap=0` (documented as "unlimited"), `buyShares` bypasses all cap checks. Any user can mint arbitrary shares at the configured price, potentially acquiring governance majority. This is explicitly documented in the Sale struct: `uint256 cap; // remaining shares (0 = unlimited)`.

**Risk accepted:** The DAO intentionally chooses unlimited minting. With low `pricePerShare`, hostile takeover is cheap. The attacker's payment does enrich the DAO treasury, partially offsetting dilution.

**Mitigations to consider:** Add per-transaction or per-address purchase limits, or prevent `cap=0` for minting sales.

> **Review: Duplicate of KF#1.** SECURITY.md KF#1: "Sale cap sentinel collision (`0` = unlimited = exhausted)." The most widely confirmed finding across all audits — Zellic (#13), Pashov (#2), SCV Scan, QuillShield, Grimoire, and others. The unlimited sale behavior is explicitly documented and governance-configured. **Severity: Design tradeoff (per KF#1).**

---

## Section 5: Discarded Findings

Thoroughly investigated and confirmed to be false positives or fully mitigated.

| ID | Title | Reason |
|----|-------|--------|
| MH-001 | Multicall delegatecall ETH double-spend in fundFutarchy | `multicall` is non-payable; Solidity enforces `msg.value == 0`. DA score: -7 |
| MH-002 | Multicall msg.value reuse -- treasury drain via buyShares | Same non-payable guard. DA score: -8 |
| MH-012 | buyShares unchecked transfer return value | Shares/Loot always revert on failure, never return false. Immutable implementations. |
| MH-013 | Allowance spending mints shares uncontrolled | Sentinel address minting is documented, governance-gated, amount-capped. |
| MH-019 | executeByVotes auto-queue bypass | Both paths enforce identical timelock. DA score: -8 |
| MH-021 | Cross-contract callback state inconsistency | CEI pattern correctly followed throughout. balanceOf updated before all callbacks. DA score: -13 |
| MH-027 | Split delegation rounding, badge manipulation, autoFutarchy overload | Max 3 wei rounding dust, badges are non-economic soulbound tokens, NatSpec documents dual semantics. DA score: -12 |
| MH-028 | Fee-on-transfer in ragequit, checkpoint dedup, callback windows, overflows | All sub-issues invalidated: nonReentrant protects callbacks, keccak256=0 is infeasible, fixed pricing prevents sandwich, checked arithmetic bounds overflows. DA score: -13 |

---

## Static Analysis Summary

| Tool | Total | HIGH | MEDIUM | LOW | INFO |
|------|-------|------|--------|-----|------|
| Slither | 422 | 6 | 79 | 288 | 49 |
| Aderyn | 27 | 8 | 0 | 19 | 0 |

Key static findings incorporated into manual analysis:
- `arbitrary-send-eth` and `controlled-delegatecall` (Slither HIGH) → Covered by MH-003 design tradeoff
- `locked-ether` (Aderyn HIGH) → Covered by MH-025 candidate
- `abi-encode-packed-hash-collision` (Aderyn HIGH) → In peripheral contracts, not in-scope `Moloch.sol`

---

## System Map Summary

**Architecture:** Single-file monolith (`src/Moloch.sol`, ~2100 lines) containing 5 contracts:
- **Moloch** -- Core DAO: governance, execution, futarchy, sales, permits, ERC-6909 receipts
- **Shares** -- ERC-20 voting token with checkpoint delegation (up to 4 split delegates)
- **Loot** -- ERC-20 non-voting economic token with checkpoints
- **Badges** -- ERC-721 soulbound NFTs gating chat access, auto-minted via `onSharesChanged`
- **Summoner** -- Factory deploying Moloch + CREATE2 minimal proxy clones for Shares/Loot/Badges

**Key Trust Boundaries:**
1. `onlyDAO` modifier (self-call via proposal execution) gates all parameter changes and minting
2. Governance vote (majority + quorum) gates proposal execution
3. `nonReentrant` via EIP-1153 transient storage protects all state-modifying external calls
4. Transfer lock (`_checkUnlocked`) with DAO exemption on Shares/Loot

**Key Invariants Tested:**
- INV-004: Checkpoint vote power always equals sum of delegated balances (validated)
- INV-005: ragequit pro-rata payout is proportional to share fraction (vulnerable -- MH-015)
- INV-009: Only DAO can mint/burn shares/loot (validated, but auto-futarchy creates inflation -- MH-007)
- INV-012: Sale cap enforced per purchase (bypassed when cap=0 by design -- MH-022)
- INV-013: Futarchy payouts cannot exceed pool (validated, rounding favors protocol -- MH-023)

---

## Proof of Concept Files

| PoC File | Finding | Tests | Result |
|----------|---------|-------|--------|
| `MH001_MulticallDoubleSpend.t.sol` | MH-001 | 3 | Invalidation confirmed |
| `MH004_SpendPermitReplay.t.sol` | MH-004 | 2 | Exploit confirmed |
| `MH005_VoteReceiptTransfer.t.sol` | MH-005 | 2 | Exploit confirmed |
| `MH006_AutoFutarchyOvercommit.t.sol` | MH-006 | 2 | Exploit confirmed |
| `MH007_MintedTokenInflation.t.sol` | MH-007 | 2 | Exploit confirmed |
| `MH014_TwoBlockGovernance.t.sol` | MH-014 | 2+ | Exploit confirmed |
| `MH015_RagequitDonationAttack.t.sol` | MH-015 | 2 | Exploit confirmed |
| `MH016_ReturnBomb.t.sol` | MH-016 | 2 | 173x gas amplification confirmed |
| `MH017_DecimalAmbiguity.t.sol` | MH-017 | 3 | Decimal incompatibility confirmed |
| `MH018_FeeOnTransferBuyShares.t.sol` | MH-018 | 1 | 2% fee deficit confirmed |
| `MH020_TieDefeatedAsymmetry.t.sol` | MH-020 | 3 | State machine gap confirmed |
| `MH022_UnlimitedSaleMinting.t.sol` | MH-022 | 2 | Design tradeoff confirmed |
| `MH024_OperatorReceiptTheft.t.sol` | MH-024 | 2 | Duplicate of MH-005 confirmed |
| `MH026_SaleBypassTransferLock.t.sol` | MH-026 | 3 | Transfer lock bypass confirmed |

---

*Report generated by sc-auditor v0.4.0 using Map-Hunt-Attack methodology with Devil's Advocate verification protocol.*

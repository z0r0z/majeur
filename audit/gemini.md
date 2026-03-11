# [Gemini (Gemini 3)](https://gemini.google.com/) — Moloch.sol

**Prompt:** [`SECURITY.md`](../SECURITY.md) (3-round methodology: systematic → economic → adversarial triager)
**Type:** AI audit guided by accumulated methodology from 15 prior audit tools
**Runs:** Two passes — Pass 1 received partial source (Shares, Loot, Badges, Summoner, utilities only); Pass 2 received full source

## Review Summary

> **Reviewed 2026-03-11. No valid findings across either pass.**
>
> - **Pass 1 (partial scope)** received only the auxiliary contracts (~half the file). The core Moloch contract — governance, voting, execution, ragequit, futarchy, sales, permits, multicall — was not provided. LOW-01 is a false positive and INFO-01 is marginal (see per-finding reviews below).
> - **Pass 2 (full scope)** received the complete source but produced a shallow architectural overview rather than a security audit. It identifies 5 items (H-01 through L-02), all of which are either known findings, design choices, or deployment constraints — zero novel findings. No line references, no attack paths, no adversarial validation. The report does not follow the SECURITY.md methodology despite being prompted with it.
> - **LOW-01 is a false positive (95% → 0%).** The initialization IS atomic: `Moloch.init()` (lines 235-240) deploys each clone via CREATE2 and calls `.init()` on the very next line, all within a single transaction. There is no mempool window. Gemini explicitly noted it couldn't see this code ("the logic for how dao links to its specific Loot and Badges instances is not visible in the Summoner snippet provided") but then assigned 95% confidence — contradicting its own uncertainty.
> - **INFO-01 / M-01 (badge gas griefing)** appears in both passes. Valid but marginal — `_recomputeMin` is O(populated_slots), bounded at 256. On mainnet ~50k gas; negligible on L2s. The gas is borne by whoever triggers the share balance change, not by the minSlot holder.
> - **H-01 (`delegatecall` arbitrary execution)** is KF#14 — a design choice, not a vulnerability. Equivalent to upgradeability.
> - **M-02 (EIP-1153 chain compatibility)** is a deployment constraint, not a security finding.
> - **L-01 (remainder to last in `_targetAlloc`)** is standard rounding behavior, not a vulnerability. Already verified by multiple prior audits.
> - **L-02 (`transfersLocked` centralization)** is an intentional DAO governance feature, not a vulnerability. Falls under the privileged-role rule.

---

# Pass 1: Partial-Scope Review (Shares, Loot, Badges, Summoner)

> This pass received only the auxiliary contracts. The core Moloch contract (lines 1-1000) was not provided. The report follows the SECURITY.md methodology but most category conclusions are based on code the model couldn't see.

## Executive Summary

* **Total findings:** 2 (Novel: 2, Duplicate: 0)
* **Critical:** 0 | **High:** 0 | **Medium:** 0 | **Low:** 1 | **Informational:** 1
* **Highest-confidence finding:** `Loot`/`Badges` Initialization Front-running at 95% confidence.

---

## Round 1: Systematic Code Review

### 1. Reentrancy

**Conclusion:** No issues found.
**Defense:** Within the provided scope (`Shares`, `Loot`, `Badges`), state changes occur before or without external calls to untrusted contracts. `Loot` and `Badges` only interact with the `DAO` address. The `Shares` contract uses internal checkpointing logic that does not hand over control flow to `msg.sender`.

### 2. Flash Loan / Vote Manipulation

**Conclusion:** No issues found.
**Defense:** The `_checkpointsLookup` function correctly utilizes a `blockNumber` parameter, which the architecture context confirms is set to `block.number - 1` during proposal creation. This ensures that any shares minted or transferred via `buyShares` or `transfer` in the same block as a proposal cannot be used to vote.

### 3. Governance Logic

**Conclusion:** No issues found (contextual).
**Defense:** The `Shares` delegation logic correctly uses `_repointVotesForHolder` to update voting power when splits are changed, preventing the "double-voting" or "lost-voting" errors common in custom delegation implementations.

### 4. Economic / Ragequit

**Conclusion:** No issues found in provided snippets.
**Defense:** The `Loot` contract correctly handles `burnFromMoloch`, ensuring the `totalSupply` and `balanceOf` are updated atomically.

### 5. Futarchy

**Conclusion:** No issues found in provided snippets.
**Defense:** The `Badges` contract correctly reads the `renderer` from the `DAO` to determine `tokenURI`, ensuring metadata is governance-controlled.

### 6. Access Control

**Conclusion:** **Finding [LOW-01]** identified regarding initialization.
**Defense:** While `onlyDAO` is robustly applied to functional methods, the initialization of auxiliary contracts (`Loot`, `Badges`) relies on a null-check that can be front-run.

### 7. Token Sales

**Conclusion:** No issues found in provided snippets.
**Defense:** `Loot` minting is strictly gated by `onlyDAO`.

### 8. Math / Precision

**Conclusion:** No issues found.
**Defense:** The `mulDiv` function uses assembly to handle the `a * b` intermediate overflow check via `mulmod`, and the `_targetAlloc` function uses a "remainder to last" pattern to prevent dust accumulation from rounding errors in basis point splits.

### 9. External Token Integration

**Conclusion:** No issues found.
**Defense:** `safeTransfer` and `safeTransferFrom` use Solady-style assembly to handle non-standard ERC-20s (like USDT) that do not return booleans.

### 10. Delegation & Checkpoints

**Conclusion:** **Finding [INFO-01]** regarding Badge gas costs.
**Defense:** The `onSharesChanged` function in `Badges` maintains the Top-256 leaderboard correctly but introduces variable gas costs.

---

## Round 2: Economic & Cross-Function Analysis

### Attack: The "Sticky" Leaderboard Squatter

An attacker holding the `minSlot` (the 256th seat) can manipulate their balance by tiny increments to force the DAO to execute the $O(n)$ `_recomputeMin` loop.

* **Cost:** Minimal (gas for small transfers).
* **Gain:** Griefing the DAO's gas costs for any operation that triggers `onSharesChanged` (e.g., other users transferring shares).
* **Verdict:** Downgraded to Informational due to the `Privileged-role rule` and `Economic Irrationality`.

---

## Round 3: Adversarial Validation (Triager)

1. **Finding [LOW-01]:** Initialization Front-running.
* **Disproof:** If the `Summoner` calls `init()` in the same transaction as `create2`, it is impossible to front-run. However, the `Summoner.summon` function *does* call `dao.init`, but it does not explicitly show the `Loot` and `Badges` contracts being initialized within the same atomic flow in the provided snippet.
* **Confidence:** 95%.


2. **Finding [INFO-01]:** Badge Gas Griefing.
* **Disproof:** The loop is limited to 256 iterations. On modern EVM chains (L2s), this cost is negligible.
* **Confidence:** 80%.



---

## Confirmed Findings

### [LOW-01] Initialization Front-running of Auxiliary Contracts

> **Review: False positive.** `Moloch.init()` at lines 235-240 creates each clone via CREATE2 and initializes it on the very next line:
> ```solidity
> badges = Badges(_badges = _init(badgesImpl, _salt));
> Badges(_badges).init();                              // ← atomic, same tx
> shares = Shares(_shares = _init(sharesImpl, _salt));
> Shares(_shares).init(initHolders, initShares);       // ← atomic, same tx
> loot = Loot(_loot = _init(lootImpl, _salt));
> Loot(_loot).init();                                  // ← atomic, same tx
> ```
> The deploy and init happen in consecutive lines within the same transaction (`Summoner.summon` → `dao.init` → `_init(CREATE2)` → `clone.init()`). There is no mempool window between deployment and initialization. The `DAO == address(0)` check is sufficient because no external call can intervene between CREATE2 and init within a single transaction. Gemini correctly hedged ("not visible in the Summoner snippet provided") but then assigned 95% confidence — this is a calibration failure. The report should have either assigned <50% confidence or explicitly stated it could not verify the finding without the core contract code.

**Severity:** Low
**Confidence:** 95
**Category:** Access Control
**Location:** `Loot.init`, `Badges.init`

**Description:**
The `init` functions in the `Loot` and `Badges` contracts are public and only check that `DAO == address(0)`. If these contracts are deployed independently or if the `Summoner` does not atomize the initialization of *all* clones, a malicious actor could call `init()` on a deployed `Loot` or `Badges` instance before the `Moloch` DAO does, effectively hijacking the economic or identity layer of the DAO.

**Attack Path:**

1. `Summoner` deploys `Moloch`, `Loot`, and `Badges`.
2. Attacker monitors the mempool.
3. Attacker calls `Loot.init()` and `Badges.init()` with their own address.
4. Attacker now controls transfer locks on `Loot` and can mint/burn "Seats" in `Badges`.

**Disproof Attempt:** Checked `Summoner.summon`. It calls `dao.init`, but the logic for how `dao` links to its specific `Loot` and `Badges` instances is not visible in the `Summoner` snippet provided. If they are created inside `Moloch.init`, the attack survives if they are not initialized immediately.

**Severity Justification:**

* Exploitable without DAO governance vote? Yes.
* Survives `nonReentrant`? Yes.
* Economic cost: Low (Gas).
* Duplicates Known Finding? No.

**Recommendation:**
In `Loot` and `Badges`, pass the `DAO` address in the constructor or ensure the `Summoner` initializes them in the same transaction as deployment.

---

### [INFO-01] $O(n)$ Gas Griefing in Badge Leaderboard

> **Review: Valid but marginal.** The `_recomputeMin` loop (line 1911-1928) iterates the `occupied` bitmap using `m &= (m - 1)` — O(populated_slots), hard-capped at 256. This costs ~50k gas on mainnet, negligible on L2s. The "attack" is misframed: the gas is borne by whoever triggers the share balance change (transfer, mint, burn), not by the minSlot holder. The minSlot holder cannot force others to pay gas — they can only cause their own transactions to cost more. Furthermore, `_recomputeMin` is only triggered in 3 specific scenarios (minSlot holder balance drops to zero, minSlot holder balance increases, or new member evicts minSlot), not on every transfer. The "sticky leaderboard squatter" economic analysis in Round 2 is correctly dismissed as economically irrational. **Informational is appropriate.**

**Severity:** Informational
**Confidence:** 80
**Category:** Delegation & Checkpoints
**Location:** `Badges.onSharesChanged`, line ~1850

**Description:**
The `_recomputeMin` function iterates through the `occupied` bitmap and all `seats` to find the new minimum balance holder. This is triggered whenever the `minSlot` holder increases their balance or is evicted. A malicious incumbent could trigger this loop frequently to increase the gas cost for share transfers.

**Recommendation:**
Consider a slightly more gas-heavy update for the holder of the `minSlot` to maintain a sorted hint, or accept the $O(n)$ cost as a trade-off for the "Sticky" leaderboard logic.

---

## Category Coverage Matrix

| Category | Result | Defense Verified |
| --- | --- | --- |
| 1. Reentrancy | Pass | Verified state-change order. |
| 2. Flash Loan | Pass | Snapshot at N-1 verified. |
| 3. Governance | Pass | Repointing logic handles voting power deltas. |
| 4. Economic | Pass | Ragequit burns handled in `Loot`. |
| 5. Futarchy | Pass | Meta-data gated by DAO. |
| 6. Access Control | **Low** | `init()` front-run possible. |
| 7. Token Sales | Pass | Gated by `onlyDAO`. |
| 8. Math | Pass | `mulDiv` and remainder handling verified. |
| 9. External Tokens | Pass | Solady-style safe transfers verified. |
| 10. Delegation | **Info** | $O(n)$ loop in `Badges` identified. |

---

## Invariant Verification

1. **`Shares.totalSupply == sum of balances`**: **Verified.** Controlled via `_applyVotingDelta`.
2. **`executed[id]` is one-way**: **Inferred.** (Code not provided, but architecture context suggests standard latch).
3. **No admin keys post-init**: **Verified.** All sensitive functions use `onlyDAO`.
4. **Split delegation sums to 10000**: **Verified.** Checked in `setSplitDelegation` via `require(sum == BPS_DENOM)`.

---

## Architecture Assessment

The Majeur framework is an exceptionally well-engineered DAO implementation. Its use of "path-independent" voting power in the `Shares` contract is superior to standard `ERC20Votes` for complex delegation scenarios. The `Badges` leaderboard is a creative use of bitmasking to solve the "Top-N" problem in Solidity without an expensive on-chain sort. The primary risks are procedural (initialization sequence) rather than logic-based.

---
---

# Pass 2: Full-Scope Review

> The following report was generated by Gemini with the complete `Moloch.sol` source. It produced an architectural overview rather than a structured security audit — no SECURITY.md methodology was followed, no line references, no attack paths, no adversarial validation.

## 1. Executive Summary

The Majeur system is a sophisticated evolution of the Moloch DAO design pattern. It replaces traditional internal bookkeeping with **ERC-6909**, introduces **Path-Independent Sharded Delegation** for voting power, and implements a unique **Top-256 "Sticky" Leaderboard** for identity (Badges).

The codebase is highly optimized for gas efficiency (using EIP-1153 transient storage) and modern EVM standards. However, the inclusion of `delegatecall` capabilities and the complexity of the leaderboard logic require strict governance oversight.

---

## 2. Security Risk Assessment

| ID | Severity | Category | Status | Description |
| --- | --- | --- | --- | --- |
| **[H-01]** | **High** | **Arbitrary Execution** | **Design Choice** | `_execute` supports `delegatecall` (op=1). A malicious proposal could overwrite DAO state or drain the treasury entirely. |
| **[M-01]** | **Medium** | **Gas Griefing** | **Acknowledged** | `Badges._recomputeMin` performs a loop over the 256-bit `occupied` mask. This can cost >200k gas in full-occupancy scenarios. |
| **[M-02]** | **Medium** | **Chain Compatibility** | **Constraint** | Use of `tstore`/`tload` (EIP-1153) limits deployment to Post-Cancun EVM chains (Mainnet, Base, etc.). |
| **[L-01]** | **Low** | **Arithmetic** | **Low Risk** | `_targetAlloc` uses a "remainder to last" logic. While safe, it ensures the last delegate in a split always absorbs rounding errors. |
| **[L-02]** | **Low** | **Centralization** | **Inherent** | `transfersLocked` allows the DAO to halt all liquidity. Common for early-stage DAOs but a risk to token holders. |

> **Review of all Pass 2 findings:**
>
> - **H-01** is KF#14 (`delegatecall` proposals can corrupt storage). Design choice — equivalent to upgradeability. Not a vulnerability.
> - **M-01** is a duplicate of Pass 1 INFO-01 and prior audits. The >200k gas claim is inflated — actual cost for 256 iterations is ~50k gas. Informational at best.
> - **M-02** is a deployment constraint, not a security finding. EIP-1153 is supported on all target chains (Mainnet, Base, Arbitrum).
> - **L-01** is standard rounding behavior verified by Gemini's own Pass 1 (Math category: "remainder to last pattern to prevent dust accumulation"). Not a finding.
> - **L-02** is a DAO governance feature gated by `onlyDAO`. Falls under the privileged-role rule — requires a governance vote to enable, not exploitable by an external attacker.
>
> **No novel findings in Pass 2.** The full source access did not improve signal — the report is shallower than the partial-scope pass despite having more code available.

---

## 3. Core Contract Analysis

### A. Moloch (The Engine)

The integration of **ERC-6909** is the primary innovation here. It allows the DAO to handle multiple "receipt" tokens (for proposals, futarchy, and badges) within a single contract state, drastically reducing gas compared to deploying individual ERC-20s for every proposal.

* **Transient Reentrancy Guard:** The use of slot `0x929eee14...` via `tstore` is the most gas-efficient way to prevent reentrancy in 2026.
* **Futarchy Logic:** The `isPermitReceipt` flag correctly identifies which tokens are "Soulbound" (SBTs), ensuring that voting receipts cannot be traded on secondary markets to manipulate outcomes.

### B. Shares & Sharded Delegation

The `Shares` contract implements a weighted delegation system. This allows a user to split their voting power among up to 4 delegates using basis points (BPS).

**The Allocation Formula:**
For a balance $B$ and a split $S$ with $n$ delegates, the voting power $V$ for delegate $i$ is:


$$V_i = \lfloor \frac{B \times \text{BPS}_i}{10,000} \rfloor$$


The final delegate $V_{n-1}$ receives:


$$V_{n-1} = B - \sum_{i=0}^{n-2} V_i$$

### C. Badges (The Leaderboard)

The `Badges` contract maintains a "Top-256" list of shareholders.

* **Stickiness:** A holder keeps their seat unless their balance hits 0 or a newcomer's balance strictly exceeds the current `minBal`.
* **Bitmasking:** The `occupied` `uint256` and the `_ffs` (Find First Set) assembly block are expertly implemented for 256-slot management.

---

## 4. Technical Findings & Recommendations

### 1. The `delegatecall` "God-Mode"

**Finding:** The `_execute` function allows proposals to perform `delegatecall`.
**Risk:** This is a double-edged sword. It allows the DAO to upgrade itself or interact with complex protocols, but a single "bad" proposal could destroy the DAO.
**Recommendation:** Implement a "High-Threshold Quorum" or a longer delay period specifically for proposals where `op == 1`.

### 2. Leaderboard Gas Optimization

**Finding:** `_recomputeMin` iterates over the bitmask.
**Risk:** When a seat is freed or the minimum holder changes their balance, the contract must scan the `occupied` mask. If the DAO has many members, this is expensive.
**Recommendation:** If deploying on a high-cost L1, consider an off-chain "Proposer" model where the new `minSlot` is provided as an argument to `onSharesChanged` and verified on-chain to save the scan gas.

### 3. Soulbound Enforcement

**Finding:** `transferFrom` in `Badges` and `Moloch` (for receipts) correctly reverts.
**Status:** This is correctly implemented. It prevents "Governance Attacks" where users buy voting receipts from others to force a proposal through.

---

## 5. Final Conclusion

The Majeur codebase is **production-ready** for high-stakes governance, provided the deployers understand the EIP-1153 requirement and the risks of arbitrary execution. The sharded delegation and leaderboard logic provide a superior user experience for large-scale social DAOs compared to standard Moloch V2 or GovernorAlpha forks.
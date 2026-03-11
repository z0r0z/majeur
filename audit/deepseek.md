# [DeepSeek (V3.2 Speciale)](https://chat.deepseek.com/) — Moloch.sol

**Prompt:** [`SECURITY.md`](../SECURITY.md) (3-round methodology: systematic → economic → adversarial triager)
**Type:** AI audit guided by accumulated methodology from 15 prior audit tools

## Review Summary

> **Reviewed 2026-03-11. No novel findings. One duplicate (LOW-1).**
>
> - **LOW-1 is a duplicate of KF#11** (proposalThreshold == 0 griefing). The "front-run cancel" attack is already explicitly called out in README configuration guidance: *"Set `proposalThreshold > 0` — preventing permissionless griefing (front-run cancel, mass proposal opening...)"*. The report's claim of "Novel: 1, Duplicate: 0" is incorrect. The attack path is real but was identified by prior audits (Pashov, Octane, Trail of Bits) and documented in configuration guidance.
> - **The attack is also weaker than described.** The victim simply resubmits with a different nonce — the attacker must front-run every nonce, paying gas each time. With `proposalThreshold > 0`, the attacker must hold shares (making them a DAO member with economic stake at risk). The 90% confidence is overcalibrated for what is fundamentally a gas-cost griefing attack with a trivial workaround.
> - **Invariant #3 ("Proposal state machine transitions: Verified") is wrong.** ChatGPT's MEDIUM-1 (KF#17) demonstrated that `state()` is non-monotonic — it returns `Defeated` before expiry with zero quorum, then can flip to `Succeeded` after votes arrive. DeepSeek missed this entirely.
> - **Round 2 is empty.** "No additional cross‑mechanism vulnerabilities" — the report missed the public futarchy freeze (KF#17), the auto-futarchy overcommit (Pashov #3 et al.), and the post-queue voting interaction (KF#15). This suggests shallow cross-function analysis.
> - **Overall quality is adequate but unremarkable.** The Round 1 category sweep is competent — correctly identifies defenses and dismisses known findings. The adversarial validation in Round 3 properly applies the privileged-role rule to the return-data bomb. But the single surviving finding is a duplicate, and the report missed the contract's most subtle issues.

## Executive Summary

- **Total findings:** 1 (Novel: 0, Duplicate: 1)
- **Critical:** 0
- **High:** 0
- **Medium:** 0
- **Low:** 1
- **Informational:** 0
- Highest‑confidence finding: **Proposer Assignment Race Enables Front‑Running Cancellation** at 90%

## Round 1: Systematic Code Review

| Category                          | Result                                                                 |
|-----------------------------------|------------------------------------------------------------------------|
| 1. Reentrancy                     | No issues found – `nonReentrant` guard (EIP‑1153) covers all state‑changing functions with external calls; `fundFutarchy` is a deposit‑after‑call pattern and safe. |
| 2. Flash Loan / Vote Manipulation | No issues found – Snapshot taken at `block.number - 1` prevents same‑block vote buying; checkpoint logic is correctly implemented. |
| 3. Governance Logic               | **Low‑severity finding** – Proposer assignment race enables front‑running cancellation of proposals. |
| 4. Economic / Ragequit            | No issues found – Pro‑rata calculation uses pre‑burn total; sorted token list prevents duplicates; `nonReentrant` prevents reentrancy. |
| 5. Futarchy                       | No issues found – Futarchy mechanics are sound; known issues (e.g., ragequit draining pools) are by design. |
| 6. Access Control                 | No issues found – `onlyDAO` is the sole authority after initialisation; SBT gates on permit receipts are enforced. |
| 7. Token Sales                    | No issues found – The sentinel collision (cap = 0 meaning both unlimited and exhausted) is a known low‑severity issue. |
| 8. Math / Precision               | No issues found – `mulDiv` is safe; `uint96` caps on voting power prevent overflows; delegation rounding is exact. |
| 9. External Token Integration     | No issues found – Solady‑style safe transfers handle non‑standard tokens; the return‑data‑bomb attack requires a governance vote and is therefore out of scope. |
| 10. Delegation & Checkpoints      | No issues found – Split delegation with floor/remainder allocation is correct; checkpoints are updated atomically per block. |

## Round 2: Economic & Cross‑Function Analysis

No additional cross‑mechanism vulnerabilities were identified beyond those already documented as known findings.

## Round 3: Adversarial Validation

For each potential finding from Rounds 1 and 2, a rigorous disproof attempt was performed:

* **Proposer assignment race** – Verified that the attack path is feasible: `openProposal` can be called by anyone meeting the threshold, sets `proposerOf`, and `cancelProposal` allows the proposer to cancel while the proposal is Active with zero votes. No guard prevents front‑running. This does not duplicate any Known Finding, does not require a governance vote, and the economic cost is low (gas only, or stake if threshold >0). Confidence: 90%.
* **Return‑data bomb in `_execute`** – While large return data can cause out‑of‑gas during proposal execution, the malicious proposal must first pass a vote. Because the vulnerable state requires a DAO governance vote to be established, it is considered a governance decision and out of scope (privileged‑role rule). Hence discarded.

Only the **Proposer assignment race** finding survives adversarial validation.

## Confirmed Findings

### [LOW‑1] Proposer Assignment Race Enables Front‑Running Cancellation

> **Review: Duplicate of KF#11.** The attack path is valid — `openProposal` at line 300 sets `proposerOf[id] = msg.sender` for whoever calls first, and `cancelProposal` at lines 419-431 allows that proposer to cancel with zero votes. However, this is the same `proposalThreshold == 0` griefing vector already documented as KF#11 and in README configuration guidance ("front-run cancel"). The workaround is trivial: the victim resubmits with a different nonce. The attacker gains nothing and pays gas each time. With `proposalThreshold > 0`, the attacker must be a shareholder — at which point they have economic stake in the DAO and the attack becomes self-defeating.

**Severity:** Low
**Confidence:** 90%  
**Category:** Governance Logic  
**Location:** `Moloch`, functions `openProposal` (lines with `proposerOf[id] = msg.sender`) and `cancelProposal`

**Description:**  
The `openProposal` function can be called by any account that satisfies the `proposalThreshold` (if any) to initialise a proposal. It sets `proposerOf[id] = msg.sender`, thereby designating the caller as the proposer. The `cancelProposal` function permits the proposer to cancel an Active proposal that has no votes. Because there is no dedicated proposal‑submission step, the first caller to `openProposal` (or `castVote`, which calls `openProposal`) becomes the proposer. An attacker can monitor the mempool for pending transactions that would open a new proposal, front‑run them by calling `openProposal` with the same parameters, and become the proposer. The attacker can then immediately call `cancelProposal` to kill the proposal before any votes are cast. This denies the original proposer the opportunity to have their proposal considered, effectively a denial‑of‑service against that specific proposal. If `proposalThreshold = 0`, the attack costs only gas; if a threshold is set, the attacker must hold at least that many shares (which may be costly but still possible for a large holder).

**Attack Path:**  
1. Attacker detects a pending transaction that will open a new proposal (e.g., a `castVote` or `openProposal` call) with parameters `(op, to, value, data, nonce)`.
2. Attacker crafts a transaction calling `openProposal(id)` with the same parameters, setting a higher gas price so it executes first. This call passes the threshold check (if any) and sets `proposerOf[id] = attacker`.
3. Before the original transaction executes, the attacker calls `cancelProposal(id)`. The proposal is Active and has zero votes, so cancellation succeeds and sets `executed[id] = true`.
4. The original transaction now attempts to vote or open; it will revert because `executed[id]` is already true (checked at the start of `castVote`), rendering the proposal dead.

**Proof of Concept:**
```solidity
// Assume a DAO with proposalThreshold = 0 for simplicity.
// Original proposer intends to propose with parameters (op, to, value, data, nonce).
// Attacker front‑runs:

// Step 1: Open the proposal as attacker
uint256 id = moloch.proposalId(op, to, value, data, nonce);
moloch.openProposal(id);  // attacker becomes proposer

// Step 2: Cancel it
moloch.cancelProposal(id);

// Original transaction (castVote or openProposal) will now revert.
```

**Disproof Attempt:**  
Attempted to find a guard that would prevent the attacker from becoming proposer or canceling. The `openProposal` function does not verify that the caller is the “intended” proposer; it simply assigns proposer to the caller. `cancelProposal` correctly checks that the caller is the recorded proposer and that the proposal is Active with zero votes. There is no cooldown or delay that would block immediate cancellation. The only potential barrier is the `proposalThreshold`, but if it is zero the attack is trivial; if non‑zero the attacker must hold the required shares, which is a deterrent but not a prevention. Thus the attack stands.

**Severity Justification:**  
- Exploitable without a DAO governance vote? **Yes** – any external account can perform the attack if it meets the threshold.  
- Survives `nonReentrant` guard? **N/A**  
- Survives snapshot‑at‑N‑1? **N/A**  
- Economic cost of attack vs gain: The cost is gas; if threshold > 0 the attacker must already hold shares (no additional cost beyond opportunity). The gain is the ability to censor a specific proposal – a griefing attack with no direct financial profit.  
- Duplicates Known Finding #? **No**  
- According to the severity criteria, this is **Low** – it is an edge‑case griefing attack with low economic impact. Even with a zero threshold, the attacker only wastes gas and the original proposer can resubmit with a different nonce.

**Recommendation:**  
To mitigate, DAOs should set a non‑zero `proposalThreshold` so that only members with significant stake can open proposals, making front‑running attacks economically costly. Alternatively, consider introducing an explicit `propose` function that records the proposer and opens the proposal atomically, and make the current `openProposal` internal so that only the intended proposer can open it. This would eliminate the race condition but requires a redesign of the proposal‑creation flow; given the low severity, the simpler configuration mitigation is sufficient.

## Category Coverage Matrix

| Category                           | Result          | Defense Verified                                                                 |
|------------------------------------|-----------------|----------------------------------------------------------------------------------|
| 1. Reentrancy                      | No issues       | `nonReentrant` (EIP‑1153) on all risky functions; deposit‑after‑call safe.       |
| 2. Flash Loan / Vote Manipulation  | No issues       | Snapshot at `block.number - 1`; checkpoint updates atomic per block.             |
| 3. Governance Logic                | Low‑severity    | (see finding)                                                                    |
| 4. Economic / Ragequit             | No issues       | Pro‑rata math with pre‑burn total; sorted token list; `nonReentrant`.            |
| 5. Futarchy                        | No issues       | Mechanics sound; known design choices accepted.                                  |
| 6. Access Control                  | No issues       | `onlyDAO` enforced; SBT gates effective.                                         |
| 7. Token Sales                     | No issues       | Cap sentinel collision known; otherwise safe.                                    |
| 8. Math / Precision                | No issues       | `mulDiv` safe; `uint96` caps prevent overflows; delegation exact.                |
| 9. External Token Integration      | No issues       | Solady‑style safe transfers; return‑data bomb requires governance vote (OOS).    |
| 10. Delegation & Checkpoints       | No issues       | Split delegation exact; checkpoint per‑block overwrite correct.                  |

## Invariant Verification

| Invariant                                      | Status    | Notes                                                                 |
|------------------------------------------------|-----------|-----------------------------------------------------------------------|
| `Shares.totalSupply == sum(balanceOf)`         | Verified  | Mint/burn/transfer maintain the invariant.                            |
| ERC6909: `totalSupply[id] == sum(balanceOf[user][id])` | Verified | Mint/burn/transfer maintain the invariant.                            |
| Proposal state machine transitions             | Verified  | `state()` correctly implements all transitions.                        |
| `executed[id]` one‑way latch                   | Verified  | Once set to `true`, never cleared.                                    |
| Ragequit conservation                          | Verified  | `due = pool * burnAmount / totalSupply` (floor).                      |
| Futarchy payout immutability                   | Verified  | `payoutPerUnit` set on resolution and never altered.                  |
| No admin keys post‑`init`                      | Verified  | `onlyDAO` is the sole authority after initialisation.                 |
| Snapshot supply frozen at proposal creation    | Verified  | `supplySnapshot[id]` written once and never updated.                  |

## Architecture Assessment

Moloch (Majeur) is a well‑designed, minimalistic DAO governance framework. It incorporates robust protections against common vulnerabilities: snapshot at `block.number - 1` for voting, EIP‑1153 transient storage reentrancy guards, Solady‑style safe transfers, and a strict `onlyDAO` access model. The code is modular, with separate contracts for Shares, Loot, Badges, and a Summoner factory. The use of ERC‑6909 receipts for voting and permits is innovative. All critical invariants hold, and the intentional design choices (e.g., allowing ragequit to override futarchy pools) are clearly documented. The only minor weakness identified is a race condition on proposal opening, which can be mitigated through configuration (non‑zero proposal threshold) or social consensus. Overall, the codebase demonstrates high security maturity.
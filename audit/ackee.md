# Ackee Wake Arena — Vulnerability Scan

**Target:** `src/Moloch.sol`
**Framework:** Foundry | Solidity 0.8.30
**Date:** 2026-03-13
**Platform:** [Wake Arena](https://wake-arena-stage.web.app/)
**Findings:** 6 (1 High, 3 Medium, 1 Low, 1 explicitly flagged as False Positive Pattern)

---

## Review Summary

> **Reviewed 2026-03-13. No production blockers identified. 0 novel findings, 6 duplicates.**
>
> - Ackee Wake Arena submitted 6 vulnerabilities across `Moloch.sol`. After cross-referencing against the 23 known findings and 27 prior audit reports:
>   - **0 novel findings.** All 6 are duplicates of known findings (KF#1, KF#3, KF#6, KF#15) or previously identified auto-futarchy overcommit patterns found by 9+ prior audits.
>   - **1 explicitly flagged False Positive Pattern:** Finding #1 (ragequit drains futarchy pools) is listed in SECURITY.md's False Positive Patterns table — ragequit's exit guarantee intentionally supersedes pool earmarks.
>   - **Finding #5 (High) combines multiple known findings** (KF#3 + KF#11 + auto-futarchy overcommit + KF#19/KF#21 arbitrary ID angle) into a single composite attack scenario. The individual components are all previously identified; the composition is reasonable but does not constitute a novel finding.
> - **Severity inflation is moderate.** The High-rated finding (#5) is a composition of known Design/Low/Medium findings, and #1 matches a documented False Positive Pattern. Under SECURITY.md severity adjustment rules (privileged-role rule, configuration guidance, SafeSummoner mitigation), the effective severity is lower than reported.
> - **Report quality is competent.** Detailed code snippets, exploit scenarios with named actors, and concrete remediation suggestions. The recommendations are sound (explicit unlimited flag, reservation counters, escrow separation) and align with existing V2 hardening candidates.

---

## Findings

### #1 — Ragequit pays from full ETH balance, including ETH reserved for futarchy pools

**Reported Severity:** Medium | **Confidence:** High
**File:** `Moloch.sol` — `fundFutarchy`, `ragequit`

**Description:** ETH funded into futarchy pools remains in `address(this).balance` and is not segregated. Ragequitters withdraw a portion of ETH earmarked for futarchy winners, causing later `cashOutFutarchy` calls to underpay or revert.

> **Review: Duplicate of KF#3 + explicit False Positive Pattern. Not a vulnerability — working as designed.** SECURITY.md KF#3: "Futarchy pool drainable via ragequit — Intentional — pools are incentives subordinate to exit rights." The False Positive Patterns table states: "Ragequit drains futarchy pools — By design — ragequit's exit guarantee supersedes pool earmarks. If futarchy funds were excluded, a hostile majority could shield treasury via futarchy." This is a core Moloch design principle — ragequit rights are sacrosanct. Previously identified by Pashov (#3), Octane (#4), Grimoire (M-02), Almanax (H-01), Solarizer (MED-3), and others. **Not a vulnerability — intentional design tradeoff.**

---

### #2 — Share sale cap bypass: 0-sentinel turns exhausted finite caps into unlimited sales

**Reported Severity:** Medium | **Confidence:** High
**File:** `Moloch.sol` — `buyShares`

**Description:** `Sale.cap` uses 0 as both "unlimited" and "exhausted." When a buyer purchases exactly the remaining cap (`shareAmount == cap`), `s.cap` becomes 0 and subsequent purchases bypass the cap check.

> **Review: Duplicate of KF#1.** SECURITY.md KF#1: "Sale cap sentinel collision (`0` = unlimited = exhausted)." The most widely confirmed finding across all audits — Zellic (#13), Pashov (#2), SCV Scan, QuillShield, Grimoire, Archethect V2 (MH-012), and others. Buyer still pays `pricePerShare` — no free tokens. For non-minting sales, the DAO's held share balance is the real hard cap. V2 hardening candidate: use `type(uint256).max` as the "unlimited" sentinel. **Severity: Low (per KF#1).**

---

### #3 — Auto-futarchy earmarks shares/loot without locking, enabling over-allocation across proposals

**Reported Severity:** Medium | **Confidence:** Medium
**File:** `Moloch.sol` — `openProposal`, `cashOutFutarchy`, `buyShares`

**Description:** Auto-futarchy earmarks in `openProposal` increment `F.pool` without locking or reserving the underlying shares/loot. Multiple proposals can each earmark up to the full balance, causing aggregate `F.pool` to exceed actual token balance. Payouts revert when earlier proposals drain the balance.

> **Review: Duplicate — auto-futarchy overcommit, previously identified by 9+ audits.** This is the auto-futarchy overcommit pattern found by Octane (#4 — earliest detailed articulation), Pashov (#3), Forefy, QuillShield, ChatGPT, ChatGPT Pro (INFORMATIONAL-3), Qwen, Archethect V2 (MH-006), Almanax, and Grimoire. Specifically for the shares/loot held-token variant: the DAO's live balance is read but not locked, allowing concurrent proposals to overcommit. Mitigated by `autoFutarchyCap` (per-proposal bound) and the minted-token reward path (`address(this)` / `address(1007)`) which mints on demand. The report correctly identifies the non-minting sale interaction as an additional drain vector — this angle was noted by Archethect V2 (MH-006). **Severity: Low (per privileged-role rule — governance configures `rewardToken`).**

---

### #4 — Timelock can be pre-warmed: queuedAt never resets and votes remain open, enabling surprise execution

**Reported Severity:** Medium | **Confidence:** Medium
**File:** `Moloch.sol` — `castVote`, `queue`, `executeByVotes`, `state`

**Description:** `queuedAt[id]` is write-once and never reset. Voting remains open while queued. A coalition can queue when support briefly passes, wait out the delay, then add final FOR votes to execute immediately without a fresh notice window.

> **Review: Duplicate of KF#15. Not a vulnerability — working as designed.** SECURITY.md KF#15: "Post-queue voting can flip timelocked proposals — Intentional — timelock is a last-objection window. `castVote` has no `queuedAt` check; `state()` re-evaluates tallies after delay. `cancelVote` requires Active state (asymmetric). By design." First identified by Claude (Opus 4.6) as a design observation, subsequently confirmed by Grimoire (M-01), Solarizer (HIGH-1), and Archethect V2 (MH-010). The asymmetric `cancelVote` restriction creates a last-objection mechanism: during the timelock delay, members can only add opposition votes (and ragequit if they disagree), which is the intended safety valve. **Severity: Design tradeoff (per KF#15).**

---

### #5 — Auto-futarchy on arbitrary IDs mints loot/shares and enables treasury drain via ragequit

**Reported Severity:** High | **Confidence:** High
**File:** `Moloch.sol` — `openProposal`, `resolveFutarchyNo`, `cashOutFutarchy`, `_payout`, `ragequit`

**Description:** `openProposal` accepts any attacker-supplied `id` and unconditionally enables/funds futarchy when `autoFutarchyParam != 0`, without validating that `id` corresponds to a real executable intent. Combined with the Expired/Defeated resolution path and minted loot/shares reward tokens, an attacker can farm auto-funded pools on arbitrary IDs and convert payouts into real treasury assets via ragequit.

> **Review: Composite of multiple known findings — KF#3, KF#11, KF#19/KF#21, and auto-futarchy overcommit. No novel component.** This finding chains together:
> - **Arbitrary ID opening → auto-futarchy earmark:** This is the KF#19/KF#21 angle (raw IDs accepted without validation, permit/namespace overlap).
> - **NO-resolution farming:** This is the auto-futarchy overcommit / NO-coalition farming pattern found by 9+ audits and documented in KF#3: "a majority NO coalition can also collect auto-funded pools by repeatedly defeating proposals — this is by design (NO voters are rewarded for correct predictions)."
> - **Minted loot/shares → ragequit extraction:** This is KF#3 (ragequit drains futarchy pools — by design).
> - **`proposalThreshold == 0` enabling permissionless opening:** This is KF#11 (enforced by SafeSummoner).
>
> The chain is reasonable but each link is independently known. SafeSummoner enforces `proposalThreshold > 0` (KF#11), `autoFutarchyCap > 0` (KF#3), and non-zero quorum (KF#17), which collectively bound the extractable value per exploit to `autoFutarchyCap` and require the attacker to be a DAO member with shares above threshold. **Severity: Low (per configuration guidance + SafeSummoner mitigation + privileged-role rule).**

---

### #6 — Futarchy pool funds stuck when the winning side has zero supply

**Reported Severity:** Low | **Confidence:** High
**File:** `Moloch.sol` — `_finalizeFutarchy`, `cashOutFutarchy`, `fundFutarchy`

**Description:** When the winning side has zero receipt supply, `_finalizeFutarchy` sets `resolved = true` with `payoutPerUnit == 0`. All claims return 0 while pool funds remain held by the DAO with no futarchy-specific recovery path.

> **Review: Duplicate of KF#6.** SECURITY.md KF#6: "Zero-winner futarchy lockup — If no one votes for winning side, pool tokens are permanently inaccessible via `cashOutFutarchy`. Funds remain in DAO treasury." Previously identified by Pashov (#4). The funds are not lost — they remain in the DAO contract and can be recovered via a governance vote (treasury transfer proposal). The zero-supply edge case is uncommon in practice (requires a proposal to resolve with zero votes on the winning side). **Severity: Low (per KF#6).**

---

## Cross-Reference Summary

| # | Ackee Finding | Known Finding | Previously Found By |
|---|--------------|---------------|-------------------|
| 1 | Ragequit drains futarchy ETH pools | KF#3 (Design) + False Positive Pattern | Pashov, Octane, Grimoire, Almanax, Solarizer, +6 others |
| 2 | Sale cap 0-sentinel collision | KF#1 (Low) | Zellic, Pashov, SCV Scan, QuillShield, Grimoire, Archethect V2, +4 others |
| 3 | Auto-futarchy overcommit (shares/loot) | Auto-futarchy overcommit pattern | Octane, Pashov, Forefy, QuillShield, ChatGPT, ChatGPT Pro, Qwen, Archethect V2, Almanax |
| 4 | Pre-warmed timelock via post-queue voting | KF#15 (Design) | Claude, Grimoire, Solarizer, Archethect V2 |
| 5 | Arbitrary ID auto-futarchy + ragequit drain | KF#3 + KF#11 + KF#19/KF#21 composite | Multiple (all components previously known) |
| 6 | Zero-winner futarchy pool lockup | KF#6 (Low) | Pashov |

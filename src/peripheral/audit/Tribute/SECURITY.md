# Tribute.sol Security

> **Purpose:** Security audit prompt and tracking document for `Tribute.sol` — the OTC
> escrow peripheral for Moloch DAOs. Paste this document along with a copy of
> `src/peripheral/Tribute.sol` into your AI of choice.
>
> Prior audits: Cantina, Winfunc, Zellic, Pashov Skills, Grimoire (6 agents), ChatGPT 5.4.
> Reports in this directory and `audit/tribute-pashov-skills.md`, `audit/tribute-grimoire.md`, `audit/tribute-chatgpt.md`.

### Instructions

You are a senior Solidity security auditor. Analyze `Tribute.sol` (~340 lines, 1 contract + 3 free functions) — a standalone OTC escrow peripheral for Moloch DAOs. Work in **two rounds**:

**Round 1: Defense Verification.** For each defense mechanism in the table below, verify it works as described by tracing the actual code. Cite specific line numbers. State whether the defense holds or is broken. Then verify each of the 6 key invariants against the code. Produce a conclusion for every defense and every invariant — "Verified" or "Violated" with evidence.

**Round 2: Adversarial Hunt.** Attempt to find vulnerabilities NOT covered by the Known Findings table (T-1 through T-7) or the False Positive Patterns table. For each candidate:
1. Check it against the Known Findings table — if it matches, discard it as a duplicate.
2. Check it against the False Positive Patterns table — if it matches, discard it.
3. Attempt to disprove it by finding the guard, constraint, or code path that prevents exploitation.
4. Rate your confidence (0-100). Only include findings that survive all three checks.

**Report format:** For each finding: `[SEVERITY-N] Title`, severity, confidence, location (file:lines), description, attack path with concrete function calls, disproof attempt, recommendation. For Round 1: a table of defenses verified/violated and invariants verified/violated.

---

## Contract Overview

| Property | Value |
|----------|-------|
| **File** | `src/peripheral/Tribute.sol` |
| **Lines** | ~340 |
| **Role** | Standalone OTC escrow. Proposers lock ETH/ERC-20 tributes targeting a DAO. DAOs claim tributes atomically (swap). Proposers can cancel. |
| **State** | `tributes[proposer][dao][tribTkn] → TributeOffer`. Two append-only ref arrays for on-chain discovery (paginated view functions). |
| **Access** | No owner, no admin. `proposeTribute` = anyone. `cancelTribute` = proposer only (keyed by `msg.sender`). `claimTribute` = DAO only (keyed by `msg.sender`). |
| **Dependencies** | ERC20 tokens (via Solady-style safeTransferFrom/safeTransfer), ETH transfers |
| **Integration target** | Moloch DAO contracts which have `receive() external payable {}` and execute proposals via `to.call{value}(data)` |

---

## Audit History

| # | Date | Tool / Auditor | Mode | Findings | Report |
|---|------|----------------|------|----------|--------|
| 1 | 2026-03-12 | Cantina Apex | Multi-agent review | 2 (1 Medium, 1 Low-Medium) | [`cantina-20260312.md`](cantina-20260312.md) |
| 2 | 2026-03-15 | Winfunc | Multi-phase deep validation | 3 (1 Medium, 2 Medium) | [`winfunc-20260315.md`](winfunc-20260315.md) |
| 3 | 2026-03-15 | Zellic V12 | Autonomous scan | 2 (1 High → Dup, 1 Low → novel) | [`zellic-20260315.md`](zellic-20260315.md) |
| 4 | 2026-03-16 | Pashov Skills v1 | 4-agent parallel vector scan | 2 (85, 80) — both known | [`../../audit/tribute-pashov-skills.md`](../../audit/tribute-pashov-skills.md) |
| 5 | 2026-03-16 | Grimoire | 4 Sigils + 2 Familiars | 0 novel (4 Info, all known) | [`../../audit/tribute-grimoire.md`](../../audit/tribute-grimoire.md) |
| 6 | 2026-03-16 | ChatGPT (GPT 5.4) | 2 runs (pre/post instructions) | Run 1: 0 novel (1 FP, 3 dup). Run 2: 1 novel (T-7) | [`../../audit/tribute-chatgpt.md`](../../audit/tribute-chatgpt.md) |
| 7 | 2026-03-16 | Claude (Opus 4.6) | 2-round (defense verification + adversarial hunt) | 0 novel, 7/7 defenses verified, 6/6 invariants verified | [`claude-20260316.md`](claude-20260316.md) |

**Aggregate: 7 audits, 7 unique findings (all addressed). 0 Critical, 0 High, 0 Medium (after patches), 1 Low, 6 Informational.**

**Deployment:** Tribute.sol redeployed with all patches to [`0x00000000068d348f971845d60236dAe210ea80A6`](https://contractscan.xyz/contract/0x00000000068d348f971845d60236dAe210ea80A6). Previous deployment at `0x000000000066524fcf78Dc1E41E9D525d9ea73D0` is deprecated.

---

## Known Findings

| # | Finding | Severity | Status | First Found | Also Confirmed By |
|---|---------|----------|--------|-------------|-------------------|
| T-1 | Fee-on-transfer token permanently locks tribute funds | Info | Documented — unsupported token type | Zellic #1 | Pashov Skills #1, Grimoire Sigil 2 |
| T-2 | ETH push to proposer DoS via reverting receive | Info | N/A to Moloch integration | Pashov Skills #2 | Grimoire Sigil 3, ChatGPT LOW-3 |
| T-3 | Rebasing token downward rebase locks funds | Info | Same root cause as T-1 | Pashov Skills #2 (80) | — |
| T-4 | Unbounded ref array growth | Info | Mitigated — pagination with OOB + limit=0 guard | Winfunc #21/23 | Zellic #3, Grimoire Sigil 3, ChatGPT INFO-4 |
| T-5 | CEI violation in proposeTribute (interaction before effects) | Info | **Fixed** — `safeTransferFrom` moved after all state writes | Grimoire Sigil 1 | — |
| T-6 | `limit=0` pagination returns ambiguous `next=0` | Info | **Fixed** — early return on `limit == 0` | Grimoire Sigil 3 | — |
| T-7 | Stale ref resurrection on key reuse — cancel/repost same key causes duplicate entries in paginated views | Low | Accepted — view-only, no fund risk | ChatGPT 5.4 (Run 2) | — |

### Legacy Findings (pre-patch, now resolved)

| # | Finding | Severity | Status | First Found |
|---|---------|----------|--------|-------------|
| L-1 | Bait-and-switch: proposer cancel+repost with worse terms | Medium | **Patched** — `claimTribute` now verifies `(tribAmt, forTkn, forAmt)` via `TermsMismatch` | Cantina MAJEUR-10 |
| L-2 | Counterfactual escrow theft via summon frontrun | Low-Medium | Accepted (impractical) | Cantina MAJEUR-17 |
| L-3 | Fake ERC20 funding — `proposeTribute` doesn't verify token receipt | Medium | Accepted (social engineering, not smart contract bug) | Winfunc #14 |

---

## Hardening Patches

| Patch | Finding | Description |
|-------|---------|-------------|
| Bait-and-switch prevention | L-1 | `claimTribute` requires `(tribAmt, forTkn, forAmt)` as explicit params, verified against stored values, reverts `TermsMismatch` |
| CEI fix in `proposeTribute` | T-5 | `safeTransferFrom` moved after all state writes (offer fields + ref array pushes) |
| Pagination limit=0 guard | T-6 | Early return on `start >= len \|\| limit == 0` in both view functions |
| Pagination OOB guard | T-4 | Early return on `start >= len` prevents infinite loop |

---

## Defense Mechanisms

| Defense | Mechanism | What It Prevents |
|---------|-----------|-----------------|
| **EIP-1153 reentrancy guard** | Transient storage `TSTORE`/`TLOAD` in `nonReentrant` on all 3 mutating functions | All reentrancy (same-function, cross-function, ERC777 hooks) |
| **CEI ordering** | `proposeTribute` writes all state before `safeTransferFrom`. `cancelTribute`/`claimTribute` delete mapping before external calls | Reentrancy even without the guard |
| **Bait-and-switch prevention** | `claimTribute` requires `(tribAmt, forTkn, forAmt)` as explicit params, verified against stored values, reverts `TermsMismatch` | Proposer cancel + re-propose with worse terms between DAO approval and execution |
| **Overwrite guard** | `if (offer.tribAmt != 0) revert` in `proposeTribute` | Double-locking same `(proposer, dao, tribTkn)` key |
| **ETH/ERC20 mutual exclusion** | `msg.value != 0` branch requires `tribTkn == address(0)` and `tribAmt == 0`; else branch requires `tribTkn != address(0)` and `tribAmt != 0` | Mixed ETH+ERC20 in single offer, msg.value double-counting |
| **Pagination bounds** | `start >= len \|\| limit == 0` early return in view functions | Infinite loop on out-of-bounds start, ambiguous next=0 on limit=0 |
| **Solady safe transfers** | Assembly `safeTransfer`/`safeTransferFrom` with extcodesize + returndatasize checks | USDT missing-return, EOA token address, non-contract calls |

---

## Key Invariants

1. Sum of all active `offer.tribAmt` for ETH tributes (`tribTkn == address(0)`) ≤ `address(this).balance`
2. For each active offer: `offer.tribAmt > 0` and `offer.forAmt > 0`
3. Mapping key `(proposer, dao, tribTkn)` is unique — no two active offers share a key
4. Only the proposer (`msg.sender` at proposal time) can cancel; only the target DAO (`msg.sender` at claim time) can claim
5. `claimTribute` is atomic — both legs complete or neither does (EVM revert atomicity)
6. Ref arrays are monotonically non-decreasing in length (append-only)

---

## Critical Code Paths (Priority Order)

1. **`claimTribute`** — Atomic OTC swap. Deletes offer, pays proposer (ETH or ERC20 pull), sends tribute to DAO. Two external calls after state deletion.
2. **`proposeTribute`** — Deposit + state write. ETH via msg.value or ERC20 via safeTransferFrom (after state writes).
3. **`cancelTribute`** — Refund. Deletes offer, returns tribute to proposer.
4. **`getActiveDaoTributes` / `getActiveProposerTributes`** — Paginated views. Iterate ref arrays, filter by `tribAmt != 0`.

---

## Design Constraints (Intentional — Do Not Flag)

- **Fee-on-transfer / rebasing tokens unsupported.** Recorded `tribAmt` must equal actual balance held. NatSpec documents this. Consistent with Moloch.sol's transfer patterns and Uniswap V2/V3.
- **ETH push to proposer.** `claimTribute` pushes ETH directly. If proposer is a contract with reverting receive, DAO cannot claim that offer. N/A to Moloch DAOs (all have `receive() external payable {}`). Proposer chose their own address.
- **Ref arrays are append-only.** Stale entries from cancelled/claimed offers are never removed. Mitigated by pagination. No on-chain state-changing function iterates these arrays.
- **No sweep function.** Force-sent ETH (selfdestruct) is permanently stranded. Contract never uses `address(this).balance` for accounting — all amounts from mappings.

---

## False Positive Patterns (Do NOT Flag These)

| Pattern | Why It's Not a Bug |
|---------|-------------------|
| "safeTransfer corrupts the free memory pointer" | Solady pattern: `mstore(0x34, 0)` only zeros high bytes of FMP word (0x40–0x53). Actual FMP value lives in bytes 0x54–0x5F, untouched. Verified byte-by-byte. |
| "ETH locked when DAO can't receive" | EVM reverts are atomic. If `safeTransferETH(dao, ...)` reverts, `delete tributes[...]` is also reverted. No funds locked. |
| "safeTransferFrom uses caller() instead of a from parameter" | Intentional Solady convention. `from = caller()` is always `msg.sender` of the outer call. All call sites verified correct. |
| "Proposer can lock their own ETH by bricking receive()" | Self-inflicted. No third party can trigger this. Proposer chose their own address. |
| "Ref arrays can be spammed" | Spam requires gas + real token deposits per offer. Pagination mitigates view DoS. Core functions are O(1). |
| "No expiry / deadline on tributes" | By design. Proposer can cancel anytime. DAO claims via governance vote. |

---

## Assembly Verification

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

## Expanding Coverage

To add new audit results:
1. Save the report as `{tool}-{date}.md` in this directory
2. Update the **Audit History** table above
3. Deduplicate new findings into **Known Findings**
4. Update finding statuses as fixes are applied

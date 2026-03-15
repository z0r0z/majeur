# Moloch.sol — Nemesis Audit (2026-03-15)

> Iterative deep-logic audit via [Nemesis](https://github.com/0xiehnnkta/nemesis-auditor) on commit `7a39232`.
> Methodology: Feynman Auditor (Pass 1) + State Inconsistency Auditor (Pass 2) in parallel, consolidated with cross-feed analysis.

---

## Methodology

Nemesis runs two complementary agents in an iterative back-and-forth loop:

1. **Pass 1 — Feynman Auditor** (full run): Questions every line, every ordering choice, every guard presence/absence. Exposes implicit assumptions and flags suspects.
2. **Pass 2 — State Inconsistency Auditor** (full run): Maps every coupled state pair, every mutation path, and every gap where one side updates without the other.
3. **Consolidation**: Cross-feed analysis — findings from each pass evaluated against the other's output. Duplicates merged, false positives eliminated.

**Scope:** All 5 contracts in `src/Moloch.sol` — Moloch (L1–1050), Shares (L1052–1604), Loot (L1606–1700), Badges (L1702–1942), Summoner (L2054–2110), plus free functions (L1960–2052).

---

## Coupled State Dependency Map

Key invariants verified by the State Inconsistency pass:

| State Var A | State Var B | Invariant | Verified |
|---|---|---|---|
| `balanceOf[owner][id]` | `totalSupply[id]` (ERC-6909) | sum(balanceOf) == totalSupply | Yes |
| `tallies[id].*Votes` | `hasVoted[id][v]` + `voteWeight[id][v]` + receipt `balanceOf` | tally == sum(weights for all hasVoted != 0); receipt supply == tally per side | Yes |
| `Shares.balanceOf[a]` | `_checkpoints[delegates(a)]` | checkpoint votes reflect delegated balances | Yes |
| `Shares.totalSupply` | `_totalSupplyCheckpoints` | latest checkpoint == totalSupply | Yes |
| `_delegates[a]` + `_splits[a]` | `_checkpoints[each delegate]` | delegation change moves votes correctly | Yes |
| `futarchy[id].pool` | `futarchy[id].finalWinningSupply` + `totalSupply[rid]` | supply frozen before resolution snapshot | Yes |
| Badges: `occupied` bitmap | `seats[]` + `seatOf` + `_ownerOf` + `balanceOf` + `minSlot/minBal` | bitmap, seats, and ERC-721 state consistent across all paths | Yes |

**All coupled state invariants hold.** No state desync bugs found across any mutation path.

---

## Mutation Path Symmetry Verification

| Operation Pair | Symmetric? | Notes |
|---|---|---|
| `castVote` ↔ `cancelVote` | Yes | Both atomically update tallies, hasVoted, voteWeight, and receipts |
| `_mint6909` ↔ `_burn6909` | Yes | Checked/unchecked blocks correctly ordered relative to invariant |
| `Shares.mintFromMoloch` ↔ `Shares.burnFromMoloch` | Yes | Both call `_writeTotalSupplyCheckpoint()` + `_afterVotingBalanceChange()` |
| `Shares.transfer` ↔ `Shares.transferFrom` | Yes | Both route through `_moveTokens`; transferFrom adds allowance check |
| `ERC-6909 transfer` ↔ `ERC-6909 transferFrom` | Yes | Identical state updates, differ only in auth |
| `executeByVotes` ↔ `spendPermit` | Yes* | Both set `executed[id]`, call `_resolveFutarchyYes`. *See Finding NEM-01 |
| Ragequit: pre-burn total capture | Correct | Standard Moloch pattern: `total` captured before burn, pro-rata uses pre-burn denominator |

---

## Findings

### NEM-01 — `spendPermit` Does Not Guard Against Already-Executed Intent Hashes

- **Severity:** Medium
- **Validity:** Valid (Duplicate of KF#16 / KF#8 extension)
- **Discovery path:** Feynman-only (Pass 1)

#### Description

`executeByVotes` (L502) checks `if (executed[id]) revert AlreadyExecuted()` before executing. `spendPermit` (L668) sets `executed[tokenId] = true` but never checks it beforehand. Since both use `_intentHashId` to compute the token ID, a permit and proposal for the same `(op, to, value, data, nonce)` share the same ID. If a proposal is executed via votes, a permit holder could call `spendPermit` to execute the same action again — the `executed` check is missing.

#### Assessment

**Duplicate of KF#16 (Claude Opus 4.6) and KF#8 extension (Cantina MAJEUR-21).** Both `setPermit` and proposal creation are `onlyDAO` — the DAO would have to create both paths for the same intent hash, which is a governance-level configuration error. No external attacker can produce this collision without DAO governance approval. The shared ID namespace is a known design tension documented in KF#8 and KF#16.

**No fix needed — duplicate.**

---

### NEM-02 — Vote Receipt Tokens Are Freely Transferable, Permanently Locking Votes

- **Severity:** Low
- **Validity:** Valid (Duplicate of KF#1)
- **Discovery path:** Feynman-only (Pass 1)

#### Description

Vote receipt IDs from `_receiptId()` are not marked in `isPermitReceipt`, so they pass the SBT check in `transfer`/`transferFrom` (L916/L929). Once a voter transfers receipt tokens, `cancelVote` reverts at `_burn6909` (L405) due to insufficient balance. The voter's tally contribution becomes permanently locked.

#### Assessment

**Duplicate of KF#1 (Pashov — Low, design tradeoff).** Receipt transferability is intentional for the futarchy prediction market use case. Voters who transfer receipts forfeit cancel rights by design. The `hasVoted` check (L363) prevents re-voting.

**No fix needed — by design.**

---

### NEM-03 — Governance Parameter Mutability Affects In-Flight Proposals

- **Severity:** Low
- **Validity:** Valid (Duplicate of KF#15 variant)
- **Discovery path:** Feynman-only (Pass 1)

#### Description

`state()` reads current governance parameters (`timelockDelay`, `proposalTTL`, `quorumBps`, `quorumAbsolute`, `minYesVotesAbsolute`) rather than snapshotted values. A second proposal that modifies these parameters can retroactively affect in-flight proposals — e.g., removing the timelock delay for a queued proposal.

#### Assessment

**Duplicate of KF#15 (post-queue voting is intentional design).** This is standard governance behavior (OpenZeppelin Governor also uses current parameters). Changing parameters requires passing DAO governance, which itself goes through the same process. The `bumpConfig()` emergency brake exists for invalidating all pending proposals. The timelock-as-last-objection-window design is explicitly documented.

**No fix needed — by design.**

---

### NEM-04 — Auto-Futarchy Earmark Accumulates Without Global Cap for Minted Reward Types

- **Severity:** Low
- **Validity:** Valid (Duplicate of KF#3)
- **Discovery path:** Feynman-only (Pass 1), confirmed by State pass

#### Description

When `rewardToken` is `address(this)` (mint shares) or `address(1007)` (mint loot), `openProposal` earmarks `F.pool += amt` (L336) without checking total outstanding obligations across all active proposals. The per-proposal `autoFutarchyCap` limits individual proposals but not aggregate exposure. Additionally, `_payout` (L992-995) mints from thin air for these token types, and each minting increases `lootTotalSupply` which increases the basis for subsequent earmarks (L322), creating a feedback loop.

#### Assessment

**Duplicate of KF#3.** SafeSummoner enforces `autoFutarchyCap > 0` when futarchy is enabled. The configuration guidance in README explicitly warns about minted futarchy rewards and recommends non-minted reward tokens (ETH, held shares/loot) which have natural balance caps.

**No fix needed — mitigated by SafeSummoner + configuration guidance.**

---

### NEM-05 — Non-Minting Sale Seats DAO Contract Address in Badge System

- **Severity:** Informational
- **Validity:** Valid (novel observation, not exploitable)
- **Discovery path:** Feynman-only (Pass 1)

#### Description

When `buyShares` uses non-minting mode (`s.minting = false`, L750-752), `shares.transfer(msg.sender, shareAmount)` is called with the Moloch contract as `from`. `_moveTokens` triggers `_afterVotingBalanceChange(DAO, ...)` which calls `onSharesChanged(DAO)`. This can seat the DAO contract address in the badge system, consuming one of the 256 available slots.

#### Assessment

**Novel observation, informational severity.** The DAO contract address occupying a badge seat is cosmetically wasteful but not exploitable — the seat is "sticky" and the DAO address holds real shares. The DAO can manually `burnSeat` for its own address, or use `minting = true` for sales. The badge is meaningless for the DAO contract (cannot use chat). SafeSummoner defaults to `minting = true`. No security impact.

**No fix needed — cosmetic, governance-recoverable.**

---

### NEM-06 — `openProposal` Accepts Arbitrary IDs Without Validation

- **Severity:** Low
- **Validity:** Valid (Duplicate of KF#11 variant)
- **Discovery path:** Feynman-only (Pass 1)

#### Description

`openProposal` (L278) takes a `uint256 id` with no validation that it corresponds to a real `_intentHashId`. Any caller meeting `proposalThreshold` can call `openProposal(arbitrary_id)`, appending garbage entries to `proposalIds` (L299) and triggering auto-futarchy earmarking.

#### Assessment

**Duplicate of KF#11 (front-run cancel, proposal spam).** SafeSummoner enforces `proposalThreshold > 0` which gates proposal creation behind real stake. The fake proposals can never be executed (no matching intent hash). The `proposalIds` array pollution affects off-chain tooling but not on-chain security. Auto-futarchy earmarking for minting reward types is bounded by `autoFutarchyCap`.

**No fix needed — mitigated by SafeSummoner.**

---

## State Inconsistency Verification Summary

The State Inconsistency Auditor performed 8 verification phases:

| Phase | Result |
|---|---|
| 1. Map coupled state pairs | 7 pair groups identified across 5 contracts |
| 2. Find all mutation paths | Complete mutation matrix built |
| 3. Cross-check mutations | All mutations update coupled state correctly |
| 4. Operation ordering | No stale reads or ordering bugs within functions |
| 5. Parallel path comparison | All parallel paths symmetric |
| 6. Multi-step user journeys | Vote→transfer→cancel, delegation→transfer→clear all traced clean |
| 7. Masking code analysis | Unchecked blocks in `_mint6909`/`_burn6909` are safe (ordering relative to checked counterparts) |
| 8. Verification gate | All findings code-trace verified |

**Key verifications:**
- `_writeCheckpoint` deduplication (L1540: `if (last.votes == newVal) return`) is safe — same-block overwrite takes priority
- Ragequit pre-burn total capture (L772) is the correct Moloch pattern
- Futarchy resolution receipt supply freeze confirmed — `castVote` blocked by `F.resolved` check (L366-367), `cancelVote` blocked by state check (L396)
- Badges eviction path (L1876-1891) correctly sequences burnSeat/mintSeat and bitmap updates

---

## Summary

| ID | Finding | Severity | Status | KF# |
|---|---|---|---|---|
| NEM-01 | `spendPermit` missing `executed` guard | Medium | Duplicate | KF#16/KF#8 |
| NEM-02 | Transferable vote receipts lock votes | Low | Duplicate | KF#1 |
| NEM-03 | Governance param mutability on in-flight proposals | Low | Duplicate | KF#15 |
| NEM-04 | Uncapped minted auto-futarchy earmarks | Low | Duplicate | KF#3 |
| NEM-05 | Non-minting sale seats DAO in badges | Info | Novel (cosmetic) | — |
| NEM-06 | `openProposal` arbitrary ID pollution | Low | Duplicate | KF#11 |

**0 Critical. 0 High. 1 Medium (duplicate). 4 Low (all duplicates). 1 Informational (novel, cosmetic).**

**State inconsistency analysis: 0 findings.** All coupled state invariants verified across all mutation paths. The codebase demonstrates careful invariant maintenance — unchecked blocks are correctly ordered, parallel code paths are symmetric, and cross-contract state (Moloch ↔ Shares ↔ Badges) is consistently synchronized.

**Novel finding: NEM-05** (DAO address badge seat in non-minting sales) is cosmetically interesting but informational — no security impact, governance-recoverable, and SafeSummoner defaults avoid the pattern.

**Convergence:** Pass 2 (State) produced no new suspects or gaps to feed back to Feynman. The loop converged in 2 passes. No further iterations needed.

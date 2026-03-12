# Formal Verification Report: Majeur DAO Framework

- Date: March 12th, 2026
- Audit Repo: https://github.com/z0r0z/majeur
- Audit Commit: `a68e2fe9b1049643716d258ca8357001f9a79066`
- Author: Specialist AI created by [@DevDacian](https://x.com/DevDacian) ([@cyfrin](https://x.com/cyfrin))
- Certora Prover version: 8.8.1

---

## Table of Contents

- [About Majeur](#about-majeur)
- [Formal Verification Methodology](#formal-verification-methodology)
- [Project Structure](#project-structure)
- [Verification Properties](#verification-properties)
  - [SafeSummoner (9 properties)](#safesummoner-9-properties)
  - [Tribute (11 properties)](#tribute-11-properties)
  - [Loot (14 properties)](#loot-14-properties)
  - [Badges (16 properties)](#badges-16-properties)
  - [Shares (20 properties)](#shares-20-properties)
  - [DAICO (19 properties)](#daico-19-properties)
  - [Moloch (53 properties)](#moloch-53-properties)
- [Assumptions](#assumptions)
- [Setup and Execution](#setup-and-execution)
- [Resources](#resources)

---

## About Majeur

Majeur is a DAO framework built on the Moloch governance pattern. The core `Moloch` contract manages ERC-6909 receipt tokens, proposals (with voting, futarchy, and ragequit), share sales, and treasury allowances. It is supported by `Shares` (ERC-20 with primary and split delegation checkpoints), `Loot` (non-voting ERC-20 for economic claims), and `Badges` (ERC-721 soulbound tokens for seat-based council membership).

Peripheral contracts include `DAICO` (decentralized autonomous ICO with configurable sales, tap mechanisms, and LP integration), `Tribute` (escrow for tribute offers between proposers and DAOs), and `SafeSummoner` (deployment validation ensuring Safe-based DAO summoning parameters are valid). All governance parameter changes are gated by `onlyDAO` (`msg.sender == address(this)`), meaning the DAO governs itself with no external admin keys.

---

## Formal Verification Methodology

Certora Formal Verification (FV) provides mathematical proofs of smart contract correctness by verifying code against a formal specification. Unlike testing and fuzzing which examine specific execution paths, Certora FV examines all possible states and execution paths.

The process involves crafting properties in CVL (Certora Verification Language) and submitting them alongside compiled Solidity smart contracts to a remote prover. The prover transforms the contract bytecode and rules into a mathematical model and determines the validity of rules.

### Types of Properties

**Invariants** — System-wide properties that MUST always hold true. These are parametric — automatically verified against every external function in the contract. Once proven, invariants serve as trusted assumptions via `requireInvariant`.

**Parametric Rules** — Rules verified against every non-view external function using `method f` with `calldataarg args`. Used for properties like "only mint can increase totalSupply" or "counter values never decrease."

**Access Control Rules** — Rules verifying that state-changing functions revert when the caller lacks the required role. Uses the `@withrevert` pattern: call the function, then `assert !lastReverted => hasRole(...)`.

**Revert Condition Rules** — Rules verifying that functions revert under specific invalid conditions (zero inputs, paused state, missing allowlist, etc.). Uses `@withrevert` followed by `assert lastReverted`.

**Integrity Rules** — Rules verifying that successful function calls produce the correct state changes (e.g., transfer moves exact amounts, deposit records match inputs, preview functions match actual operations, round-trip conversions never inflate value).

**Sanity (Satisfy) Rules** — Lightweight reachability checks ensuring functions are not vacuously verified. Uses `satisfy true` to confirm at least one non-reverting execution path exists.

### Key modeling decisions

- **Harness-based verification**: Each contract was verified through a simplified harness that preserves all validation and state-transition logic while stripping external dependencies (token transfers, LP initialization, CREATE2 prediction). This isolates the contract's own invariants from external call havoc
- **Ghost sum variables with hooks**: `Shares`, `Loot`, and `Moloch` (ERC-6909) use ghost `mathint` variables with `Sstore` hooks to track the sum of all balances. `Shares` and `Moloch` additionally use `Sload` hooks on `balanceOf` to constrain individual balances to be bounded by the ghost sum, eliminating false counterexamples from the prover's arbitrary state exploration in the presence of `unchecked` arithmetic
- **Inductive parametric rules for split delegation**: Invariants 60-63 (`Shares` split delegation properties) are expressed as parametric rules with explicit inductive hypotheses rather than CVL `invariant` declarations, since they require bounded quantification over dynamic arrays
- **Write-once property coupling**: `Moloch` write-once properties (invariants 5-8) require coupling constraints between related fields that are always set together in `openProposal` (e.g., `supplySnapshot` is only set when `snapshotBlock` is already set)
- **Partial claim modeling for L-01**: The `DAICOHarness` includes a `daoTapBalance` mapping that models the `min(owed, allowance, daoBalance)` constraint from the real contract. The harness intentionally reproduces the L-01 bug where `lastClaim` advances by full elapsed time even on partial claims
- **External call summarization**: All external token transfers (`transfer`, `transferFrom`), Moloch callbacks (`onSharesChanged`, `getPastVotes`), and Summoner calls are summarized as `NONDET` to focus verification on the contract's own state transitions
- **Futarchy harness simplification**: The `MolochHarness` includes a simplified futarchy module that strips token validation/pull logic and the full `state()` function, preserving core state transitions (`fundFutarchy`, `resolveFutarchyNo`, `cashOutFutarchy`, `_finalizeFutarchy`) and their revert conditions. The `_receiptId` function replaces `keccak256(abi.encodePacked(...))` with a deterministic injective function (`id * 3 + support`) that the prover can reason about
- **mulDiv bound lemma**: A standalone integrity rule proves `mulDiv(pool, amt, total) <= pool` when `amt <= total`, with `max_uint128` bounds on `pool` and `amt` to prevent overflow. This lemma underpins ragequit and futarchy payout safety
- **Target allocation sum harness**: The `SharesHarness` includes a `targetAllocSum` function that mirrors `_targetAlloc`'s allocation logic (proportional BPS division with remainder-to-last) as an external view, enabling CVL to verify that allocations sum exactly to the input balance

---

## Project Structure

```
certora/
├── conf/
│   ├── Badges.conf
│   ├── DAICO.conf
│   ├── Loot.conf
│   ├── Moloch.conf
│   ├── SafeSummoner.conf
│   ├── Shares.conf
│   └── Tribute.conf
├── harnesses/
│   ├── BadgesHarness.sol       # Struct-in-mapping getters for seats, bitmap, min tracking
│   ├── DAICOHarness.sol        # Simplified sale/buy/tap logic + daoTapBalance for L-01
│   ├── LootHarness.sol         # ERC-20 with transfersLocked, DAO-gated mint/burn
│   ├── MolochHarness.sol       # ERC-6909, proposals, voting, settings, sale, allowance, futarchy, ragequit
│   └── SharesHarness.sol       # ERC-20 + delegation checkpoints, split delegation getters, targetAlloc
├── specs/
│   ├── Badges.spec             # 16 properties: bidirectional mapping, soulbound, seats
│   ├── DAICO.spec              # 19 properties: sale, buy, tap, LP config, L-01 finding
│   ├── Loot.spec               # 14 properties: ERC-20 accounting, transfer lock, DAO auth
│   ├── Moloch.spec             # 53 properties: ERC-6909, proposals, voting, settings, sale, allowance, futarchy, ragequit, execution
│   ├── SafeSummoner.spec       #  9 properties: deployment validation revert conditions
│   ├── Shares.spec             # 20 properties: ERC-20, delegation, checkpoints, targetAlloc, DAO auth
│   └── Tribute.spec            # 11 properties: escrow integrity, monotonicity, isolation
└── invariants.md               # 126 protocol invariants (source of truth)
```

---

## Verification Properties

142 properties across 7 contracts: 8 Invariants, 35 Parametric rules, 9 Access Control rules, 49 Revert Condition rules, 18 Integrity rules, 23 Sanity rules.

### `SafeSummoner` (9 properties)

Deployment validation: all 8 revert conditions for invalid `safeSummon` parameters (invariants 119-126) plus reachability.

| ID&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; | Name | Type | Description | Status |
|:------|:----------------------------------------|:----------|:-------------------------------------------------------|:------:|
| [SS-119](./specs/SafeSummoner.spec#L32-L56) | `quorumBpsOutOfRange` | Revert Condition | `safeSummon` reverts if `quorumBps > 10000` | ✓ |
| [SS-120](./specs/SafeSummoner.spec#L62-L83) | `proposalThresholdRequired` | Revert Condition | `safeSummon` reverts if `proposalThreshold == 0` | ✓ |
| [SS-121](./specs/SafeSummoner.spec#L89-L111) | `proposalTTLRequired` | Revert Condition | `safeSummon` reverts if `proposalTTL == 0` | ✓ |
| [SS-122](./specs/SafeSummoner.spec#L117-L137) | `noInitialHolders` | Revert Condition | `safeSummon` reverts if `initHolders` is empty | ✓ |
| [SS-123](./specs/SafeSummoner.spec#L143-L168) | `timelockExceedsTTL` | Revert Condition | `safeSummon` reverts if `timelockDelay > 0` and `proposalTTL <= timelockDelay` | ✓ |
| [SS-124](./specs/SafeSummoner.spec#L175-L200) | `quorumRequiredForFutarchy` | Revert Condition | `safeSummon` reverts if futarchy enabled with no quorum | ✓ |
| [SS-125](./specs/SafeSummoner.spec#L207-L239) | `mintingSaleWithDynamicQuorum` | Revert Condition | `safeSummon` reverts for minting sale with dynamic-only quorum | ✓ |
| [SS-126](./specs/SafeSummoner.spec#L245-L270) | `salePriceRequired` | Revert Condition | `safeSummon` reverts if sale active but `salePricePerShare == 0` | ✓ |
| [SS-SAN1](./specs/SafeSummoner.spec#L276-L293) | `safeSummonSanity` | Sanity | `safeSummon` is reachable with valid config | ✓ |

### `Tribute` (11 properties)

Escrow integrity: offer lifecycle (propose, cancel, claim), isolation between proposers/DAOs, and discovery array monotonicity (invariants 97-105).

| ID&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; | Name | Type | Description | Status |
|:------|:----------------------------------------|:----------|:-------------------------------------------------------|:------:|
| [T-97](./specs/Tribute.spec#L47-L57) | `proposeTributeRevertsOnExistingOffer` | Revert Condition | `proposeTribute` reverts if an offer already exists for the key | ✓ |
| [T-98](./specs/Tribute.spec#L63-L74) | `cancelTributeDeletesEntry` | Integrity | After `cancelTribute`, the tribute entry is fully zeroed | ✓ |
| [T-99](./specs/Tribute.spec#L80-L90) | `claimTributeDeletesEntry` | Integrity | After `claimTribute`, the tribute entry is fully zeroed | ✓ |
| [T-100](./specs/Tribute.spec#L96-L105) | `cancelTributeRevertsIfNoOffer` | Revert Condition | `cancelTribute` reverts when no offer exists | ✓ |
| [T-101](./specs/Tribute.spec#L111-L120) | `claimTributeRevertsIfNoOffer` | Revert Condition | `claimTribute` reverts when no offer exists | ✓ |
| [T-102](./specs/Tribute.spec#L131-L145) | `cancelDoesNotAffectOtherProposer` | Access Control | `cancelTribute` does not modify another proposer's offer | ✓ |
| [T-103](./specs/Tribute.spec#L154-L167) | `claimDoesNotAffectOtherDao` | Access Control | `claimTribute` does not modify tributes directed at other DAOs | ✓ |
| [T-104](./specs/Tribute.spec#L174-L183) | `daoTributeRefsMonotonic` | Parametric | `daoTributeRefs` length never decreases | ✓ |
| [T-105](./specs/Tribute.spec#L190-L199) | `proposerTributeRefsMonotonic` | Parametric | `proposerTributeRefs` length never decreases | ✓ |
| [T-SAN1](./specs/Tribute.spec#L205-L210) | `proposeTributeSanity` | Sanity | `proposeTribute` is reachable | ✓ |
| [T-SAN2](./specs/Tribute.spec#L212-L216) | `cancelTributeSanity` | Sanity | `cancelTribute` is reachable | ✓ |

### `Loot` (14 properties)

ERC-20 accounting: sum-of-balances invariant via ghost + hook, transfer lock enforcement, DAO-gated mint/burn authorization, and transfer integrity (invariants 74-79).

| ID&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; | Name | Type | Description | Status |
|:------|:----------------------------------------|:----------|:-------------------------------------------------------|:------:|
| [L-74](./specs/Loot.spec#L41-L62) | `totalSupplyIsSumOfBalances` | Invariant | `totalSupply` equals the sum of all `balanceOf` values | ✓ |
| [L-75a](./specs/Loot.spec#L69-L82) | `transferRevertsWhenLocked` | Revert Condition | `transfer` reverts when locked and neither party is DAO | ✓ |
| [L-75b](./specs/Loot.spec#L84-L96) | `transferFromRevertsWhenLocked` | Revert Condition | `transferFrom` reverts when locked and neither party is DAO | ✓ |
| [L-76](./specs/Loot.spec#L103-L114) | `onlyMintBurnChangeTotalSupply` | Parametric | Only `mintFromMoloch` and `burnFromMoloch` change `totalSupply` | ✓ |
| [L-77](./specs/Loot.spec#L121-L130) | `daoWriteOnce` | Parametric | `DAO` address cannot change once set to non-zero | ✓ |
| [L-78](./specs/Loot.spec#L136-L144) | `initRevertsIfDaoSet` | Revert Condition | `init` reverts when `DAO` is already set | ✓ |
| [L-79a](./specs/Loot.spec#L152-L159) | `mintRequiresDAO` | Access Control | Only `DAO` can call `mintFromMoloch` | ✓ |
| [L-79b](./specs/Loot.spec#L161-L168) | `burnRequiresDAO` | Access Control | Only `DAO` can call `burnFromMoloch` | ✓ |
| [L-S1](./specs/Loot.spec#L175-L194) | `transferIntegrity` | Integrity | `transfer` moves exact amounts between sender and receiver | ✓ |
| [L-S2](./specs/Loot.spec#L196-L206) | `transferSelfIntegrity` | Integrity | Self-transfer preserves balance | ✓ |
| [L-SAN1](./specs/Loot.spec#L212-L216) | `transferSanity` | Sanity | `transfer` is reachable | ✓ |
| [L-SAN2](./specs/Loot.spec#L218-L221) | `mintSanity` | Sanity | `mintFromMoloch` is reachable | ✓ |
| [L-SAN3](./specs/Loot.spec#L223-L226) | `burnSanity` | Sanity | `burnFromMoloch` is reachable | ✓ |
| [L-SAN4](./specs/Loot.spec#L228-L231) | `initSanity` | Sanity | `init` is reachable | ✓ |

### `Badges` (16 properties)

ERC-721 soulbound: bidirectional mapping consistency (`seatOf` ↔ `_ownerOf`) via 5 coupled invariants, soulbound transfer revert, seat management validation, and DAO authorization (invariants 80-92).

| ID&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; | Name | Type | Description | Status |
|:------|:----------------------------------------|:----------|:-------------------------------------------------------|:------:|
| [B-80](./specs/Badges.spec#L37-L41) | `transferFromAlwaysReverts` | Revert Condition | `transferFrom` always reverts (soulbound enforcement) | ✓ |
| [B-81](./specs/Badges.spec#L47-L48) | `balanceZeroOrOne` | Invariant | `balanceOf` is always 0 or 1 | ✓ |
| [B-82](./specs/Badges.spec#L54-L60) | `seatOfInRange` | Invariant | If `balanceOf == 1` then `seatOf` is in `[1, 256]` | ✓ |
| [B-83](./specs/Badges.spec#L67-L86) | `biMapForward` | Invariant | Forward mapping: `seatOf[a] != 0` implies `_ownerOf[seatOf[a]] == a` | ✓ |
| [B-S1](./specs/Badges.spec#L93-L99) | `seatImpliesBalance` | Invariant | `seatOf[a] != 0` implies `balanceOf[a] != 0` | ✓ |
| [B-84](./specs/Badges.spec#L107-L166) | `biMapReverse` | Invariant | Reverse mapping: `_ownerOf[s] != 0` implies `seatOf[_ownerOf[s]] == s` | ✓ |
| [B-87](./specs/Badges.spec#L172-L178) | `mintSeatRequiresValidRange` | Revert Condition | `mintSeat` reverts for seat outside `[1, 256]` | ✓ |
| [B-88](./specs/Badges.spec#L185-L194) | `mintSeatRequiresVacant` | Revert Condition | `mintSeat` reverts when seat is occupied | ✓ |
| [B-89](./specs/Badges.spec#L201-L211) | `mintSeatRequiresNoBadge` | Revert Condition | `mintSeat` reverts when recipient already has a badge | ✓ |
| [B-90a](./specs/Badges.spec#L217-L224) | `mintSeatOnlyDAO` | Access Control | Only `DAO` can call `mintSeat` | ✓ |
| [B-90b](./specs/Badges.spec#L226-L233) | `burnSeatOnlyDAO` | Access Control | Only `DAO` can call `burnSeat` | ✓ |
| [B-91](./specs/Badges.spec#L240-L251) | `daoWriteOnce` | Parametric | `DAO` address cannot change once set | ✓ |
| [B-92](./specs/Badges.spec#L257-L264) | `initRevertsIfDaoSet` | Revert Condition | `init` reverts when `DAO` is already set | ✓ |
| [B-SAN1](./specs/Badges.spec#L270-L273) | `mintSeatSanity` | Sanity | `mintSeat` is reachable | ✓ |
| [B-SAN2](./specs/Badges.spec#L275-L278) | `burnSeatSanity` | Sanity | `burnSeat` is reachable | ✓ |
| [B-SAN3](./specs/Badges.spec#L280-L283) | `initSanity` | Sanity | `init` is reachable | ✓ |

### `Shares` (20 properties)

ERC-20 with voting: sum-of-balances invariant via ghost + Sload hook, transfer lock, split delegation constraints (BPS sum, max splits, no zero/duplicate delegates), target allocation sum conservation, checkpoint temporal ordering, and DAO authorization (invariants 56-68, 71-73).

| ID&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; | Name | Type | Description | Status |
|:------|:----------------------------------------|:----------|:-------------------------------------------------------|:------:|
| [S-56](./specs/Shares.spec#L63-L88) | `totalSupplyIsSumOfBalances` | Invariant | `totalSupply` equals the sum of all `balanceOf` values | ✓ |
| [S-57](./specs/Shares.spec#L96-L115) | `transferIntegrity` | Integrity | `transfer` moves exact amounts between sender and receiver | ✓ |
| [S-58a](./specs/Shares.spec#L123-L135) | `transferRevertsWhenLocked` | Revert Condition | `transfer` reverts when locked and neither party is DAO | ✓ |
| [S-58b](./specs/Shares.spec#L138-L149) | `transferFromRevertsWhenLocked` | Revert Condition | `transferFrom` reverts when locked and neither party is DAO | ✓ |
| [S-59](./specs/Shares.spec#L157-L168) | `onlyMintBurnChangeTotalSupply` | Parametric | Only `mintFromMoloch`, `burnFromMoloch`, and `init` change `totalSupply` | ✓ |
| [S-60](./specs/Shares.spec#L178-L200) | `splitBpsSumInvariant` | Parametric | Split delegation BPS values sum to exactly 10000 | ✓ |
| [S-61](./specs/Shares.spec#L207-L215) | `maxSplitsEnforced` | Parametric | Split delegation count never exceeds `MAX_SPLITS` (4) | ✓ |
| [S-62](./specs/Shares.spec#L222-L245) | `noZeroSplitDelegate` | Parametric | No split delegation entry has `address(0)` as delegate | ✓ |
| [S-63](./specs/Shares.spec#L252-L284) | `noDuplicateSplitDelegates` | Parametric | No split delegation config has duplicate delegates | ✓ |
| [S-64](./specs/Shares.spec#L370-L386) | `targetAllocSumsToBalance` | Integrity | `_targetAlloc` allocations sum to exactly the input balance | ✓ |
| [S-66](./specs/Shares.spec#L393-L410) | `checkpointFromBlockNonDecreasing` | Parametric | New checkpoint `fromBlock` values are >= previous (temporal ordering) | ✓ |
| [S-67](./specs/Shares.spec#L291-L297) | `getPastVotesRevertsOnFutureBlock` | Revert Condition | `getPastVotes` reverts for `blockNumber >= block.number` | ✓ |
| [S-68](./specs/Shares.spec#L304-L310) | `getPastTotalSupplyRevertsOnFutureBlock` | Revert Condition | `getPastTotalSupply` reverts for `blockNumber >= block.number` | ✓ |
| [S-71](./specs/Shares.spec#L318-L326) | `daoWriteOnce` | Parametric | `DAO` address cannot change once set | ✓ |
| [S-72](./specs/Shares.spec#L333-L339) | `initRevertsIfDaoSet` | Revert Condition | `init` reverts when `DAO` is already set | ✓ |
| [S-73a](./specs/Shares.spec#L348-L353) | `mintRequiresDAO` | Access Control | Only `DAO` can call `mintFromMoloch` | ✓ |
| [S-73b](./specs/Shares.spec#L357-L362) | `burnRequiresDAO` | Access Control | Only `DAO` can call `burnFromMoloch` | ✓ |
| [S-SAN1](./specs/Shares.spec#L416-L420) | `transferSanity` | Sanity | `transfer` is reachable | ✓ |
| [S-SAN2](./specs/Shares.spec#L422-L425) | `mintSanity` | Sanity | `mintFromMoloch` is reachable | ✓ |
| [S-SAN3](./specs/Shares.spec#L427-L431) | `delegateSanity` | Sanity | `delegate` is reachable | ✓ |

### `DAICO` (19 properties)

Sale and tap mechanism: sale configuration authorization, buy revert conditions (no sale, expired, zero pay, zero output, slippage), tap revert conditions (zero rate, zero ops, zero elapsed), `lastClaim` update integrity, tap claim amount bounds, LP config validation, and **L-01 finding verification** (invariants 106-118).

| ID&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; | Name | Type | Description | Status |
|:------|:----------------------------------------|:----------|:-------------------------------------------------------|:------:|
| [D-106a](./specs/DAICO.spec#L41-L53) | `setSaleRecordsSenderAsDao` | Integrity | `setSale` records `msg.sender` as the DAO key | ✓ |
| [D-106b](./specs/DAICO.spec#L56-L69) | `setSaleWithTapRecordsSender` | Integrity | `setSaleWithTap` records `msg.sender` as the DAO key | ✓ |
| [D-107](./specs/DAICO.spec#L75-L84) | `buyRevertsOnNoSale` | Revert Condition | `buy` reverts when no active sale exists | ✓ |
| [D-108](./specs/DAICO.spec#L90-L102) | `buyRevertsOnExpired` | Revert Condition | `buy` reverts after deadline has passed | ✓ |
| [D-109](./specs/DAICO.spec#L108-L114) | `buyRevertsOnZeroPay` | Revert Condition | `buy` reverts when `payAmt == 0` | ✓ |
| [D-110](./specs/DAICO.spec#L120-L137) | `buyRevertsOnZeroBuyAmt` | Revert Condition | `buy` reverts when computed `buyAmt` would be zero | ✓ |
| [D-111](./specs/DAICO.spec#L143-L162) | `buyRevertsOnSlippage` | Revert Condition | `buy` reverts on slippage violation | ✓ |
| [D-112](./specs/DAICO.spec#L168-L190) | `buyExactOutRevertsOnSlippage` | Revert Condition | `buyExactOut` reverts on slippage violation | ✓ |
| [D-113](./specs/DAICO.spec#L196-L203) | `claimTapRevertsOnZeroRate` | Revert Condition | `claimTap` reverts when `ratePerSec == 0` | ✓ |
| [D-114](./specs/DAICO.spec#L209-L216) | `claimTapRevertsOnZeroOps` | Revert Condition | `claimTap` reverts when `ops == address(0)` | ✓ |
| [D-115](./specs/DAICO.spec#L222-L232) | `claimTapRevertsOnZeroElapsed` | Revert Condition | `claimTap` reverts when elapsed time is zero | ✓ |
| [D-117](./specs/DAICO.spec#L238-L247) | `claimTapUpdatesLastClaim` | Integrity | After `claimTap`, `lastClaim == block.timestamp` | ✓ |
| [D-118](./specs/DAICO.spec#L253-L262) | `setLPConfigRevertsOnBadBps` | Revert Condition | `setLPConfig` reverts when `lpBps >= 10000` | ✓ |
| [D-116](./specs/DAICO.spec#L268-L290) | `claimTapAmountCapped` | Integrity | `claimTap` returns at most `min(owed, available)` | ✓ |
| [D-L1a](./specs/DAICO.spec#L306-L334) | `claimTapForfeitureOnPartialClaim` | Integrity | **L-01**: `claimTap` must not consume more time than paid for — violated because `lastClaim` advances full elapsed even when `claimed < owed` | ✗ |
| [D-L1b](./specs/DAICO.spec#L337-L356) | `claimTapPartialClaimExists` | Sanity | **L-01**: Demonstrates a concrete partial claim scenario exists where `claimed < owed` | ✓ |
| [D-SAN1](./specs/DAICO.spec#L362-L367) | `setSaleSanity` | Sanity | `setSale` is reachable | ✓ |
| [D-SAN2](./specs/DAICO.spec#L369-L372) | `buySanity` | Sanity | `buy` is reachable | ✓ |
| [D-SAN3](./specs/DAICO.spec#L374-L378) | `claimTapSanity` | Sanity | `claimTap` is reachable | ✓ |

### `Moloch` (53 properties)

Core DAO: ERC-6909 sum-of-balances invariant (ghost + Sstore/Sload hooks), permit receipt transfer blocking, proposal state immutability (executed latch, terminal state, write-once fields), config monotonicity, voting revert conditions and post-condition integrity (tally isolation, hasVoted/voteWeight correctness), futarchy state machine (resolved latch, payoutPerUnit write-once, cashOut/fund revert conditions, finalization integrity), ragequit revert conditions and mulDiv bound lemma, execution state checks (Unopened rejection, timelock auto-queue), governance setter authorization (`onlyDAO` enforcement across 14 setters), state variable modification authorization (10 governance parameters), sale/allowance integrity, and token address immutability (invariants 1, 3-8, 10-11, 13-17, 19-24, 27-28, 30-41, 43-49, 51-52, 94).

| ID&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; | Name | Type | Description | Status |
|:------|:----------------------------------------|:----------|:-------------------------------------------------------|:------:|
| [M-1](./specs/Moloch.spec#L107-L124) | `totalSupplyIsSumOfBalances6909` | Invariant | ERC-6909 `totalSupply[id]` equals sum of all `balanceOf[*][id]` (ghost + Sstore/Sload hooks) | ✓ |
| [M-3a](./specs/Moloch.spec#L131-L138) | `transferRevertsForPermitReceipt` | Revert Condition | `transfer` reverts for permit receipt tokens | ✓ |
| [M-3b](./specs/Moloch.spec#L140-L148) | `transferFromRevertsForPermitReceipt` | Revert Condition | `transferFrom` reverts for permit receipt tokens | ✓ |
| [M-4](./specs/Moloch.spec#L154-L163) | `executedIsOneWayLatch` | Parametric | `executed[id]` never reverts from `true` to `false` | ✓ |
| [M-5](./specs/Moloch.spec#L169-L178) | `createdAtWriteOnce` | Parametric | `createdAt[id]` cannot change once set to non-zero | ✓ |
| [M-6](./specs/Moloch.spec#L184-L193) | `snapshotBlockWriteOnce` | Parametric | `snapshotBlock[id]` cannot change once set to non-zero | ✓ |
| [M-7](./specs/Moloch.spec#L199-L213) | `supplySnapshotWriteOnce` | Parametric | `supplySnapshot[id]` cannot change once set to non-zero | ✓ |
| [M-8](./specs/Moloch.spec#L219-L228) | `queuedAtWriteOnce` | Parametric | `queuedAt[id]` cannot change once set to non-zero | ✓ |
| [M-10](./specs/Moloch.spec#L616-L623) | `executedStateIsTerminal` | Parametric | Executed state cannot transition to any other state | ✓ |
| [M-11](./specs/Moloch.spec#L234-L245) | `configMonotonic` | Parametric | `config` is monotonically non-decreasing | ✓ |
| [M-13](./specs/Moloch.spec#L251-L258) | `castVoteRevertsIfExecuted` | Revert Condition | `castVote` reverts if proposal is executed | ✓ |
| [M-14](./specs/Moloch.spec#L264-L274) | `castVoteRevertsIfAlreadyVoted` | Revert Condition | `castVote` reverts if caller already voted | ✓ |
| [M-15](./specs/Moloch.spec#L280-L288) | `castVoteRevertsOnInvalidSupport` | Revert Condition | `castVote` reverts for `support > 2` | ✓ |
| [M-16](./specs/Moloch.spec#L630-L643) | `castVotePostConditions` | Integrity | After successful vote: `hasVoted == support + 1` and `voteWeight > 0` | ✓ |
| [M-17](./specs/Moloch.spec#L650-L666) | `castVoteTallyIntegrity` | Integrity | Only the relevant tally component changes; others remain unchanged | ✓ |
| [M-19](./specs/Moloch.spec#L701-L710) | `futarchyResolvedIsOneWayLatch` | Parametric | `futarchy[id].resolved` never reverts from `true` to `false` | ✓ |
| [M-20](./specs/Moloch.spec#L716-L729) | `payoutPerUnitWriteOnce` | Parametric | `futarchy[id].payoutPerUnit` cannot change once set to non-zero | ✓ |
| [M-21](./specs/Moloch.spec#L735-L742) | `cashOutRevertsIfNotResolved` | Revert Condition | `cashOutFutarchy` reverts when not resolved | ✓ |
| [M-22](./specs/Moloch.spec#L748-L756) | `fundFutarchyRevertsIfResolved` | Revert Condition | `fundFutarchy` reverts when already resolved | ✓ |
| [M-23](./specs/Moloch.spec#L763-L778) | `finalWinningSupplyMatchesReceipt` | Integrity | After finalization, `finalWinningSupply` equals receipt token `totalSupply` | ✓ |
| [M-24](./specs/Moloch.spec#L785-L797) | `mulDivBoundLemma` | Integrity | `mulDiv(pool, amt, total) <= pool` when `amt <= total` (ragequit payout bound) | ✓ |
| [M-27](./specs/Moloch.spec#L803-L809) | `ragequitRevertsOnZeroBurn` | Revert Condition | `ragequit` reverts when both burn amounts are zero | ✓ |
| [M-28](./specs/Moloch.spec#L815-L822) | `ragequitRevertsIfNotRagequittable` | Revert Condition | `ragequit` reverts when `ragequittable` is false | ✓ |
| [M-30](./specs/Moloch.spec#L294-L304) | `proposalThresholdOnlyViaSet` | Parametric | `proposalThreshold` only changes via `setProposalThreshold` | ✓ |
| [M-31](./specs/Moloch.spec#L310-L320) | `proposalTTLOnlyViaSet` | Parametric | `proposalTTL` only changes via `setProposalTTL` | ✓ |
| [M-32](./specs/Moloch.spec#L326-L336) | `timelockDelayOnlyViaSet` | Parametric | `timelockDelay` only changes via `setTimelockDelay` | ✓ |
| [M-33](./specs/Moloch.spec#L342-L352) | `quorumAbsoluteOnlyViaSet` | Parametric | `quorumAbsolute` only changes via `setQuorumAbsolute` | ✓ |
| [M-34](./specs/Moloch.spec#L358-L368) | `minYesVotesAbsoluteOnlyViaSet` | Parametric | `minYesVotesAbsolute` only changes via `setMinYesVotesAbsolute` | ✓ |
| [M-35](./specs/Moloch.spec#L374-L384) | `quorumBpsOnlyViaSet` | Parametric | `quorumBps` only changes via `setQuorumBps` | ✓ |
| [M-36](./specs/Moloch.spec#L390-L400) | `ragequittableOnlyViaSet` | Parametric | `ragequittable` only changes via `setRagequittable` | ✓ |
| [M-37](./specs/Moloch.spec#L406-L416) | `rendererOnlyViaSet` | Parametric | `renderer` only changes via `setRenderer` | ✓ |
| [M-38](./specs/Moloch.spec#L422-L434) | `autoFutarchyOnlyViaSet` | Parametric | `autoFutarchyParam` and `autoFutarchyCap` only change via `setAutoFutarchy` | ✓ |
| [M-39](./specs/Moloch.spec#L440-L450) | `rewardTokenOnlyViaSet` | Parametric | `rewardToken` only changes via `setFutarchyRewardToken` | ✓ |
| [M-40](./specs/Moloch.spec#L548-L558) | `isPermitReceiptOnlyViaSet` | Parametric | `isPermitReceipt[id]` only changes via `setPermitReceipt` | ✓ |
| [M-41](./specs/Moloch.spec#L673-L695) | `governanceSettersRevertIfNotDAO` | Access Control | All 14 governance setters revert when `msg.sender != address(this)` | ✓ |
| [M-43](./specs/Moloch.spec#L456-L463) | `buySharesRevertsIfNotActive` | Revert Condition | `buyShares` reverts when sale is not active | ✓ |
| [M-44](./specs/Moloch.spec#L469-L473) | `buySharesRevertsOnZeroAmount` | Revert Condition | `buyShares` reverts when `shareAmount == 0` | ✓ |
| [M-45](./specs/Moloch.spec#L564-L571) | `setSaleRevertsOnZeroPrice` | Revert Condition | `setSale` reverts when `pricePerShare == 0` | ✓ |
| [M-46](./specs/Moloch.spec#L479-L490) | `buySharesDecreasesCap` | Integrity | `buyShares` decreases cap by exactly `shareAmount` | ✓ |
| [M-47](./specs/Moloch.spec#L496-L511) | `buySharesRevertsOnSlippage` | Revert Condition | `buyShares` reverts on slippage violation | ✓ |
| [M-48](./specs/Moloch.spec#L517-L528) | `spendAllowanceDecreases` | Integrity | `spendAllowance` decreases allowance by exactly `amount` | ✓ |
| [M-49](./specs/Moloch.spec#L534-L542) | `spendAllowanceRevertsIfInsufficient` | Revert Condition | `spendAllowance` reverts when allowance is insufficient | ✓ |
| [M-51](./specs/Moloch.spec#L829-L837) | `executeRevertsIfUnopened` | Revert Condition | `executeByVotes` reverts for Unopened proposals (`snapshotBlock == 0`) | ✓ |
| [M-52](./specs/Moloch.spec#L844-L858) | `executeTimelockAutoQueue` | Integrity | With timelock, first `executeByVotes` call sets `queuedAt` without executing | ✓ |
| [M-94a](./specs/Moloch.spec#L578-L587) | `sharesAddressImmutable` | Parametric | `shares` address never changes | ✓ |
| [M-94b](./specs/Moloch.spec#L589-L598) | `lootAddressImmutable` | Parametric | `loot` address never changes | ✓ |
| [M-94c](./specs/Moloch.spec#L600-L609) | `badgesAddressImmutable` | Parametric | `badges` address never changes | ✓ |
| [M-SAN1](./specs/Moloch.spec#L864-L868) | `castVoteSanity` | Sanity | `castVote` is reachable | ✓ |
| [M-SAN2](./specs/Moloch.spec#L870-L873) | `buySharesSanity` | Sanity | `buyShares` is reachable | ✓ |
| [M-SAN3](./specs/Moloch.spec#L875-L879) | `spendAllowanceSanity` | Sanity | `spendAllowance` is reachable | ✓ |
| [M-SAN4](./specs/Moloch.spec#L881-L885) | `fundFutarchySanity` | Sanity | `fundFutarchy` is reachable | ✓ |
| [M-SAN5](./specs/Moloch.spec#L887-L891) | `cashOutFutarchySanity` | Sanity | `cashOutFutarchy` is reachable | ✓ |
| [M-SAN6](./specs/Moloch.spec#L893-L897) | `ragequitSanity` | Sanity | `ragequit` is reachable | ✓ |

---

## Assumptions

### Safe Assumptions

All `require` statements annotated with `"SAFE: ..."` in the specs represent real-world constraints that do not exclude valid attack scenarios:

- **Environment constraints**: `e.msg.value == 0` for non-payable functions (prevents Solidity ABI revert false positives); `e.block.timestamp <= max_uint64` (year ~584 billion)
- **Conservation bounds**: Individual `balanceOf` values bounded by `totalSupply` or ghost sum (follows from the proven sum-of-balances invariant)
- **Write-once coupling**: `supplySnapshot[id] != 0 => snapshotBlock[id] != 0` (these fields are always set together in `openProposal`)
- **Futarchy synchronization**: `payoutPerUnit != 0 => resolved` (both fields are set atomically in `_finalizeFutarchy`)
- **Overflow guards**: `config < max_uint64` (18.4 quintillion — unreachable in practice since each DAO settings call increments by one); `pool <= max_uint128` and `amt <= max_uint128` for `mulDiv` bound lemma (prevents overflow in intermediate multiplication)
- **Address separation**: `from != to` for transfer integrity (self-transfer verified separately); `otherProposer != msg.sender` for isolation rules
- **Inductive hypotheses**: Pre-state `require` statements in parametric rules for split delegation properties (BPS sum, max count, no zero delegates, no duplicates) — these mirror the invariant being proved

### Proved Assumptions

Invariants used as preconditions via `requireInvariant` in other rules:

- `totalSupplyIsSumOfBalances` — Used in `transferIntegrity` (both `Loot` and `Shares`) to bound sender and receiver balances
- `balanceZeroOrOne` — Used in `Badges` invariants `seatOfInRange`, `biMapForward`, `biMapReverse`, and `seatImpliesBalance`
- `seatOfInRange` — Used in `biMapForward` and `biMapReverse` to prevent uint16 truncation counterexamples
- `seatImpliesBalance` — Used in `biMapForward` and `biMapReverse` to link badge ownership with seat assignment
- `biMapForward` — Used in `biMapReverse` preserved blocks to establish injectivity of the ownership mapping

---

## Setup and Execution

The Certora Prover can be run either remotely (using Certora's cloud infrastructure) or locally (building from source); both modes share the same initial setup steps.

### Common Setup (Steps 1–4)

The instructions below are for Ubuntu 24.04. For step-by-step installation details refer to this setup [tutorial](https://alexzoid.com/first-steps-with-certora-fv-catching-a-real-bug#heading-setup).

1. Install Java (tested with JDK 21)

```bash
sudo apt update
sudo apt install default-jre
java -version
```

2. Install [pipx](https://pipx.pypa.io/) — installs Python CLI tools in isolated environments, avoiding dependency conflicts

```bash
sudo apt install pipx
pipx ensurepath
```

3. Install Certora CLI. To match a specific prover version, pin it explicitly (e.g. `certora-cli==8.8.1`)

```bash
pipx install certora-cli
```

4. Install solc-select and the Solidity compiler version required by the project

```bash
pipx install solc-select
solc-select install 0.8.30
solc-select use 0.8.30
```

### Remote Execution

5. Set up Certora key. You can get a free key through the Certora [Discord](https://discord.gg/certora) or on their website. Once you have it, export it:

```bash
echo "export CERTORAKEY=<your_certora_api_key>" >> ~/.bashrc
source ~/.bashrc
```

> **Note:** If a local prover is installed (see below), it takes priority. To force remote execution, add the `--server production` flag:
> ```bash
> certoraRun certora/conf/Moloch.conf --server production
> ```

### Local Execution

Follow the full build instructions in the [CertoraProver repository (v8.8.1)](https://github.com/Certora/CertoraProver/tree/8.8.1). Once the local prover is installed it takes priority over the remote cloud by default. Tested on Ubuntu 24.04.

1. Install prerequisites

```bash
# JDK 19+
sudo apt install openjdk-21-jdk

# SMT solvers (z3 and cvc5 are required, others are optional)
# Download binaries and place them in PATH:
#   z3:   https://github.com/Z3Prover/z3/releases
#   cvc5: https://github.com/cvc5/cvc5/releases

# LLVM tools
sudo apt install llvm

# Rust 1.81.0+
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
cargo install rustfilt

# Graphviz (optional, for visual reports)
sudo apt install graphviz
```

2. Set up build output directory

```bash
export CERTORA="$HOME/CertoraProver/target/installed/"
mkdir -p "$CERTORA"
export PATH="$CERTORA:$PATH"
```

3. Clone and build

```bash
git clone --recurse-submodules https://github.com/Certora/CertoraProver.git
cd CertoraProver
git checkout tags/8.8.1
./gradlew assemble
```

4. Verify installation with test example

```bash
certoraRun.py -h
cd Public/TestEVM/Counter
certoraRun counter.conf
```

### Running Verification

Run all 7 contracts:

```bash
certoraRun certora/conf/SafeSummoner.conf
certoraRun certora/conf/Tribute.conf
certoraRun certora/conf/Loot.conf
certoraRun certora/conf/Badges.conf
certoraRun certora/conf/Shares.conf
certoraRun certora/conf/DAICO.conf
certoraRun certora/conf/Moloch.conf
```

Run a specific rule:

```bash
certoraRun certora/conf/Moloch.conf --rule configMonotonic supplySnapshotWriteOnce
```

Compilation-only check (no cloud submission):

```bash
certoraRun certora/conf/Moloch.conf --compilation_steps_only
```

---

## Resources

To learn more about Certora formal verification:

- [Updraft Assembly & Formal Verification Course](https://updraft.cyfrin.io/courses/formal-verification) — Comprehensive video course covering assembly and formal verification from the ground up
- [Find Highs Using Certora Formal Verification](https://dacian.me/find-highs-before-external-auditors-using-certora-formal-verification) — Practical guide with a companion [repo](https://github.com/devdacian/solidity-fuzzing-comparison) containing simplified examples based on real code and bugs from private audits
- [RareSkills Certora Book](https://rareskills.io/tutorials/certora-book) — Structured tutorial covering CVL syntax, patterns, and common pitfalls
- [Alex FV Resources](https://github.com/alexzoid-eth/fv-resources) — Curated collection of formal verification resources, examples, and references
- [Certora Tutorials](https://docs.certora.com/en/latest/docs/user-guide/tutorials.html) — Official Certora documentation and guided tutorials

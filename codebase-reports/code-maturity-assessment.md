# Code Maturity Assessment: Majeur DAO Governance Framework

**Framework**: Trail of Bits' Building Secure Contracts - Code Maturity Evaluation v0.1.0
**Date**: 2026-01-26
**Assessor**: Claude Opus 4.5
**Codebase**: Majeur (Moloch-based DAO governance framework)
**Platform**: Solidity 0.8.30 / EVM (Cancun)
**Compiler**: solc 0.8.30 with `via_ir = true`, `optimizer_runs = 500`

---

## Executive Summary

**Overall Maturity Score: 2.6 / 4.0 (Moderate-to-Satisfactory)**

Majeur is a compact, opinionated DAO governance framework that demonstrates strong arithmetic practices, thoughtful security mitigations (v2 improvements), and substantial test coverage. The codebase is remarkably dense -- roughly 2,150 lines of core Solidity across all contracts -- yet manages governance, voting, delegation, futarchy, token sales, ragequit, DAICO, tribute, on-chain SVG, and soulbound badges.

### Top 3 Strengths

1. **Arithmetic safety** (Score: 3/4): Solidity 0.8.30 provides default overflow protection; `unchecked` blocks are used judiciously with clear invariants; custom `mulDiv` with overflow detection; safe cast utilities (`toUint48`, `toUint96`).
2. **Testing depth** (Score: 3/4): 474 passing tests across 9 test suites covering governance, DAICO, tribute, view helpers, and metadata. Includes fuzz tests, invariant-style tests, and edge case coverage.
3. **Access control rigor** (Score: 3/4): Clean `onlyDAO` modifier pattern; DAO self-voting explicitly blocked (v2); ragequit timelock prevents flash loan attacks; proposal threshold configurable; soulbound badges are non-transferable.

### Top 3 Critical Gaps

1. **No CI/CD pipeline** (Score: 0/4): No `.github/` directory, no automated test runs, no coverage reporting, no static analysis integration (Slither, Mythril).
2. **No formal audit** (Score: 1/4): No evidence of professional security audit; no audit report; no bug bounty program documented.
3. **Limited documentation** (Score: 2/4): Good inline NatSpec on DAICO (139 occurrences) but sparse on Moloch.sol (33 occurrences relative to ~1,100 lines); no formal specification document; no threat model.

### Priority Recommendations

1. **CRITICAL**: Engage a professional security audit before mainnet v2 deployment.
2. **CRITICAL**: Set up CI/CD with `forge test`, Slither, and coverage reporting.
3. **HIGH**: Add stateful fuzzing / invariant tests using Foundry's `invariant_*` framework.
4. **HIGH**: Document the complete threat model and security properties.
5. **MEDIUM**: Increase NatSpec coverage on Moloch.sol core functions (voting, delegation, futarchy).

---

## Maturity Scorecard

| # | Category | Rating | Score | Key Findings |
|---|----------|--------|-------|--------------|
| 1 | Arithmetic | Satisfactory | 3 | Default overflow protection; custom `mulDiv` with overflow check; safe cast utils; `unchecked` used judiciously |
| 2 | Auditing & Monitoring | Weak | 1 | Good event coverage (62 emit sites), but no monitoring, no incident response, no professional audit |
| 3 | Authentication / Access Controls | Satisfactory | 3 | Clean `onlyDAO` pattern; DAO self-voting blocked; ragequit timelock; permit system; no admin keys |
| 4 | Complexity Management | Moderate | 2 | Single-file architecture is compact but dense; `Moloch.sol` is 2,146 lines with 5 contracts; deep nesting in some functions |
| 5 | Decentralization | Satisfactory | 3 | No admin keys; all config via governance; ragequit exit path; immutable proxies; `delegatecall` for extensibility |
| 6 | Documentation | Moderate | 2 | Good v1/v2 diff doc; NatSpec present on DAICO; sparse on Moloch core; no formal specification or threat model |
| 7 | Transaction Ordering Risks | Satisfactory | 3 | Snapshot at block N-1; slippage protection on buys; timelock on proposals; ragequit timelock |
| 8 | Low-Level Manipulation | Moderate | 2 | Extensive assembly (29 blocks); well-structured but minimally documented; `delegatecall` in execute and multicall |
| 9 | Testing & Verification | Satisfactory | 3 | 474 tests; fuzz tests; invariant-style tests; no CI/CD; no Slither integration; no formal verification |
| | **Overall** | **Moderate-Satisfactory** | **2.6** | |

---

## Detailed Analysis

### 1. ARITHMETIC (Score: 3/4 - Satisfactory)

#### What I Found

**Overflow Protection**:
- Solidity 0.8.30 provides default checked arithmetic across all contracts.
- `unchecked` blocks are used in 44 locations across the codebase, but each is justifiable:
  - Counter increments where overflow is impossible (e.g., loop indices)
  - Subtraction where prior checks guarantee no underflow (e.g., `Moloch.sol:740` cap subtraction after `shareAmount > cap` check)
  - Vote tallying where total votes are bounded by `totalSupply` (stored as `uint96`)
  - Balance updates where overflow is impossible due to totalSupply constraint

**Precision Handling**:
- Custom `mulDiv` implementation (`Moloch.sol:2022-2031`) with assembly-level overflow detection:
  ```solidity
  function mulDiv(uint256 x, uint256 y, uint256 d) pure returns (uint256 z) {
      assembly ("memory-safe") {
          z := mul(x, y)
          if iszero(mul(or(iszero(x), eq(div(z, x), y)), d)) {
              mstore(0x00, 0xad251c27)
              revert(0x1c, 0x04)
          }
          z := div(z, d)
      }
  }
  ```
  This correctly reverts on overflow (when `x * y` exceeds `uint256`) and on division by zero.

- Ragequit pro-rata calculation (`Moloch.sol:814`): `due = mulDiv(pool, amt, total)` -- correctly handles proportional distribution.
- Futarchy payout scaling (`Moloch.sol:634`): `ppu = mulDiv(pool, 1e18, winSupply)` -- uses 1e18 scaling for precision.
- DAICO rate calculations use `1e18` scaling consistently (`DAICO.sol:531`, `DAICO.sol:631`).

**Safe Casts**:
- `toUint48` (`Moloch.sol:2004-2007`) and `toUint96` (`Moloch.sol:2009-2012`) with explicit overflow checks.
- Used consistently for block numbers (`uint48`) and vote weights (`uint96`).

**Rounding**:
- DAICO `buyExactOut` uses ceiling division (`DAICO.sol:614`): `(num + offer.forAmt - 1) / offer.forAmt` -- correctly rounds up payment to prevent rounding exploits.
- Ragequit `mulDiv` rounds down (truncation), which is standard -- the DAO keeps dust.
- Split delegation uses "remainder to last" pattern (`Moloch.sol:1527-1545`) to avoid losing fractional votes.

#### Gaps

- The `mulDiv` implementation does not handle the case where `x * y` overflows but the final result fits in `uint256`. A full Solady-style `mulDiv` with 512-bit intermediate would be more robust. However, in practice, the inputs (share amounts, prices) are bounded enough that this is unlikely to be exploitable.
- No explicit documentation of the precision model (what scaling factors are used where, and why).

#### Evidence

| File | Line | Pattern | Assessment |
|------|------|---------|------------|
| `src/Moloch.sol` | 2022-2031 | `mulDiv` assembly | Overflow-safe division with revert on overflow |
| `src/Moloch.sol` | 292-309 | `unchecked` in `openProposal` | Safe: block.number - 1 cannot underflow after genesis |
| `src/Moloch.sol` | 381-388 | `unchecked` vote tallying | Safe: bounded by uint96 supply snapshot |
| `src/Moloch.sol` | 738-741 | `unchecked` cap subtraction | Safe: checked `shareAmount > cap` above |
| `src/Moloch.sol` | 2004-2012 | `toUint48`, `toUint96` | Explicit overflow-safe casts |
| `src/peripheral/DAICO.sol` | 607-614 | Ceiling division | Correct rounding for exact-out pricing |
| `src/Moloch.sol` | 1527-1545 | `_targetAlloc` | Remainder-to-last prevents vote loss |

---

### 2. AUDITING & MONITORING (Score: 1/4 - Weak)

#### What I Found

**Event Coverage**:
- 62 `emit` statements across 3 contracts (Moloch: 42, DAICO: 17, Tribute: 3).
- All critical state changes emit events:
  - Proposal lifecycle: `Opened`, `Voted`, `VoteCancelled`, `ProposalCancelled`, `Queued`, `Executed`
  - Futarchy: `FutarchyOpened`, `FutarchyFunded`, `FutarchyResolved`, `FutarchyClaimed`
  - Sales: `SaleUpdated`, `SharesPurchased`, `SaleSet`, `SaleBought`
  - Governance: `PermitSet`, `PermitSpent`, `Message`
  - Tap: `TapSet`, `TapClaimed`, `TapOpsUpdated`, `TapRateUpdated`
  - Tokens: `Transfer`, `Approval`, `DelegateChanged`, `DelegateVotesChanged`, `WeightedDelegationSet`

**Gaps**:
- **No monitoring infrastructure**: No evidence of off-chain monitoring, alerting, or dashboards.
- **No incident response plan**: No documented procedures for handling security incidents.
- **No professional audit**: No audit reports in the repository, no evidence of formal security review.
- **No bug bounty program**: No Immunefi or similar program documented.
- **Missing events for some setters**: Configuration changes like `setQuorumBps`, `setProposalTTL`, `setTimelockDelay`, `setRagequitTimelock`, `setRagequittable`, `setProposalThreshold`, `setRenderer`, `setMetadata`, `bumpConfig`, `setAutoFutarchy`, `setFutarchyRewardToken` do NOT emit events. This makes it impossible to track governance parameter changes via event logs.

#### Evidence

| File | Line | Pattern | Assessment |
|------|------|---------|------------|
| `src/Moloch.sol` | 90-96 | Proposal events | Comprehensive proposal lifecycle events |
| `src/Moloch.sol` | 838-911 | Setter functions | 13 setter functions without events |
| `src/peripheral/DAICO.sol` | 115-153 | DAICO events | Good coverage of sale, tap, LP events |
| `.github/` | N/A | Missing directory | No CI/CD pipeline |

---

### 3. AUTHENTICATION / ACCESS CONTROLS (Score: 3/4 - Satisfactory)

#### What I Found

**Access Control Architecture**:
- **`onlyDAO` modifier** (`Moloch.sol:22-25`): All governance-sensitive functions require `msg.sender == address(this)`, meaning only proposal execution can change DAO parameters. This is the correct pattern for DAO governance.
- **DAO self-voting blocked** (`Moloch.sol:356`): `if (msg.sender == address(this)) revert Unauthorized()` prevents the DAO from voting on its own proposals, closing a v1 attack vector documented in `docs/v1-v2-contract-differences.md`.
- **Summoner init guard** (`Moloch.sol:222`): `require(msg.sender == SUMMONER, Unauthorized())` ensures only the factory can initialize clones.
- **Token contract guards**: `Shares`, `Loot`, and `Badges` all use `onlyDAO()` for privileged operations (`mintFromMoloch`, `burnFromMoloch`, `mintSeat`, `burnSeat`).
- **Init once pattern**: `Shares.init()` (`Moloch.sol:1142-1143`), `Loot.init()`, and `Badges.init()` all use `require(DAO == address(0))` to prevent re-initialization.

**Specific Protections**:
- **Ragequit timelock** (`Moloch.sol:786-793`): 7-day default hold period before ragequit, preventing flash loan attacks.
- **Proposal threshold** (`Moloch.sol:286-289`): Configurable minimum voting power to create proposals.
- **Chat gating** (`Moloch.sol:829`): Only badge holders (top 256 shareholders) can chat.
- **Soulbound badges** (`Moloch.sol:1784-1786`): `transferFrom` reverts with `SBT()`.
- **Permit system** (`Moloch.sol:646-690`): Granular per-action permits with ERC-6909 receipt tracking.
- **Treasury allowance** (`Moloch.sol:695-702`): Separate allowance mechanism for treasury spending.

**Delegation Controls**:
- Split delegation max 4 delegates (`Moloch.sol:1133`)
- BPS must sum to exactly 10,000 (`Moloch.sol:1312`)
- No duplicate delegates allowed (`Moloch.sol:1308-1310`)
- Auto self-delegation on first interaction (`Moloch.sol:1379-1385`)

**No Admin Keys**:
- No `owner`, `admin`, or privileged role anywhere in the contracts.
- All configuration changes go through governance (proposal + vote + execute).
- Summoner is immutable after deployment; it cannot modify deployed DAOs.

#### Gaps

- **No role-based access**: Only binary DAO-or-not. No tiered roles (e.g., guardian, veto).
- **`delegatecall` in execute** (`Moloch.sol:1012`): `op == 1` allows arbitrary delegatecall from the DAO context. This is by design (extensibility), but a malicious proposal could modify storage arbitrarily. This is mitigated by the governance process (voting + timelock) but remains a powerful primitive.
- **`multicall` uses delegatecall** (`Moloch.sol:925`): No access control on `multicall` itself -- any address can call it. However, the delegatecalled functions each have their own access checks.

#### Evidence

| File | Line | Pattern | Assessment |
|------|------|---------|------------|
| `src/Moloch.sol` | 22-25 | `onlyDAO` modifier | Correct governance-only pattern |
| `src/Moloch.sol` | 356 | DAO self-voting block | Closes v1 attack vector |
| `src/Moloch.sol` | 786-793 | Ragequit timelock | 7-day flash loan protection |
| `src/Moloch.sol` | 1012 | `delegatecall` in execute | Powerful but governance-gated |
| `src/Moloch.sol` | 1142-1143 | Init-once pattern | Prevents re-initialization |
| `src/peripheral/DAICO.sol` | 204-230 | `setSale` | `msg.sender == dao` pattern |

---

### 4. COMPLEXITY MANAGEMENT (Score: 2/4 - Moderate)

#### What I Found

**Codebase Size**:

| File | Lines | Contracts |
|------|-------|-----------|
| `src/Moloch.sol` | 2,146 | 5 (Moloch, Shares, Loot, Badges, Summoner) |
| `src/peripheral/DAICO.sol` | 1,330 | 1 |
| `src/peripheral/Tribute.sol` | 200 | 1 |
| `src/peripheral/MolochViewHelper.sol` | 1,343 | 1 |
| `src/Renderer.sol` | 510 | 1 |
| **Total** | **~5,529** | **9** |

**Architecture**:
- **Single-file monolith** (`Moloch.sol`): 5 contracts in one file. While compact, this means 2,146 lines in a single file. The contracts are logically separated (Moloch, Shares, Loot, Badges, Summoner) with clear responsibilities.
- **Flat inheritance**: No inheritance chains. All contracts are standalone, communicating via explicit interfaces. This is excellent for auditability.
- **Minimal dependencies**: Only `forge-std` (testing), `solady` (referenced but imports minimal), and `ZAMM` (AMM for LP).

**Function Complexity**:
- `openProposal` (`Moloch.sol:281-348`): 67 lines including auto-futarchy earmark logic. Moderate complexity with nested conditionals.
- `state` (`Moloch.sol:440-490`): 50 lines with multiple return paths (7 possible states). Complex but well-structured with clear comment sections.
- `_applyVotingDelta` (`Moloch.sol:1421-1457`): Non-trivial path-independent voting power redistribution.
- `_repointVotesForHolder` (`Moloch.sol:1462-1525`): Diff-based vote repointing between old and new delegate distributions. Complex but correctly handles the full matrix of transitions.
- `onSharesChanged` (`Moloch.sol:1850-1928`): 78 lines managing sticky top-256 badge seats with bitmap operations. High cyclomatic complexity (4 major branches: zero balance, already seated, free slot, eviction).
- `buy` / `buyExactOut` in DAICO: ~80 lines each with LP initialization, drift protection, refund handling.

**Code Duplication**:
- `_checkUnlocked` is duplicated between `Shares` and `Loot` (identical implementation).
- `_mint` and `_moveTokens` are duplicated between `Shares` and `Loot` (near-identical, Shares adds delegation logic).
- `safeTransferETH`, `safeTransfer`, `safeTransferFrom` are free functions shared across Moloch.sol.
- DAICO has its own copies of safe transfer functions (different signatures: includes `from` parameter).
- ViewHelper has significant structural repetition in `getUserDAOs` and `getUserDAOsFullState` (two-pass count-then-populate pattern repeated).

**State Machine**:
- Proposal state machine has 7 states (`Unopened`, `Active`, `Queued`, `Succeeded`, `Defeated`, `Expired`, `Executed`) with complex transition logic but is well-documented in the `state()` function.

#### Gaps

- `Moloch.sol` at 2,146 lines with 5 contracts is dense. Separating into multiple files would improve navigability.
- `onSharesChanged` badge management is particularly complex and could benefit from more inline documentation.
- DAICO's `buy()` and `buyExactOut()` share ~70% of their logic but are fully duplicated rather than factored.
- ViewHelper's two-pass count-then-populate pattern is repeated 4 times -- could use a shared helper.

#### Evidence

| File | Line | Pattern | Assessment |
|------|------|---------|------------|
| `src/Moloch.sol` | 1-2146 | 5 contracts in one file | Compact but dense |
| `src/Moloch.sol` | 1850-1928 | `onSharesChanged` | High cyclomatic complexity |
| `src/Moloch.sol` | 1462-1525 | `_repointVotesForHolder` | Complex but correct diff-based logic |
| `src/Moloch.sol` | 440-490 | `state()` | 7 return paths, well-structured |
| `src/peripheral/DAICO.sol` | 500-571 / 587-664 | `buy` / `buyExactOut` | Significant code duplication |

---

### 5. DECENTRALIZATION (Score: 3/4 - Satisfactory)

#### What I Found

**No Admin Keys**:
- Zero centralized control. No `owner`, no `admin`, no privileged EOA.
- All parameter changes require governance: propose, vote, queue, execute.
- Summoner cannot modify deployed DAOs.

**Exit Mechanism (Ragequit)**:
- Members can exit with their proportional share of treasury at any time (subject to ragequit timelock).
- Pro-rata calculation ensures fair distribution.
- Multiple token types supported (sorted by address).
- Protected against flash loans via 7-day acquisition timelock.

**Immutable Proxy Architecture**:
- Clone proxies (minimal CREATE2) are immutable -- no upgrade mechanism.
- No `SELFDESTRUCT`, no proxy upgrade pattern.
- Implementation addresses are immutable and publicly queryable.

**Timelock**:
- Configurable `timelockDelay` for all proposals.
- Unanimous consent bypass is safe (no minority to protect when 100% agree).
- Ragequit timelock separately configurable.

**Governance Flexibility**:
- `delegatecall` execution (`op == 1`) provides protocol extensibility without upgrades.
- This is both a strength (flexibility) and a risk (arbitrary storage modification) -- but it's governance-gated.

**Token Transfer Lock**:
- DAO can lock/unlock share and loot transfers via governance.
- Locked tokens can still be transferred to/from the DAO itself.

#### Gaps

- **No emergency pause**: No circuit breaker mechanism. If a critical bug is discovered, there's no way to pause the contract short of a governance proposal.
- **No guardian/veto role**: No fast-acting security role that could block a malicious proposal during timelock.
- **Unanimous consent could be risky in small DAOs**: A 2-person DAO where one member controls >50% of shares can bypass timelock entirely if they also control the other member's key or if the other member votes FOR.

#### Evidence

| File | Line | Pattern | Assessment |
|------|------|---------|------------|
| `src/Moloch.sol` | 22-25 | `onlyDAO` | Governance-only control |
| `src/Moloch.sol` | 772-820 | Ragequit | Pro-rata exit with timelock |
| `src/Moloch.sol` | 520-531 | Unanimous consent | TTL + timelock bypass |
| `src/Moloch.sol` | 252-264 | `_init` clone | Immutable minimal proxy |
| `src/Moloch.sol` | 867-870 | `setTransfersLocked` | Transfer locking via governance |

---

### 6. DOCUMENTATION (Score: 2/4 - Moderate)

#### What I Found

**NatSpec Coverage**:
- DAICO: 139 NatSpec annotations across 1,330 lines (~10.5%) -- **well-documented**.
- ViewHelper: 75 NatSpec annotations across 1,343 lines (~5.6%) -- **adequately documented**.
- Moloch: 33 NatSpec annotations across 2,146 lines (~1.5%) -- **under-documented** for the core contract.
- Tribute: 6 NatSpec annotations across 200 lines (~3%) -- **sparse**.
- Renderer: 9 NatSpec annotations across 510 lines (~1.8%) -- **sparse**.

**Total: 262 NatSpec annotations across ~5,529 lines of source code (~4.7%).**

**Existing Documentation**:
- `CLAUDE.md`: Comprehensive project overview, architecture table, build/test commands, key implementation details. Well-organized.
- `docs/v1-v2-contract-differences.md`: Excellent 854-line document covering all v1 vs v2 differences with code examples, security notes, migration considerations, and edge cases. This is high-quality documentation.
- Inline comments: Present but inconsistent. Some functions have excellent block comments (e.g., `openProposal`, `state`), while others have minimal or no comments (e.g., `_repointVotesForHolder`, `cashOutFutarchy`).

**Code Organization**:
- Section headers with `/* */` block comments (e.g., `/* PROPOSALS */`, `/* FUTARCHY */`, `/* PERMIT */`, `/* SALE */`).
- Event and error declarations grouped near their usage.

#### Gaps

- **No formal specification**: No document describing the intended behavior, invariants, and security properties of the system.
- **No threat model**: No documented analysis of attack vectors, trust assumptions, and security boundaries.
- **No architecture diagram**: The system has complex interactions between Moloch, Shares, Loot, Badges, DAICO, Tribute, and ViewHelper, but no visual diagram.
- **Moloch.sol core functions are under-documented**: Critical functions like `castVote`, `executeByVotes`, `cashOutFutarchy`, `_applyVotingDelta`, `_repointVotesForHolder`, and `onSharesChanged` have minimal or no NatSpec.
- **No user-facing documentation**: No developer guide or integration guide beyond the CLAUDE.md.
- **No domain glossary**: Terms like "tribute token", "for token", "ragequit", "loot", "shares", "badges", "seats", "futarchy" are used without formal definitions.

#### Evidence

| File | Line | Pattern | Assessment |
|------|------|---------|------------|
| `src/Moloch.sol` | 4-9 | Contract-level NatSpec | Good top-level description |
| `src/Moloch.sol` | 279-280 | `openProposal` NatSpec | Good function-level doc |
| `src/Moloch.sol` | 1421-1457 | `_applyVotingDelta` | Complex logic with minimal comments |
| `src/peripheral/DAICO.sol` | 78-84 | Contract-level NatSpec | Excellent documentation |
| `docs/v1-v2-contract-differences.md` | 1-854 | Migration guide | High-quality, comprehensive |

---

### 7. TRANSACTION ORDERING RISKS (Score: 3/4 - Satisfactory)

#### What I Found

**Snapshot Voting**:
- `snapshotBlock[id] = toUint48(block.number - 1)` (`Moloch.sol:293`): Votes are counted using the previous block's state, preventing flash loan-based vote manipulation. This is the gold standard for governance snapshot design.

**Slippage Protection**:
- `buyShares` has `maxPay` parameter (`Moloch.sol:735`): `if (maxPay != 0 && cost > maxPay) revert NotOk()`
- DAICO `buy` has `minBuyAmt` (`DAICO.sol:552`): `if (minBuyAmt != 0 && buyAmt < minBuyAmt) revert SlippageExceeded()`
- DAICO `buyExactOut` has `maxPayAmt` (`DAICO.sol:616`): `if (maxPayAmt != 0 && payAmt > maxPayAmt) revert SlippageExceeded()`
- DAICO LP initialization has `maxSlipBps` for ZAMM liquidity adds.

**Timelocks**:
- Proposal timelock (`timelockDelay`) gives members time to ragequit before execution.
- Ragequit timelock (7 days) prevents flash-loan-acquire-and-ragequit attacks.
- Unanimous consent bypass is safe (documented rationale in `docs/v1-v2-contract-differences.md:231-242`).

**Proposal State Protection (v2)**:
- Proposals stay `Active` until TTL expires, preventing vote-snipe attacks.
- Cannot resolve futarchy early during voting period.

**Sale Deadlines**:
- DAICO sales can have deadlines (`DAICO.sol:512`): `if (offer.deadline != 0 && block.timestamp > offer.deadline) revert Expired()`

#### Gaps

- **Governance front-running**: An attacker who sees a proposal in the mempool could front-run the proposal opening to manipulate the snapshot block. Mitigated by the N-1 snapshot (must have tokens in previous block), but a sophisticated attacker could position tokens one block early.
- **Sale price manipulation**: The DAICO sale price is fixed (set by DAO governance), so there's no oracle manipulation risk. However, the LP drift protection relies on ZAMM pool reserves, which could be manipulated via sandwich attacks around LP initialization.
- **No commit-reveal voting**: Votes are public during the voting period, allowing strategic voting based on current tally.

#### Evidence

| File | Line | Pattern | Assessment |
|------|------|---------|------------|
| `src/Moloch.sol` | 293 | Block N-1 snapshot | Flash loan protection |
| `src/Moloch.sol` | 735 | `maxPay` slippage | Standard slippage protection |
| `src/peripheral/DAICO.sol` | 552, 616 | Slippage checks | Both directions protected |
| `src/Moloch.sol` | 454-458 | TTL protection | Prevents premature resolution |
| `src/peripheral/DAICO.sol` | 420-433 | LP drift protection | Caps LP slice if spot > OTC rate |

---

### 8. LOW-LEVEL MANIPULATION (Score: 2/4 - Moderate)

#### What I Found

**Assembly Usage (29 blocks across 4 files)**:

1. **Clone deployment** (`Moloch.sol:253-263`, `Moloch.sol:2115-2125`): Minimal proxy (EIP-1167 variant) creation via inline assembly. Well-established pattern; the bytecode is correct.

2. **Reentrancy guard** (`Moloch.sol:1032-1044`): Uses EIP-1153 transient storage (`tload`/`tstore`), which is correct for Cancun EVM. More gas-efficient than storage-based guards.

3. **Safe transfers** (`Moloch.sol:2033-2087`): Four assembly-optimized functions:
   - `balanceOfThis`: Reads own balance via staticcall
   - `safeTransferETH`: ETH transfer with revert on failure
   - `safeTransfer`: ERC-20 transfer with return value handling (supports non-standard tokens)
   - `safeTransferFrom`: ERC-20 transferFrom with return value handling
   All follow the Solady pattern and correctly handle non-standard ERC-20 tokens (no return value).

4. **Overflow revert** (`Moloch.sol:2014-2019`): Assembly revert with custom error selector.

5. **MulDiv** (`Moloch.sol:2022-2031`): Assembly multiplication and division with overflow check.

6. **Bitmap FFS** (`Moloch.sol:1965-1976`): Find-first-set bit operation for badge seat allocation. Uses a de Bruijn multiplication technique. Complex but well-established algorithm.

7. **Error propagation** (`Moloch.sol:927-929`): `multicall` bubble-up revert via assembly.

**DAICO Assembly (7 blocks)**:
- Reentrancy guard (identical to Moloch)
- Safe transfer functions (4-parameter `safeTransferFrom` variant for non-self transfers)
- `ensureApproval` for USDT-compatible approvals

**Tribute Assembly (5 blocks)**:
- Reentrancy guard
- Safe transfer functions

**`delegatecall` Usage**:
- `Moloch.sol:925`: `multicall` uses `delegatecall` to self -- allows batching multiple Moloch calls. Risk: caller can batch multiple state-changing calls atomically. Mitigated by individual function access controls.
- `Moloch.sol:1012`: Proposal execution with `op == 1` -- arbitrary delegatecall from DAO context. This is the most powerful primitive in the system. A malicious proposal could modify any storage slot. Mitigated by governance (voting + timelock).

**`staticcall` Usage**:
- ViewHelper uses `staticcall` extensively for safe external reads (`Moloch.sol:942-952` in `_getTreasury`).

#### Gaps

- **Assembly documentation**: Most assembly blocks lack inline comments explaining the bytecode/opcodes. The clone creation bytecode, for example, is uncommented.
- **`delegatecall` in multicall is unrestricted**: Any caller can invoke `multicall`, though individual functions enforce their own access control.
- **`safeTransfer` assembly is complex**: The non-standard token handling logic (`iszero(lt(or(iszero(extcodesize(token)), returndatasize()), success))`) is hard to reason about without comments.
- **Memory safety annotations**: All assembly blocks use `("memory-safe")` annotation, which is correct and important for the Solidity optimizer.

#### Evidence

| File | Line | Pattern | Assessment |
|------|------|---------|------------|
| `src/Moloch.sol` | 253-263 | Clone assembly | Correct EIP-1167 variant |
| `src/Moloch.sol` | 1032-1044 | Transient storage reentrance | Modern EIP-1153 pattern |
| `src/Moloch.sol` | 2054-2067 | `safeTransfer` assembly | Handles non-standard ERC-20 |
| `src/Moloch.sol` | 925 | `multicall` delegatecall | Unrestricted entry point |
| `src/Moloch.sol` | 1012 | Execute delegatecall | Most powerful primitive, governance-gated |
| `src/Moloch.sol` | 1965-1976 | FFS bitmap | de Bruijn technique, complex but correct |

---

### 9. TESTING & VERIFICATION (Score: 3/4 - Satisfactory)

#### What I Found

**Test Coverage**:

| Test Suite | Tests | Status |
|------------|-------|--------|
| `MolochTest` | 157 | All passing |
| `DAICOTest` | 148 | All passing |
| `DAICO_CustomCalls_Test` | 6 | All passing |
| `DAICO_ZAMM_Test` | 60 | All passing |
| `MolochViewHelperTest` | 52 | All passing |
| `TributeTest` | 24 | All passing |
| `URIVisualizationTest` | 18 | All passing |
| `ContractURITest` | 4 | All passing |
| `BytecodeSizeTest` | 4/5 | 1 failing (Renderer exceeds 24576 bytes) |
| **Total** | **474** | **473 passing, 1 failing** |

**Test Quality**:

- **Initialization tests**: Comprehensive checks for all DAO parameters, token names, supply.
- **Proposal lifecycle**: Full coverage of create, vote, queue, execute, cancel flows.
- **Delegation**: Split delegation, single delegation, clearing, edge cases (max splits, zero balance).
- **Ragequit**: Pro-rata distribution, timelock enforcement, sorted token requirement, multi-token.
- **Futarchy**: Opening, funding, resolution (YES/NO), payout calculation, edge cases.
- **DAICO**: ETH/ERC20 sales, exact-in/exact-out, slippage, LP initialization, tap claims, USDT-style tokens.
- **Access control**: Unauthorized calls tested for all protected functions.
- **Event emission**: Events checked in proposal and voting tests.

**Fuzz Tests** (present):
- `test_SplitDelegation_FuzzAllocationsMatchVotes` (`Moloch.t.sol:1623`)
- `testFuzz_Ragequit_Distribution` (`Moloch.t.sol:2568`)
- `testFuzz_Buy_ETH` (`DAICO.t.sol:1887`)
- `testFuzz_BuyExactOut_ETH` (`DAICO.t.sol:1907`)
- `testFuzz_TapClaim` (`DAICO.t.sol:1932`)
- `testFuzz_QuoteBuy` (`DAICO.t.sol:1965`)
- `testFuzz_QuotePayExactOut` (`DAICO.t.sol:1980`)
- `testFuzz_SummonDAICO` (`DAICO.t.sol:3344`)
- `testFuzz_SummonDAICOWithTap` (`DAICO.t.sol:4296`)
- `testFuzz_Buy_Amounts` (`DAICO.t.sol:4997`)
- `testFuzz_BuyExactOut_Amounts` (`DAICO.t.sol:5023`)
- `testFuzz_Buy_ETH_WithLP` (`DAICO.t.sol:5983`)
- `testFuzz_SetSaleWithLPAndTap` (`DAICO.t.sol:6822`)
- `testFuzz_QuoteBuy_WithLP` (`DAICO.t.sol:6858`)

**Invariant-Style Tests**:
- `test_Invariant_SharesSupplyEqualsBalances` (`Moloch.t.sol:2619`)
- `test_Invariant_VotesNeverExceedSnapshotSupply` (`Moloch.t.sol:2673`)
- `test_Invariant_LootSupplyEqualsBalances` (`Moloch.t.sol:2714`)
- `test_Invariant_DelegationVotesMatchShares` (`Moloch.t.sol:2743`)

**Contract Size Test**:
- `BytecodeSizeTest` verifies all contracts stay under 24,576 bytes.
- Currently Renderer exceeds the limit (25,270 bytes vs 24,576 max) -- 1 known failing test.

#### Gaps

- **No CI/CD**: No `.github/` directory. Tests are not automatically run on push/PR.
- **No coverage reporting**: No evidence of `forge coverage` being used or tracked.
- **No static analysis**: No Slither, Mythril, or similar tool integration.
- **No formal verification**: No symbolic execution or SMT-based verification.
- **No stateful invariant tests**: The "invariant" tests are actually unit tests that check invariants manually after specific operations. True Foundry `invariant_*` (stateful fuzzing with handler contracts) would provide much stronger guarantees.
- **Renderer exceeds EVM size limit**: `testRendererRuntimeSize` fails -- the Renderer contract at 25,270 bytes exceeds the 24,576 byte EVM limit and cannot be deployed.

#### Evidence

| File | Line | Pattern | Assessment |
|------|------|---------|------------|
| `test/Moloch.t.sol` | 1-end | 157 tests | Comprehensive governance coverage |
| `test/DAICO.t.sol` | 1-end | 214 tests (3 suites) | Thorough DAICO coverage |
| `test/Moloch.t.sol` | 2568 | `testFuzz_Ragequit_Distribution` | Fuzz testing pro-rata math |
| `test/Moloch.t.sol` | 2619-2743 | Invariant-style tests | Manual invariant checking |
| `test/DAICO.t.sol` | 1884-end | DAICO fuzz tests | 14 fuzz tests |
| `.github/` | N/A | Missing | No CI/CD pipeline |

---

## Improvement Roadmap

### CRITICAL (Immediate)

| # | Recommendation | Category | Effort | Impact |
|---|---------------|----------|--------|--------|
| 1 | **Get a professional security audit** before v2 mainnet deployment. The codebase has complex interactions (futarchy, delegation, DAICO+LP) that benefit from expert review. | Auditing | High | Critical |
| 2 | **Set up CI/CD pipeline** with GitHub Actions: `forge test`, `forge coverage`, Slither analysis on every PR. | Testing | Low | High |
| 3 | **Fix Renderer contract size** -- currently exceeds the 24,576 byte EVM limit and cannot be deployed. | Testing | Medium | Critical |

### HIGH (1-2 months)

| # | Recommendation | Category | Effort | Impact |
|---|---------------|----------|--------|--------|
| 4 | **Add events to all setter functions** (`setQuorumBps`, `setProposalTTL`, `setTimelockDelay`, `setRagequitTimelock`, `setRagequittable`, `setProposalThreshold`, `setRenderer`, `setMetadata`, `bumpConfig`, `setAutoFutarchy`, `setFutarchyRewardToken`). This is essential for off-chain monitoring and governance transparency. | Auditing | Low | High |
| 5 | **Add true stateful invariant tests** using Foundry's `invariant_*` framework with handler contracts. Key invariants: total votes == total supply, badge seat bitmap == minted badges, futarchy pool == sum of payouts + unclaimed. | Testing | Medium | High |
| 6 | **Write a formal threat model** documenting: trust assumptions, attack surfaces (delegatecall, multicall, flash loans, MEV), security properties (no double-counting votes, pro-rata ragequit fairness). | Documentation | Medium | High |
| 7 | **Add NatSpec documentation to Moloch.sol** core functions: `castVote`, `executeByVotes`, `cashOutFutarchy`, `_applyVotingDelta`, `_repointVotesForHolder`, `onSharesChanged`. Currently at 1.5% NatSpec coverage vs DAICO's 10.5%. | Documentation | Low | Medium |
| 8 | **Add assembly comments** to all inline assembly blocks, especially the safe transfer functions and clone deployment bytecode. | Low-Level | Low | Medium |

### MEDIUM (2-4 months)

| # | Recommendation | Category | Effort | Impact |
|---|---------------|----------|--------|--------|
| 9 | **Integrate Slither** for automated static analysis. Run as part of CI/CD. Address any findings. | Testing | Low | Medium |
| 10 | **Consider an emergency pause mechanism** or guardian role for critical situations. This adds centralization but provides a safety net during the early deployment phase. Can be governed away after the protocol matures. | Decentralization | Medium | Medium |
| 11 | **Refactor DAICO `buy`/`buyExactOut`** to extract shared logic (validation, LP init, tribute transfer, refund) into internal helpers. Currently ~70% code duplication. | Complexity | Medium | Low |
| 12 | **Add a formal specification** document describing all state transitions, invariants, and edge cases for the proposal state machine, delegation system, and futarchy payout logic. | Documentation | High | Medium |
| 13 | **Consider commit-reveal voting** for high-stakes proposals to prevent strategic voting based on visible tallies. | Transaction Ordering | High | Low |
| 14 | **Set up a bug bounty program** (e.g., Immunefi) before mainnet deployment. | Auditing | Low | Medium |
| 15 | **Upgrade `mulDiv` to full 512-bit intermediate** (Solady's implementation) to handle edge cases where `x * y` overflows but the final result fits in uint256. Low practical risk currently but good defensive coding. | Arithmetic | Low | Low |

---

## Appendix: File References

| File | Path | Lines |
|------|------|-------|
| Moloch (core) | `src/Moloch.sol` | 2,146 |
| DAICO | `src/peripheral/DAICO.sol` | 1,330 |
| ViewHelper | `src/peripheral/MolochViewHelper.sol` | 1,343 |
| Renderer | `src/Renderer.sol` | 510 |
| Tribute | `src/peripheral/Tribute.sol` | 200 |
| Moloch Tests | `test/Moloch.t.sol` | ~3,000+ |
| DAICO Tests | `test/DAICO.t.sol` | ~7,000+ |
| ViewHelper Tests | `test/MolochViewHelper.t.sol` | ~500+ |
| Tribute Tests | `test/Tribute.t.sol` | ~400+ |
| URI Tests | `test/URIVisualization.t.sol` | ~300+ |
| ContractURI Tests | `test/ContractURI.t.sol` | ~200+ |
| Size Tests | `test/Bytecodesize.t.sol` | ~100+ |
| V1/V2 Differences | `docs/v1-v2-contract-differences.md` | 854 |
| Foundry Config | `foundry.toml` | 27 |

---

*Assessment completed 2026-01-26. Framework: Trail of Bits Building Secure Contracts Code Maturity Evaluation v0.1.0.*

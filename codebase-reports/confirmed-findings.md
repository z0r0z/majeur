# Confirmed Security Findings -- Majeur

**Date:** 2026-01-27
**Sources:** Trail of Bits Code Maturity Assessment + Guidelines Advisor Report
**Verification:** All findings below were verified against the codebase by automated code inspection (Opus 4.5). Erroneous claims from both source reports have been excluded. Line numbers and statistics have been corrected where the source reports were inaccurate.
**Codebase:** Majeur v2 (`everything` branch, commit `786a72f`)
**Compiler:** Solidity 0.8.33, EVM Cancun, via_ir=true, optimizer_runs=500

---

## Corrected Maturity Scorecard

The Code Maturity Assessment originally scored the project at 2.9/4.0 with Arithmetic=2 and Testing=2, based on the erroneous claim that "zero fuzz tests or invariant tests exist." Verification found **14 fuzz test functions** and **4 invariant-checking unit tests**. The corrected scorecard:

| # | Category | Original Score | Corrected Score | Rating | Correction Notes |
|---|----------|---------------|----------------|--------|-----------------|
| 1 | Arithmetic | 2 | **3** | Satisfactory | Custom `mulDiv` with overflow check, 14 fuzz tests cover ragequit pro-rata, split delegation, and DAICO pricing. Heavy `unchecked` usage (36 blocks) still lacks `// SAFETY:` justification comments. |
| 2 | Auditing (Events/Monitoring) | 3 | 3 | Satisfactory | No correction needed. Comprehensive v2 events with indexed params, 14+ dedicated emission tests. |
| 3 | Authentication / Access Controls | 4 | 4 | Strong | No correction needed. `onlyDAO` on all setters, DAO self-vote prevention, no admin keys. |
| 4 | Complexity Management | 3 | 3 | Satisfactory | No correction needed. Monolith Moloch.sol (2,251 lines) but logically partitioned. |
| 5 | Decentralization | 3 | 3 | Satisfactory | No correction needed. Full DAO governance, ragequit exit, no upgradeability. |
| 6 | Documentation | 3 | 3 | Satisfactory | No correction needed. README (885 lines), v1-v2 diff doc (1,008 lines). |
| 7 | Transaction Ordering / MEV | 3 | 3 | Satisfactory | No correction needed. Snapshot at block N-1, ragequit timelock, slippage bounds. |
| 8 | Low-Level Manipulation | 3 | 3 | Satisfactory | No correction needed. Assembly is well-scoped with `memory-safe`, Solady patterns. |
| 9 | Testing & Verification | 2 | **3** | Satisfactory | 499 tests (not 475) including 14 fuzz tests, 4 invariant-checking tests, 11 bytecode size tests. Slither has been run (output at `codebase-reports/slither-raw.txt`), though not integrated into CI. |
| | **OVERALL** | **2.9** | **3.1** | **Satisfactory** | Two category corrections (Arithmetic 2->3, Testing 2->3) |

### Corrected Statistics

| Metric | Original (Erroneous) | Corrected (Verified) |
|--------|---------------------|---------------------|
| Total tests | 475 | **499** |
| Fuzz tests | 0 | **14** |
| Invariant-style tests | 0 | **4** (manual, not Foundry-native stateful) |
| Bytecodesize.t.sol tests | 0 | **11** |
| `unchecked` blocks in src/ | "over 15" | **36** (30 in Moloch.sol, 4 in DAICO.sol, 2 in Tribute.sol) |
| Total unchecked blocks (full count) | not stated | **44** (adds MolochViewHelper:2, CovenantRenderer:1, Display.sol:5) |
| Events defined | 35 | **41** unique (45 total declarations) |
| README lines | 886 | **885** |
| v1-v2 diff doc lines | 1,009 / 763 (conflicting) | **1,008** |
| Test lines | ~14,200 | **15,460** |
| Test/source ratio | 2.3x | **2.48x** |

---

## Confirmed Findings by Severity

### CRITICAL

**C-2: Delegatecall execution via governance can corrupt storage**
- **Location:** `src/Moloch.sol:1105-1115`, specifically `op=1` path at line 1112
- **Code:**
  ```solidity
  function _execute(uint8 op, address to, uint256 value, bytes calldata data)
      internal returns (bool ok, bytes memory retData) {
      if (op == 0) {
          (ok, retData) = to.call{value: value}(data);
      } else {
          (ok, retData) = to.delegatecall(data);
      }
  ```
- **Issue:** Proposals with `op=1` execute arbitrary delegatecalls from the Moloch contract's context. A malicious (or buggy) target contract could overwrite any storage slot in the Moloch contract, including critical governance parameters, token references, and proposal state. A single governance proposal with delegatecall to a malicious target could steal the entire treasury, modify quorum settings, mint unlimited shares, etc.
- **Assessment:** This is **by design** for maximum governance flexibility (allows installing "modules" or complex state changes). The attack requires passing a full governance vote and surviving the timelock period, which provides significant protection. Test `test_DelegateCallExecution` at `test/Moloch.t.sol:1192` exercises this path.
- **Recommendation:** Consider adding a governance-configurable allowlist of delegatecall targets, or at minimum, document this risk prominently and ensure frontends clearly warn when proposals use `op=1`.

> **Note on excluded C-1:** The Guidelines Advisor report flagged `multicall` + `msg.value` double-spend on `fundFutarchy` as CRITICAL. This is **not exploitable** because `multicall` (line 1022) is **not payable**, so it cannot be called with `msg.value > 0`. The double-spend scenario is impossible. Additionally, `fundFutarchy` does NOT have `nonReentrant` (the report's stated mitigation was also wrong). Downgraded to INFORMATIONAL.

---

### HIGH

**H-1: No formal specification for state machine transitions**
- **Location:** `src/Moloch.sol:465-515` (`state()` function)
- **Issue:** The 7-state proposal state machine (Unopened, Active, Queued, Succeeded, Defeated, Expired, Executed) is implemented in code but not formally specified. Edge cases like unanimous consent bypass (line 481), zero-TTL proposals, and the interaction between `queue()` and `executeByVotes()` are complex. NatSpec at lines 459-464 and `CLAUDE.md` serve as informal docs but no standalone specification exists.
- **Recommendation:** Create a formal state transition diagram with all preconditions and postconditions for each transition, reviewable independently from the code.

**H-2: Unbounded `proposalIds` array**
- **Location:** `src/Moloch.sol:73` (declaration), line 319 (push in `openProposal`)
- **Issue:** `proposalIds` grows without bound. No pruning or archival mechanism exists. Over time, this makes the ViewHelper's `getProposalCount()` and `_getProposals()` more expensive. ViewHelper's `_getProposals` at line 766 paginates, mitigating RPC timeout risk, but the array itself is unbounded.
- **Recommendation:** Document the expected growth rate and gas implications. Pagination in ViewHelper already exists and mitigates the read-side concern.

**H-3: Missing static analysis in CI**
- **Location:** `.github/workflows/ci.yml` (28 lines)
- **Issue:** The CI pipeline runs `forge build`, `forge test -vvv`, and `biome lint dapp` but no static analysis tools. Slither has been run locally (output at `codebase-reports/slither-raw.txt`) but is not integrated into CI. No Mythril, Echidna, Medusa, Certora, or Halmos configuration exists.
- **Recommendation:** Add `slither .` to the CI pipeline. Slither can catch common vulnerability patterns and would complement the existing test suite.

**H-4: `ragequit` token array has no length bound**
- **Location:** `src/Moloch.sol:828-876`
- **Issue:** A user can pass an arbitrarily long token array to `ragequit`. Each token requires an external call (`balanceOfThis` or `address.balance`) and potentially an ERC-20 transfer. The ascending-sort requirement (line 865) prevents duplicates but does not limit array size. With enough tokens, this could hit the block gas limit.
- **Recommendation:** Consider adding a maximum token count (e.g., 50) to prevent gas-griefing, or document the practical limit based on gas costs.

---

### MEDIUM

**M-1: Tally fields are `uint96`, limiting max supply to ~79 billion tokens**
- **Location:** `src/Moloch.sol:66-70` (Tally struct), lines 397-404 (unchecked accumulation)
- **Code:**
  ```solidity
  struct Tally {
      uint96 forVotes;
      uint96 againstVotes;
      uint96 abstainVotes;
      ...
  }
  ```
- **Issue:** Tally accumulation is `unchecked`. If total share supply exceeds `type(uint96).max` (~79.2e27 wei = ~79.2 billion tokens at 18 decimals), tally overflow would produce incorrect vote counts. The `toUint96` cast at line 392 ensures individual `weight` fits in uint96, but the accumulation across multiple voters is unchecked.
- **Recommendation:** Document the maximum supported supply. At 18 decimals, 79 billion tokens is large, but unbounded minting via governance could theoretically exceed this.

**M-2: Tribute discovery arrays grow without bound**
- **Location:** `src/peripheral/Tribute.sol:53` (`daoTributeRefs`), line 56 (`proposerTributeRefs`)
- **Issue:** `daoTributeRefs` and `proposerTributeRefs` are append-only. Cancelled or claimed tributes remain in the arrays (only the main `tributes` mapping is deleted). The `getActiveDaoTributes` function (line 183) iterates the entire array in two passes (lines 188-219), creating O(n) gas growth over time.
- **Recommendation:** Consider a cleanup mechanism, or switch to a mapping-based structure with an explicit count.

**M-3: `ensureApproval` grants `type(uint256).max` approval to ZAMM**
- **Location:** `src/peripheral/DAICO.sol:1400-1425`
- **Issue:** The DAICO contract checks allowance against `type(uint128).max` threshold and approves `not(0)` (type(uint256).max) to the hardcoded ZAMM address (line 76: `0x000000000000040470635EB91b7CE4D132D616eD`). If ZAMM is compromised, it could drain all tokens the DAICO contract has received. LP operations are optional (only activated when `lpBps > 0`).
- **Recommendation:** Consider exact-amount approvals instead of infinite approvals, or document the ZAMM trust assumption prominently.

**M-4: Clone initialization front-running (non-exploitable)**
- **Location:** `src/Moloch.sol:1248-1257` (Shares.init), lines 1767-1769 (Loot.init), lines 1865-1867 (Badges.init)
- **Code:**
  ```solidity
  require(DAO == address(0), Unauthorized());
  DAO = payable(msg.sender);
  ```
- **Issue:** Implementation contracts check `require(DAO == address(0))` for one-time initialization. The implementation contracts themselves can be initialized by anyone (first caller sets `DAO`). Since clones have their own storage, this does not affect deployed DAOs. The Moloch implementation uses `require(msg.sender == SUMMONER)` (line 234), not an `initialized` flag.
- **Assessment:** Confirmed but correctly assessed as **non-exploitable** -- implementations are only used as templates for cloning.
- **Recommendation:** Consider adding a constructor that sets `DAO` to a dead address in implementation contracts, preventing external initialization.

**M-5: No access control on `queue()` function**
- **Location:** `src/Moloch.sol:518-525`
- **Issue:** Anyone can call `queue()` to start the timelock countdown on a Succeeded proposal. This is by design (permissionless queueing), but in combination with a short `timelockDelay`, an attacker could front-run the proposer to start the countdown earlier than intended.
- **Recommendation:** Document this as intentional (anyone can queue a passing proposal).

---

### LOW

**L-1: Duplicated safe transfer functions across contracts**
- **Locations:**
  - `safeTransferETH`: Moloch.sol:2151, DAICO.sol:1350, Tribute.sol:239
  - `safeTransfer`: Moloch.sol:2160, DAICO.sol:1359, Tribute.sol:248
  - `safeTransferFrom`: Moloch.sol:2176, DAICO.sol:1375, Tribute.sol:264
  - `balanceOfThis`: Moloch.sol:2140, DAICO.sol:1339
- **Issue:** Identical assembly-based token transfer functions are duplicated across three contract files. A bug fix in one file might not be applied to others. Note: `safeTransferFrom` signatures differ intentionally -- Moloch takes `(token, amount)`, DAICO takes `(token, from, to, amount)`, Tribute takes `(token, to, amount)`.
- **Recommendation:** Consider extracting shared utilities into a library, or add cross-reference comments in each copy.

**L-2: `_ffs` magic constants lack documentation**
- **Location:** `src/Moloch.sol:2071-2082`
- **Issue:** The find-first-set function uses De Bruijn multiplication technique with opaque magic constants for O(1) bit position lookup. Verified correct by 258+ tests (`test/Moloch.t.sol:3777-3799` covering all 256 single-bit positions, zero input, and multi-bit inputs), but the algorithm source is not documented.
- **Recommendation:** Add a comment referencing the De Bruijn bit isolation technique.

**L-3: No `forge coverage` in CI**
- **Location:** `.github/workflows/ci.yml`
- **Issue:** Code coverage is not measured or tracked. While the test/source ratio is 2.48x, specific functions may have untested paths. Also missing: `forge snapshot` for gas regression testing.
- **Recommendation:** Add `forge coverage` to CI and set minimum coverage thresholds.

**L-4: `safeTransfer` ERC-20 compatibility limitations**
- **Location:** `src/Moloch.sol:2160-2174`, `src/peripheral/DAICO.sol:1395-1425`
- **Issue:** The safe transfer implementation handles void-return and bool-return tokens (Solady-style). DAICO's `ensureApproval` handles USDT-style tokens via allowance threshold check. However, fee-on-transfer tokens would break ragequit pro-rata calculations since `mulDiv(pool, amt, total)` computes expected amounts but actual received amounts would differ.
- **Recommendation:** Document which ERC-20 token behaviors are supported and which are not (e.g., fee-on-transfer, rebasing tokens).

**L-5: `getSeats()` popcount has unnecessary double loop**
- **Location:** `src/Moloch.sol:1934-1952`
- **Issue:** `getSeats()` iterates the occupied bitmap twice: first loop (lines 1938-1942) counts set bits using `m &= (m - 1)` but discards the positions, second loop (lines 1944-1950) re-iterates to extract positions. A single-pass approach would be more efficient.
- **Recommendation:** Minor gas optimization opportunity for a view function; low priority.

**L-6: `buyShares` CEI pattern has ETH refund before share minting**
- **Location:** `src/Moloch.sol:795-799` (refund), lines 808-816 (minting)
- **Issue:** In the ETH payment path, excess ETH is refunded via `safeTransferETH(msg.sender, msg.value - cost)` before share minting. The comment at line 786 says "EFFECTS (CEI)" but actual order is Check-Effect-Interaction-Effect. The `nonReentrant` guard (line 772) makes this safe, but without it, the refund before share issuance would be a reentrancy vector.
- **Recommendation:** No action needed since `nonReentrant` is in place. Consider correcting the CEI comment for accuracy.

---

## Confirmed Improvement Recommendations

Ordered by priority, reflecting corrected assessment (fuzz tests exist but can be expanded):

### CRITICAL Priority (Before Production v2 Deployment)

| # | Recommendation | Category | Effort | Notes |
|---|---------------|----------|--------|-------|
| 1 | **Professional security audit** before v2 mainnet deployment | All | External | The codebase is marked "unaudited" (README line 882). Complex interactions between futarchy, delegation, DAICO+LP, and ragequit benefit from expert review. |
| 2 | **Expand fuzz testing** to cover futarchy payout (`mulDiv(amount, payoutPerUnit, 1e18)`) and vote tally accumulation. Existing 14 fuzz tests cover ragequit and DAICO but not futarchy. | Testing | 1-2 days | Corrected: fuzz tests exist but don't yet cover all arithmetic paths. |
| 3 | **Add Foundry-native stateful invariant tests** (`invariant_*` with Handler contracts) for total supply consistency, voting power conservation, and ragequit proportionality | Testing | 2-3 days | Existing 4 invariant-checking tests are manual unit tests, not stateful fuzzers. |

### HIGH Priority

| # | Recommendation | Category | Effort |
|---|---------------|----------|--------|
| 4 | **Integrate Slither into CI** -- output exists locally but is not part of the CI pipeline | Testing | 0.5 days |
| 5 | **Document all `unchecked` blocks** with `// SAFETY: <reason>` comments (36 blocks, priority: ragequit line 833, tallies line 397, ERC-6909 lines 1074-1088, checkpoints line 1344, token mint line 1311) | Arithmetic | 1-2 days |
| 6 | **Add coverage reporting to CI** (`forge coverage`) and enforce minimum threshold | Testing | 0.5 days |
| 7 | **Add gas snapshot regression** (`forge snapshot --check`) -- ViewHelper is near the 24,576-byte EVM limit at ~24,392 bytes | Testing | 0.5 days |
| 8 | **Add ragequit-disable cooldown** -- currently `setRagequittable(false)` takes effect immediately. A mandatory waiting period would prevent same-timelock-window ragequit-disable + value-extraction attacks | Decentralization | 1-2 days |
| 9 | **Create formal state machine specification** for the 7-state proposal lifecycle including unanimous consent bypass, zero-TTL behavior, and queue/execute interaction | Documentation | 1-2 days |

### MEDIUM Priority

| # | Recommendation | Category | Effort |
|---|---------------|----------|--------|
| 10 | **Extract shared utilities** -- consolidate duplicated `nonReentrant` (Moloch:1138, DAICO:170, Tribute:224) and `safeTransfer*` into a shared library | Complexity | 1 day |
| 11 | **Write a threat model document** -- document known attack vectors, trust assumptions, security boundaries, residual risks | Documentation | 1-2 days |
| 12 | **Document system invariants** formally (e.g., "total shares == sum of all balances", "sum of delegate checkpoints == total supply") | Documentation | 1 day |
| 13 | **Formal verification for ragequit pro-rata** -- Halmos or Certora could provide mathematical guarantees for the `mulDiv(pool, amt, total)` calculation | Testing | 1 week |
| 14 | **Upgrade `mulDiv` to 512-bit intermediate** -- current implementation reverts if `x * y` exceeds 2^256 even when `x * y / d` would fit. Solady's full-precision implementation would be more robust. Low practical risk currently. | Arithmetic | 0.5 days |
| 15 | **Document max supply limitation** -- Tally `uint96` fields limit max meaningful supply to ~79 billion tokens at 18 decimals | Documentation | 0.5 days |
| 16 | **Document ERC-20 compatibility** -- fee-on-transfer and rebasing tokens would break ragequit and DAICO calculations | Documentation | 0.5 days |

---

## Confirmed Positive Observations

### Security Architecture

1. **No admin keys or privileged roles anywhere.** All state changes require `onlyDAO` governance approval (`src/Moloch.sol:22-24, 897-999`). Verified across all contracts.

2. **v2 security hardening is comprehensive:**
   - Ragequit timelock (7 days default, `src/Moloch.sol:42, 841-848`) prevents flash loan ragequit attacks
   - Snapshot at block N-1 (`src/Moloch.sol:307`) prevents same-block vote manipulation
   - DAO self-voting blocked (`src/Moloch.sol:372`) closes v1 attack vector
   - Quorum excludes DAO-held shares (`src/Moloch.sol:314-315`) prevents governance deadlocks
   - Unanimous consent bypasses timelock only at 100% FOR (`src/Moloch.sol:481, 555`)

3. **Immutable deployment model.** Summoner stores implementation as immutables (`src/Moloch.sol:2200`). ERC-1167 minimal proxy clones have fixed implementations. No UUPS, transparent proxy, or beacon proxy patterns. The only "upgradeable" component is the renderer, which is purely cosmetic.

4. **EIP-1153 transient storage reentrancy guards** (`src/Moloch.sol:1136-1150`) -- gas-efficient (~100 gas vs ~5,000+ for SSTORE-based guards), well-established pattern.

5. **No external dependencies in production.** Solady is remapped but never imported in any src/ file. ZAMM is interface-only. All utilities are self-contained.

### Testing

6. **499 tests, all passing.** Test/source ratio of 2.48x (15,460 test lines / 6,244 source lines).

7. **14 fuzz test functions** covering:
   - Ragequit pro-rata distribution (`testFuzz_Ragequit_Distribution`)
   - Split delegation BPS allocation (`test_SplitDelegation_FuzzAllocationsMatchVotes`)
   - DAICO buy/sell exact-in and exact-out with various amounts
   - Tap claiming with varying rates and elapsed time
   - Quote accuracy across parameter ranges
   - Summon parameter variations with LP and tap

8. **4 invariant-checking unit tests:**
   - `test_Invariant_SharesSupplyEqualsBalances` (Moloch.t.sol:2653)
   - `test_Invariant_VotesNeverExceedSnapshotSupply` (Moloch.t.sol:2707)
   - `test_Invariant_LootSupplyEqualsBalances` (Moloch.t.sol:2748)
   - `test_Invariant_DelegationVotesMatchShares` (Moloch.t.sol:2777)

9. **14+ dedicated event emission tests** (`test/Moloch.t.sol:3649-3774`) systematically verifying all governance events with `vm.expectEmit`.

10. **258+ `_ffs` verification tests** (`test/Moloch.t.sol:3777-3799`) covering all 256 single-bit positions, zero input, and multi-bit inputs.

11. **11 bytecode size tests** (`test/Bytecodesize.t.sol`) verifying all contracts stay under the 24,576-byte EVM limit.

### Code Quality

12. **Comprehensive event coverage** for all governance state changes. The `ConfigUpdated(bytes32 indexed param, uint256 oldValue, uint256 newValue)` pattern covers 9 scalar setters. Individual events for complex setters. Full lifecycle events for proposals, futarchy, DAICO, and tributes (41 unique events).

13. **Flat inheritance hierarchy.** Zero `is` inheritance chains. Contracts are standalone with explicit interfaces. Eliminates diamond problem, storage layout conflicts, and C3 linearization issues.

14. **Excellent v1-v2 migration documentation** (`docs/v1-v2-contract-differences.md`, 1,008 lines) covering every behavioral change with before/after code, security rationale, JavaScript examples, and deployment considerations.

15. **Strong NatSpec coverage** on Moloch.sol externals (ragequit, state, executeByVotes, castVote, openProposal, all config setters) and DAICO.sol user-facing functions with worked examples.

16. **Well-structured assembly.** All 29 assembly blocks across 4 source files use `"memory-safe"` annotation. Patterns follow established Solady-style implementations for safe transfers. Assembly usage is justified in every case (clone deployment, EIP-1153, safe transfers, math utilities, SVG string manipulation).

17. **CI pipeline exists** (`.github/workflows/ci.yml`) running `forge build`, `forge test -vvv`, and `biome lint dapp` on pushes to main/everything branches and PRs.

---

## Appendix: Key File References

| File | Lines | Purpose |
|------|-------|---------|
| `src/Moloch.sol` | 2,251 | Core: Moloch + Shares + Loot + Badges + Summoner + utilities |
| `src/peripheral/DAICO.sol` | 1,425 | Token sales + tap mechanism + LP integration |
| `src/peripheral/MolochViewHelper.sol` | 1,352 | Batch reader for dApps |
| `src/peripheral/Tribute.sol` | 281 | OTC escrow |
| `src/Renderer.sol` | 43 | Metadata router |
| `src/renderers/Display.sol` | 287 | SVG rendering library |
| `src/renderers/*.sol` (6 files) | 605 | 5 sub-renderers + RendererInterfaces.sol |
| `test/Moloch.t.sol` | 3,801 | 176 tests: core governance |
| `test/DAICO.t.sol` | 7,779 | 214 tests: DAICO |
| `test/MolochViewHelper.t.sol` | 2,101 | 52 tests: batch reads |
| `test/Tribute.t.sol` | 478 | 24 tests: OTC escrow |
| `test/ContractURI.t.sol` | 247 | 4 tests: on-chain metadata |
| `test/URIVisualization.t.sol` | 807 | 18 tests: SVG rendering |
| `test/Bytecodesize.t.sol` | 247 | 11 tests: contract sizes |
| `.github/workflows/ci.yml` | 28 | CI pipeline |

### Critical Line References

| Reference | File:Line | Description |
|-----------|-----------|-------------|
| `onlyDAO` modifier | `src/Moloch.sol:22-24` | Governance-only control |
| DAO self-voting block | `src/Moloch.sol:372` | `if (msg.sender == address(this)) revert Unauthorized()` |
| Snapshot at block N-1 | `src/Moloch.sol:307` | Flash loan protection |
| Quorum exclusion | `src/Moloch.sol:314-315` | DAO votes excluded from supply |
| `unchecked` tallies | `src/Moloch.sol:397-404` | Vote accumulation unchecked |
| `state()` machine | `src/Moloch.sol:465-515` | 7-path proposal state machine |
| Unanimous consent | `src/Moloch.sol:481, 555` | 100% FOR bypasses TTL and timelock |
| `nonReentrant` guard | `src/Moloch.sol:1136-1150` | EIP-1153 transient storage |
| `mulDiv` implementation | `src/Moloch.sol:2128-2136` | Overflow-checked multiply-divide |
| `_ffs` assembly | `src/Moloch.sol:2071-2082` | De Bruijn bit scanning |
| Safe transfers | `src/Moloch.sol:2141-2193` | Solady-pattern ERC20 ops |
| delegatecall execution | `src/Moloch.sol:1105-1115` | op=1 arbitrary delegatecall |
| multicall (non-payable) | `src/Moloch.sol:1022-1033` | Batch self-delegatecall |
| Ragequit timelock | `src/Moloch.sol:841-848` | 7-day hold requirement |
| `unchecked` ragequit body | `src/Moloch.sol:833-875` | Entire ragequit body unchecked |
| `unchecked` ERC-6909 | `src/Moloch.sol:1074-1088` | Mint/burn balance/supply unchecked |
| `unchecked` checkpoints | `src/Moloch.sol:1344-1353` | Vote power updates unchecked |
| `unchecked` token mint | `src/Moloch.sol:1311-1320` | Balance increment unchecked |
| Tally struct (uint96) | `src/Moloch.sol:66-70` | Limits max supply |
| DAICO slippage (exact-in) | `src/peripheral/DAICO.sol:552` | `minBuyAmt` check |
| DAICO slippage (exact-out) | `src/peripheral/DAICO.sol:616` | `maxPayAmt` check |
| ZAMM hardcoded | `src/peripheral/DAICO.sol:76` | `ensureApproval` grants max approval |
| Tribute arrays | `src/peripheral/Tribute.sol:53-56` | Append-only, unbounded |

---

*Consolidated from Trail of Bits Code Maturity Assessment (52/71 claims confirmed, 19 erroneous) and Guidelines Advisor Report (60/67 claims confirmed, 7 erroneous). All findings above have been verified against the codebase.*

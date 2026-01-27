# Verification Results

**Date:** 2026-01-27
**Verified by:** Automated code inspection (Opus 4.5)

## Summary
- 60 out of 67 claims CONFIRMED
- 7 out of 67 claims ERRONEOUS

## Erroneous Claims

| ID | Claim | What Report Says | What Code Actually Shows | Severity Impact |
|----|-------|-----------------|------------------------|-----------------|
| C-1 | multicall + msg.value double-spend on `fundFutarchy` | `fundFutarchy` could be called multiple times via `multicall` with the same `msg.value`, enabling double-spend. Report says `nonReentrant` guard on transient storage would block the second call. | `multicall` (line 1022) is NOT `payable`, so it cannot be called with `msg.value > 0` at all. The double-spend scenario via multicall is impossible because `multicall` would revert before any delegatecall executes. Additionally, the report's reasoning that `nonReentrant` would prevent the exploit is also wrong: `fundFutarchy` does NOT have `nonReentrant` at all. The correct mitigation is simpler: `multicall` is non-payable. | CRITICAL downgraded to INFORMATIONAL. The theoretical concern about msg.value reuse in delegatecall loops is valid in general, but not exploitable here because `multicall` is non-payable. |
| S-1 | v1-v2 differences doc is 763 lines | Section 1.1 states "`docs/v1-v2-contract-differences.md` (763 lines)" | The file is 1008 lines (`wc -l` confirms). | No severity impact (documentation metric). |
| S-2 | Events defined count is 35 | Summary Statistics table states "Events defined: 35" | There are 41 unique event names across source files (45 total declarations including duplicates). The report undercounts by 6, likely missing: `TapOpsUpdated`, `TapRateUpdated`, `LPConfigSet`, `LPInitialized`, `AutoFutarchySet`, `FutarchyRewardTokenSet`. | No severity impact (documentation metric). |
| S-3 | `toUint96` cast at line 392 | Section 8.2 says "The `toUint96` cast at line 392 ensures `weight` fits in uint96" | Line 392 uses `uint96(shares.getPastVotes(msg.sender, snap))` -- a direct Solidity cast, not the `toUint96` safe cast function. In Solidity 0.8.x, explicit narrowing conversions DO revert on overflow, so the cast is still safe, but the function name cited is wrong. | No severity impact (the safety property holds, but the specific function name is incorrect). |
| S-4 | safeTransferFrom "2-arg vs 4-arg" grouping | Section 9.2 implies DAICO and Tribute share the same `safeTransferFrom` signature, stating "Moloch's takes only `token, amount` while DAICO's takes `token, from, to, amount`" | All three contracts have DIFFERENT signatures: Moloch is 2-arg `(token, amount)`, DAICO is 4-arg `(token, from, to, amount)`, and Tribute is 3-arg `(token, to, amount)`. The report correctly identifies Moloch vs DAICO difference but incorrectly groups Tribute with DAICO. | No severity impact (documentation accuracy). |
| C-1a | `fundFutarchy` access characterization | Report Section 12, C-1 states fundFutarchy "can only be called via governance or directly" | `fundFutarchy` (line 578) is `public payable` with NO access control -- anyone can call it, not just governance. The function has no `onlyDAO` modifier. The report's characterization that it "can only be called via governance or directly" is misleading; it can be called by anyone. | CRITICAL finding description accuracy. The underlying double-spend concern via multicall is still moot (multicall is non-payable). |
| S-6 | `castVote` line range 369-415 is 46 lines | Report Section 5.1 says `castVote` is at `Moloch.sol:369-415` with 46 lines | Lines 369-415 is actually 47 lines (415 - 369 + 1 = 47). | No severity impact (minor arithmetic). |
| S-7 | `onSharesChanged` line range and count | Report says `onSharesChanged` at `Moloch.sol:1956-2033` is 77 lines | The function is at lines 1956-2033 in the Badges contract (77 lines = 2033-1956+1 = 78 lines). Minor off-by-one. | No severity impact. |

## Confirmed Claims

| ID | Claim | Verification Evidence |
|----|-------|----------------------|
| C-2 | Delegatecall execution via governance can corrupt storage | `_execute` at line 1105-1115 confirms `op=1` performs `to.delegatecall(data)`. This is by design for governance flexibility. The finding correctly identifies this as a high-impact design choice gated by governance voting + timelock. Assessment is fair as a documentation/awareness issue, though "CRITICAL" may be overstated since it requires passing a governance vote. |
| H-1 | No formal specification for state machine transitions | Verified: `state()` function at line 465-515 implements a 7-state machine. No separate specification document exists. `CLAUDE.md` and inline NatSpec at lines 459-464 serve as informal docs. The state machine is complex (unanimous consent bypass at line 481, zero-TTL behavior, queue/execute interaction). H-1 is confirmed as a documentation gap. |
| H-2 | Unbounded `proposalIds` array | `proposalIds` declared at line 73, pushed at line 319 in `openProposal`. No pruning mechanism exists. `getProposalCount()` at line 287-289 returns `proposalIds.length`. ViewHelper's `_getProposals` at line 766 paginates, mitigating RPC timeout risk. The array growth is real but pagination exists. |
| H-3 | Missing static analysis in CI | `.github/workflows/ci.yml` confirmed: runs `forge build`, `forge test -vvv`, and `biome lint dapp`. No Slither, Mythril, or formal verification tools. |
| H-4 | `ragequit` token array has no length bound | `ragequit` function at line 828-876: takes `address[] calldata tokens` with no length check beyond `tokens.length != 0`. The ascending-sort requirement (line 865) prevents duplicates but does not limit array size. |
| M-1 | Tally fields are `uint96` | Tally struct at lines 66-70 confirmed: `uint96 forVotes`, `uint96 againstVotes`, `uint96 abstainVotes`. Unchecked accumulation at lines 397-400. |
| M-2 | Tribute discovery arrays grow without bound | `daoTributeRefs` at line 53, `proposerTributeRefs` at line 56 confirmed as append-only. `getActiveDaoTributes` at line 183 iterates entire array in two passes (lines 188-219). |
| M-3 | `ensureApproval` grants max approval to ZAMM | `ensureApproval` at line 1400 confirmed: checks allowance against `type(uint128).max` threshold and approves `not(0)` (type(uint256).max). ZAMM hardcoded at line 76. |
| M-4 | Clone initialization front-running | `Shares.init` at line 1248-1249: `require(DAO == address(0), Unauthorized()); DAO = payable(msg.sender);`. Same pattern in `Loot.init` (line 1767-1769) and `Badges.init` (line 1865-1867). No constructor guard on implementations. Confirmed but correctly assessed as non-exploitable. |
| M-5 | No access control on `queue()` function | `queue()` at line 518-525: `public` with no access restrictions. Anyone can call it on a Succeeded proposal. Confirmed. |
| L-1 | Duplicated safe transfer functions | `safeTransferETH` at Moloch:2151, DAICO:1350, Tribute:239. `safeTransfer` at Moloch:2160, DAICO:1359, Tribute:248. `safeTransferFrom` at Moloch:2176, DAICO:1375, Tribute:264. All confirmed as duplicated assembly implementations. |
| L-2 | `_ffs` magic constants lack documentation | `_ffs` at lines 2071-2082 confirmed: uses De Bruijn-style bit manipulation with opaque magic constants. Only `@dev` comment on `onSharesChanged`, none on `_ffs` itself explaining the algorithm. |
| L-3 | No `forge coverage` in CI | CI config confirmed: no `forge coverage` or `forge snapshot` commands. |
| L-4 | `safeTransfer` ERC20 compatibility | `safeTransfer` at line 2160-2174 confirmed: Solady-style pattern handling void-return and bool-return tokens. `ensureApproval` in DAICO (line 1395-1425) handles USDT-style tokens via allowance threshold check. |
| L-5 | `getSeats()` popcount double loop | Lines 1934-1952 confirmed: first loop (1938-1942) counts set bits discarding positions, second loop (1944-1950) re-iterates to extract positions. |
| L-6 | `buyShares` CEI pattern concern | Lines 794-799 confirmed: ETH refund (`safeTransferETH`) happens before share minting (lines 808-816). Comment at line 786 says "EFFECTS (CEI)" but actual order is Check-Effect-Interaction-Effect. `nonReentrant` is present (line 772). |
| Stats-1 | Total source lines: 6,244 | `wc -l` confirmed: exactly 6,244 lines across 12 source files. |
| Stats-2 | Total test lines: 15,460 | `wc -l` confirmed: exactly 15,460 lines across 7 test files. |
| Stats-3 | Total tests: 499 | Forge test summary confirmed: 11+4+148+6+60+176+52+24+18 = 499 tests, all passing. |
| Stats-4 | Test/source ratio: 2.48x | 15,460 / 6,244 = 2.476x, rounds to 2.48x. Confirmed. |
| Stats-5 | Fuzz tests: 14 (now 13 in Moloch + DAICO) | Grep found 13 `testFuzz_` functions in test files, plus 1 `test_SplitDelegation_FuzzAllocationsMatchVotes` which is a fuzz test by naming convention. Total 14 confirmed. |
| Stats-6 | Invariant-style tests: 4 | Found 4 `test_Invariant_*` functions in Moloch.t.sol at lines 2653, 2707, 2748, 2777. Confirmed as manual invariant checks, not Foundry-native `invariant_*` stateful tests. |
| Stats-7 | Assembly blocks (src): 29 | Grep confirmed: Moloch.sol:12, DAICO.sol:7, Tribute.sol:5, Display.sol:5 = 29 total. |
| Stats-8 | Unchecked blocks (src): 44 | Grep confirmed: 44 total across Moloch.sol:30, DAICO.sol:4, Tribute.sol:2, MolochViewHelper.sol:2, CovenantRenderer.sol:1, Display.sol:5. |
| Stats-9 | External dependencies: 0 (solady remapped but unused) | Grep confirmed: no `import.*solady` in any src/ file. Solady is remapped in foundry.toml but never imported. |
| Stats-10 | Inline assembly files: 4/12 (33%) | Grep confirmed: Moloch.sol, DAICO.sol, Tribute.sol, Display.sol contain assembly blocks. |
| Stats-11 | Individual test file line counts and test counts | All 7 test files match: Moloch.t.sol:176/3801, DAICO.t.sol:214(148+6+60)/7779, MolochViewHelper.t.sol:52/2101, Tribute.t.sol:24/478, ContractURI.t.sol:4/247, URIVisualization.t.sol:18/807, Bytecodesize.t.sol:11/247. |
| Arch-1 | No inheritance for core contracts | Verified: Moloch, Shares, Loot, Badges, Summoner, DAICO, Tribute are all standalone contracts with no `is` inheritance clauses. |
| Arch-2 | Reentrancy guard uses identical slot across 3 contracts | Confirmed: `REENTRANCY_GUARD_SLOT = 0x929eee149b4bd21268` in Moloch:1136, DAICO:168, Tribute:222. |
| Arch-3 | `onlyDAO` modifier defined 4 times | Moloch:22 (`address(this)`), Shares:1210 (`DAO`), Loot:1760 (`DAO`), Badges:1855 (`DAO`). Confirmed with correct semantic differences. |
| Arch-4 | Renderer has 5 immutable sub-renderer addresses | Renderer.sol lines 9-13: `covenant`, `proposal`, `receipt`, `permit`, `badge` -- all `immutable`. Confirmed. |
| Arch-5 | Renderer is the only upgradeable component | `setRenderer` at line 963 allows DAO governance to change renderer. All other components are immutable. Confirmed. |
| Arch-6 | ViewHelper uses `constant` for SUMMONER and DAICO addresses | Lines 312 and 315 confirmed: `ISummoner public constant SUMMONER` and `IDAICO public constant DAICO`. |
| Arch-7 | Summoner `molochImpl` is immutable at line 2200 | Line 2200: `Moloch public immutable molochImpl;`. Confirmed. |
| Arch-8 | Clone deployment uses custom minimal proxy pattern | `_init` at line 264-276 and Summoner at lines 2221-2231 use identical custom EIP-1167-style minimal proxy assembly. Confirmed. |
| Arch-9 | ZAMM hardcoded at DAICO.sol line 76 | Line 76: `IZAMM constant ZAMM = IZAMM(0x000000000000040470635EB91b7CE4D132D616eD);`. Confirmed. |
| Sec-1 | Ragequit timelock at 7 days default | Line 42: `uint64 public ragequitTimelock = 7 days;`. Also re-set in `init()` at line 243. Confirmed. |
| Sec-2 | Snapshot voting uses block.number - 1 | Line 307: `uint48 snap = toUint48(block.number - 1);`. Confirmed. |
| Sec-3 | DAO self-voting blocked | Line 372: `if (msg.sender == address(this)) revert Unauthorized();`. Confirmed. |
| Sec-4 | Quorum excludes DAO-held shares | Line 315: `supply -= _shares.getPastVotes(address(this), snap);`. Confirmed. |
| Sec-5 | Unanimous consent bypasses timelock | Line 555: `bool unanimous = tallies[id].forVotes == supplySnapshot[id] && supplySnapshot[id] != 0;`. Line 481 in `state()`: `if (tallies[id].forVotes < supplySnapshot[id]) return ProposalState.Active;`. Confirmed. |
| Sec-6 | `buyShares` has `maxPay` slippage protection | Line 784: `if (maxPay != 0 && cost > maxPay) revert NotOk();`. Confirmed. |
| Sec-7 | DAICO `buy()` has `minBuyAmt` and `buyExactOut()` has `maxPayAmt` | `buy` at line 552: `if (minBuyAmt != 0 && buyAmt < minBuyAmt) revert SlippageExceeded();`. `buyExactOut` at line 616: `if (maxPayAmt != 0 && payAmt > maxPayAmt) revert SlippageExceeded();`. Confirmed. |
| CI-1 | CI triggers on push to main and everything branches, and PRs | `.github/workflows/ci.yml` lines 4-6: `push: branches: [main, everything]` and `pull_request`. Confirmed. |
| CI-2 | CI runs forge build, forge test -vvv, biome lint dapp | Lines 18-19 and 28: confirmed all three commands. |
| NatSpec-1 | Key Moloch functions have NatSpec | `castVote` at 364-368, `ragequit` at 821-827, `executeByVotes` at 528-537, `state` at 459-464 all have `@notice` and `@dev`. Config setters at 893-1008 have `@notice` annotations. Confirmed. |
| NatSpec-2 | DAICO has thorough NatSpec with worked examples | Lines 188-203 confirmed: detailed examples for `setSale` function. `buy` at 490-499 and `buyExactOut` at 577-586 also have thorough NatSpec. |
| NatSpec-3 | `_init()` at line 264 lacks NatSpec | Confirmed: no `@notice`, `@dev`, `@param`, or `@return` tags on `_init`. |
| NatSpec-7 | Shares contract (line 1187) has minimal NatSpec | Confirmed: `Shares` starts at line 1187. Functions `init()`, `transfer()`, `transferFrom()`, `setSplitDelegation()` lack `@notice` annotations. Only internal helpers have `@dev` comments. |
| NatSpec-4 | `_mint6909` at line 1074 and `_burn6909` at line 1082 lack NatSpec | Confirmed: no NatSpec on either function. |
| NatSpec-5 | Free functions at lines 2110-2193 lack param/return tags | Confirmed: `toUint48`, `toUint96`, `mulDiv`, `balanceOfThis`, `safeTransferETH`, `safeTransfer`, `safeTransferFrom` all lack `@param` and `@return` tags. |
| NatSpec-6 | Loot contract has almost no NatSpec | Confirmed: Loot contract (lines 1744-1841) has zero NatSpec annotations. |
| Misc-1 | `_buildInitCalls` at DAICO.sol:1139-1215 (76 lines) | Confirmed: function starts at line 1139 and ends at line 1215. 1215-1139+1 = 77 lines (off by 1 from report's "76"). |
| Misc-2 | `_getProposals` at MolochViewHelper.sol:766-878 (112 lines) | Line 766 starts function, line 878 is closing brace. 878-766+1 = 113 (report says 112, off by 1). |
| Misc-3 | `test_DelegateCallExecution` exists at line 1192 | Confirmed: `function test_DelegateCallExecution() public {` at Moloch.t.sol:1192. |
| Misc-4 | PermitSet event missing `spender` indexed | Line 112: `event PermitSet(address spender, uint256 indexed id, uint256 newCount);` -- `spender` is NOT indexed, only `id` is. Confirmed. |

---

# Trail of Bits Guidelines Advisor Report: Majeur (Moloch DAO Framework)

**Date:** 2026-01-27
**Codebase:** Majeur v2 (`everything` branch, commit `786a72f`)
**Compiler:** Solidity 0.8.33, EVM Cancun, via_ir=true, optimizer_runs=500
**Scope:** Core contracts (`src/`), peripherals, renderers, tests (`test/`), deployment scripts (`script/`)

---

## Table of Contents

1. [System Documentation](#1-system-documentation)
2. [On-Chain vs Off-Chain Computation](#2-on-chain-vs-off-chain-computation)
3. [Upgradeability](#3-upgradeability)
4. [Delegatecall & Proxy Pattern](#4-delegatecall--proxy-pattern)
5. [Function Composition](#5-function-composition)
6. [Inheritance](#6-inheritance)
7. [Events](#7-events)
8. [Common Pitfalls](#8-common-pitfalls)
9. [Dependencies](#9-dependencies)
10. [Testing & Verification](#10-testing--verification)
11. [Platform-Specific Guidance](#11-platform-specific-guidance)
12. [Prioritized Recommendations](#12-prioritized-recommendations)

---

## 1. System Documentation

### 1.1 Plain English Descriptions

**Strengths:**
- `CLAUDE.md` provides a thorough architectural overview covering all contracts, their purposes, and relationships.
- `docs/v1-v2-contract-differences.md` (763 lines) documents every v1-to-v2 change with commit references, diff tables, and code examples.
- NatSpec coverage is strong on external/public functions in `Moloch.sol`. Key functions like `castVote` (line 364-368), `ragequit` (line 821-827), `executeByVotes` (line 528-537), `state` (line 459-464), and all config setters (lines 893-1008) have `@notice` and `@dev` annotations.
- DAICO.sol has thorough NatSpec on all user-facing functions with worked examples (lines 188-203).

**Gaps:**
- **No formal specification document.** While CLAUDE.md and the v1-v2 diff serve as informal specs, there is no rigorous specification describing the intended state machine transitions, invariants, or security properties. Trail of Bits recommends a standalone specification that can be used as a reference during audits.
- **Missing NatSpec on several internal functions:**
  - `_init()` at `Moloch.sol:264` - cloning mechanism undocumented beyond assembly comments.
  - `_mint6909()` at `Moloch.sol:1074` and `_burn6909()` at `Moloch.sol:1082` - no NatSpec.
  - Multiple free functions at file scope (lines 2110-2193) - `toUint48`, `toUint96`, `mulDiv`, `balanceOfThis`, `safeTransferETH`, `safeTransfer`, `safeTransferFrom` lack `@param` and `@return` tags.
- **No architecture diagram.** The contract relationships (Summoner -> Moloch -> Shares/Loot/Badges, Moloch <-> Renderer, DAICO <-> Moloch) are described in text but not visualized.
- **Shares contract** (line 1187) has minimal NatSpec: only `@dev` on internal helpers but no `@notice` on `init()`, `transfer()`, `transferFrom()`, `setSplitDelegation()`.
- **Badges contract** (line 1843) has minimal NatSpec: only `@dev` on `onSharesChanged()` and `_ffs()`.
- **Loot contract** (line 1744) has almost no NatSpec at all.

### 1.2 Documentation Quality Assessment

| Area | Rating | Evidence |
|------|--------|----------|
| Architecture overview | Good | CLAUDE.md table mapping contracts to purposes |
| Function-level docs | Moderate | Strong on Moloch.sol externals, weak on Shares/Loot/Badges |
| State machine docs | Weak | `state()` has inline comments but no formal state diagram |
| Security properties | Weak | Mentioned in CLAUDE.md but not formally documented |
| Deployment docs | Good | CLAUDE.md lists all scripts with examples |
| API differences | Excellent | `v1-v2-contract-differences.md` is comprehensive |

---

## 2. On-Chain vs Off-Chain Computation

### 2.1 Complexity Analysis

**Heavy on-chain computation identified:**

1. **MolochViewHelper.sol** - The entire contract (1352 lines) performs complex batch reads on-chain. Functions like `getDAOsFullState()` (line 396) iterate over all DAOs and for each DAO iterate over all members and all proposals, performing O(DAOs * Members * Proposals) external calls. This is read-only (view), so gas is paid by the caller/node but can cause timeouts on RPC endpoints.

2. **Badges.onSharesChanged()** (`Moloch.sol:1956-2033`) - Called on every share balance change (transfers, mints, burns). The `_recomputeMin()` function (line 2052) iterates over all 256 possible seats using a bitmap, which in the worst case is O(256). This is mitigated by only being called when the minimum seat holder changes.

3. **Split delegation** (`Moloch.sol:1398-1631`) - The `setSplitDelegation()` function performs O(n^2) duplicate checking (line 1414: `for (uint256 j = i + 1; j != n; ++j)`) and `_repointVotesForHolder()` performs O(oldLen * newLen) cross-matching (line 1599-1617). This is bounded by `MAX_SPLITS = 4`, so worst case is 4*4 = 16 iterations.

4. **Ragequit token loop** (`Moloch.sol:858-873`) - Iterates over user-supplied token array with external calls (`balanceOfThis`, `_payout`) for each token. No upper bound on array length, though the ascending-sort requirement prevents duplicates.

5. **Tribute discovery arrays** (`Tribute.sol:53-56`) - `daoTributeRefs` and `proposerTributeRefs` are append-only arrays that grow unboundedly. `getActiveDaoTributes()` (line 183) performs two full passes over all refs, including deleted entries, creating O(n) gas growth over time.

**Appropriate on-chain computation:**
- Snapshot-based voting with binary search checkpoint lookup (`Moloch.sol:1697-1729`) is efficient at O(log n).
- ERC-6909 receipt minting during voting is minimal overhead.
- The `mulDiv` assembly function (line 2128) is gas-optimized.

### 2.2 Gas Optimization Observations

- EIP-1153 transient storage for reentrancy guards (`Moloch.sol:1136-1150`) is a good Cancun-era optimization.
- Free functions at file scope (`safeTransfer`, `safeTransferFrom`, etc.) avoid the overhead of library linking.
- Clone proxy deployment (`Moloch.sol:264-276`) provides significant gas savings over full deployment.

### 2.3 Computation Pattern Concerns

| Pattern | Location | Concern |
|---------|----------|---------|
| Unbounded array iteration | `Tribute.sol:188-219` | `getActiveDaoTributes` iterates entire ref array |
| Unbounded token loop | `Moloch.sol:858-873` | Ragequit token array has no length cap |
| Quadratic member-proposal iteration | `MolochViewHelper.sol:836-877` | Every proposal checks every member for votes |

---

## 3. Upgradeability

### 3.1 Upgrade Strategy

The project uses an **immutable deployment model** with no upgradeability mechanism:

- **Summoner** (`Moloch.sol:2196`) deploys Moloch clones via CREATE2. Once deployed, the implementation is immutable (`Moloch public immutable molochImpl` at line 2200).
- **Moloch** clones deploy Shares, Loot, and Badges as immutable clones (lines 250-255).
- **Renderer** uses immutable sub-renderer addresses (lines 9-13 of `Renderer.sol`), though the DAO can change its renderer address via `setRenderer()` (line 963).
- **ViewHelper** uses `constant` for Summoner and DAICO addresses (lines 312-315 of `MolochViewHelper.sol`), making them non-upgradeable.

**Assessment:** The no-upgradeability approach is appropriate for a DAO governance framework where immutability is a feature (members trust the code they join). However:

- **No migration path exists.** If a critical bug is found in Moloch.sol, existing DAOs cannot upgrade. New DAOs would need a new Summoner with a fixed implementation, and existing members would need to ragequit and re-join.
- **Renderer is the only upgradeable component** - the DAO can vote to change its renderer address (`setRenderer()` at line 963). This is appropriate since renderers are purely cosmetic.
- **ViewHelper cannot be upgraded** since its Summoner address is a `constant`. A new ViewHelper would need to be deployed and the frontend updated.

### 3.2 Data Separation

There is no data/logic separation pattern. All state lives within the Moloch clone (proposals, tallies, ERC-6909 balances, futarchy) and its child clones (Shares, Loot, Badges). This is consistent with the non-upgradeable design but means state cannot be preserved across version migrations.

---

## 4. Delegatecall & Proxy Pattern

### 4.1 Clone Proxy Pattern

The project uses a minimal proxy (clone) pattern for deploying DAOs and their sub-contracts:

**Summoner clone deployment** (`Moloch.sol:2221-2231`):
```solidity
assembly ("memory-safe") {
    mstore(0x24, 0x5af43d5f5f3e6029573d5ffd5b3d5ff3)
    mstore(0x14, _implementation)
    mstore(0x00, 0x602d5f8160095f39f35f5f365f5f37365f73)
    dao := create2(callvalue(), 0x0e, 0x36, _salt)
```

This is a custom minimal proxy similar to EIP-1167 but not identical. The same pattern is used for Shares/Loot/Badges deployment inside `_init()` (line 264).

**Storage layout concerns:**

- **Moloch.sol**: The implementation contract stores `sharesImpl`, `badgesImpl`, `lootImpl` as `immutable` (lines 50-52), which are embedded in the clone's bytecode via the proxy pattern. The `SUMMONER` is also `immutable` (line 49), set to `msg.sender` during construction.
- **Critical: `SUMMONER` immutable in clone context.** The `SUMMONER` address is set to `msg.sender` in the Moloch constructor (line 49). In the clone, this value comes from the implementation's bytecode where `msg.sender` was the Summoner deployer. The `init()` function checks `require(msg.sender == SUMMONER)` (line 234), so only the Summoner can initialize a clone. This is correct behavior.
- **Shares/Loot/Badges** use `DAO` as a mutable state variable (not immutable), initialized via `init()` to `msg.sender` (the Moloch clone). The `require(DAO == address(0))` guard (e.g., `Shares.sol:1249`) prevents re-initialization. This is the standard clone initialization pattern.

### 4.2 Delegatecall Exposure

**`executeByVotes` with `op=1` (delegatecall)** (`Moloch.sol:1105-1115`):
```solidity
function _execute(uint8 op, address to, uint256 value, bytes calldata data)
    internal returns (bool ok, bytes memory retData) {
    if (op == 0) {
        (ok, retData) = to.call{value: value}(data);
    } else {
        (ok, retData) = to.delegatecall(data);
    }
```

This allows governance to execute arbitrary delegatecalls from the DAO's context. This is by design (allows installing "modules" or complex state changes), but it is extremely powerful - a malicious proposal could overwrite any storage slot in the Moloch contract.

**`multicall` function** (`Moloch.sol:1022-1033`):
```solidity
function multicall(bytes[] calldata data) public returns (bytes[] memory results) {
    for (uint256 i; i != data.length; ++i) {
        (bool success, bytes memory result) = address(this).delegatecall(data[i]);
```

`multicall` is publicly callable and performs delegatecalls to `address(this)`. Since each delegatecall preserves `msg.sender`, this allows batching multiple DAO function calls in a single transaction. However, `multicall` itself is not gated by `onlyDAO`, so anyone can call it. The individual functions being delegatecalled will check their own authorization (e.g., `onlyDAO`). The risk is that `msg.sender` in the delegatecall context is the original caller, not the Moloch contract, so `onlyDAO` checks within delegatecalled functions will correctly require the original caller to be the Moloch contract itself.

**FINDING: `multicall` + `msg.value` forwarding.** Each delegatecall in the loop forwards `msg.value` via the context. If a payable function is called multiple times via multicall, each sub-call sees the same `msg.value`, potentially allowing `msg.value` to be "reused." This is a known multicall concern. In Moloch's case, the payable functions that check `msg.value` (like `buyShares` at line 795 or `fundFutarchy` at line 608) could theoretically be exploited via multicall to spend `msg.value` multiple times. However, since `buyShares` and `fundFutarchy` have `nonReentrant` guards and `multicall` uses `delegatecall` (same contract, same storage), the reentrancy guard should trigger on the second call. But `nonReentrant` uses transient storage which resets per transaction - with delegatecall from the same contract, the guard slot is the same, so the second call in a multicall batch would indeed be blocked by the reentrancy guard.

### 4.3 Initialization Safety

- **No `initializer` modifier pattern** - instead uses `require(DAO == address(0))` one-time checks.
- **No `disableInitializers` on implementation** - the implementation contracts (Moloch, Shares, Loot, Badges) can be initialized directly. The Moloch implementation has `SUMMONER = msg.sender` set during construction, so `init()` requires `msg.sender == SUMMONER`, which prevents unauthorized initialization. For Shares/Loot/Badges, the implementation instances can be initialized by anyone (first caller sets `DAO`), but since they are only used as implementation templates for cloning, this is not exploitable - the implementations themselves hold no meaningful state.

---

## 5. Function Composition

### 5.1 Function Size Analysis

**Large functions (high complexity):**

| Function | File:Line | Lines | Concern |
|----------|-----------|-------|---------|
| `openProposal` | `Moloch.sol:295-362` | 67 | Multiple responsibilities: snapshot, registry, auto-futarchy |
| `castVote` | `Moloch.sol:369-415` | 46 | Combines validation, auto-open, tally, receipt minting |
| `ragequit` | `Moloch.sol:828-876` | 48 | Token loop with complex validation |
| `buyShares` | `Moloch.sol:769-819` | 50 | Payment handling + share issuance |
| `onSharesChanged` | `Moloch.sol:1956-2033` | 77 | Complex bitmap/seat management with 4 code paths |
| `buy` | `DAICO.sol:500-571` | 71 | LP integration, payment handling, token transfer |
| `buyExactOut` | `DAICO.sol:587-664` | 77 | Similar to `buy` with inverse calculation |
| `_buildInitCalls` | `DAICO.sol:1139-1215` | 76 | Complex call array construction |
| `_buildDAOFullState` | `MolochViewHelper.sol:659-725` | 66 | Multi-field struct population |
| `_getProposals` | `MolochViewHelper.sol:766-878` | 112 | Nested loops for proposal + voter enumeration |
| `setSplitDelegation` | `Moloch.sol:1398-1433` | 35 | Validation + storage mutation + vote repointing |
| `_applyVotingDelta` | `Moloch.sol:1527-1563` | 36 | Complex before/after allocation calculation |
| `_repointVotesForHolder` | `Moloch.sol:1568-1631` | 63 | O(n*m) cross-matching of old/new distributions |

**Assessment:** Most functions are within acceptable size limits. The largest (`_getProposals` at 112 lines) is a pure view function, so complexity there is less concerning. `onSharesChanged` at 77 lines with 4 distinct code paths could benefit from extraction into sub-functions for readability, but the single-function approach avoids extra JUMP overhead.

### 5.2 Separation of Concerns

**Well-separated:**
- Renderer system: Router (`Renderer.sol`) dispatches to 5 independent sub-renderers (Covenant, Proposal, Receipt, Permit, Badge). Each is independently deployable and testable.
- Token contracts (Shares, Loot, Badges) are separate from Moloch governance logic.
- Peripheral contracts (DAICO, Tribute) are fully external to Moloch.

**Tightly coupled:**
- `Moloch.sol` contains governance, ERC-6909, sales, messaging, allowances, permits, and futarchy all in a single contract (2251 lines). While this reduces inter-contract calls and gas costs, it increases the attack surface of any single proposal execution.

---

## 6. Inheritance

### 6.1 Hierarchy Analysis

The project uses **no inheritance** for core contracts. This is a deliberate design choice:

- `Moloch` is a standalone contract with no base contracts.
- `Shares`, `Loot`, `Badges` are standalone contracts with no base contracts.
- `Summoner` is standalone.
- `DAICO`, `Tribute` are standalone.
- Renderers use interfaces (`ICovenantRenderer`, `ICardRenderer`) but only for external dispatch.

**Assessment:** The zero-inheritance approach eliminates:
- Diamond problem risks
- Storage layout conflicts in proxy patterns
- Hidden function shadowing
- Complex C3 linearization issues

This is excellent from a security perspective. The trade-off is code duplication (e.g., `onlyDAO` modifier is defined 4 times - in Moloch, Shares, Loot, and Badges), but each has a slightly different implementation (Moloch checks `address(this)`, the others check `DAO`).

### 6.2 Interface Usage

Interfaces are used appropriately:
- `IMajeurRenderer` (`Moloch.sol:2085-2089`) - for renderer dispatch
- `IMoloch` in `RendererInterfaces.sol` (line 10) - minimal interface for renderers
- `ISummoner`, `IShares`, `ILoot`, `IBadges`, `IERC20`, `IMoloch`, `IDAICO` in `MolochViewHelper.sol` - for batch reads
- `IZAMM`, `IMoloch`, `ISharesLoot`, `ISummoner` in `DAICO.sol` - for external integrations

---

## 7. Events

### 7.1 Event Coverage Assessment

**Comprehensive event coverage for core operations:**

| Operation | Event | File:Line | Indexed | Assessment |
|-----------|-------|-----------|---------|------------|
| Proposal opened | `Opened` | `Moloch.sol:90` | `id` | Good |
| Vote cast | `Voted` | `Moloch.sol:91` | `id`, `voter` | Good |
| Vote cancelled | `VoteCancelled` | `Moloch.sol:92` | `id`, `voter` | Good |
| Proposal cancelled | `ProposalCancelled` | `Moloch.sol:93` | `id`, `by` | Good |
| Proposal queued | `Queued` | `Moloch.sol:94` | `id` | Good |
| Proposal executed | `Executed` | `Moloch.sol:95` | `id`, `by` | Good |
| Config changes | `ConfigUpdated` | `Moloch.sol:98` | `param` | Good - generic pattern |
| Allowance set | `AllowanceSet` | `Moloch.sol:99` | `spender`, `token` | Good |
| Transfer lock | `TransfersLockSet` | `Moloch.sol:100` | none | OK - rare operation |
| Metadata set | `MetadataSet` | `Moloch.sol:101` | none | OK - rare operation |
| Renderer set | `RendererSet` | `Moloch.sol:102` | `old`, `new` | Good |
| Ragequit | `Ragequit` | `Moloch.sol:107` | `member` | Good |
| Permit set | `PermitSet` | `Moloch.sol:112` | `id` | Missing: `spender` not indexed |
| Permit spent | `PermitSpent` | `Moloch.sol:113` | `id`, `by` | Good |
| Sale updated | `SaleUpdated` | `Moloch.sol:130` | `payToken` | Good |
| Share purchase | `SharesPurchased` | `Moloch.sol:133` | `buyer`, `payToken` | Good |
| Message | `Message` | `Moloch.sol:142` | `from`, `index` | Good |
| ERC-6909 transfer | `Transfer` | `Moloch.sol:174` | `from`, `to`, `id` | Good |
| Futarchy opened | `FutarchyOpened` | `Moloch.sol:206` | `id`, `rewardToken` | Good |
| Futarchy funded | `FutarchyFunded` | `Moloch.sol:207` | `id`, `from` | Good |
| Futarchy resolved | `FutarchyResolved` | `Moloch.sol:208` | `id` | Good |
| Futarchy claimed | `FutarchyClaimed` | `Moloch.sol:211` | `id`, `claimer` | Good |
| New DAO | `NewDAO` | `Moloch.sol:2197` | `summoner`, `dao` | Good |
| DAICO sale set | `SaleSet` | `DAICO.sol:115` | `dao`, `tribTkn`, `forTkn` | Good |
| DAICO sale bought | `SaleBought` | `DAICO.sol:124` | `buyer`, `dao`, `tribTkn` | Good |
| Tap set | `TapSet` | `DAICO.sol:133` | `dao`, `ops`, `tribTkn` | Good |
| Tap claimed | `TapClaimed` | `DAICO.sol:137` | `dao`, `ops` | Good |
| Tribute proposed | `TributeProposed` | `Tribute.sol:12` | `proposer`, `dao` | Good |
| Tribute cancelled | `TributeCancelled` | `Tribute.sol:20` | `proposer`, `dao` | Good |
| Tribute claimed | `TributeClaimed` | `Tribute.sol:28` | `proposer`, `dao` | Good |

### 7.2 Event Gaps

1. **`PermitSet` event** (`Moloch.sol:112`): `address spender` is not indexed, making it harder to filter permits by spender. Only `id` is indexed.
2. **`TransfersLockSet` has no indexed parameters** (`Moloch.sol:100`): Not a significant issue since this is a rare governance action.
3. **Badges `mintSeat`/`burnSeat`**: Emit standard ERC-721 `Transfer` events (lines 1902, 1912). Good.

### 7.3 Naming Conventions

Events follow a consistent `PastTense` or `Action` naming convention:
- Governance: `Opened`, `Voted`, `Executed`, `Queued`
- Config: `ConfigUpdated`, `AllowanceSet`, `RendererSet`
- Futarchy: `FutarchyOpened`, `FutarchyFunded`, `FutarchyResolved`, `FutarchyClaimed`

This is consistent and clear.

---

## 8. Common Pitfalls

### 8.1 Reentrancy

**Protection mechanism:** EIP-1153 transient storage reentrancy guard:
```solidity
uint256 constant REENTRANCY_GUARD_SLOT = 0x929eee149b4bd21268;
modifier nonReentrant() virtual {
    assembly ("memory-safe") {
        if tload(REENTRANCY_GUARD_SLOT) {
            mstore(0x00, 0xab143c06)
            revert(0x1c, 0x04)
        }
        tstore(REENTRANCY_GUARD_SLOT, address())
    }
    _;
    assembly ("memory-safe") {
        tstore(REENTRANCY_GUARD_SLOT, 0)
    }
}
```

This pattern is used identically in Moloch (`Moloch.sol:1136-1150`), DAICO (`DAICO.sol:168-182`), and Tribute (`Tribute.sol:222-236`). The same `REENTRANCY_GUARD_SLOT` value (`0x929eee149b4bd21268`) is used across all three contracts, but since each contract has its own transient storage space, there is no cross-contract collision.

**Functions protected by `nonReentrant`:**
- `Moloch.sol`: `executeByVotes` (544), `cashOutFutarchy` (639), `spendPermit` (715), `spendAllowance` (743), `buyShares` (773), `ragequit` (831)
- `DAICO.sol`: `buy` (503), `buyExactOut` (590), `claimTap` (781)
- `Tribute.sol`: `proposeTribute` (74), `cancelTribute` (108), `claimTribute` (132)

**Functions NOT protected that perform external calls:**
- `Moloch.sol:batchCalls` (1012) - `onlyDAO` gated, performs arbitrary external calls
- `Moloch.sol:multicall` (1022) - publicly callable, performs delegatecalls to self
- `Moloch.sol:init` (258-261) - init calls loop, but this is a one-time initialization
- `Moloch.sol:openProposal` (295) - no external calls that could re-enter (only reads from Shares)

**FINDING: `batchCalls` lacks `nonReentrant` guard.** While gated by `onlyDAO`, a malicious proposal using `batchCalls` could call back into the Moloch contract's non-reentrant functions. The `nonReentrant` guard on those target functions provides protection, but nested reentrancy through `batchCalls` -> external contract -> Moloch callback is a vector. Since `batchCalls` requires a governance vote to execute, the risk is governance-level rather than external-attacker-level.

### 8.2 Integer Overflow/Underflow

Solidity 0.8.33 provides built-in overflow protection. The codebase uses `unchecked` blocks extensively (44 occurrences across source files):

**Potentially concerning `unchecked` blocks:**

1. **Tally accumulation** (`Moloch.sol:397-404`):
   ```solidity
   unchecked {
       if (support == 1) t.forVotes += weight;
       else if (support == 0) t.againstVotes += weight;
       else t.abstainVotes += weight;
       hasVoted[id][msg.sender] = support + 1;
       voteWeight[id][msg.sender] = weight;
   }
   ```
   `forVotes`, `againstVotes`, `abstainVotes` are `uint96` fields. `weight` is also `uint96`. The sum could overflow `uint96` if total supply exceeds `type(uint96).max` (79 billion tokens at 18 decimals). The `toUint96` cast at line 392 ensures `weight` fits in uint96, and `totalSupply` is tracked as uint256 in Shares, but the tally field accumulation is unchecked. **If total share supply exceeds ~79 billion tokens (79e27 wei), tally overflow is possible.** This is an edge case but should be documented as a limitation.

2. **Supply snapshot subtraction** (`Moloch.sol:315`):
   ```solidity
   supply -= _shares.getPastVotes(address(this), snap);
   ```
   This is inside an `unchecked` block (line 306). If the DAO's past votes somehow exceeded total supply (e.g., via delegation bugs), this would underflow. However, votes are derived from balances which are subsets of supply, so this should be safe in practice.

3. **Ragequit payout calculation** (`Moloch.sol:869`):
   ```solidity
   due = mulDiv(pool, amt, total);
   ```
   Inside an `unchecked` block, but `mulDiv` itself has overflow protection (reverts on overflow). The surrounding subtraction `cap - shareAmount` at line 789 is also unchecked but preceded by a `cap >= shareAmount` check at line 779.

### 8.3 Access Control

**Access control model:**
- `onlyDAO` modifier: `require(msg.sender == address(this))` - governance proposals execute as the DAO itself via `call` or `delegatecall`. This is the primary access gate for all configuration changes.
- Token contracts use their own `onlyDAO` modifier: `require(msg.sender == DAO)` where `DAO` is the Moloch clone address.
- DAICO uses `msg.sender` as the DAO identifier for storage keys (e.g., `sales[msg.sender][tribTkn]`).

**Access control gaps:**
1. **`multicall` is publicly callable** (`Moloch.sol:1022`). Any external caller can batch delegatecalls to the Moloch contract. Since each delegatecalled function checks its own authorization, and `msg.sender` is preserved in the delegatecall context, this is safe - an unauthorized caller cannot bypass `onlyDAO` checks through multicall.

2. **`openProposal` has no access control beyond optional threshold** (`Moloch.sol:295-362`). Anyone can open (snapshot) a proposal if `proposalThreshold` is 0. This is by design but means an attacker could front-run proposal opening to choose an unfavorable snapshot block. The `castVote` auto-open at line 375 mitigates this by allowing voters to open during voting.

3. **DAICO sale configuration trust model** (`DAICO.sol:204-230`): `setSale` uses `msg.sender` as the DAO address. Only the DAO itself can configure its sales, which requires a governance vote. This is correct.

### 8.4 Flash Loan Attack Vectors

**Mitigations in place:**
- **Ragequit timelock** (`Moloch.sol:42`): `uint64 public ragequitTimelock = 7 days` prevents flash-loan-borrow -> ragequit -> return attacks. The `lastAcquisitionTimestamp` tracking in Shares (line 1205) and Loot (line 1755) enforces this.
- **Snapshot voting** (`Moloch.sol:307`): Uses `block.number - 1` for snapshots, preventing same-block manipulation.
- **DAO self-voting blocked** (`Moloch.sol:372`): `if (msg.sender == address(this)) revert Unauthorized()` prevents the DAO treasury shares from voting.

### 8.5 Frontrunning Concerns

1. **Sale purchase frontrunning**: `buyShares` (`Moloch.sol:769`) has a `maxPay` slippage parameter (line 784). DAICO `buy()` has `minBuyAmt` (line 552) and `buyExactOut()` has `maxPayAmt` (line 616). These provide adequate frontrun protection.

2. **Ragequit frontrunning**: An attacker could see a ragequit transaction and front-run it by draining treasury tokens via a previously approved allowance. The ragequit timelock helps but doesn't fully prevent this if the attacker has pre-existing allowances.

3. **Proposal execution frontrunning**: `executeByVotes` is callable by anyone once a proposal succeeds. The first caller executes it. This is by design (permissionless execution) but means the executor can sandwich the execution.

### 8.6 Sentinel Address Pattern

The codebase uses sentinel addresses for special meanings:
- `address(0)` = ETH (in ragequit, payments)
- `address(this)` = mint shares (in `_payout`, line 1127)
- `address(1007)` = mint loot (in `_payout`, line 1129)
- `address(this)` also used as futarchy reward token marker

**FINDING: `address(1007)` sentinel collision risk.** Address `0x00000000000000000000000000000000000003EF` is used as a sentinel for "mint loot." While extremely unlikely, if a contract were deployed at this address, tokens could not be transferred to/from it via ragequit (blocked at line 863). The ragequit explicitly blocks this address to prevent draining minted-loot markers.

---

## 9. Dependencies

### 9.1 External Libraries

| Library | Source | Usage | Concern |
|---------|--------|-------|---------|
| forge-std | foundry-rs/forge-std | Test framework only | Low risk - not in production |
| solady | vectorized/solady | Remapped but **not imported** in any src file | No actual dependency |
| ZAMM | zammdefi/ZAMM | Only used via `IZAMM` interface in DAICO.sol | Interface-only dependency |

**Key observation:** Despite `@solady` being configured as a remapping, **no source file imports from solady**. The Display library (`renderers/Display.sol`) re-implements common utilities (Base64 encoding, hex checksummed addresses, string operations) from scratch using inline assembly. This eliminates the external dependency risk but increases the maintenance burden and surface area for bugs in these utilities.

### 9.2 Copied/Duplicated Code

The following code patterns are duplicated across contracts:

1. **Reentrancy guard** - Identical assembly in `Moloch.sol:1136-1150`, `DAICO.sol:168-182`, `Tribute.sol:222-236`. All use the same slot value `0x929eee149b4bd21268`.

2. **Safe transfer functions** - Duplicated across all three contract files:
   - `safeTransferETH` appears in `Moloch.sol:2151`, `DAICO.sol:1350`, `Tribute.sol:239`
   - `safeTransfer` appears in `Moloch.sol:2160`, `DAICO.sol:1359`, `Tribute.sol:248`
   - `safeTransferFrom` appears in `Moloch.sol:2176`, `DAICO.sol:1375`, `Tribute.sol:264` (with different signatures - Moloch's takes only `token, amount` while DAICO's takes `token, from, to, amount`)
   - `balanceOfThis`/`balanceOf` appears in `Moloch.sol:2140`, `DAICO.sol:1339`

3. **`onlyDAO` modifier** - Defined 4 times with slightly different semantics:
   - `Moloch.sol:22`: `require(msg.sender == address(this))`
   - `Shares:1210`: `require(msg.sender == DAO)`
   - `Loot:1761`: `require(msg.sender == DAO)`
   - `Badges:1855`: `require(msg.sender == DAO)`

**Assessment:** The duplication is intentional to keep contracts self-contained (no library imports = simpler deployment and verification). The risk is that a bug fix in one copy may not be applied to others. The `safeTransferFrom` difference between Moloch and DAICO/Tribute (2-arg vs 4-arg) is a meaningful API difference, not a copy error.

### 9.3 ZAMM Integration Risk

DAICO.sol hardcodes the ZAMM singleton address (line 76):
```solidity
IZAMM constant ZAMM = IZAMM(0x000000000000040470635EB91b7CE4D132D616eD);
```

If ZAMM is compromised or has a bug, DAICO LP operations could be affected. However, LP operations are optional (only activated when `lpBps > 0`) and the DAICO contract uses `ensureApproval` (line 1400) which grants max approval to ZAMM. A malicious ZAMM could drain approved tokens.

---

## 10. Testing & Verification

### 10.1 Test Suite Overview

| Test File | Tests | Lines | Focus |
|-----------|-------|-------|-------|
| `Moloch.t.sol` | 176 | 3,801 | Core governance, voting, delegation, execution, ragequit, futarchy, badges, permits, sales, chat, config events |
| `DAICO.t.sol` | 214 (148+6+60) | 7,779 | Token sales, tap mechanism, LP config, summon helpers, ZAMM integration |
| `MolochViewHelper.t.sol` | 52 | 2,101 | Batch read functions, pagination, DAICO views |
| `Tribute.t.sol` | 24 | 478 | OTC escrow propose/cancel/claim |
| `ContractURI.t.sol` | 4 | 247 | On-chain metadata, DUNA covenant |
| `URIVisualization.t.sol` | 18 | 807 | SVG rendering |
| `Bytecodesize.t.sol` | 11 | 247 | Contract size limits |
| **Total** | **499** | **15,460** | |

**All 499 tests pass.** Test-to-source ratio: 15,460 test lines / 6,244 source lines = **2.48x** coverage by line count.

### 10.2 Fuzz Testing

Fuzz tests are present in both core test files:

**Moloch.t.sol:**
- `test_SplitDelegation_FuzzAllocationsMatchVotes` (line 1657) - Fuzzes split delegation BPS allocations
- `testFuzz_Ragequit_Distribution` (line 2602) - Fuzzes ragequit share/loot/treasury amounts

**DAICO.t.sol:**
- `testFuzz_Buy_ETH` (line 1887) - Fuzzes ETH buy amounts
- `testFuzz_BuyExactOut_ETH` (line 1907) - Fuzzes exact-out buy amounts
- `testFuzz_TapClaim` (line 1932) - Fuzzes tap rate and elapsed time
- `testFuzz_QuoteBuy` (line 1965) - Fuzzes quote calculations
- `testFuzz_QuotePayExactOut` (line 1980) - Fuzzes exact-out quote calculations
- `testFuzz_SummonDAICO` (line 3344) - Fuzzes summon parameters
- `testFuzz_SummonDAICOWithTap` (line 4296) - Fuzzes summon+tap parameters
- `testFuzz_Buy_Amounts` (line 4997) - Fuzzes buy with various amounts
- `testFuzz_BuyExactOut_Amounts` (line 5023) - Fuzzes exact-out with various amounts
- `testFuzz_Buy_ETH_WithLP` (line 5983) - Fuzzes LP-integrated buys
- `testFuzz_SetSaleWithLPAndTap` (line 6822) - Fuzzes LP+tap setup
- `testFuzz_QuoteBuy_WithLP` (line 6858) - Fuzzes LP-aware quotes

### 10.3 Invariant-Style Tests

Present in `Moloch.t.sol`:
- `test_Invariant_SharesSupplyEqualsBalances` (line 2653) - Share supply conservation
- `test_Invariant_VotesNeverExceedSnapshotSupply` (line 2707) - Vote weight bounds
- `test_Invariant_LootSupplyEqualsBalances` (line 2748) - Loot supply conservation
- `test_Invariant_DelegationVotesMatchShares` (line 2777) - Delegation correctness

**Note:** These are not Foundry-native `invariant_*` tests (which use stateful fuzzing). They are manually constructed invariant checks. The project would benefit from true stateful invariant testing using Foundry's `invariant_*` framework.

### 10.4 Coverage Gaps

1. **No formal invariant testing** - No `invariant_*` test functions or `Handler` contracts for stateful fuzzing.
2. **Limited edge case testing for checkpoint binary search** - The `_checkpointsLookup` function (line 1697) is critical for vote weight determination but only tested indirectly through voting tests.
3. **No cross-contract reentrancy tests** - While individual functions have reentrancy guards, there are no tests verifying that `multicall` + payable function interactions are safe.
4. **No gas benchmarking tests** - The `Bytecodesize.t.sol` checks contract sizes but no tests verify gas consumption bounds for critical operations.
5. **Tribute cleanup** - `daoTributeRefs` and `proposerTributeRefs` grow unboundedly. No tests verify behavior when these arrays become very large.
6. **No test for `op=1` (delegatecall) execution** - `test_DelegateCallExecution` exists (line 1192) but tests should verify storage safety and potential corruption vectors.

### 10.5 CI/CD

`.github/workflows/ci.yml` runs:
1. `forge build` - compilation check
2. `forge test -vvv` - full test suite with verbose output
3. `biome lint dapp` - frontend linting

Triggered on push to `main` and `everything` branches, and on pull requests.

**Missing from CI:**
- `forge coverage` - no coverage reporting
- `forge snapshot` - no gas snapshot comparison
- Static analysis tools (Slither, Mythril)
- Formal verification

---

## 11. Platform-Specific Guidance

### 11.1 Solidity Version

Using Solidity 0.8.33 (pinned in `foundry.toml:2`). This is a recent, stable compiler version with:
- Built-in overflow protection (with `unchecked` opt-out)
- Custom errors (used extensively)
- User-defined value types support
- Transient storage (`tstore`/`tload`) support (used for reentrancy guards)

**No compiler warnings observed** during test execution.

### 11.2 Inline Assembly Usage

The codebase uses inline assembly extensively (29 occurrences across 4 source files):

**Moloch.sol (12 occurrences):**
- Clone deployment (lines 265-276, 2221-2231)
- Reentrancy guard (lines 1139-1149)
- Multicall error forwarding (lines 1027-1029)
- Overflow revert (lines 2121-2124)
- `mulDiv` (lines 2129-2137)
- Token transfer helpers (lines 2141-2193)

**Display.sol (5 occurrences):**
- String escaping (lines 141-163)
- `toString` (lines 169-185)
- `slice` (lines 192-211)
- Hex checksummed address (lines 217-249)
- Base64 encoding (lines 255-286)

**DAICO.sol (7 occurrences):**
- Reentrancy guard (lines 171-181)
- Token transfer helpers (lines 1340-1425)

**Tribute.sol (5 occurrences):**
- Reentrancy guard (lines 225-235)
- Token transfer helpers (lines 240-280)

All assembly blocks are marked `"memory-safe"`, which is correct for the operations performed. The assembly is well-structured and follows established patterns (e.g., Solady-style safe transfers).

**Concern:** The `_ffs` function in Badges (`Moloch.sol:2071-2082`) uses a complex bit manipulation lookup table. While functionally correct (and verified by `FfsHelper` in tests), the magic constants are opaque and would benefit from a comment linking to the algorithm source.

### 11.3 EVM Version Considerations

Target EVM: **Cancun** (configured in `foundry.toml:3`)

Cancun-specific features used:
- `tstore`/`tload` (EIP-1153) for reentrancy guards - This means the contracts **will not work on chains that don't support Cancun** (pre-Dencun L1 or older L2s).

### 11.4 Contract Size

`Bytecodesize.t.sol` verifies all contracts stay under the 24,576-byte EVM limit. The `foundry.toml` sets `code_size_limit = 30000` to bypass forge's local check, with a note that this only bypasses the local check, not the EVM limit.

The `via_ir = true` and `optimizer_runs = 500` configuration is specifically tuned to balance ViewHelper size (near the limit at ~24,392 bytes) against stack depth issues.

### 11.5 Tools Integration

- **Foundry** (forge, anvil) - primary development toolchain
- **Biome** - frontend linting
- **No static analysis tools configured** (Slither, Mythril, etc.)
- **No formal verification tools** (Certora, Halmos, etc.)

---

## 12. Prioritized Recommendations

### CRITICAL

**C-1: `multicall` + `msg.value` double-spend vector**
- **Location:** `Moloch.sol:1022-1033`
- **Issue:** `multicall` performs delegatecalls in a loop. In Solidity, `msg.value` persists across delegatecalls within the same transaction. If a payable function checks `msg.value` (e.g., `fundFutarchy` at line 608: `if (msg.value != amount) revert NotOk()`), it could be called multiple times with the same `msg.value`. The `nonReentrant` guard prevents this for functions that use it, but `fundFutarchy` is indeed protected by `nonReentrant` indirectly (it's not `nonReentrant` itself but can only be called via governance or directly). Direct calls to `fundFutarchy` via `multicall` could exploit this: a user could call `fundFutarchy` twice in one multicall, each time checking `msg.value`, but only sending ETH once.
- **Recommendation:** Add `nonReentrant` to `fundFutarchy`, or add a check that `msg.value` has not already been consumed. Alternatively, consider making `multicall` non-payable or tracking consumed ETH.

**C-2: Delegatecall execution via governance can corrupt storage**
- **Location:** `Moloch.sol:1105-1115`, specifically `op=1` path at line 1112
- **Issue:** Proposals with `op=1` execute arbitrary delegatecalls from the Moloch contract's context. A malicious (or buggy) target contract could overwrite Moloch's storage slots, including critical governance parameters, token references, and proposal state.
- **Assessment:** This is by design for maximum governance flexibility, but it represents the single highest-impact attack vector in the system. A single governance proposal with delegatecall to a malicious target could steal the entire treasury, modify quorum settings, mint unlimited shares, etc.
- **Recommendation:** Consider adding a governance-configurable allowlist of delegatecall targets, or at minimum, document this risk prominently and ensure frontends clearly warn when proposals use `op=1`.

### HIGH

**H-1: No formal specification for state machine transitions**
- **Issue:** The 7-state proposal state machine (`Unopened -> Active -> Queued -> Succeeded/Defeated/Expired -> Executed`) is implemented in code but not formally specified. Edge cases like unanimous consent bypass (line 481), zero-TTL proposals, and the interaction between queue() and executeByVotes() are complex.
- **Recommendation:** Create a formal state transition diagram with all preconditions and postconditions for each transition. This should be reviewed independently from the code.

**H-2: Unbounded `proposalIds` array**
- **Location:** `Moloch.sol:73`, pushed at line 319
- **Issue:** `proposalIds` grows without bound. Over time, this makes the ViewHelper's `getProposalCount()` and `_getProposals()` more expensive. There is no mechanism to archive or prune old proposals.
- **Recommendation:** Document the expected growth rate and gas implications. Consider pagination limits in the ViewHelper to prevent RPC timeouts.

**H-3: Missing static analysis in CI**
- **Location:** `.github/workflows/ci.yml`
- **Issue:** The CI pipeline runs `forge build` and `forge test` but no static analysis tools (Slither, Mythril) or formal verification.
- **Recommendation:** Add `slither .` to the CI pipeline. Slither can catch common vulnerability patterns and would complement the existing test suite.

**H-4: `ragequit` token array has no length bound**
- **Location:** `Moloch.sol:828-876`
- **Issue:** A user can pass an arbitrarily long token array to `ragequit`. Each token requires an external call (`balanceOfThis` or `address.balance`) and potentially an ERC-20 transfer. With enough tokens, this could hit the block gas limit.
- **Recommendation:** Consider adding a maximum token count (e.g., 50) to prevent gas-griefing. Alternatively, document the practical limit based on gas costs.

### MEDIUM

**M-1: Tally fields are `uint96`, which limits max supply to ~79 billion tokens**
- **Location:** `Moloch.sol:66-70`
- **Issue:** `Tally.forVotes`, `Tally.againstVotes`, `Tally.abstainVotes` are `uint96`. The accumulation is `unchecked` (line 397). If total share supply exceeds `type(uint96).max` (~79.2e27 wei = ~79.2 billion tokens at 18 decimals), tally overflow would produce incorrect vote counts.
- **Recommendation:** Document the maximum supported supply. At 18 decimals, 79 billion tokens is a large number, but unbounded minting via governance could exceed this.

**M-2: Tribute discovery arrays grow without bound**
- **Location:** `Tribute.sol:53-56`
- **Issue:** `daoTributeRefs` and `proposerTributeRefs` are append-only. Cancelled or claimed tributes remain in the arrays (only the main `tributes` mapping is deleted). The `getActiveDaoTributes` function (line 183) iterates the entire array on every call.
- **Recommendation:** Consider a cleanup mechanism, or switch to a mapping-based structure with an explicit count.

**M-3: `ensureApproval` grants `type(uint256).max` approval to ZAMM**
- **Location:** `DAICO.sol:1400-1425`
- **Issue:** The DAICO contract grants max approval to the hardcoded ZAMM address. If ZAMM is compromised, it could drain all tokens the DAICO contract has received.
- **Recommendation:** Consider exact-amount approvals instead of infinite approvals, or document the ZAMM trust assumption prominently.

**M-4: Clone initialization front-running**
- **Location:** `Shares.sol:1248-1257`, `Loot.sol:1767-1769`, `Badges.sol:1865-1867`
- **Issue:** Implementation contracts check `require(DAO == address(0))` for one-time initialization. If the implementation contract itself is initialized (DAO set to a non-zero address), it cannot be re-initialized, but since clones have their own storage, this doesn't affect clones. However, the implementation contracts are live on-chain and could be initialized by anyone to set DAO to their address. While this is not exploitable (implementations are never used directly for governance), it could cause confusion.
- **Recommendation:** Consider adding a constructor that sets `DAO` to a dead address in implementation contracts, preventing external initialization.

**M-5: No access control on `queue()` function**
- **Location:** `Moloch.sol:518-525`
- **Issue:** Anyone can call `queue()` to start the timelock countdown on a Succeeded proposal. This is by design (permissionless queueing), but in combination with a short `timelockDelay`, an attacker could front-run the proposer to start the countdown earlier than intended.
- **Recommendation:** This is likely acceptable by design (anyone can queue a passing proposal), but should be documented.

### LOW

**L-1: Duplicated safe transfer functions across contracts**
- **Location:** `Moloch.sol:2140-2193`, `DAICO.sol:1339-1425`, `Tribute.sol:239-281`
- **Issue:** The same assembly-based token transfer functions are duplicated across three contract files. A bug fix in one file might not be applied to others.
- **Recommendation:** Consider extracting these into a shared Solidity library file imported by all contracts, or at minimum, add a comment in each copy referencing the canonical source.

**L-2: `_ffs` magic constants lack documentation**
- **Location:** `Moloch.sol:2071-2082`
- **Issue:** The find-first-set function uses magic constant tables. While verified by `FfsHelper` in tests, the algorithm origin is not documented.
- **Recommendation:** Add a comment referencing the De Bruijn bit isolation technique or the specific algorithm source.

**L-3: No `forge coverage` in CI**
- **Location:** `.github/workflows/ci.yml`
- **Issue:** Code coverage is not measured or tracked. While the test-to-source ratio is good (2.48x), specific functions may have untested paths.
- **Recommendation:** Add `forge coverage` to CI and set minimum coverage thresholds for core contracts.

**L-4: `safeTransfer` may not handle all non-compliant ERC20s**
- **Location:** `Moloch.sol:2160-2174`
- **Issue:** The safe transfer implementation handles both void-return and bool-return tokens. The check `iszero(and(eq(mload(0x00), 1), success))` with fallback `iszero(lt(or(iszero(extcodesize(token)), returndatasize()), success))` is Solady-style. However, some tokens (e.g., USDT) require allowance to be set to 0 before setting a new non-zero value. The Moloch contract doesn't call `approve` directly (it uses `safeTransferFrom`), so this is only relevant for DAICO's `ensureApproval` function, which handles this case correctly.
- **Recommendation:** Document which ERC-20 token behaviors are supported and which are not (e.g., fee-on-transfer tokens would break ragequit calculations).

**L-5: `getSeats()` popcount has unnecessary double loop**
- **Location:** `Moloch.sol:1934-1952`
- **Issue:** `getSeats()` iterates the occupied bitmap twice: once to count set bits, once to extract them. The first loop (lines 1938-1941) uses `m &= (m - 1)` to count bits but discards the bit positions. A single-pass approach would be more efficient.
- **Recommendation:** Minor gas optimization opportunity for a view function; low priority.

**L-6: `buyShares` CEI pattern has ETH refund after state change**
- **Location:** `Moloch.sol:795-799`
- **Issue:** In the ETH payment path, after checking `msg.value >= cost` and updating cap (line 789), excess ETH is refunded: `safeTransferETH(msg.sender, msg.value - cost)`. While `nonReentrant` prevents reentrancy, the pattern sends ETH before share minting (lines 808-816). The `nonReentrant` guard makes this safe, but without it, the refund before share issuance would be a reentrancy vector.
- **Recommendation:** No action needed since `nonReentrant` is in place, but the code comment at line 786 is somewhat misleading since the actual CEI order is Check-Effect-Interaction-Effect.

---

## Summary Statistics

| Metric | Value |
|--------|-------|
| Total source lines | 6,244 |
| Total test lines | 15,460 |
| Test/source ratio | 2.48x |
| Total tests | 499 |
| Passing tests | 499 (100%) |
| Fuzz tests | 14 |
| Invariant-style tests | 4 (manual, not Foundry-native) |
| Assembly blocks (src) | 29 |
| Unchecked blocks (src) | 44 |
| Events defined | 35 |
| External dependencies | 0 (in production; solady remapped but unused) |
| Inline assembly files | 4/12 source files (33%) |
| CRITICAL findings | 2 |
| HIGH findings | 4 |
| MEDIUM findings | 5 |
| LOW findings | 6 |

---

*Report generated by Trail of Bits Guidelines Advisor analysis framework.*
*This report is based solely on static code analysis and does not include dynamic testing or formal verification results.*

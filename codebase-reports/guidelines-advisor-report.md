# Majeur DAO Governance Framework - Trail of Bits Guidelines Advisor Report

**Date:** 2026-01-26
**Framework:** Building Secure Contracts - Development Guidelines (Trail of Bits)
**Codebase:** Majeur (Moloch-style DAO Governance)
**Solidity Version:** 0.8.30
**EVM Target:** Cancun

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [System Documentation & Specifications](#2-system-documentation--specifications)
3. [Architecture Analysis](#3-architecture-analysis)
4. [Upgradeability Review](#4-upgradeability-review)
5. [Delegatecall & Proxy Pattern Review](#5-delegatecall--proxy-pattern-review)
6. [Function Composition Analysis](#6-function-composition-analysis)
7. [Inheritance Assessment](#7-inheritance-assessment)
8. [Events Coverage](#8-events-coverage)
9. [Common Pitfalls Analysis](#9-common-pitfalls-analysis)
10. [Dependencies Review](#10-dependencies-review)
11. [Testing & Verification](#11-testing--verification)
12. [Platform-Specific Guidance](#12-platform-specific-guidance)
13. [Prioritized Recommendations](#13-prioritized-recommendations)
14. [Overall Assessment](#14-overall-assessment)

---

## 1. Executive Summary

Majeur is a minimalist yet feature-rich DAO governance framework implementing Moloch-style governance with modern enhancements. The codebase comprises approximately 6,084 lines of Solidity source code across 5 contract files, with 15,196 lines of tests across 7 test files.

**Key Strengths:**
- Zero external dependency in production contracts (no imports at all)
- Extensive test coverage (474 passing tests, including fuzz tests)
- Well-documented v1-to-v2 security improvements (ragequit timelock, DAO self-voting prevention, quorum deadlock fix)
- EIP-1153 transient storage reentrancy guards
- Thoughtful architecture using minimal proxy clones for gas-efficient deployments

**Key Concerns:**
- Renderer contract exceeds the 24,576-byte EVM code size limit (25,270 bytes)
- Delegatecall execution path (op=1) in proposals is extremely powerful and needs careful governance
- `multicall` function uses delegatecall in a loop without reentrancy guard
- Several inline assembly blocks that replicate well-audited library patterns but increase audit surface
- Duplicated safe transfer functions across three separate contracts
- No formal verification or invariant testing harness

---

## 2. System Documentation & Specifications

### 2.1 Plain English System Description

Majeur is an opinionated on-chain DAO governance framework with these core primitives:

**Token System:**
- **Shares** (ERC-20 + ERC-20Votes): Voting power + economic rights. Supports split delegation across up to 4 delegates with BPS-weighted allocation. Delegatable.
- **Loot** (ERC-20): Economic rights only (no voting power). Non-delegatable.
- **Badges** (ERC-721 SBT): Soulbound tokens auto-minted to the top 256 shareholders. Used to gate DAO chatroom access. Non-transferable.
- **Receipts** (ERC-6909): Minted when votes are cast, used for futarchy payouts. Permit receipts are soulbound.

**Governance:**
- Proposals are identified by a hash of `(dao, op, to, value, keccak256(data), nonce, config)`.
- Voting uses snapshot checkpoints at block N-1 to prevent flash loan attacks.
- Proposals can be auto-opened on first vote or explicitly opened.
- Quorum can be configured as absolute count, BPS of votable supply, or both.
- DAO-held shares are excluded from quorum denominator (v2 fix).
- Unanimous consent (100% FOR) bypasses both TTL and timelock.
- The DAO contract itself is prevented from voting.

**Economic Features:**
- **Ragequit**: Members can burn shares/loot to receive pro-rata treasury distribution, subject to a configurable timelock (default 7 days).
- **Futarchy**: Prediction markets on proposals where voters bet on outcomes using ERC-6909 receipts.
- **Token Sales**: Built-in fixed-price share/loot sales with ETH or ERC-20 payment tokens.
- **DAICO**: External contract managing token sales with tap mechanism (controlled fund release to operations team) and optional ZAMM DEX liquidity provisioning.
- **Tribute**: OTC escrow system for tribute proposals.

**Deployment:**
- Factory pattern using `Summoner` contract that deploys minimal proxy clones via CREATE2.
- Each DAO clone deploys its own Shares, Loot, and Badges clones via CREATE2 from the DAO address.
- Deterministic addressing enables pre-computation of addresses for initialization.

### 2.2 Documentation Quality Assessment

| Document | Status | Quality |
|----------|--------|---------|
| `CLAUDE.md` | Present | Good -- comprehensive project overview |
| `README.md` | Present | Not reviewed in detail |
| `docs/v1-v2-contract-differences.md` | Present | Excellent -- thorough security changelog with attack vectors |
| `docs/viewhelper-stack-bug.md` | Present | Good -- documents a specific bug fix |
| NatSpec in `Moloch.sol` | Partial | 33 NatSpec comments for a 2,145-line file. Many public functions lack `@notice`/`@param`/`@return` |
| NatSpec in `DAICO.sol` | Good | 139 NatSpec comments for 1,425 lines |
| NatSpec in `MolochViewHelper.sol` | Good | 75 NatSpec comments for 1,342 lines |
| NatSpec in `Tribute.sol` | Minimal | 6 NatSpec comments for 281 lines |
| NatSpec in `Renderer.sol` | Minimal | 9 NatSpec comments for 891 lines |

### 2.3 Documentation Gaps

1. **Missing function-level NatSpec in `Moloch.sol`**: The following public/external functions lack complete NatSpec documentation:
   - `castVote()` -- has only a brief `@dev` comment, no `@param`/`@return`
   - `cancelVote()` -- no NatSpec
   - `cancelProposal()` -- no NatSpec
   - `state()` -- no NatSpec despite being a critical state machine function
   - `ragequit()` -- no NatSpec
   - `buyShares()` -- no NatSpec
   - `chat()` -- no NatSpec
   - `transfer()`/`transferFrom()` (ERC-6909) -- no NatSpec
   - All setter functions (`setQuorumBps`, `setMinYesVotesAbsolute`, etc.) -- no NatSpec

2. **Missing architectural decision documentation**: No formal document explaining:
   - Why EIP-1153 transient storage was chosen over slot-based reentrancy (portability concern)
   - The trust model between Moloch, Shares, Loot, and Badges contracts
   - Why inline assembly is used for safe transfers rather than importing a library
   - The rationale for `address(1007)` as a sentinel for loot minting in `_payout()`

3. **Missing invariant documentation**: No formal specification of system invariants, e.g.:
   - Sum of all delegate votes == total share supply at any given block
   - Ragequit distributions are exactly pro-rata
   - ERC-6909 receipt supply matches vote tallies

4. **Missing threat model / trust assumptions**: No documented threat model describing:
   - What the DAO can do via proposals (essentially arbitrary)
   - Trust boundaries between peripheral contracts (DAICO, Tribute) and core (Moloch)
   - Known acceptable risks

---

## 3. Architecture Analysis

### 3.1 On-Chain vs Off-Chain Distribution

**On-chain components:**
- All governance logic, token management, treasury operations, and futarchy settlement
- On-chain SVG metadata rendering (`Renderer.sol`)
- On-chain message board (`chat()` + `messages[]`)
- View helper for batch reading (`MolochViewHelper.sol`)

**Off-chain components:**
- Frontend dApps (`Majeur.html`, `DAICO.html`) -- no build step, served as static HTML
- Deployment scripts (Foundry Solidity scripts + bash scripts)

**Assessment:**
The architecture is heavily on-chain, which is appropriate for a trustless governance framework. The on-chain SVG rendering in `Renderer.sol` is ambitious but creates code size pressure (the contract exceeds the EVM limit). The on-chain chatroom is gas-expensive but provides censorship-resistant communication gated by badge ownership.

The `MolochViewHelper.sol` is a read-only batch view contract that aggregates many cross-contract calls. This is a good pattern for reducing frontend RPC calls, though the contract is very large (approaching size limits).

### 3.2 Contract Interaction Map

```
Summoner (Factory)
    |
    |-- creates --> Moloch (DAO proxy clone)
                       |
                       |-- creates --> Shares (ERC-20 clone)
                       |-- creates --> Loot (ERC-20 clone)
                       |-- creates --> Badges (ERC-721 SBT clone)
                       |
                       |-- references --> Renderer (on-chain SVG)
                       |
                       |-- interacts <--> DAICO (token sales + tap)
                       |-- interacts <--> Tribute (OTC escrow)
                       |
                       |-- read by --> MolochViewHelper (batch reader)
```

### 3.3 Trust Boundaries

| Boundary | Trust Level | Notes |
|----------|-------------|-------|
| Summoner -> Moloch | Factory | One-way creation; Summoner has no ongoing access |
| Moloch -> Shares/Loot/Badges | Full Trust | Moloch is the DAO of these tokens; has mint/burn/lock authority |
| Moloch -> Renderer | Read-only | Only called for URI generation; can be changed by governance |
| Moloch -> DAICO | Allowance-based | DAICO operates via ERC-20 approve + Moloch allowance mechanism |
| Moloch -> Tribute | Caller-based | Tribute is called by DAO for claim; proposers interact directly |
| Moloch governance | Unlimited | Proposals with op=0 can call any address; op=1 can delegatecall |

### 3.4 Critical Observation: Governance Power

The DAO governance system grants **unlimited execution power** via proposals:
- `op=0` (call): Can call any external contract with any calldata and ETH value
- `op=1` (delegatecall): Can execute arbitrary code in the DAO's context, potentially modifying any storage slot

This is by design (Moloch-style governance), but it means the security of the entire system ultimately depends on the quality of the governance process (quorum, timelock, voter vigilance).

---

## 4. Upgradeability Review

### 4.1 Upgrade Mechanism

Majeur does **not** use a traditional upgrade pattern (e.g., UUPS, transparent proxy). The minimal proxy clones deployed by the Summoner have immutable bytecode -- they always delegate to the same implementation.

However, the governance system provides effective upgradeability through:

1. **`batchCalls()` + `bumpConfig()`**: The DAO can migrate to a new system by:
   - Deploying new contracts
   - Transferring assets via proposals
   - Bumping config to invalidate old proposal IDs

2. **`delegatecall` execution (op=1)**: Proposals can execute delegatecall to arbitrary addresses, effectively running upgrade logic in the DAO's context. This is extremely powerful and dangerous.

3. **Renderer replacement**: The renderer can be changed via `setRenderer()` governance call, providing UI-level upgradeability.

### 4.2 Assessment

**Verdict: Acceptable but requires documentation.**

The lack of a formal upgrade mechanism is appropriate for a trust-minimized DAO. The implicit upgradeability via `delegatecall` proposals should be explicitly documented as a risk, with guidance that DAOs should:
- Set a meaningful timelock delay to give members time to ragequit before risky proposals execute
- Consider high quorum thresholds for `delegatecall` proposals (not currently enforceable at the contract level)

### 4.3 Storage Layout Concern

Since Moloch uses minimal proxy clones (not upgradeable proxies), there is no storage collision risk in the traditional sense. However, `delegatecall` proposals (op=1) execute in the DAO's storage context, meaning a malicious or buggy target contract could corrupt DAO storage. This is an inherent risk of the design and should be prominently documented.

---

## 5. Delegatecall & Proxy Pattern Review

### 5.1 Minimal Proxy Clones

**Location:** `Moloch.sol:252-264` (clone creation), `Moloch.sol:2115-2125` (Summoner clone creation)

The clone pattern uses raw assembly to deploy EIP-1167 minimal proxies. The bytecode pattern:
```
602d5f8160095f39f35f5f365f5f37365f73{impl}5af43d5f5f3e6029573d5ffd5b3d5ff3
```

**Assessment:** The pattern is well-established. The CREATE2 usage with deterministic salts enables address prediction, which DAICO leverages for pre-computing init call targets.

**Potential Issue:** The salt for token clones is `bytes32(bytes20(address(this)))`, meaning it's derived from the DAO address. This is deterministic and correct but means that if a DAO is created at the same address on a different chain (via the same Summoner), the token clones would also have the same addresses. This is expected behavior for cross-chain consistency.

### 5.2 Delegatecall in Execution

**Location:** `Moloch.sol:1012`
```solidity
(ok, retData) = to.delegatecall(data);
```

This is called from `_execute()` when `op == 1`. It runs arbitrary code in the DAO's context with full storage access. This is protected by:
- Full governance flow (proposal + quorum + majority + timelock)
- Unanimous consent bypass (which requires 100% participation)
- `nonReentrant` modifier on `executeByVotes()`

### 5.3 Delegatecall in Multicall

**Location:** `Moloch.sol:925`
```solidity
(bool success, bytes memory result) = address(this).delegatecall(data[i]);
```

**FINDING (MEDIUM):** The `multicall()` function uses `delegatecall` to self, but:
1. It is **not** protected by `nonReentrant`
2. It allows anyone to call it (no access control)
3. It delegatecalls to `address(this)`, which means it executes functions in the DAO's context

However, since it delegates to `address(this)`, it can only call functions that exist on the DAO contract. Functions with `onlyDAO` modifier would succeed because `msg.sender` is preserved as `address(this)` in a delegatecall to self. But wait -- `multicall` is a public function callable by anyone. When an external user calls `multicall`, `msg.sender` in the delegated call context remains the original caller (because delegatecall to self doesn't change `msg.sender`).

Actually, upon closer inspection: when `multicall` is called externally, `address(this).delegatecall(data[i])` will execute the target function with `msg.sender` preserved as the external caller. The `onlyDAO()` modifier checks `msg.sender == address(this)`, which would fail for external callers. So `multicall` cannot be used by external callers to bypass access control on `onlyDAO` functions.

**However**, if `multicall` is called as part of a governance proposal execution (where `msg.sender == address(this)`), then `onlyDAO` checks would pass. This is the intended use case.

**Revised assessment:** The `multicall` delegatecall pattern is safe because `msg.sender` is preserved correctly. But the lack of `nonReentrant` on `multicall` should be noted -- though in practice, the functions it calls (`setQuorumBps`, `setMetadata`, etc.) are simple storage writes that don't make external calls.

---

## 6. Function Composition Analysis

### 6.1 Function Size and Complexity

| Function | Lines | Complexity | Assessment |
|----------|-------|------------|------------|
| `Moloch.openProposal()` | ~65 | High | Handles snapshot, registry, auto-futarchy. Could benefit from extracting auto-futarchy into a helper. |
| `Moloch.castVote()` | ~45 | Medium | Well-structured with clear validation flow |
| `Moloch.state()` | ~50 | High | Complex state machine with many branches. Comments help but function is dense. |
| `Moloch.ragequit()` | ~45 | Medium | Good use of unchecked block, clear CEI pattern |
| `Shares._repointVotesForHolder()` | ~55 | High | Complex diff-based vote repointing. The algorithm is correct but difficult to audit. |
| `Shares._applyVotingDelta()` | ~35 | Medium | Path-independent allocation change |
| `Badges.onSharesChanged()` | ~70 | High | Seat management with bitmap, eviction, re-computation. Most complex single function. |
| `DAICO._initLP()` | ~80 | High | LP initialization with drift protection, ZAMM interaction |
| `DAICO.buy()` | ~65 | High | Complex buy flow with LP deduction, ETH/ERC20 branching |
| `DAICO.claimTap()` | ~40 | Medium | Clear CEI pattern |

### 6.2 Function Modularity Assessment

**Good patterns:**
- `_payout()` (Moloch.sol:1017) -- clean abstraction for ETH/share/loot/ERC20 payouts
- `_intentHashId()` -- single source of truth for proposal ID computation
- `_receiptId()` -- clean receipt ID derivation
- `_currentDistribution()` -- good encapsulation of delegation state

**Areas for improvement:**
- `openProposal()` mixes proposal registry logic with auto-futarchy earmarking. These are separate concerns.
- `buyShares()` in Moloch.sol handles both ETH and ERC20, minting and transfer, shares and loot -- consider decomposing.
- The Renderer contract (`Renderer.sol`, 891 lines) is a monolithic SVG generator. Its size exceeds the EVM limit. Consider splitting into multiple contracts (e.g., separate renderers for badges, receipts, and contract URIs).

---

## 7. Inheritance Assessment

### 7.1 Inheritance Structure

Majeur uses **no inheritance** in its production contracts. All contracts (`Moloch`, `Shares`, `Loot`, `Badges`, `Summoner`, `DAICO`, `Tribute`, `Renderer`, `MolochViewHelper`) are standalone contracts with no parent classes.

This is a deliberate design choice that:
- **Pros:** Eliminates diamond inheritance issues, makes storage layout explicit, reduces deployment bytecode, simplifies auditing
- **Cons:** Leads to code duplication (especially safe transfer functions), requires manual implementation of standard interfaces

### 7.2 Code Duplication Findings

**FINDING (LOW): Duplicated safe transfer functions across contracts**

The following free functions are duplicated with near-identical implementations:

| Function | `Moloch.sol` | `DAICO.sol` | `Tribute.sol` |
|----------|:---:|:---:|:---:|
| `safeTransferETH()` | Lines 2045-2052 | Lines 1350-1357 | Lines 239-246 |
| `safeTransfer()` | Lines 2054-2068 | Lines 1359-1373 | Lines 248-262 |
| `safeTransferFrom()` (2-arg) | Lines 2070-2087 | N/A | Lines 264-281 |
| `safeTransferFrom()` (4-arg) | N/A | Lines 1375-1392 | N/A |
| `balanceOfThis()` / `balanceOf()` | Lines 2034-2043 | Lines 1339-1348 | N/A |

The DAICO version of `safeTransferFrom` takes 4 arguments (including explicit `from` and `to`), while the Moloch/Tribute versions take 2 arguments (using `caller()` and `address()` implicitly). This is a meaningful API difference, not just duplication.

**Risk:** If a bug is found in one copy, the others may not be updated. However, since these are free functions (not library imports), this is mitigated by the fact that each contract is deployed independently.

---

## 8. Events Coverage

### 8.1 Event Emission Analysis

| Contract | Events Defined | Emit Calls | Assessment |
|----------|---------------|------------|------------|
| `Moloch` | 16 | 42 | Good coverage |
| `DAICO` | 7 | 17 | Good coverage |
| `Tribute` | 3 | 3 | Good coverage |
| `Renderer` | 0 | 0 | Expected (view-only) |
| `MolochViewHelper` | 0 | 0 | Expected (view-only) |

### 8.2 Critical Operations with Events

| Operation | Event | Status |
|-----------|-------|--------|
| Proposal opened | `Opened` | Covered |
| Vote cast | `Voted` | Covered |
| Vote cancelled | `VoteCancelled` | Covered |
| Proposal cancelled | `ProposalCancelled` | Covered |
| Proposal queued | `Queued` | Covered |
| Proposal executed | `Executed` | Covered |
| Permit set | `PermitSet` | Covered |
| Permit spent | `PermitSpent` | Covered |
| Sale configured | `SaleUpdated` | Covered |
| Shares purchased | `SharesPurchased` | Covered |
| Futarchy opened/funded/resolved/claimed | 4 events | Covered |
| Chat message | `Message` | Covered |
| ERC-6909 transfer | `Transfer` | Covered |
| ERC-6909 operator set | `OperatorSet` | Covered |
| Shares/Loot transfer | `Transfer` | Covered |
| Delegation changed | `DelegateChanged` | Covered |
| Split delegation set | `WeightedDelegationSet` | Covered |
| Badge minted/burned | `Transfer` (ERC-721) | Covered |

### 8.3 Missing Events

**FINDING (LOW):** The following governance configuration changes emit no events:

| Function | Missing Event |
|----------|---------------|
| `setQuorumBps()` | No event emitted |
| `setMinYesVotesAbsolute()` | No event emitted |
| `setQuorumAbsolute()` | No event emitted |
| `setProposalTTL()` | No event emitted |
| `setTimelockDelay()` | No event emitted |
| `setRagequittable()` | No event emitted |
| `setRagequitTimelock()` | No event emitted |
| `setProposalThreshold()` | No event emitted |
| `setRenderer()` | No event emitted |
| `setMetadata()` | No event emitted |
| `setAutoFutarchy()` | No event emitted |
| `setFutarchyRewardToken()` | No event emitted |
| `bumpConfig()` | No event emitted |
| `setAllowance()` | No event emitted |
| `setTransfersLocked()` | No event emitted |

These functions modify critical governance parameters but produce no on-chain trail. While they are only callable via governance proposals (which do emit `Executed` events), the parameter changes themselves are not independently auditable from events alone. Off-chain indexers must decode the proposal calldata to determine what changed.

**FINDING (LOW):** The `ragequit()` function does not emit a dedicated Ragequit event. The individual token transfers emit `Transfer` events, but there is no composite event indicating "user X ragequit Y shares and Z loot for N tokens."

---

## 9. Common Pitfalls Analysis

### 9.1 Reentrancy

**Status: Well-mitigated**

All state-modifying functions that make external calls use the `nonReentrant` modifier based on EIP-1153 transient storage (`tload`/`tstore`). This is a modern, gas-efficient approach.

| Function | External Call | Reentrancy Guard |
|----------|--------------|------------------|
| `executeByVotes()` | Arbitrary call/delegatecall | `nonReentrant` |
| `spendPermit()` | Arbitrary call/delegatecall | `nonReentrant` |
| `spendAllowance()` | `_payout()` -> `safeTransfer`/`safeTransferETH` | `nonReentrant` |
| `buyShares()` | `safeTransferFrom()`, `safeTransferETH()` | `nonReentrant` |
| `ragequit()` | `_payout()` in loop | `nonReentrant` |
| `cashOutFutarchy()` | `_payout()` | `nonReentrant` |
| `multicall()` | `delegatecall` to self | **No guard** (see analysis in Section 5.3) |
| `batchCalls()` | Arbitrary calls | **No guard** but `onlyDAO` restricted |
| `init()` | `initCalls[].target.call()` | **No guard** but only callable once |

**FINDING (MEDIUM):** `batchCalls()` makes arbitrary external calls in a loop without `nonReentrant`. It is gated by `onlyDAO` (only callable via governance), and since proposal execution itself is `nonReentrant`, a `batchCalls` invoked via `executeByVotes` would inherit the guard. However, if `batchCalls` is invoked via `multicall` (which uses delegatecall and is not `nonReentrant`), and `multicall` is called by the DAO via a governance proposal's delegatecall... the transient storage guard from `executeByVotes` should still be active since the outer call set it. This is safe but relies on the transient storage guard being set by the outermost `nonReentrant` call.

**Transient Storage Portability Note:** EIP-1153 transient storage requires the Cancun EVM version. The `foundry.toml` correctly sets `evm_version = "cancun"`. If deploying to chains that don't support Cancun, the contracts will fail to deploy. This is documented implicitly by the EVM version setting but should be explicitly called out.

### 9.2 Integer Overflow/Underflow

**Status: Mostly well-handled**

Solidity 0.8.30 provides default overflow protection. The codebase uses `unchecked` blocks in 44 places across source files. Analysis of each unchecked block:

**Safe unchecked usages:**
- `block.number - 1` in `openProposal()` (line 293): Safe because `block.number >= 1` in practice
- Vote tally increments (lines 382-387): Protected by the fact that `weight <= totalSupply`, and three uint96 values cannot overflow if total supply fits in uint96
- Ragequit token loop (lines 778-819): The `total` is the sum of two uint256 values; `amt <= total` is guaranteed by prior burns; the `mulDiv` ensures no overflow
- Shares balance operations in `_mint` (line 1208), `_moveTokens` (line 1219): The `unchecked` on the addition is safe because `balanceOf[to] + amount <= totalSupply` and total supply is checked
- Checkpoint operations (lines 1556 onwards): Safe due to length checks

**Potential concern:**
- `castVote()` lines 382-387: Vote tallies use `uint96`. The `unchecked` block means if `forVotes + weight` would overflow `uint96`, it would silently wrap. However, since each individual weight comes from `getPastVotes` (which returns values capped at total supply, also uint96), and the total of all votes cannot exceed total supply, this is safe as long as total supply fits in uint96. The `toUint96()` safe cast is used elsewhere but not enforced on total supply. The `_mint` function in Shares uses `totalSupply += amount` which would revert on overflow (not unchecked), so total supply is bounded to uint256 max, but the uint96 cast of individual voting weights could theoretically fail if supply exceeds uint96 max (7.9e28). This is a theoretical concern for extreme supply scenarios.

### 9.3 Access Control

**Status: Well-implemented**

| Pattern | Usage | Assessment |
|---------|-------|------------|
| `onlyDAO` modifier | All governance parameter setters | Correct -- checks `msg.sender == address(this)` |
| `SUMMONER` check | `init()` | Correct -- only Summoner can initialize |
| `DAO` check on tokens | `mintFromMoloch`, `burnFromMoloch`, etc. | Correct -- only the DAO can mint/burn |
| Proposer check | `cancelProposal()` | Correct -- only proposer can cancel |
| Badge gate | `chat()` | Correct -- requires badge ownership |
| DAO self-vote prevention | `castVote()` | Correct (v2) -- prevents `address(this)` from voting |

**FINDING (LOW):** There is no role-based access control. All governance power flows through proposal execution. This is by design (minimalism) but means there is no emergency pause mechanism. If a critical vulnerability is discovered, the DAO must go through the full governance process (unless unanimous consent is achievable) to mitigate it.

### 9.4 Front-Running

**Status: Largely mitigated**

- **Vote front-running:** Snapshots at `block.number - 1` prevent acquiring tokens and voting in the same block.
- **Ragequit front-running:** The 7-day timelock prevents flash-loan-style ragequit attacks.
- **Sale front-running:** The `buyShares()` function has a `maxPay` parameter for slippage protection on ETH sales.
- **DAICO front-running:** Both `buy()` and `buyExactOut()` have slippage bounds (`minBuyAmt` and `maxPayAmt`).

**No mitigation for:**
- Proposal content front-running: Since proposal IDs are deterministic hashes, an attacker observing a pending proposal submission in the mempool could front-run by opening it first (changing the `proposerOf` mapping). This is a minor griefing vector.
- MEV on `ragequit()`: Token ordering is enforced (ascending), but sandwich attacks around ragequit treasury distributions are theoretically possible.

### 9.5 Rounding and Precision

**Status: Adequate with some considerations**

The `mulDiv` function (lines 2022-2031) implements standard multiply-then-divide with overflow checking. It always rounds down (truncation).

**Potential issues:**
1. **Ragequit rounding:** `due = mulDiv(pool, amt, total)` rounds down. This means small holders may lose dust amounts. The last ragequitter gets whatever is left. This is standard Moloch behavior and acceptable.

2. **Futarchy payout rounding:** `payoutPerUnit = mulDiv(pool, 1e18, winSupply)` rounds down, then `payout = mulDiv(amount, F.payoutPerUnit, 1e18)` also rounds down. Double rounding means winners may receive slightly less than their exact share. Small dust may remain unclaimed in the contract.

3. **Split delegation rounding:** `_targetAlloc()` uses `mulDiv(bal, B[i], BPS_DENOM)` for all delegates except the last, who receives the remainder. This "remainder to last" approach ensures no votes are lost but creates asymmetry -- the last delegate in the array gets any rounding difference.

### 9.6 Denial of Service

**FINDING (LOW):** The `proposalIds` array grows unboundedly (line 305: `proposalIds.push(id)`). While the array itself does not have a gas-intensive iteration in the core contracts, the `MolochViewHelper._getProposals()` function iterates over slices of this array. A DAO with many proposals could have expensive view calls, though pagination mitigates this.

**FINDING (LOW):** The `messages` array grows unboundedly. Same concern as above, mitigated by pagination in the ViewHelper.

**FINDING (LOW):** The `daoTributeRefs` and `proposerTributeRefs` arrays in `Tribute.sol` grow unboundedly and are never cleaned up. The `getActiveDaoTributes()` function iterates over all refs (including cancelled ones) to find active tributes, which becomes increasingly expensive over time.

### 9.7 Timestamp Dependence

**Status: Acceptable**

The codebase uses `block.timestamp` for:
- Proposal expiry (`proposalTTL`)
- Timelock enforcement (`timelockDelay`)
- Ragequit timelock (`ragequitTimelock` + `lastAcquisitionTimestamp`)
- Tap claim calculation (`ratePerSec` * elapsed time)

Miners can manipulate timestamps by ~15 seconds. This is not a concern for Majeur because:
- Governance timeframes are typically days/weeks
- Tap claims are continuous (small timestamp manipulation = small fund change)
- Ragequit timelocks are 7+ days

---

## 10. Dependencies Review

### 10.1 External Dependencies

| Dependency | Version | Usage | Assessment |
|------------|---------|-------|------------|
| `forge-std` | N/A (submodule) | Test framework only | Standard, no production risk |
| `solady` | N/A (submodule) | Only used by ZAMM's tests | No production risk |
| `ZAMM` | N/A (submodule) | Used only in DAICO tests | DAICO references ZAMM at hardcoded address `0x000000000000040470635EB91b7CE4D132D616eD` |

**Key finding:** The production contracts have **zero imports**. All source files in `src/` are completely self-contained, with free-standing utility functions defined at file scope. This is excellent for security (no supply chain risk) but means the inline assembly patterns for safe transfers have not benefited from the extensive auditing that libraries like Solady receive.

### 10.2 Hardcoded External Addresses

| Contract | Address | Purpose | Risk |
|----------|---------|---------|------|
| `DAICO.sol` | `0x000000000000040470635EB91b7CE4D132D616eD` | ZAMM DEX singleton | If ZAMM is compromised or upgraded, LP functionality breaks |
| `MolochViewHelper.sol` | `0xadc33cbf7715219D9DC0d3958020835AaE36c338` | v2 Summoner | Hardcoded; ViewHelper must be redeployed if Summoner changes |
| `MolochViewHelper.sol` | `0x000000000033e92DB97B4B3beCD2c255126C60aC` | DAICO contract | Same concern |

### 10.3 Sentinel Addresses

The codebase uses magic addresses as sentinels:
- `address(0)` -- ETH (standard)
- `address(this)` -- minted shares (in `_payout`)
- `address(1007)` -- minted loot (in `_payout`)

**FINDING (LOW):** Using `address(1007)` as a sentinel for loot minting is non-standard and could theoretically collide with a real contract address. While the probability is astronomically low (would require brute-forcing a specific private key), it is unconventional. The value should be documented with a rationale.

### 10.4 Copied Code Analysis

The inline assembly patterns for safe transfers closely resemble patterns from Solady's `SafeTransferLib`. The implementations handle:
- Non-standard ERC-20 tokens that don't return a boolean
- Zero-address / non-contract checks
- Memory-safe assembly annotations

These patterns are well-known and battle-tested, but since they are manually copied rather than imported, any bug fixes in the original source will not be automatically applied.

---

## 11. Testing & Verification

### 11.1 Test Coverage Summary

| Test Suite | Tests Passed | Tests Failed | Tests Skipped |
|-----------|:---:|:---:|:---:|
| `MolochTest` | 157 | 0 | 0 |
| `DAICOTest` | 148 | 0 | 0 |
| `DAICO_ZAMM_Test` | 60 | 0 | 0 |
| `DAICO_CustomCalls_Test` | 6 | 0 | 0 |
| `MolochViewHelperTest` | 52 | 0 | 0 |
| `TributeTest` | 24 | 0 | 0 |
| `URIVisualizationTest` | 18 | 0 | 0 |
| `BytecodeSizeTest` | 5 | **1** | 0 |
| `ContractURITest` | 4 | 0 | 0 |
| **Total** | **474** | **1** | **0** |

**Failing test:** `testRendererRuntimeSize()` -- The Renderer contract's runtime bytecode (25,270 bytes) exceeds the EVM limit (24,576 bytes). This is a known issue.

### 11.2 Test Quality Assessment

**Strengths:**
- **Fuzz testing:** Multiple fuzz tests exist:
  - `testFuzz_Ragequit_Distribution` -- tests ragequit pro-rata math with random inputs
  - `testFuzz_Buy_ETH`, `testFuzz_BuyExactOut_ETH` -- DAICO buy flows
  - `testFuzz_TapClaim` -- tap mechanism
  - `testFuzz_QuoteBuy`, `testFuzz_QuotePayExactOut` -- quote accuracy
  - `testFuzz_SummonDAICO`, `testFuzz_SummonDAICOWithTap` -- factory flows
  - `testFuzz_Buy_ETH_WithLP`, `testFuzz_QuoteBuy_WithLP` -- LP integration
  - `testFuzz_SplitDelegation_FuzzAllocationsMatchVotes` -- delegation invariant
  - `testFuzz_Buy_Amounts`, `testFuzz_BuyExactOut_Amounts` -- DAICO arithmetic

- **Invariant checks:** Several test functions explicitly check invariants:
  - `test_Invariant_SharesSupplyEqualsBalances` -- sum of balances == total supply
  - `test_Invariant_VotesNeverExceedSnapshotSupply` -- voting power bounded by supply
  - `test_Invariant_LootSupplyEqualsBalances` -- loot balance consistency
  - `test_Invariant_DelegationVotesMatchShares` -- delegation accounting

- **Edge case testing:** Tests cover many edge cases:
  - Zero amounts, zero addresses
  - Double voting prevention
  - Expired proposals
  - Locked transfers
  - Self-transfer behavior
  - Empty DAO scenarios
  - Unauthorized access attempts

- **Cross-contract integration tests:**
  - `test_CrossContract_ShareTransferDuringProposal`
  - `test_CrossContract_DelegationAndVoting`
  - `test_CrossContract_MultipleProposalsSameBlock`
  - `test_CrossContract_RagequitDuringProposal`

**Weaknesses:**

1. **No formal invariant testing harness:** While there are functions named `test_Invariant_*`, these are unit tests that check invariants in specific scenarios. Foundry's `invariant` testing mode (stateful fuzzing) is not used. This would be the most impactful testing improvement.

2. **No property-based testing for split delegation:** The delegation system is the most complex part of the codebase. While `testFuzz_SplitDelegation_FuzzAllocationsMatchVotes` exists, a full invariant test that randomly applies delegation changes, transfers, mints, and burns while asserting vote conservation would be valuable.

3. **Limited negative testing for DAICO LP:** The LP drift protection formula is complex. More fuzz tests exploring edge cases (extreme drift, zero reserves, etc.) would improve confidence.

4. **No test for the `multicall` + `batchCalls` interaction:** No test verifies the behavior of nested calls through `multicall -> batchCalls -> external call`.

5. **No gas benchmarking tests:** While `forge snapshot` is mentioned in the CLAUDE.md, no dedicated gas benchmark tests exist to track gas regressions.

6. **Missing formal verification:** No use of symbolic execution tools (Halmos, KEVM) or verification annotations.

### 11.3 Code Coverage

Code coverage was not measured during this analysis (would require running `forge coverage`), but based on test function enumeration:
- Moloch core: High coverage (157 tests covering governance, voting, delegation, ragequit, futarchy, sales, badges, permits, allowances, metadata)
- DAICO: High coverage (214 tests covering sales, taps, LP, summon wrappers, fuzz tests)
- Tribute: Moderate coverage (24 tests covering propose, cancel, claim flows)
- MolochViewHelper: Moderate coverage (52 tests for batch read functions)
- Renderer: Good coverage (18 + 4 tests for SVG rendering and contract URIs)

---

## 12. Platform-Specific Guidance

### 12.1 Solidity Version

**Current:** `pragma solidity ^0.8.30;`

**Assessment:** Using 0.8.30 with the `^` caret operator allows compilation with any 0.8.x version >= 0.8.30. Since the contracts use:
- EIP-1153 transient storage (`tload`/`tstore`) -- requires 0.8.24+
- `mcopy` is not used directly but is available
- Named parameters in `assembly ("memory-safe")` blocks

**Recommendation:** Consider pinning to `0.8.30` (without `^`) to ensure deterministic compilation. The `foundry.toml` already pins `solc_version = "0.8.30"`, but the pragma allows other tooling to use different versions.

### 12.2 Compiler Configuration

```toml
optimizer = true
optimizer_runs = 500
via_ir = true
code_size_limit = 30000
```

**Assessment:**
- `via_ir = true`: Required for some of the complex contracts (ViewHelper, Renderer). Significantly increases compilation time but produces better-optimized code.
- `optimizer_runs = 500`: Balanced setting. Lower values produce smaller code; higher values optimize for repeated calls.
- `code_size_limit = 30000`: This **only bypasses the local forge check**. The EVM hard limit of 24,576 bytes still applies. The Renderer contract exceeds this limit and cannot be deployed as-is.

### 12.3 Inline Assembly Usage

The codebase contains 29 assembly blocks across 4 source files. Analysis:

| Category | Count | Risk Level | Assessment |
|----------|-------|------------|------------|
| Safe transfer helpers | 12 | Low | Well-known patterns from Solady |
| Reentrancy guard (tload/tstore) | 9 | Low | Standard EIP-1153 pattern |
| Clone deployment | 3 | Low | Standard EIP-1167 pattern |
| `mulDiv` | 1 | Low | Standard multiplication-before-division |
| Safe casts (`_revertOverflow`) | 1 | Low | Simple revert helper |
| `_ffs` (find first set bit) | 1 | Medium | Complex bit manipulation; should be verified against reference implementations |
| Error bubbling in `multicall` | 1 | Low | Standard revert forwarding |
| Token balance check (`balanceOfThis`) | 1 | Low | Simple staticcall pattern |

**FINDING (MEDIUM):** The `_ffs` function in `Badges` (lines 1965-1976) uses a sophisticated bit manipulation technique to find the first set bit. This is a compact implementation but extremely difficult to verify by inspection. It should be tested against a simple reference implementation across all 256 possible single-bit inputs.

### 12.4 Compiler Warnings

Not checked during this analysis. Recommend running `forge build 2>&1 | grep -i "warning"` and addressing any warnings.

---

## 13. Prioritized Recommendations

### CRITICAL

1. **Fix Renderer code size (exceeds EVM limit)**
   - **File:** `src/Renderer.sol`
   - **Issue:** Runtime bytecode is 25,270 bytes, exceeding the 24,576-byte EVM limit
   - **Impact:** Contract cannot be deployed to any EVM chain
   - **Recommendation:** Split the Renderer into multiple contracts (e.g., badge renderer, receipt renderer, contract URI renderer) and use a dispatcher pattern

### HIGH

2. **Add stateful invariant testing (Foundry invariant mode)**
   - **Issue:** No stateful fuzzing to verify system invariants under random sequences of operations
   - **Impact:** Complex interactions between delegation, voting, minting, burning, and ragequit may have undiscovered edge cases
   - **Recommendation:** Create an invariant test harness that:
     - Randomly mints/burns/transfers shares and loot
     - Randomly sets/clears split delegations
     - Randomly casts/cancels votes
     - Asserts at every step: sum of votes == total supply, ragequit distributions are pro-rata, ERC-6909 balances match tallies

3. **Document the delegatecall execution risk prominently**
   - **File:** `src/Moloch.sol:1012`
   - **Issue:** `op=1` delegatecall proposals can execute arbitrary code in the DAO's storage context
   - **Impact:** A malicious or buggy delegatecall target could corrupt all DAO storage
   - **Recommendation:** Add prominent NatSpec warnings and consider requiring higher quorum or longer timelock for delegatecall proposals (though this would be a contract change)

4. **Verify the `_ffs` bit manipulation function**
   - **File:** `src/Moloch.sol:1965-1976` (Badges contract)
   - **Issue:** The find-first-set implementation uses opaque magic constants
   - **Impact:** A bug would cause incorrect badge seat assignment
   - **Recommendation:** Add a comprehensive unit test that verifies `_ffs(1 << i) == i` for all `i` in `[0, 255]`, and `_ffs(0)` reverts or returns a sentinel

### MEDIUM

5. **Add events for governance configuration changes**
   - **File:** `src/Moloch.sol` (all `set*` functions)
   - **Issue:** 15+ governance parameter setter functions emit no events
   - **Impact:** Off-chain monitoring and indexing cannot track parameter changes without decoding proposal calldata
   - **Recommendation:** Add a generic `GovernanceParamChanged(bytes32 param, uint256 oldValue, uint256 newValue)` event or individual events

6. **Add a dedicated `Ragequit` event**
   - **File:** `src/Moloch.sol:773-820`
   - **Issue:** No composite event for ragequit operations
   - **Recommendation:** Add `event Ragequit(address indexed member, uint256 sharesToBurn, uint256 lootToBurn, address[] tokens)`

7. **Consider extracting safe transfer functions into a shared library**
   - **Files:** `Moloch.sol`, `DAICO.sol`, `Tribute.sol`
   - **Issue:** Three copies of nearly identical safe transfer assembly code
   - **Impact:** Maintenance burden; bug fixes must be applied to all copies
   - **Recommendation:** Create a `SafeTransferLib.sol` and import it, or at minimum, document that the three copies must be kept in sync

8. **Add `nonReentrant` to `batchCalls()`**
   - **File:** `src/Moloch.sol:914-919`
   - **Issue:** `batchCalls()` makes arbitrary external calls without reentrancy protection
   - **Impact:** Low risk since `onlyDAO` restricts access, but defense-in-depth is appropriate
   - **Recommendation:** Add `nonReentrant` modifier

### LOW

9. **Document the `address(1007)` sentinel value**
   - **File:** `src/Moloch.sol:1023`
   - **Issue:** Magic number used as sentinel for loot minting
   - **Recommendation:** Add a named constant `address constant LOOT_MINT_SENTINEL = address(1007)` with a NatSpec comment explaining the choice

10. **Add complete NatSpec to all public functions in Moloch.sol**
    - **Issue:** 33 NatSpec comments for a 2,145-line file with many undocumented public functions
    - **Recommendation:** Prioritize documenting `state()`, `ragequit()`, `castVote()`, and the ERC-6909 functions

11. **Clean up stale tribute references in `Tribute.sol`**
    - **File:** `src/peripheral/Tribute.sol:53-56`
    - **Issue:** `daoTributeRefs` and `proposerTributeRefs` grow unboundedly and are never cleaned
    - **Recommendation:** Document that these are append-only logs, or implement cleanup on cancel/claim

12. **Add explicit EVM version documentation**
    - **Issue:** The transient storage reentrancy guard requires Cancun or later
    - **Recommendation:** Add a comment in each contract that uses `tload`/`tstore` noting the minimum EVM version requirement

13. **Pin the Solidity pragma**
    - **Issue:** `pragma solidity ^0.8.30` allows any 0.8.x compiler >= 0.8.30
    - **Recommendation:** Use `pragma solidity 0.8.30;` (exact version) for deterministic compilation

14. **Consider adding an emergency pause mechanism**
    - **Issue:** No way to pause the system without going through governance
    - **Recommendation:** This is a design philosophy question. If the project values minimalism over safety rails, document this explicitly as a known accepted risk. If emergency response capability is desired, consider a simple pause flag with multi-sig control.

---

## 14. Overall Assessment

### Summary Scores

| Category | Score | Notes |
|----------|-------|-------|
| Documentation | 7/10 | Good v1-v2 docs; lacking NatSpec on many functions |
| Architecture | 9/10 | Clean, minimal, well-separated concerns |
| Upgradeability | 8/10 | Appropriate no-upgrade design with governance escape hatches |
| Access Control | 9/10 | Comprehensive onlyDAO + per-function checks |
| Reentrancy Protection | 8/10 | Modern EIP-1153 guards on most functions; a few gaps |
| Arithmetic Safety | 8/10 | Careful use of unchecked; mulDiv for safe math |
| Event Coverage | 7/10 | All major operations covered; governance setters missing events |
| Testing | 8/10 | 474 tests including fuzz; missing stateful invariants |
| Dependencies | 10/10 | Zero production dependencies -- exceptional |
| Code Quality | 8/10 | Clean, gas-optimized, but some code duplication |
| **Overall** | **8.2/10** | Production-quality codebase with well-considered security |

### Path to Production

The codebase demonstrates high quality and clear security awareness, as evidenced by the v1-to-v2 security improvements. To prepare for production deployment:

1. **Immediate:** Fix the Renderer contract size issue (CRITICAL)
2. **Before deployment:** Add stateful invariant tests and verify `_ffs` (HIGH)
3. **Before deployment:** Document delegatecall risks and add governance change events (HIGH/MEDIUM)
4. **Post-deployment:** Consider formal audit by a specialized firm (the codebase is well-organized for an efficient audit)
5. **Ongoing:** Monitor for compiler updates and maintain safe transfer function parity across contracts

### Notable Design Decisions (Positive)

1. **Zero imports in production code** -- Eliminates all supply chain risk
2. **EIP-1153 transient storage for reentrancy** -- Gas-efficient, no storage slot conflicts with proxy pattern
3. **Snapshot at block N-1** -- Prevents flash loan voting attacks
4. **Ragequit timelock** -- Prevents flash loan treasury extraction
5. **DAO self-voting prevention** -- Closes governance manipulation vector
6. **Quorum excluding DAO-held shares** -- Prevents governance deadlocks with treasury shares
7. **Unanimous consent bypass** -- Practical optimization for small DAOs
8. **Deterministic CREATE2 addressing** -- Enables pre-computation for initialization flows
9. **Path-independent delegation accounting** -- Prevents rounding drift across delegation changes

---

*Report generated by Trail of Bits Guidelines Advisor analysis framework. This report identifies areas for improvement based on development best practices and does not constitute a formal security audit.*

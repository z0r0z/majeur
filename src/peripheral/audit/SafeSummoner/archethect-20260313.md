# Security Audit Report: SafeSummoner

**Target:** `src/peripheral/SafeSummoner.sol`
**Framework:** Foundry | Solidity 0.8.30
**Date:** 2026-03-13
**Methodology:** Map-Hunt-Attack with Devil's Advocate verification
**Hotspots analyzed:** 14 (all attacked and verified)
**PoC tests written:** 0 (no exploitable findings)

---

## Executive Summary

SafeSummoner is a stateless factory wrapper around the deployed Summoner singleton that enforces audit-derived configuration guidance and builds initCalls from typed structs. It provides preset deployment functions, modular DAICO composition (ShareSale + TapVest + LPSeedSwapHook), CREATE2 deployment, and multicall batching.

The audit identified **0 confirmed exploitable issues**. **2 design tradeoffs** and **1 informational observation** are documented. **11 hypotheses** were thoroughly investigated and invalidated through the Devil's Advocate protocol. The contract's stateless architecture eliminates entire vulnerability classes (reentrancy, storage corruption, access control) by construction.

### Severity Distribution

| Severity | Proved | Confirmed (Unproven) | Candidates | Design Tradeoffs | Discarded |
|----------|--------|---------------------|------------|------------------|-----------|
| HIGH | 0 | 0 | 0 | 0 | 0 |
| MEDIUM | 0 | 0 | 0 | 0 | 0 |
| LOW | 0 | 0 | 0 | 1 | 0 |
| INFORMATIONAL | 0 | 0 | 1 | 1 | 0 |

---

## Review Summary

> **Reviewed 2026-03-13. No production blockers identified. 0 novel findings.**
>
> - Archethect SC-Auditor Map-Hunt-Attack methodology applied to SafeSummoner.sol (~1117 lines, 1 contract).
> - **14 hotspots mapped** across 7 external functions, 5 internal builders, and 2 assembly blocks.
> - **11 hypotheses discarded** after Devil's Advocate verification — all invalidated by the stateless architecture, hardcoded targets, or documented behavior.
> - **2 design tradeoffs** documented: multicall msg.value sharing (standard pattern) and CREATE2 salt not bound to msg.sender (benign frontrun).
> - **1 candidate** at Informational severity: `_defaultThreshold` uint96 truncation, already patched with saturating cap.
> - Cross-referenced against Pashov AI Audit #1, SCV Scan #2, and ZeroSkills Slot Sleuth #3 (same date).

---

## Phase 1: System Map

### Architecture

SafeSummoner is a **stateless factory** — zero storage variables, no proxy, no upgradeability. All functions are pure builders or external call forwarders:

| Function | Type | External Calls | State Changes |
|----------|------|----------------|---------------|
| `safeSummon` | public payable | `SUMMONER.summon{value}()` | None (new DAO created by Summoner) |
| `safeSummonDAICO` | public payable | `SUMMONER.summon{value}()` | None |
| `summonStandard` | public payable | via `_summonPreset` → `SUMMONER.summon` | None |
| `summonFast` | public payable | via `_summonPreset` → `SUMMONER.summon` | None |
| `summonFounder` | public payable | `SUMMONER.summon{value}()` | None |
| `summonStandardDAICO` | public payable | via `_summonDAICOPreset` → `SUMMONER.summon` | None |
| `summonFastDAICO` | public payable | via `_summonDAICOPreset` → `SUMMONER.summon` | None |
| `multicall` | public payable | `address(this).delegatecall` (self) | None |
| `create2Deploy` | public payable | `CREATE2` opcode | None (new contract created) |
| `predictCreate2` | public view | None | None |
| `predictDAO` | public pure | None | None |
| `predictShares` | public pure | None | None |
| `predictLoot` | public pure | None | None |
| `previewCalls` | public pure | None | None |
| `previewModuleCalls` | public pure | None | None |
| `burnPermitCall` | public pure | None | None |

### Trust Boundaries

1. **Summoner singleton** (immutable constant `0x0000...9138`) — single point of DAO creation
2. **Module singletons** (caller-supplied addresses) — ShareSale, TapVest, LPSeedSwapHook
3. **initCalls execution** — built by SafeSummoner, executed by the new DAO during `init()`
4. **extraCalls passthrough** — user-supplied, appended to initCalls, executed by new DAO

### Assembly Inventory

| Location | Opcode | Target | Storage Risk |
|---|---|---|---|
| `multicall()` L211-213 | `REVERT` | Memory (revert bubbling) | **None** — no `SSTORE` |
| `create2Deploy()` L232-235 | `MLOAD`, `CALLDATACOPY`, `CREATE2` | Memory + contract creation | **None** — no `SSTORE` |
| `summonFounder()` L376-396 | None (pure Solidity, `abi.encodePacked` + `keccak256`) | Memory | **None** |

---

## Phase 2: Hotspot Identification

14 hotspots identified for attack analysis:

| # | Hotspot | Category | Risk Hypothesis |
|---|---------|----------|-----------------|
| MH-001 | `multicall` delegatecall msg.value reuse | msg_value_reuse | Double-spend ETH across sub-calls |
| MH-002 | `multicall` delegatecall reentrancy | reentrancy | Re-enter via callback during sub-call |
| MH-003 | `create2Deploy` frontrunning | frontrunning | Occupy predicted address with malicious code |
| MH-004 | `create2Deploy` FMP corruption | memory_safety | Free memory pointer not updated after assembly |
| MH-005 | `_defaultThreshold` uint96 truncation | integer_overflow | Near-zero threshold on extreme supply |
| MH-006 | `_buildCalls` count/fill mismatch | array_oob | Over/under-count causes OOB or zero-padded calls |
| MH-007 | `_buildModuleCalls` sentinel resolution | logic_error | Wrong token address wired to module |
| MH-008 | `safeSummonDAICO` module-sale conflict bypass | validation_bypass | Use both SafeConfig.saleActive and SaleModule |
| MH-009 | `extraCalls` arbitrary code injection | access_control | Attacker injects malicious initCalls |
| MH-010 | `summonFounder` address prediction divergence | logic_error | Inline prediction mismatches `_predictDAO` |
| MH-011 | `_validate` futarchy/quorum bypass | validation_bypass | Deploy futarchy DAO with zero quorum |
| MH-012 | `_validateModules` minting+dynamic quorum bypass | validation_bypass | Minting sale with dynamic-only quorum |
| MH-013 | `rollbackGuardian` with zero singleton | config_error | Guardian configured but calls address(0) |
| MH-014 | `_mergeExtra` array overflow | memory_safety | Integer overflow in length addition |

---

## Phase 3: Attack & Verify

### MH-001: multicall delegatecall msg.value reuse

**ATTACK:** Attacker calls `multicall([safeSummon_1, safeSummon_2])` with `msg.value = 1 ETH`. Both sub-calls see `msg.value = 1 ETH` via delegatecall. First forwards 1 ETH to SUMMONER. Second attempts to forward 1 ETH — but contract only holds 1 ETH total.

**VERIFY (DA score: -8):**
- The second sub-call will revert if insufficient balance → entire multicall reverts atomically
- Only the caller's own ETH is at risk — no external attacker vector
- NatSpec at L203-205 explicitly documents this behavior
- Standard pattern: Uniswap V3 Router, Seaport, OpenSea use identical multicall
- **Verdict: DISCARD** — documented self-contained behavior, caller controls both data and ETH

### MH-002: multicall delegatecall reentrancy

**ATTACK:** During a `create2Deploy` sub-call in multicall, the deployed contract's constructor calls back to SafeSummoner.

**VERIFY (DA score: -12):**
- SafeSummoner has zero storage variables — nothing to corrupt via reentrancy
- Even if constructor calls back, it hits a stateless factory with no mutable state
- `delegatecall` target is hardcoded `address(this)` — cannot redirect to external contract
- **Verdict: DISCARD** — stateless contract, no state to corrupt

### MH-003: create2Deploy frontrunning

**ATTACK:** Attacker observes pending `multicall([create2Deploy(bytecode, salt), safeSummonDAICO(...)])` in mempool. Frontruns `create2Deploy(bytecode, salt)` to occupy the address.

**VERIFY (DA score: -6):**
- CREATE2 address = `keccak256(0xff ++ deployer ++ salt ++ keccak256(bytecode))` — includes bytecode hash
- Attacker using same (bytecode, salt) deploys **correct code** at the predicted address
- Victim's `create2Deploy` reverts, but the contract they wanted already exists with correct bytecode
- Victim retries their multicall without the `create2Deploy` step
- Attacker using different bytecode produces a different address — no collision
- **Verdict: DESIGN TRADEOFF** — benign frontrun, attacker pays gas for victim's deployment. See DT-01.

### MH-004: create2Deploy FMP corruption

**ATTACK:** `create2Deploy` reads `mload(0x40)` but never updates FMP after `calldatacopy`. Post-assembly Solidity code could allocate over the copied data.

**VERIFY (DA score: -10):**
- After the assembly block, the only code is `if (deployed == address(0)) revert Create2Failed()`
- `revert` uses scratch space (0x00-0x20), not the heap
- No memory allocation occurs after the assembly block in this function
- The `create2` opcode consumes the memory region — it's no longer needed
- `memory-safe` annotation is technically imprecise but produces no observable bug
- **Verdict: DISCARD** — no allocation follows assembly, no corruption possible

### MH-005: _defaultThreshold uint96 truncation

**ATTACK:** Caller passes `initShares` summing to >7.9e30. `total / 100` exceeds `type(uint96).max`, wrapping to near-zero on cast.

**VERIFY (DA score: -4):**
- **Patched:** saturating cap `if (t > type(uint96).max) t = type(uint96).max` now prevents wrap
- Pre-patch: Moloch.sol uses uint96 throughout (vote tallies, quorum, threshold setter) — total shares exceeding uint96.max breaks the entire governance system upstream
- Requires ~7.9 trillion tokens at 1e18 decimals — absurd for any real deployment
- **Verdict: CANDIDATE (Informational)** — patched defensively, precondition breaks all governance. See C-01.

### MH-006: _buildCalls count/fill mismatch

**ATTACK:** If the pre-count `n` in `_buildCalls` doesn't match the number of `calls[i++]` writes, the array is either over-allocated (wasted gas) or under-allocated (OOB revert).

**VERIFY (DA score: -13):**
- Systematically traced all 10 conditional blocks — each `if` guard in the count section exactly matches its corresponding `if` guard in the write section
- Same conditions, same nesting, same order
- Over-count: impossible (conditions are identical)
- Under-count: impossible (conditions are identical)
- `extra` loop appended after fixed calls — `n + extra.length` allocation is correct
- **Verdict: DISCARD** — count/fill conditions are provably identical

### MH-007: _buildModuleCalls sentinel resolution

**ATTACK:** SeedModule sentinels `address(1)` and `address(2)` resolved incorrectly, wiring wrong token to LP pool.

**VERIFY (DA score: -11):**
- `_resolveSeedToken(dao, address(1))` → `_predictShares(dao)` — correct
- `_resolveSeedToken(dao, address(2))` → `_predictLoot(dao)` — correct
- `_resolveSaleToken` for minting: `sellLoot ? address(1007) : dao` — matches Moloch's `_payout` sentinels
- `_resolveSaleToken` for transfer: `sellLoot ? _predictLoot(dao) : _predictShares(dao)` — correct
- `_isSeedSentinel` checks `address(1) || address(2)` — matches resolve function's cases
- **Verdict: DISCARD** — sentinel resolution is correct and consistent

### MH-008: safeSummonDAICO module-sale conflict bypass

**ATTACK:** Call `safeSummonDAICO` with both `config.saleActive = true` and `sale.singleton != address(0)`.

**VERIFY (DA score: -12):**
- L431: `if (config.saleActive && sale.singleton != address(0)) revert ModuleSaleConflict()`
- Check is at function entry, before any other logic
- Cannot be bypassed — explicit guard
- **Verdict: DISCARD** — guarded

### MH-009: extraCalls arbitrary code injection

**ATTACK:** Attacker supplies malicious `extraCalls` that drain the new DAO during init.

**VERIFY (DA score: -9):**
- `extraCalls` execute in the new DAO's context (called by Summoner during `init()`)
- The new DAO has zero balance at init time (no funds yet deposited)
- The caller IS the deployer — they control the DAO's initial configuration
- If a malicious third party can't call `safeSummon` on behalf of another user (no authorization needed — it's a public factory)
- The share holders are baked into the CREATE2 salt — attacker can't change who owns the DAO
- **Verdict: DISCARD** — caller deploys their own DAO, controls their own initCalls

### MH-010: summonFounder address prediction divergence

**ATTACK:** The inline `keccak256(abi.encode(h, s, salt))` in `summonFounder` produces a different hash than `_predictDAO` because memory arrays encode differently than calldata arrays.

**VERIFY (DA score: -7):**
- `abi.encode` produces identical output for memory and calldata arrays (ABI encoding is canonical)
- The minimal proxy bytecode is identical (same hex literals, same `MOLOCH_IMPL`)
- Test `test_SummonFounder` passes — the predicted address matches the deployed address
- **Verdict: DISCARD** — ABI encoding is canonical, test confirms

### MH-011: _validate futarchy/quorum bypass

**ATTACK:** Deploy a futarchy-enabled DAO with zero quorum by setting `autoFutarchyParam > 0`, `quorumBps = 0`, `quorumAbsolute = 0`.

**VERIFY (DA score: -12):**
- L646: `if (c.autoFutarchyParam > 0 && quorumBps == 0 && c.quorumAbsolute == 0) revert QuorumRequiredForFutarchy()`
- Explicit guard — reverts on exact condition
- **Verdict: DISCARD** — guarded (KF#17)

### MH-012: _validateModules minting+dynamic quorum bypass

**ATTACK:** Deploy a minting SaleModule with dynamic-only quorum to enable KF#2 supply manipulation.

**VERIFY (DA score: -11):**
- L675: `if (sale.minting && quorumBps > 0 && quorumAbsolute == 0) revert MintingSaleWithDynamicQuorum()`
- Also checked in `_validate` L658 for SafeConfig's built-in sale
- Both paths guarded
- **Verdict: DISCARD** — guarded (KF#2)

### MH-013: rollbackGuardian with zero singleton

**ATTACK:** Set `config.rollbackGuardian = alice` but leave `config.rollbackSingleton = address(0)`. InitCalls target address(0).

**VERIFY (DA score: -5):**
- L794: `Call(c.rollbackSingleton, 0, abi.encodeCall(IRollbackGuardian.configure, (...)))` — calls address(0)
- EVM call to address(0) succeeds silently (no code) — guardian is never configured
- The DAO deploys thinking it has a rollback guardian, but it doesn't
- **However:** this is a deployer configuration error, not an attacker exploit
- The deployer sets both fields — if they set guardian but forget singleton, it's their mistake
- No external attacker can cause this — both fields come from the same caller
- Pashov Audit #1 evaluated this at confidence 55, below threshold
- **Verdict: DISCARD** — deployer configuration error, self-contained, no external attacker vector

### MH-014: _mergeExtra array overflow

**ATTACK:** `new Call[](a.length + b.length)` — if `a.length + b.length` overflows uint256, allocation is tiny.

**VERIFY (DA score: -14):**
- `a` is `Call[] memory` from `_buildLootMints` — max length = `initHolders.length` (calldata bounded)
- `b` is `Call[] calldata` from user — bounded by calldata size and block gas limit
- Overflow of two calldata-bounded lengths requires >2^256 elements — physically impossible
- Solidity 0.8.30 checks array allocation size against memory expansion — OOG long before overflow
- **Verdict: DISCARD** — physically impossible

---

## Section 1: Proved Findings

None. No exploitable findings identified.

---

## Section 2: Confirmed Findings (Unproven)

None.

---

## Section 3: Detected Candidates

### [I-01] MH-005: uint96 Truncation in _defaultThreshold (Patched)

**Severity:** INFORMATIONAL | **Confidence:** Confirmed | **Category:** integer_overflow
**Affected:** `src/peripheral/SafeSummoner.sol` L1055-1063

**Description:** Prior to patching, `_defaultThreshold` cast `total / 100` to `uint96` without bounds checking. If `initShares` summed to >7.9e30, the cast would silently truncate, producing a near-zero `proposalThreshold` that bypasses KF#11 spam protection.

**Status:** Patched with saturating cap: `if (t > type(uint96).max) t = type(uint96).max`.

**Residual risk:** None. The precondition (>7.9e30 total shares) breaks Moloch.sol's uint96-based governance system upstream — vote tallies, quorum, and delegation all use uint96.

> **Response: Patched (Informational).** Saturating cap added as defensive measure. The underlying system is uint96-bounded. Previously identified by Pashov AI Audit #1 at confidence 85.

---

## Section 4: Design Tradeoffs

Intentional architectural decisions that accept risk. Documented, not dismissed.

---

### [DT-01] MH-003: create2Deploy Salt Not Bound to msg.sender

**Severity:** LOW (Design Tradeoff) | **Category:** frontrunning
**Affected:** `src/peripheral/SafeSummoner.sol` L227-238

**Description:** `create2Deploy` uses the caller-supplied `salt` directly without mixing in `msg.sender`. An attacker who observes a pending transaction can frontrun `create2Deploy(bytecode, salt)` with identical parameters, deploying the correct bytecode at the predicted address before the victim's transaction. The victim's call reverts with `Create2Failed`, but the intended contract already exists with correct code.

**Risk accepted:** The frontrun is benign — the attacker deploys the victim's contract for them and pays gas. The victim retries without the `create2Deploy` step. Binding salt to `msg.sender` would break sender-independent address prediction, complicating cross-EOA and contract-based deployment flows.

> **Response: Accepted (Low).** Benign frontrun — attacker pays gas for victim's deployment. No code injection possible (CREATE2 address includes bytecode hash). Previously identified by Pashov AI Audit #1 at confidence 80.

---

### [DT-02] MH-001: multicall msg.value Sharing Across Sub-Calls

**Severity:** INFORMATIONAL (Design Tradeoff) | **Category:** msg_value_reuse
**Affected:** `src/peripheral/SafeSummoner.sol` L206-217

**Description:** `multicall` uses `delegatecall` in a loop, preserving the original `msg.value` for each sub-call. If multiple sub-calls attempt to forward ETH (e.g., two `safeSummon{value: msg.value}` calls), the second may fail or consume residual contract balance.

**Risk accepted:** Standard delegatecall-multicall pattern (Uniswap V3 Router, Seaport, OpenSea). Self-contained — only the caller's own ETH is at risk, and the caller controls the data array. NatSpec at L203-205 explicitly documents: "msg.value is shared across all calls — callers sending ETH must ensure only one sub-call consumes it."

> **Response: Accepted (Informational).** Standard pattern, documented in NatSpec. Previously identified by SCV Scan #2.

---

## Section 5: Discarded Findings

Thoroughly investigated and confirmed to be false positives or fully mitigated.

| ID | Title | Reason |
|----|-------|--------|
| MH-002 | multicall delegatecall reentrancy | Stateless contract — zero storage to corrupt. DA score: -12 |
| MH-004 | create2Deploy FMP corruption | No memory allocation follows assembly block. DA score: -10 |
| MH-006 | _buildCalls count/fill mismatch | Count conditions provably identical to fill conditions. DA score: -13 |
| MH-007 | _buildModuleCalls sentinel resolution | All sentinels correctly resolved (address(1)→shares, address(2)→loot, address(1007)→loot mint). DA score: -11 |
| MH-008 | safeSummonDAICO module-sale conflict bypass | Explicit guard at L431 reverts `ModuleSaleConflict`. DA score: -12 |
| MH-009 | extraCalls arbitrary code injection | Caller deploys their own DAO; new DAO has zero balance at init. DA score: -9 |
| MH-010 | summonFounder prediction divergence | ABI encoding is canonical for memory/calldata; test confirms. DA score: -7 |
| MH-011 | _validate futarchy/quorum bypass | Explicit guard at L646 reverts `QuorumRequiredForFutarchy`. DA score: -12 |
| MH-012 | _validateModules minting+dynamic quorum bypass | Explicit guard at L675 reverts `MintingSaleWithDynamicQuorum`. DA score: -11 |
| MH-013 | rollbackGuardian with zero singleton | Deployer config error, not attacker exploit. Self-contained. DA score: -5 |
| MH-014 | _mergeExtra array length overflow | Physically impossible — requires >2^256 calldata elements. DA score: -14 |

---

## System Map Summary

**Architecture:** Single-file stateless factory (`src/peripheral/SafeSummoner.sol`, ~1117 lines) containing:
- **SafeSummoner** — Factory wrapper with validation, call building, presets, multicall, CREATE2
- **8 interfaces** — ISummoner, IMoloch, IShareSale, ITapVest, ILPSeedSwapHook, ISharesLoot, IShareBurner, IRollbackGuardian, IMolochBumpConfig
- **6 constants** — SUMMONER, MOLOCH_IMPL, SHARES_IMPL, LOOT_IMPL, SHARE_BURNER, RENDERER

**Key Trust Boundaries:**
1. SUMMONER singleton (hardcoded) — all DAO creation goes through this
2. Module singletons (caller-supplied) — ShareSale, TapVest, LPSeedSwapHook addresses
3. initCalls (SafeSummoner-built + user extraCalls) — executed by new DAO during init
4. multicall delegatecall — target hardcoded to `address(this)`

**Key Invariants Verified:**
- INV-001: `proposalThreshold > 0` for all deployed DAOs (validated — `_validate` reverts)
- INV-002: `proposalTTL > timelockDelay` always (validated — `_validate` reverts)
- INV-003: Futarchy requires non-zero quorum (validated — `_validate` reverts KF#17)
- INV-004: Minting sales require absolute quorum (validated — both `_validate` and `_validateModules` check KF#2)
- INV-005: Call array counts match fills (validated — conditions provably identical)
- INV-006: Sentinel resolution is correct (validated — address(1)→shares, address(2)→loot, dao→shares mint, 1007→loot mint)
- INV-007: Zero storage variables (validated — no `SSTORE` in entire contract)

---

*Report generated using Archethect Map-Hunt-Attack methodology with Devil's Advocate verification protocol, applied to SafeSummoner.sol.*

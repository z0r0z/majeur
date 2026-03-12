# Moloch (Majeur) DAO Framework — Security Audit Findings

## Executive Summary
- Total findings: 3 (Novel: 3, Duplicate: 0)
- Critical: 0 | High: 0 | Medium: 0 | Low: 1 | Informational: 2
- Highest-confidence finding: DAICO `claimTap` partial claim forfeiture at 85%

---

## Round 1: Systematic Code Review

### 1. Reentrancy
No issues found — `nonReentrant` modifier using EIP-1153 transient storage (slot `0x929eee149b4bd21268`) protects all state-changing functions that make external calls: `ragequit`, `buyShares`, `spendAllowance`, `cashOutFutarchy`, `fundFutarchy`, `executeByVotes`, `spendPermit`. The `multicall` function uses `delegatecall` which preserves the transient storage context, so the guard cannot be bypassed through batched calls. DAICO and Tribute contracts use separate `nonReentrant` implementations with the same transient storage pattern.

### 2. Flash Loan / Vote Manipulation
No issues found — `snapshotBlock` is set to `block.number - 1` in `openProposal` (line 290), and `getPastVotes` requires `blockNumber < block.number` (line 1241). Shares acquired in the current block have zero voting power for any proposal opened in the same block. The `buyShares` → vote path is blocked because the snapshot predates the purchase. Same-block checkpoint overwriting correctly updates the value rather than appending, which is safe since `getPastVotes` only queries blocks strictly before the current one.

### 3. Governance Logic
No issues found — The `state()` function (lines 433-479) implements a correct state machine with no skippable or reversible transitions. `castVote` atomically opens proposals via `openProposal` if `snapshotBlock[id] == 0`, and the `createdAt[id]` check at line 352 ensures no double-open. `cancelProposal` requires zero tally (line 425), which is impossible after `castVote` atomically opens + votes. The `executed` latch (line 519) is set before `_execute` and never reset. `bumpConfig()` invalidates both proposals and permits since both use `_intentHashId` which includes `config`.

### 4. Economic / Ragequit
No issues found — Ragequit computes `total = shares.totalSupply() + loot.totalSupply()` (line 772) *before* burning (lines 773-774), ensuring the denominator is correct throughout the token distribution loop. The sorted token array with ascending check (line 787: `tk <= prev`) prevents duplicate claims. Force-fed ETH via `selfdestruct` benefits ragequitters (economically irrational for attacker). Fee-on-transfer tokens cause recipients to receive less than `due`, but this is an informational known finding (KF#8).

### 5. Futarchy
No issues found beyond KF#17 and KF#18 — `cashOutFutarchy` correctly burns receipts before payout (CEI). `payoutPerUnit` is set once during `_finalizeFutarchy` and never modified. When `winSupply == 0`, the `payoutPerUnit` remains 0, and `cashOutFutarchy` returns 0 payout (harmless — funds remain in DAO treasury per KF#6). Auto-futarchy earmarks use live balance which allows overcommitment across proposals, but this is a known design choice (earmarks are "soft" allocations from treasury).

### 6. Access Control
No issues found — `onlyDAO` (`msg.sender == address(this)`) correctly restricts all governance functions. `delegatecall` execution (op=1 in `_execute`) runs in the DAO's context, maintaining `address(this)` correctly. `init()` is guarded by `SUMMONER` (immutable) and the Shares `init` check `DAO == address(0)` (line 1113) prevents re-initialization. Permit receipts are correctly gated as SBTs in both `transfer` (line 916) and `transferFrom` (line 929).

### 7. Token Sales (Moloch.sol `buyShares`)
No issues found — Cap logic correctly prevents over-selling: `shareAmount > cap` reverts (line 716), and `s.cap -= shareAmount` in unchecked is safe because it follows the check. When cap reaches 0, `s.active` remains true but `cap == 0` means "unlimited" — this is KF#1 (sentinel collision, Low). ETH overpayment is correctly refunded (lines 733-736). The `maxPay` slippage check works correctly for both ETH and ERC-20 (line 721).

### 8. Math / Precision
No issues found in practice — `mulDiv` (line 1987) checks overflow via `eq(div(z, x), y)` and division-by-zero via the outer `mul(..., d)`. It does not support phantom overflow (where `x*y > 2^256` but `x*y/d` fits in 256 bits), but this is not triggerable in ragequit where `amt <= total` ensures `due <= pool`. Split delegation BPS must sum to exactly 10000 (enforced at line 1280). The `_targetAlloc` "remainder to last" pattern (lines 1504-1512) ensures exact conservation. `uint96` max (~79.2B * 1e18) is sufficient for realistic share supplies.

### 9. External Token Integration
No issues found beyond known issues — Solady-style safe transfers handle USDT missing-return and zero-address cases. Blacklistable tokens in ragequit are mitigated by user-controlled token array (KF#7). The `_execute` function captures return data via `(ok, retData) = to.call{value: value}(data)` — a malicious target could return large data, but this is bounded by the caller's gas and the `nonReentrant` guard prevents state exploitation during the callback.

### 10. Delegation & Checkpoints
No issues found — Split delegation enforces BPS sum == 10000 (line 1280), MAX_SPLITS == 4, no duplicate delegates (line 1277), and no address(0) delegates (line 1271). The `_applyVotingDelta` function is path-independent: it computes old/new target allocations and only moves the difference. `_repointVotesForHolder` uses a marking technique (zeroing matched `newD` entries, line 1470) to correctly handle set differences. Self-delegation is the default (`delegates()` returns account if `_delegates[account] == address(0)`). Circular delegation (A→B→A) is not an issue because voting power is assigned based on share balance, not recursively through delegation chains.

---

## Round 2: Economic & Cross-Function Analysis

### Ragequit + Futarchy Interaction
Verified as known (KF#3) — Ragequit can drain tokens earmarked for futarchy pools. This is by design: exit rights supersede earmarks.

### Sales + Quorum Interaction
Verified as known (KF#2) — Minting sale + dynamic quorum could enable quorum manipulation via supply inflation, but this is economically constrained and addressed by SafeSummoner.

### Delegation + Voting Interaction
No novel issue found. Split delegation correctly freezes voting power at the snapshot block via `getPastVotes`. A delegator changing their split configuration after a snapshot doesn't affect past votes.

### DAICO Tap + Ragequit Interaction
Novel finding identified — see [L-01] below. When ragequit reduces the DAO's treasury balance below the tap's owed amount, partial claims forfeit the unfulfilled portion.

### Tribute Discovery Array Growth
Novel finding identified — see [I-01] below. Unbounded array growth in Tribute.sol discovery arrays.

---

## Round 3: Adversarial Validation

Each finding below survived disproof attempts, is not a duplicate of KF#1-18, and does not match any of the 10 false positive patterns.

---

## Confirmed Findings

### [L-01] DAICO `claimTap` advances `lastClaim` to `block.timestamp` on partial claims, permanently forfeiting owed amounts

**Severity:** Low
**Confidence:** 85
**Category:** Economic / Ragequit (Cross-function with DAICO)
**Location:** `DAICO`, function `claimTap`, lines 805-811

**Description:**

In `DAICO::claimTap`, when the amount actually claimable is capped by either the DAO's allowance or the DAO's token balance (`claimed < owed`), the function still advances `tap.lastClaim` to `block.timestamp`. The difference `owed - claimed` is permanently forfeited — it cannot be recovered in future claims because the elapsed time that generated that entitlement has been fully consumed by the timestamp advance.

```solidity
// DAICO.sol:805-811
// Claim min(owed, allowance, daoBalance) - tap is capped by what DAO can actually pay
claimed = owed < allowance ? owed : allowance;
if (claimed > daoBalance) claimed = daoBalance;
if (claimed == 0) revert NothingToClaim();

// Update timestamp BEFORE external calls (CEI)
tap.lastClaim = uint64(block.timestamp); // @audit advances full elapsed even on partial claim
```

**Attack Path:**
1. DAO sets tap at `ratePerSec = 1000` (smallest units/sec) with `ops` as beneficiary
2. 100 seconds pass — `owed = 100,000`
3. DAO's allowance to DAICO is only `50,000` (reduced by ragequit or governance decision)
4. `claimTap` executes: `claimed = 50,000`, `lastClaim = block.timestamp`
5. The remaining `50,000` owed is permanently lost — future claims accrue from the new timestamp

This is not exploitable for profit by an external attacker, but it does cause the ops beneficiary to permanently lose entitled funds in scenarios where the DAO's resources are temporarily constrained (e.g., after a ragequit event drains treasury, or governance intentionally reduces allowance).

**Disproof Attempt:**

I checked whether the timestamp advance is intentional as a "cap exposure" mechanism. The NatSpec comment at line 780 says "Dynamically adjusts to min(owed, allowance, daoBalance) to handle ragequits/spending" which suggests awareness of partial claims, but does not explicitly document forfeiture behavior. The `pendingTap` view function (line 827) returns time-based owed "ignoring allowance/balance caps," which would mislead ops into expecting the full amount is claimable once the constraint is resolved.

The design choice is defensible (it prevents unbounded debt accumulation against a potentially depleted DAO), but the silent forfeiture without any event or mechanism for the ops team to detect or recover the difference is a footgun.

This is not a duplicate of any KF#1-18 finding. It does not require a governance vote to exploit (any external account can trigger partial claims via `claimTap`). The ops beneficiary has no mitigation path — they cannot prevent ragequit from reducing DAO balance below the owed amount.

**Severity Justification:**
- Exploitable without DAO governance vote? Yes — any caller can trigger `claimTap`; the partial claim scenario arises naturally from ragequit
- Survives `nonReentrant` guard? N/A — not a reentrancy issue
- Survives snapshot-at-N-1? N/A
- Economic cost of attack vs gain: No attacker profit — this is a loss for the ops beneficiary, not an exploit
- Duplicates Known Finding #? No

**Recommended Mitigation:**

Option A: Advance `lastClaim` proportionally to what was actually claimed:

```solidity
// Only advance lastClaim by the time corresponding to what was actually paid
uint64 claimedElapsed = uint64(claimed / uint256(tap.ratePerSec));
tap.lastClaim += claimedElapsed;
```

Note: truncation in `claimed / ratePerSec` means a tiny remainder of accrued time is lost per partial claim. For precision, an alternative is to track a `debt` accumulator.

Option B: If forfeiture is the intended design, add explicit documentation and emit an event when `claimed < owed`:

```solidity
if (claimed < owed) {
    emit TapForfeited(dao, ops, tribTkn, owed - claimed);
}
```

---

### [I-01] Tribute discovery arrays grow unboundedly and are never pruned

**Severity:** Informational
**Confidence:** 90
**Category:** External Token Integration / Gas
**Location:** `Tribute`, function `proposeTribute`, lines 100-102

**Description:**

Every call to `Tribute::proposeTribute` pushes entries to both `daoTributeRefs[dao]` and `proposerTributeRefs[msg.sender]`. These arrays are append-only — neither `cancelTribute` nor `claimTribute` removes entries:

```solidity
// Tribute.sol:100-102
daoTributeRefs[dao].push(DaoTributeRef({proposer: msg.sender, tribTkn: tribTkn}));
proposerTributeRefs[msg.sender].push(ProposerTributeRef({dao: dao, tribTkn: tribTkn}));
```

The `getActiveDaoTributes` view function (lines 183-220) iterates the full `daoTributeRefs[dao]` array on every call, performing two passes (count active, then populate result). After many propose/cancel cycles, the array is dominated by stale entries pointing to zeroed-out `TributeOffer` mappings.

**Attack Path:**

This is not directly exploitable for profit. However:
1. Over time, a popular DAO accumulates thousands of tribute entries (propose → cancel → propose cycles)
2. `getActiveDaoTributes(dao)` eventually exceeds the block gas limit for RPC `eth_call`
3. Frontend/dApp integrations that rely on this view function break
4. The on-chain tribute data becomes effectively undiscoverable

**Disproof Attempt:**

The arrays are only consumed by view functions (`getActiveDaoTributes`, `getDaoTributeCount`, `getProposerTributeCount`), so there is no direct security impact on state-changing functions. The core propose/cancel/claim logic uses the mapping (`tributes[proposer][dao][tribTkn]`) and is unaffected. However, the NatSpec at lines 41-42 describes these as "Lightweight push arrays for discovery," implying they're relied upon for off-chain indexing.

This is a known trade-off in the append-only design. Gas cost grows linearly with historical entries but has no ceiling.

**Severity Justification:**
- Exploitable without DAO governance vote? Yes — any user can propose/cancel tributes
- Survives `nonReentrant` guard? N/A
- Economic cost of attack vs gain: Attacker pays gas for each propose; no direct profit
- Duplicates Known Finding #? No

**Recommended Mitigation:**

Add paginated view functions with offset/limit parameters for frontends:

```solidity
function getActiveDaoTributesPaginated(address dao, uint256 offset, uint256 limit)
    public view returns (ActiveTributeView[] memory result, uint256 nextOffset)
```

Alternatively, implement swap-and-pop cleanup in `cancelTribute`/`claimTribute` by tracking the array index in the `TributeOffer` struct.

---

### [I-02] `mulDiv` does not support phantom overflow

**Severity:** Informational
**Confidence:** 80
**Category:** Math / Precision
**Location:** `Moloch.sol`, free function `mulDiv`, lines 1987-1996

**Description:**

The `mulDiv` function reverts when `x * y` overflows `uint256`, even if the final result `x * y / d` would fit in 256 bits. This is known as "phantom overflow":

```solidity
// Moloch.sol:1987-1996
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

The overflow check `eq(div(z, x), y)` catches truncation from `mul(x, y)`, and the `d` check prevents division by zero. However, a full-precision `mulDiv` (like Solady's or OpenZeppelin's) uses 512-bit intermediate arithmetic to handle cases where the intermediate product overflows but the final quotient fits.

**Attack Path:**

No practical attack path exists in the current codebase. `mulDiv` is used in:

1. **Ragequit** (line 791): `mulDiv(pool, amt, total)` where `amt <= total` (burn amount cannot exceed total supply), so the result is always `<= pool`. The intermediate product `pool * amt` could theoretically overflow if `pool` and `amt` are both near `2^128`, but this would require token pools of ~3.4 * 10^38 units, which is unrealistic.

2. **Auto-futarchy earmark** (line 325): `mulDiv(basis, p, 10_000)` where `p <= 10_000`. Since `basis` is share supply (max `uint96 ≈ 7.9 * 10^28`), the product is well within `uint256`.

3. **Split delegation** (line 1509): `mulDiv(bal, B[i], BPS_DENOM)` where `bal` is a token balance and `B[i] <= 10_000`. Same reasoning as above.

4. **Futarchy payout** (line 620): `mulDiv(pool, 1e18, winSupply)`. Pool is bounded by treasury size and `1e18` is fixed, so overflow requires pool > `~1.15 * 10^59`, which is unrealistic.

**Disproof Attempt:**

I systematically checked every callsite of `mulDiv` and confirmed that none can produce intermediate products exceeding `2^256` with realistic protocol parameters. The `uint96` type cap on share supplies and vote tallies naturally constrains the operands.

**Severity Justification:**
- Exploitable without DAO governance vote? No — would require unrealistic token supplies
- Economic cost of attack vs gain: N/A — not triggerable
- Duplicates Known Finding #? No

**Recommended Mitigation:**

If future features may introduce callsites with larger operands, consider replacing with Solady's `FixedPointMathLib.mulDiv` which handles phantom overflow via 512-bit intermediate arithmetic. For current usage, the existing implementation is sufficient and more gas-efficient.

---

## Category Coverage Matrix

| Category | Result | Defense Verified |
|---|---|---|
| 1. Reentrancy | No issues found | EIP-1153 transient storage `nonReentrant` on all external-call functions |
| 2. Flash Loan / Vote Manipulation | No issues found | Snapshot at `block.number - 1`; `getPastVotes` requires strict past block |
| 3. Governance Logic | No issues found | Correct state machine; `executed` latch; `config` versioning; atomic open+vote |
| 4. Economic / Ragequit | L-01 (DAICO tap) | Sorted array; pre-burn denominator; pro-rata math verified |
| 5. Futarchy | No novel issues | Resolution immutability; receipt burn before payout; KF#17/KF#18 confirmed |
| 6. Access Control | No issues found | `onlyDAO` = self-governance; SBT gate; `SUMMONER` immutable; no re-init |
| 7. Token Sales | No novel issues | Cap logic correct; ETH refund; `maxPay` slippage; KF#1 confirmed |
| 8. Math / Precision | I-02 (theoretical) | `mulDiv` overflow check; `_targetAlloc` conservation; `uint96` sufficiency |
| 9. External Token Integration | I-01 (Tribute arrays) | Solady safe transfers; user-controlled ragequit array; KF#7/KF#8 confirmed |
| 10. Delegation & Checkpoints | No issues found | BPS sum enforcement; path-independent delta; binary search lookup; no circular issues |

---

## Invariant Verification

| # | Invariant | Status | Evidence |
|---|---|---|---|
| 1 | `Shares.totalSupply == sum(balanceOf)` | Verified | `_mint` adds to both (lines 1176-1178); `_moveTokens` subtracts/adds symmetrically (1186-1188); `burnFromMoloch` subtracts both (1164-1166) |
| 2 | `ERC6909: totalSupply[id] == sum(balanceOf[*][id])` | Verified | `_mint6909` adds to both (945-948); `_burn6909` subtracts both (953-956); `transfer`/`transferFrom` are conservation-preserving (917-933) |
| 3 | Proposal state machine: no skipped/reversed transitions | Verified | `state()` evaluates conditions in priority order; `executed` latch is irreversible; `createdAt` is write-once |
| 4 | `executed[id]` is one-way latch | Verified | Set at line 519 (`executeByVotes`), line 429 (`cancelProposal`), line 668 (`spendPermit`); never set to false |
| 5 | Ragequit conservation: `due <= pool` | Verified | `mulDiv(pool, amt, total)` with `amt = sharesToBurn + lootToBurn <= total` ensures `due <= pool` |
| 6 | Futarchy `payoutPerUnit` immutability | Verified | Set once in `_finalizeFutarchy` (line 621); `F.resolved` gate (line 608) prevents re-finalization |
| 7 | No admin keys post-init | Verified | Only `onlyDAO` (`msg.sender == address(this)`) can modify governance state; no owner/admin pattern |
| 8 | Snapshot supply frozen at proposal creation | Verified | `supplySnapshot[id]` written once in `openProposal` (line 296); `openProposal` returns early if `snapshotBlock[id] != 0` (line 279) |

---

## Architecture Assessment

The Moloch (Majeur) codebase demonstrates strong security engineering. The no-admin-key architecture eliminates an entire class of centralization risks. Critical defense mechanisms — snapshot at N-1, transient storage reentrancy guards, sorted ragequit arrays, the executed latch, and config versioning — are correctly implemented and consistently applied.

The split delegation system is the most complex component, with its path-independent delta approach and "remainder to last" allocation pattern providing exact conservation of voting power across arbitrary delegation changes. The checkpoint binary search correctly handles edge cases including same-block overwrites.

The peripheral contracts (DAICO, SafeSummoner, Tribute) add useful functionality while maintaining clean separation from the core governance logic. SafeSummoner's validation layer addresses multiple configuration footguns identified in prior audits (KF#2, KF#11, KF#12, KF#17).

The two novel findings are both low severity. The DAICO tap forfeiture (L-01) is a design choice that could surprise ops beneficiaries but doesn't enable fund theft. The unbounded Tribute discovery arrays (I-01) are a gas efficiency concern with no direct security impact. The `mulDiv` phantom overflow (I-02) is purely theoretical with current parameters.

Overall, the codebase is well-hardened and the 18 known findings from prior audit rounds have been appropriately catalogued with clear severity ratings. No Critical, High, or Medium severity vulnerabilities were identified beyond those already documented (KF#17 and KF#18).

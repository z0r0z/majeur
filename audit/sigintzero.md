# Sentinel Engine — Majeur Security Audit

**Auditor:** Sentinel Engine (SigintZero)
**Type:** Automated — Static Analysis + AI-Assisted Analysis
**Date:** 2026-03-18
**Scope:** `src/Moloch.sol`, `src/peripheral/ShareSale.sol`, `src/peripheral/LPSeedSwapHook.sol`, `src/peripheral/TapVest.sol`, `src/peripheral/Tribute.sol`, `src/peripheral/SafeSummoner.sol`, `src/peripheral/RollbackGuardian.sol`

---

## Executive Summary

- **Total findings: 46**
- Critical: 1 | High: 1 | Medium: 10 | Low: 25 | Informational: 9

> **Note:** This report is the raw output of automated analysis tooling. No manual code review was performed and findings have not been manually verified for false positives. Findings may contain incorrect severity classifications or missing context.

---

## Summary — Known Finding Coverage & Comparison

### Scope Comparison

Most auditors in this engagement scoped only `Moloch.sol` (2110 lines, 5 contracts). Sentinel Engine scoped **7 contracts** including all peripheral modules (ShareSale, LPSeedSwapHook, TapVest, Tribute, SafeSummoner, RollbackGuardian), substantially increasing the attack surface reviewed.

| Auditor | Contracts Scoped | Findings | Novel |
|---|---|---|---|
| Zellic V12 | 1 (Moloch) | 26 | 4 valid for hardening |
| Cantina Apex | 3 (Moloch, Tribute, DAICO) | 24 | 5 smart contract + ~15 frontend |
| Pashov Skills | 1 (Moloch) | 13 | 2 |
| Claude (Opus) | 1 (Moloch) | 3 | 1 |
| ChatGPT Pro | 1 (Moloch) | 3 | 1 |
| Grimoire | 1 (Moloch) | 10 | 0 |
| Ackee | 1 (Moloch) | 6 | 0 |
| **Sentinel Engine** | **7 (full scope)** | **46** | **~28** |

### Known Finding (KF) Hit Rate

Of the 23 documented Known Findings, 2 are obsolete/fixed (KF#20, KF#22), leaving 21 active. Sentinel Engine matched **18 of 21 active KFs (~86% hit rate)**:

| KF | Description | Our Finding |
|---|---|---|
| KF#1 | Sale cap sentinel collision | I-03, L-23 |
| KF#2 | Minting sale + quorum bypass | L-22 |
| KF#3 | Futarchy pool drainable via ragequit | M-02 |
| KF#4 | Futarchy resolution timing | I-01 |
| KF#5 | Vote receipt transferability breaks cancelVote | L-19 |
| KF#6 | Zero-winner futarchy lockup | L-06 |
| KF#8 | Fee-on-transfer token accounting | L-05 |
| KF#9 | CREATE2 salt not bound to msg.sender | I-05 |
| KF#10 | Permit/proposal namespace overlap | M-09 |
| KF#11 | proposalThreshold == 0 griefing | I-02 |
| KF#12 | init() missing quorumBps validation | L-14 |
| KF#13 | Earmark double-counting (loot supply not snapshotted) | M-01 |
| KF#14 | delegatecall proposals corrupt storage | L-02 |
| KF#15 | Post-queue voting can flip proposals | L-18 |
| KF#16 | spendPermit doesn't check executed | L-01 |
| KF#17 | Public futarchy attachment on arbitrary IDs | L-25 |
| KF#18 | fundFutarchy accepts cancelled proposal IDs | L-10 |
| KF#21 | Permit IDs enter proposal/futarchy lifecycle | L-01, M-09 |

**KFs missed (3):**
- KF#7: Blacklistable token ragequit DoS (caller can omit token — user-controlled mitigation)
- KF#19: bumpConfig emergency brake bypass via raw proposal IDs
- KF#23: Counterfactual Tribute theft via summon frontrun (accepted as impractical)

### Novel Findings

Sentinel Engine identified **~28 findings not covered by any prior KF**, the highest novel count of any auditor. This is largely driven by peripheral contract coverage that other auditors did not scope:

- **C-01** (Critical): ShareSale unchecked overflow — free token acquisition. Not seen in any prior audit.
- **H-01** (High): LPSeedSwapHook cancel-after-seed bricks pool. Not seen in any prior audit.
- **M-03**: SafeSummoner multicall msg.value double-spend. Not previously reported.
- **M-04**: Flash loan bypasses proposalThreshold. Not previously reported.
- **M-05**: Soulbound token falsely declares ERC-721 compliance.
- **M-06**: Governance can trap members by disabling all exit mechanisms.
- **M-07**: Governance parameter changes retroactively alter active proposals.
- **M-08**: Snapshot front-running via silent early return.
- **M-10**: TapVest reconfiguration silently forfeits unclaimed funds.
- Plus 19 additional Low/Informational novel findings across peripherals.

### Assessment

Sentinel Engine achieved the broadest coverage of any auditor in this engagement by scoping all 7 contracts rather than Moloch.sol alone. The 86% KF hit rate on Moloch.sol findings demonstrates strong detection capability on established vulnerability patterns. The 28 novel findings — particularly C-01 (ShareSale overflow) and H-01 (LPSeedSwapHook cancel bug) — represent meaningful new discoveries in peripheral contracts that no prior auditor reviewed.

The primary limitation is that this is raw automated output without manual verification. Some findings may be false positives or have incorrect severity classifications. A manual review pass is recommended before acting on findings.

---

## Critical

### C-01 — ShareSale.buy unchecked multiplication overflow allows free token acquisition

**Severity:** Critical
**Location:** `src/peripheral/ShareSale.sol:67-70` (`buy`)

**Description:** ShareSale.buy computes `cost = amount * s.price / 1e18` inside an `unchecked` block. If `amount * s.price` exceeds `type(uint256).max`, the multiplication wraps around (phantom overflow), producing a small or zero `cost`. The attacker then pays this near-zero cost while receiving `amount` shares/loot tokens from the DAO's allowance via `spendAllowance`. For example: with price = 1e16 (0.01 ETH/share), setting amount = type(uint256).max / 1e16 + 1 causes the product to overflow. The wrapped result divided by 1e18 yields a cost of ~0, while the attacker receives an enormous number of shares. Even with a reasonable price, the attacker can choose amount values that cause overflow to a specific small target.

```solidity
        uint256 cost;
        unchecked {
            cost = amount * s.price / 1e18;
        }
```

**Impact:** CRITICAL -- An attacker can drain the entire share/loot allowance of any DAO using ShareSale, acquiring tokens for free or near-free. These tokens can then be used for governance attacks or ragequit to drain the DAO treasury.

**Recommendation:** Remove the `unchecked` block around the cost calculation, or add an explicit overflow check: `require(amount <= type(uint256).max / s.price, 'overflow')`. The checked arithmetic in Solidity 0.8+ would naturally revert on overflow if `unchecked` were removed.

---

## High

### H-01 — cancel() allows cancellation after seeding, permanently bricking the ZAMM pool

**Severity:** High
**Location:** `src/peripheral/LPSeedSwapHook.sol:295-300` (`cancel`), `src/peripheral/LPSeedSwapHook.sol:353-354` (`beforeAction`)

**Description:** cancel() checks only cfg.amountA == 0 but NOT cfg.seeded. If seed already executed, DAO can still call cancel() which deletes entire SeedConfig. After deletion, beforeAction reads seeds[dao].seeded as false and reverts with NotReady for swaps. For non-swap operations, dao != address(0) (poolDAO still set) but seeds[dao].seeded is false, so addLiquidity/removeLiquidity also revert with NotReady. ALL pool operations permanently bricked.

```solidity
    function cancel() public {
        SeedConfig storage cfg = seeds[msg.sender];
        if (cfg.amountA == 0) revert NotConfigured();
        delete seeds[msg.sender];
        emit Cancelled(msg.sender);
    }
```

**Impact:** All LP tokens and underlying liquidity become permanently inaccessible. Pool fully bricked.

**Recommendation:** Add check: if (cfg.seeded) revert AlreadySeeded(); at beginning of cancel().

---

## Medium

### M-01 — Futarchy pool earmark double-counting: pool increments are unbacked by actual token transfers

**Severity:** Medium
**Location:** `src/Moloch.sol:328-336` (`openProposal`)

**Description:** The auto-futarchy earmark (F.pool += amt) increments the pool as a bookkeeping entry, but the check for sufficient balance only verifies balanceOf(address(this)) at call time. Multiple proposals can each earmark up to the full balance. No tokens are moved, so later proposals' futarchy winners may fail to claim.

```solidity
                    if (rt == address(_shares)) {
                        uint256 bal = _shares.balanceOf(address(this));
                        if (amt > bal) amt = bal;
                    } else if (rt == address(_loot)) {
                        uint256 bal = _loot.balanceOf(address(this));
                        if (amt > bal) amt = bal;
                    }
                    if (amt != 0) {
                        F.pool += amt; // earmark only
```

**Impact:** Futarchy winners on later proposals may be unable to claim rewards.

**Recommendation:** Track total earmarked amounts across all proposals in a cumulative state variable. When computing available balance, subtract totalEarmarked from balanceOf(address(this)).

---

### M-02 — ETH futarchy pools not segregated from ragequit-eligible treasury balance

**Severity:** Medium
**Location:** `src/Moloch.sol:790-791` (`ragequit`), `src/Moloch.sol:559-560` (`fundFutarchy`)

**Description:** When fundFutarchy is called with ETH (rewardToken = address(0)), the ETH is sent to the Moloch contract via msg.value and tracked in F.pool accounting. However, ragequit reads `address(this).balance` which includes ALL ETH in the contract -- both general treasury AND futarchy-allocated ETH. Ragequitters receive a pro-rata share of the total ETH balance, including amounts earmarked for futarchy payouts. After ragequit depletes the ETH balance, cashOutFutarchy may fail to pay winning-side receipt holders because the ETH they were promised has been claimed by ragequitters. This creates a race condition: ragequitters can front-run futarchy resolution to capture futarchy-allocated ETH.

```solidity
                pool = tk == address(0) ? address(this).balance : balanceOfThis(tk);
```

**Impact:** Futarchy winners may not receive their full payout if members ragequit first. This undermines the futarchy mechanism's incentive structure -- voters cannot rely on receiving their rewards. The magnitude depends on the ratio of futarchy-funded ETH to total treasury ETH and the proportion of supply that ragequits.

**Recommendation:** Track futarchy-allocated ETH separately and exclude it from ragequit: maintain a `futarchyETHReserved` counter that is incremented on fundFutarchy(ETH) and decremented on cashOutFutarchy/resolution. ragequit should read `address(this).balance - futarchyETHReserved` as the available pool. Alternatively, document that ETH futarchy and ragequit have competing claims on the same pool and that ragequit can deplete futarchy funds.

---

### M-03 — msg.value reuse across delegatecall sub-calls enables double-spend of ETH

**Severity:** Medium
**Location:** `src/peripheral/SafeSummoner.sol:207-218` (`multicall`), `src/peripheral/SafeSummoner.sol:300-300` (`safeSummon`), `src/peripheral/SafeSummoner.sol:236-236` (`create2Deploy`)

**Description:** The multicall function uses delegatecall in a loop, preserving msg.value across all iterations. Every sub-call sees the same msg.value, meaning a single ETH payment can be spent multiple times. Multiple SafeSummoner functions forward msg.value to external calls (summon variants forward to SUMMONER.summon, create2Deploy uses callvalue() in CREATE2). A crafted multicall can amplify a single ETH deposit across multiple ETH-consuming operations. NatSpec acknowledges this risk but provides no enforcement.

```solidity
    function multicall(bytes[] calldata data) public payable returns (bytes[] memory results) {
        results = new bytes[](data.length);
        for (uint256 i; i != data.length; ++i) {
            (bool ok, bytes memory result) = address(this).delegatecall(data[i]);
            if (!ok) {
                assembly ("memory-safe") {
                    revert(add(result, 0x20), mload(result))
                }
            }
            results[i] = result;
        }
    }
```

**Impact:** Attacker can drain contract ETH or cause downstream protocols to receive mismatched ETH amounts.

**Recommendation:** Track cumulative ETH consumed across sub-calls. Alternatively, restrict multicall to non-payable sub-calls. Simpler approach: check address(this).balance >= msg.value before each delegatecall.

---

### M-04 — Flash loan bypasses proposalThreshold, enabling spam proposals and futarchy earmark drain

**Severity:** Medium
**Location:** `src/Moloch.sol:283-286` (`openProposal`)

**Description:** openProposal checks `shares.getVotes(msg.sender) >= threshold` using CURRENT voting power (getVotes), not historical. An attacker can: (1) flash loan shares, (2) receive shares via transfer which triggers _autoSelfDelegate and creates a checkpoint for the current block, (3) call openProposal (or castVote which auto-opens) -- the threshold check passes because getVotes returns current power, (4) return shares to the flash loan provider. The proposal is successfully opened despite the attacker having no long-term stake. If autoFutarchyParam is set, each opened proposal earmarks DAO-held shares/loot into the futarchy pool. The attacker can spam-open proposals to drain the DAO's held share/loot reserves into futarchy pools. The attacker can then vote AGAINST on these proposals with legitimately held shares (even a small amount), and when proposals resolve as Defeated, cash out the AGAINST-side futarchy rewards. Note: the actual vote uses getPastVotes (historical), so the flash-loaned shares don't contribute vote weight. The exploit is the threshold bypass + futarchy earmark drain.

```solidity
        uint96 threshold = proposalThreshold;
        if (threshold != 0) {
            require(_shares.getVotes(msg.sender) >= threshold, Unauthorized());
        }
```

**Impact:** With autoFutarchy enabled: attacker drains DAO-held shares/loot into futarchy pools. Without autoFutarchy: attacker spams proposals (nuisance). The futarchy earmark drain is the more serious impact -- earmarked tokens are locked until proposal resolution, reducing the DAO's available reserves.

**Recommendation:** Use getPastVotes instead of getVotes for the threshold check, matching the same snapshot-based approach used for vote weight. This ensures the caller held shares at the snapshot block (block.number - 1), which cannot be satisfied by same-block flash loans. Alternatively, add a minimum holding period check.

---

### M-05 — Contract declares ERC-721 compliance but is not a conformant ERC-721 implementation

**Severity:** Medium
**Location:** `src/Moloch.sol:1743-1747` (`supportsInterface`)

**Description:** Returns true for 0x80ac58cd (ERC-721) but the contract is a soulbound token that reverts on transferFrom and provides no safeTransferFrom, approve, setApprovalForAll, getApproved, or isApprovedForAll. Marketplaces, DeFi protocols, wallets, and bridges that check supportsInterface will treat Badges as transferable NFTs.

```solidity
    function supportsInterface(bytes4 interfaceId) public pure returns (bool) {
        return interfaceId == 0x01ffc9a7 // ERC165
            || interfaceId == 0x80ac58cd // ERC721
            || interfaceId == 0x5b5e139f; // ERC721Metadata
    }
```

**Impact:** External protocols will incorrectly treat Badges as transferable ERC-721 NFTs, leading to failed operations and potential stuck funds.

**Recommendation:** Remove 0x80ac58cd from supported interfaces. Return true only for ERC-165 and optionally ERC-5192 (soulbound). If ERC-721 compatibility is needed, implement all mandatory functions even if they revert.

---

### M-06 — Governance can disable ragequit and lock transfers simultaneously, trapping members

**Severity:** Medium
**Location:** `src/Moloch.sol:834-836` (`setRagequittable`), `src/Moloch.sol:838-841` (`setTransfersLocked`)

**Description:** Moloch provides two exit mechanisms for members: ragequit (burn shares/loot for pro-rata treasury) and transfer (sell shares on secondary market). Both can be disabled by governance: setRagequittable(false) disables ragequit, and setTransfersLocked(true, true) disables all transfers. If both are disabled, members have NO exit path. Their shares/loot are locked with no way to redeem value. This effectively allows a governance majority to trap minority members. There is no exit window, grace period, or notice requirement before these changes take effect. The changes are immediate upon proposal execution.

```solidity
    function setRagequittable(bool on) public payable onlyDAO {
        ragequittable = on;
    }
```

**Impact:** Members can be permanently trapped with no exit mechanism. Their share of the treasury becomes inaccessible. This is a fundamental governance trust assumption that may not be acceptable for all DAO configurations.

**Recommendation:** Consider: (1) Adding a mandatory exit window (e.g., 7-day notice period) before ragequit can be disabled, during which members can ragequit. (2) Preventing both ragequit and transfers from being disabled simultaneously (require at least one exit mechanism). (3) Making ragequittable immutable once set to true. SafeSummoner could enforce these as deployment-time constraints.

---

### M-07 — Governance parameter changes retroactively alter active proposal outcomes (TMP-5 violation)

**Severity:** Medium
**Location:** `src/Moloch.sol:504-507` (`executeByVotes`), `src/Moloch.sol:433-478` (`state`), `src/Moloch.sol:442-444` (`state`)
  + 14 additional location(s)

**Description:** Proposal state (Active, Succeeded, Defeated, Expired) is computed dynamically by state() using current governance parameters (quorumBps, quorumAbsolute, minYesVotesAbsolute, proposalTTL, timelockDelay). These parameters are mutable via onlyDAO functions. When governance changes these parameters, ALL active proposals are retroactively affected: (1) Increasing quorumBps can flip Succeeded proposals back to Active (quorum no longer met). (2) Decreasing quorumBps can promote Active proposals to Succeeded (quorum now met with fewer votes). (3) Increasing minYesVotesAbsolute can defeat previously-passing proposals. (4) Decreasing proposalTTL can expire in-flight Active proposals. (5) Changing timelockDelay affects the execution timeline of already-queued proposals. This violates the temporal invariant TMP-5 (proposal state transitions should be monotonic). The root cause is that state() computes state from current parameters rather than parameters snapshotted at proposal creation.

```solidity
        ProposalState st = state(id);

        // only Succeeded or Queued proposals are allowed through
        if (st != ProposalState.Succeeded && st != ProposalState.Queued) revert NotOk();
```

**Impact:** Governance can manipulate the outcome of any active proposal by changing parameters. A proposal that would have passed can be defeated (or vice versa) without any additional voting. This undermines voter expectations and can be used for governance attacks.

**Recommendation:** Snapshot governance parameters at proposal creation time (store quorumBps, quorumAbsolute, minYesVotesAbsolute, proposalTTL at the proposal's snapshotBlock) and use the snapshotted values in state(). This ensures proposals are evaluated under the rules active when they were created. Alternatively, document this as an intentional governance power and ensure members understand proposals can be retroactively affected.

---

### M-08 — Silent early return allows front-running to lock unfavorable snapshot block

**Severity:** Medium
**Location:** `src/Moloch.sol:279-279` (`openProposal`)

**Description:** Line 279 silently returns if snapshotBlock[id] is already set. The first caller permanently locks the snapshot. An attacker can front-run a legitimate proposer to set the snapshot at block.number-1 of the attacker's choosing -- specifically a block where the attacker has maximum voting power due to recent delegation.

```solidity
        if (snapshotBlock[id] != 0) return;
```

**Impact:** Attacker can choose the snapshot block to maximize their voting power.

**Recommendation:** Consider requiring that only the proposer can open the proposal, or use a commit-reveal scheme.

---

### M-09 — executed[tokenId] set without prior check -- permit spend blocks governance proposals sharing same intent hash

**Severity:** Medium
**Location:** `src/Moloch.sol:668-668` (`spendPermit`), `src/Moloch.sol:434-434` (`state`)

**Description:** spendPermit sets executed[tokenId] = true but never checks if it is already true. Since state() returns ProposalState.Executed when executed[id] is true, a permit spend can permanently mark a proposal as Executed, blocking castVote and executeByVotes. Conversely, a proposal execution blocks further permit spends from being meaningful.

```solidity
        executed[tokenId] = true;
```

**Impact:** A permit spend can permanently block a governance proposal or vice versa.

**Recommendation:** Use separate namespaces for permit and proposal execution tracking.

---

### M-10 — No guard prevents reconfiguration -- existing tap silently overwritten

**Severity:** Medium
**Location:** `src/peripheral/TapVest.sol:50-55` (`configure`)

**Description:** configure() has no check for existing tap. Any governance proposal calling configure() again overwrites beneficiary, token, rate and resets lastClaim. Forfeits unclaimed vested funds and redirects future vesting.

```solidity
    function configure(address token, address beneficiary, uint128 ratePerSec) public {
        if (ratePerSec == 0) revert ZeroRate();
        require(beneficiary != address(0));
        taps[msg.sender] = TapConfig(token, beneficiary, ratePerSec, uint64(block.timestamp));
        emit Configured(msg.sender, beneficiary, token, ratePerSec);
    }
```

**Impact:** Active tap silently replaced, forfeiting all unclaimed vested funds.

**Recommendation:** Add guard preventing reconfiguration if tap exists, or auto-claim before overwriting.

---

## Low

### L-01 — Futarchy resolution always resolves YES side regardless of governance outcome

**Severity:** Low
**Location:** `src/Moloch.sol:674-674` (`spendPermit`)

**Description:** spendPermit calls _resolveFutarchyYes(tokenId) which finalizes futarchy with winner=1 (FOR side). If a permit exists for the same intent hash as a defeated proposal, spending the permit resolves futarchy as YES even though the proposal was defeated.

**Impact:** Incorrect futarchy resolution pays out wrong side of prediction market.

**Recommendation:** Do not resolve futarchy from spendPermit, or check that the permit's tokenId does not have an active futarchy configuration.

---

### L-02 — Governance delegatecall (executeByVotes op=1) grants unrestricted storage write access

**Severity:** Low
**Location:** `src/Moloch.sol:976-986` (`_execute`), `src/Moloch.sol:672-672` (`spendPermit`), `src/Moloch.sol:73-73` (`_execute`)

**Description:** executeByVotes with op=1 executes `to.delegatecall(data)` in Moloch's storage context. This allows governance to: (1) overwrite any storage slot including executed[], balanceOf[], totalSupply[], allowance[], and all governance parameters, (2) bypass all onlyDAO checks since delegatecall preserves msg.sender=address(this), (3) execute arbitrary code with Moloch's ETH balance, (4) modify Shares/Loot/Badges contract addresses to point to attacker-controlled contracts. The delegatecall target can contain any logic that overwrites Moloch's storage layout, potentially breaking all invariants. This is an intentional governance power (needed for upgrades and emergency actions like ShareBurner), but represents the maximum possible centralization risk.

**Impact:** Governance majority can modify any contract state, drain all funds, change token contracts, and break all invariants. This subsumes all other governance risks.

**Recommendation:** Document the delegatecall power as a governance trust assumption. Consider restricting op=1 to a whitelist of approved delegatecall targets (e.g., ShareBurner only) or requiring a higher quorum for delegatecall proposals. SafeSummoner could enforce that op=1 proposals require supermajority.

---

### L-03 — Peripheral contracts (TapVest, ShareSale) lack independent reentrancy guards; cross-contract safety depends on Moloch's guard

**Severity:** Low
**Location:** `src/peripheral/TapVest.sol:59-96` (`claim`), `src/peripheral/TapVest.sol:131-138` (`setBeneficiary`), `src/peripheral/TapVest.sol:147-148` (`setRate`)
  + 1 additional location(s)

**Description:** TapVest.claim() and ShareSale.buy() make multiple external calls but have no reentrancy guards of their own. Their cross-contract safety depends entirely on Moloch.spendAllowance being nonReentrant. The call flow for TapVest.claim(): (1) IMoloch.allowance (view), (2) balanceOf (view), (3) IMoloch.spendAllowance (nonReentrant on Moloch), (4) safeTransferETH/safeTransfer to beneficiary. After step 3 completes, Moloch's nonReentrant is released. Step 4 sends tokens to the beneficiary, whose callback could reenter TapVest.claim(). However, tap.lastClaim was updated before external calls (CEI at L83), so reentry yields elapsed=0 -> owed=0 -> revert. For ShareSale.buy(): (1) collect payment, (2) spendAllowance (nonReentrant on Moloch, released after), (3) safeTransfer to buyer. Step 1's safeTransferFrom could trigger ERC777 hooks that reenter buy() -- but ShareSale has no mutable state (all state is on Moloch side via allowances). Reentrant buy() would just execute a second purchase, decrementing the allowance again. Combined with the unchecked overflow in cost calculation (3B-01), this could amplify the exploit. LPSeedSwapHook.seed() mitigates via cfg.seeded=true (CEI). Tribute has its own nonReentrant.

**Impact:** TapVest: no exploitable impact due to CEI on lastClaim. ShareSale: reentrant ERC777 payToken could trigger multiple purchases in a single call, each decrementing allowance. Combined with unchecked overflow (3B-01), each reentrant call could acquire shares at near-zero cost.

**Recommendation:** Defense-in-depth: add a transient-storage nonReentrant modifier to ShareSale.buy() and TapVest.claim(). TapVest's CEI on lastClaim provides sufficient protection today, but an explicit guard prevents future regression. ShareSale is more concerning because it has no state-based reentrancy protection.

---

### L-04 — Stale seats[slot].bal cache causes incorrect eviction when _recomputeMin finds no non-zero seat

**Severity:** Low
**Location:** `src/Moloch.sol:1911-1927` (`_recomputeMin`), `src/Moloch.sol:1876-1889` (`onSharesChanged`)

**Description:** _recomputeMin skips seats where seats[i].bal == 0. If all occupied slots have stale zero cached balances, it sets minSlot=0, minBal=0. In path 4 (full board), any newcomer with bal > 0 satisfies bal > minBal and evicts slot 0's holder regardless of whether slot 0 holds the actual minimum.

**Impact:** Incorrect eviction of slot 0 holder instead of true minimum holder, corrupting badge set.

**Recommendation:** Add assertion that minSlot corresponds to an occupied slot with nonzero balance before using it for eviction. Treat minBal=0 as sentinel for 'no valid cutline' and skip eviction.

---

### L-05 — Tribute escrow accounting broken with fee-on-transfer tokens

**Severity:** Low
**Location:** `src/peripheral/Tribute.sol:89-96` (`proposeTribute`)

**Description:** Tribute.proposeTribute stores the user-provided `tribAmt` as the escrowed amount after calling `safeTransferFrom(tribTkn, address(this), tribAmt)`. If the tribute token charges a fee on transfer, the contract receives less than `tribAmt` (e.g., receives tribAmt - fee). However, `offer.tribAmt` stores the full pre-fee amount. When cancelTribute or claimTribute later calls `safeTransfer(tribTkn, recipient, offer.tribAmt)`, it attempts to send more tokens than the contract actually received. This either (1) reverts if the contract has insufficient balance, permanently locking the deposit, or (2) succeeds by spending tokens from other users' tribute escrows, creating a first-in-last-out insolvency. Since Tribute is a singleton serving all DAOs, the accounting corruption affects all users of the same token.

**Impact:** With fee-on-transfer tokens: (1) individual tributes may become permanently locked (cancel/claim reverts), or (2) later tributes subsidize earlier ones, creating insolvency for late claimers. Without FOT tokens, no impact.

**Recommendation:** Measure the actual amount received using a balance-before/after pattern: `uint256 balBefore = balanceOf(tribTkn, address(this)); safeTransferFrom(...); uint256 received = balanceOf(tribTkn, address(this)) - balBefore; offer.tribAmt = received;`. Alternatively, document that fee-on-transfer tokens are not supported and add a check that received >= tribAmt.

---

### L-06 — When winSupply is zero, pool funds are permanently locked

**Severity:** Low
**Location:** `src/Moloch.sol:612-629` (`_finalizeFutarchy`), `src/Moloch.sol:618-622` (`_finalizeFutarchy`)

**Description:** If totalSupply of winning-side receipts is zero when resolved, the conditional skips setting payoutPerUnit but F.resolved is still set to true and F.pool retains its value. Pool funds become permanently irrecoverable since no one holds winner receipts to cash out.

**Impact:** Funded futarchy pool permanently irrecoverable.

**Recommendation:** When winSupply is 0 but pool is nonzero, refund the pool to the DAO treasury.

---

### L-07 — balanceOf assembly helper silently returns zero on revert, masking supply gate

**Severity:** Low
**Location:** `src/peripheral/LPSeedSwapHook.sol:384-388` (`_isReady`), `src/peripheral/LPSeedSwapHook.sol:443-452` (`balanceOf`)

**Description:** Free function balanceOf uses assembly staticcall and returns 0 on failure. If cfg.tokenB is an EOA or destroyed contract, balanceOf returns 0, which is <= cfg.minSupply for any non-zero minSupply, causing supply gate to pass. Allows seedable to return true under incorrect conditions.

**Impact:** Supply gate bypassed if tokenB becomes non-contract, allowing premature seeding.

**Recommendation:** Validate cfg.tokenB has code (extcodesize > 0) before relying on balance check, or validate tokenB during configure().

---

### L-08 — Extremely low price enables near-free token acquisition via rounding in buy()

**Severity:** Low
**Location:** `src/peripheral/ShareSale.sol:52-56` (`configure`), `src/peripheral/ShareSale.sol:68-70` (`buy`)

**Description:** configure() accepts any non-zero price (minimum: 1 wei). In buy(), cost = amount * price / 1e18 in unchecked block. With price=1, buying up to 1e18-1 tokens yields cost=0 (truncation). Even with reasonable prices, small amounts can round cost to 0.

**Impact:** Tokens acquired for free if price too low or amount small enough for cost to round to zero.

**Recommendation:** Enforce minimum price floor in configure() or check cost > 0 in buy().

---

### L-09 — First funder chooses reward token permanently when no preset is set

**Severity:** Low
**Location:** `src/Moloch.sol:545-552` (`fundFutarchy`)

**Description:** When rewardToken preset is address(0), first caller permanently sets F.rewardToken to whatever token passed. Anyone can front-run to lock proposal's futarchy market into undesirable reward token (e.g., address(shares) forcing governance token deposits).

**Impact:** Attacker locks futarchy market into unfavorable reward token.

**Recommendation:** Always require governance-set preset reward token, or restrict first-funder token choice.

---

### L-10 — Funding after proposal cancellation can permanently lock funds

**Severity:** Low
**Location:** `src/Moloch.sol:540-540` (`fundFutarchy`)

**Description:** Checks F.resolved but not executed[id]. Cancelled proposals set executed[id]=true as tombstone but if futarchy was never enabled, fundFutarchy can still be called. Funds locked since proposal can never reach Defeated/Expired state needed for resolveFutarchyNo.

**Impact:** Funds permanently locked in cancelled proposal's futarchy market.

**Recommendation:** Add check: if (executed[id]) revert NotOk();

---

### L-11 — Guardian can front-run DAO governance that attempts to revoke guardian

**Severity:** Low
**Location:** `src/peripheral/RollbackGuardian.sol:80-96` (`rollback`)

**Description:** If the DAO submits a proposal to revoke() or setGuardian(), the current guardian can front-run by calling rollback() first. bumpConfig invalidates all pending proposals including the removal proposal. Guardian has effective veto over own removal.

**Impact:** Guardian prevents own removal by invalidating the removal proposal.

**Recommendation:** Document this trust assumption. DAOs should only appoint trusted guardians or use short expiry windows.

---

### L-12 — Missing ERC-6909 per-token-id allowance mechanism

**Severity:** Low
**Location:** `src/Moloch.sol:925-937` (`transferFrom`)

**Description:** ERC-6909 specifies per-token-id allowance and approve functions. Moloch's transferFrom only checks isOperator (blanket operator flag) but does not check or deduct per-id allowances. No approve(address, uint256, uint256) function exists. Users can only grant blanket operator access over ALL token ids or no access at all.

**Impact:** Breaks ERC-6909 compliance. Integrators expecting per-id allowance pattern cannot function.

**Recommendation:** Add standard ERC-6909 approve function with per-id allowance mapping and deduction in transferFrom.

---

### L-13 — Missing futarchy gate allows vote cancellation on futarchy-resolved proposals

**Severity:** Low
**Location:** `src/Moloch.sol:394-396` (`cancelVote`), `src/Moloch.sol:365-366` (`castVote`)

**Description:** castVote checks if (F.enabled && F.resolved) revert, but cancelVote has no equivalent check. Voter can cancel vote after futarchy resolution, potentially changing proposal outcome and invalidating futarchy market results. Futarchy payouts may already have been distributed.

**Impact:** Vote cancellation after futarchy resolution can flip proposal outcome, creating inconsistency with market results.

**Recommendation:** Add same futarchy guard to cancelVote.

---

### L-14 — Missing upper-bound validation on _quorumBps allows values > 10000 (>100%)

**Severity:** Low
**Location:** `src/Moloch.sol:226-226` (`init`), `src/Moloch.sol:813-816` (`setQuorumBps`)

**Description:** The init function accepts _quorumBps as a uint16 (max 65535) and stores it directly without validation. In contrast, setQuorumBps explicitly checks if (bps > 10_000) revert NotOk(). If a DAO is initialized with _quorumBps > 10000, the quorum requirement would exceed 100% of total supply, making it impossible for any proposal to ever pass.

**Impact:** A DAO initialized with quorumBps > 10000 would have permanently unresolvable proposals.

**Recommendation:** Add the same validation as setQuorumBps: if (_quorumBps > 10_000) revert NotOk();

---

### L-15 — No per-address purchase cap enables single buyer monopolization

**Severity:** Low
**Location:** `src/peripheral/ShareSale.sol:61-100` (`buy`)

**Description:** Single buyer can purchase entire allowance in one transaction. No per-address cap, no cooldown, no maximum purchase amount. Well-funded actor monopolizes entire share offering.

**Impact:** Whale acquires all shares, centralizing governance power.

**Recommendation:** Consider optional per-address cap in Sale struct enforced via cumulative purchase mapping.

---

### L-16 — Path 2 minBal update incorrectly promotes non-minimum slot when minBal==0

**Severity:** Low
**Location:** `src/Moloch.sol:1853-1855` (`onSharesChanged`)

**Description:** When minBal==0 (invalid tracking state from _recomputeMin finding no nonzero seat), condition minBal == 0 || bal < minBal blindly assigns current holder as minimum even if their balance is very high.

**Impact:** Incorrect minSlot/minBal tracking leads to wrong eviction targets.

**Recommendation:** Call _recomputeMin() when minBal is 0 rather than blindly assigning current holder.

---

### L-17 — Simple mulDiv reverts on phantom overflow for large treasury balances

**Severity:** Low
**Location:** `src/Moloch.sol:1987-1995` (`mulDiv`), `src/Moloch.sol:791-791` (`ragequit`)

**Description:** The mulDiv implementation uses simple mul(x, y) in assembly which performs modular 256-bit multiplication, then checks div(z, x) == y to detect overflow. This is NOT the full Solady mulDiv that handles phantom overflow (where x*y overflows 256 bits but x*y/d fits in 256 bits). For a treasury with very large token balances, pool * amt can exceed 2^256 even though pool * amt / total would fit, causing ragequit to revert and trapping funds.

**Impact:** Ragequit becomes impossible for affected tokens, trapping member funds in the DAO.

**Recommendation:** Replace with the full Solady mulDiv that uses the Karatsuba/schoolbook method to handle phantom overflow, or use OpenZeppelin's Math.mulDiv.

---

### L-18 — Cancel-and-revote enables vote flipping that can manipulate proposal state transitions

**Severity:** Low
**Location:** `src/Moloch.sol:394-417` (`cancelVote`)

**Description:** Voter can cancelVote then castVote with different support to flip vote. Combined with dynamic state() computation, a Succeeded proposal can be forced back to Active by cancelling FOR votes to drop below quorum, then re-voting AGAINST.

**Impact:** Proposals oscillate between Active/Succeeded/Defeated, enabling front-running of queue/execute calls.

**Recommendation:** Consider cooldown preventing revote in same block, or snapshot tallies at quorum-crossing moment.

---

### L-19 — ERC-6909 receipt transferability enables receipt-holder mismatch with actual voter

**Severity:** Low
**Location:** `src/Moloch.sol:389-389` (`castVote`)

**Description:** ERC-6909 receipts can be transferred. Voter who transfers receipts cannot cancel vote (_burn6909 underflows). Receipt recipient cannot cancel (hasVoted mapped to original voter). But recipient CAN claim futarchy rewards without having voted.

**Impact:** Voters cannot cancel after transfer. Receipt trading creates secondary market for futarchy rewards.

**Recommendation:** Make receipt IDs non-transferable if not intentional, or document implications for cancelVote and futarchy.

---

### L-20 — ETH sent with ERC-20 payToken call is permanently locked

**Severity:** Low
**Location:** `src/peripheral/ShareSale.sol:61-83` (`buy`)

**Description:** Function is payable. When payToken != address(0), payment via safeTransferFrom (ERC-20). Accidental ETH sent is not refunded and locked in ShareSale forever with no withdrawal mechanism.

**Impact:** Users accidentally attaching ETH with ERC-20 payment lose funds permanently.

**Recommendation:** Add if (msg.value != 0) revert() in ERC-20 branch or add ETH rescue function.

---

### L-21 — SafeSummoner constraints not enforced by raw Summoner -- DAOs can be deployed with unsafe configurations

**Severity:** Low

**Description:** SafeSummoner enforces important safety constraints: minimum quorumBps, proposalTTL > 0, proposalThreshold > 0, ragequittable=true, and timelockDelay > 0. The raw Summoner contract enforces none of these. A DAO deployed via raw Summoner can have: (1) quorumBps=0 with no absolute quorum (all proposals pass with 1 vote), (2) proposalTTL=0 (proposals never expire, can accumulate indefinitely), (3) proposalThreshold=0 (anyone can create proposals), (4) ragequittable=false (no exit mechanism), (5) timelockDelay=0 (instant execution, no ragequit window). These configurations individually and in combination create governance risks that SafeSummoner was designed to prevent.

**Impact:** DAOs deployed via raw Summoner may have unsafe governance configurations that enable majority attacks, member trapping, or governance deadlock.

**Recommendation:** Document that raw Summoner deployments bypass safety checks. Consider deprecating raw Summoner in favor of SafeSummoner, or adding minimum safety checks to Moloch.init() itself.

---

### L-22 — Sale configured with minting + absolute-only quorum allows governance takeover via share purchases

**Severity:** Low
**Location:** `src/peripheral/SafeSummoner.sol:659-661` (`_validate`)

**Description:** _validate checks saleActive && saleMinting && quorumBps > 0 && quorumAbsolute == 0 but does NOT check quorumBps == 0 && quorumAbsolute > 0 case. Attacker can buy enough shares through minting sale to exceed quorumAbsolute, then pass proposals unilaterally.

**Impact:** Attacker buys shares to single-handedly meet absolute quorum, then drains treasury.

**Recommendation:** Validate that minting sale with absolute-only quorum has saleCap limiting total mintable shares relative to quorumAbsolute.

---

### L-23 — Sale overwrites without cap accounting -- remaining cap silently discarded

**Severity:** Low
**Location:** `src/Moloch.sol:699-701` (`setSale`)

**Description:** When setSale is called for a payToken that already has an active sale, the entire Sale struct is overwritten. Previously sold shares are not accounted for, allowing cap resets.

**Impact:** More shares/loot could be sold than intended if caps are reset.

**Recommendation:** Emit previous sale's remaining cap in event, or require explicit deactivation first.

---

### L-24 — Zero-address in initHolders leads to shares minted to address(0)

**Severity:** Low
**Location:** `src/peripheral/SafeSummoner.sol:321-337` (`summonStandard`)

**Description:** No check that initHolders entries are non-zero. Shares minted to address(0) are effectively burned but still count toward total supply, inflating quorum denominator.

**Impact:** Quorum denominator inflated by unmovable shares at address(0).

**Recommendation:** Validate no initHolders entry is address(0).

---

### L-25 — fundFutarchy can open any arbitrary proposal id via openProposal

**Severity:** Low
**Location:** `src/Moloch.sol:541-541` (`fundFutarchy`)

**Description:** If snapshotBlock[id]==0, calls openProposal(id) with unconstrained id parameter. Any user meeting proposalThreshold can open arbitrary proposal ids, squatting on ids or polluting proposalIds array.

**Impact:** Proposal id namespace pollution and governance interference.

**Recommendation:** Validate proposal id corresponds to legitimate proposal before allowing funding to open it.

---

## Informational

### I-01 — No access control allows front-running or griefing of futarchy resolution timing

**Severity:** Informational
**Location:** `src/Moloch.sol:573-573` (`resolveFutarchyNo`)

**Description:** resolveFutarchyNo is public with no access restriction. Any address can call it the moment a proposal enters Defeated or Expired state, removing any ability for the DAO to control the timing of resolution.

**Impact:** Adversary controls timing of No-side resolution.

**Recommendation:** Document that anyone can trigger resolution once the proposal is Defeated/Expired.

---

### I-02 — Setting threshold to zero disables proposal gating entirely

**Severity:** Informational
**Location:** `src/Moloch.sol:843-845` (`setProposalThreshold`), `src/Moloch.sol:283-286` (`openProposal`)

**Description:** When proposalThreshold is 0, the threshold check in openProposal is skipped entirely, meaning any address including those with zero voting power can open proposals. Enables proposal spam.

**Impact:** Proposal spam and UX degradation.

**Recommendation:** Consider enforcing a minimum non-zero threshold or document the risks of zero-threshold configuration.

---

### I-03 — cap=0 creates unlimited sale with no upper bound

**Severity:** Informational
**Location:** `src/Moloch.sol:699-701` (`setSale`), `src/Moloch.sol:716-716` (`buyShares`)

**Description:** When cap is set to 0, buyShares treats it as unlimited. A single buyer could mint an arbitrarily large number of shares/loot, gaining majority governance control.

**Impact:** Attacker could acquire majority governance control in single transaction.

**Recommendation:** Add per-transaction or per-address limits when cap=0.

---

### I-04 — Auto-futarchy uses stale reward token address without validation

**Severity:** Informational
**Location:** `src/Moloch.sol:309-315` (`openProposal`)

**Description:** If rewardToken is address(0), the fallback address(1007) is used as a sentinel. The reward token is locked at proposal-open time. If the DAO admin later changes rewardToken, previously opened proposals still have their futarchy configured with the old reward token.

**Impact:** Proposals may not receive expected futarchy funding if rewardToken changes.

**Recommendation:** Document the behavior that reward token is locked at proposal-open time.

---

### I-05 — Multicall with create2Deploy allows deterministic address squatting via front-running

**Severity:** Informational
**Location:** `src/peripheral/SafeSummoner.sol:210-210` (`multicall`)

**Description:** Permissionless multicall can batch create2Deploy calls. Attacker can front-run and deploy different contract at a predicted address using same salt but different creation code. General CREATE2 front-running amplified by multicall batch capability.

**Impact:** Deployment at expected address blocked or hijacked.

**Recommendation:** Integrators should incorporate msg.sender into salt to prevent address squatting.

---

### I-06 — Malicious ERC-20 token as forTkn can revert on safeTransferFrom to block claim permanently

**Severity:** Informational
**Location:** `src/peripheral/Tribute.sol:164-164` (`claimTribute`)

**Description:** The proposer chooses forTkn. If forTkn is a malicious or pausable ERC-20 that always reverts on transferFrom, the DAO can never successfully call claimTribute. The proposer can still cancelTribute to recover their funds.

**Impact:** DAO cannot claim a specific tribute. No fund loss since proposer can cancel.

**Recommendation:** Document that DAOs should verify forTkn is a legitimate, transferable ERC-20 before attempting to claim.

---

### I-07 — Proposer address could be a contract that reverts on ETH receive -- blocking claim

**Severity:** Informational
**Location:** `src/peripheral/Tribute.sol:158-158` (`claimTribute`)

**Description:** When forTkn is address(0) (ETH), safeTransferETH sends ETH to the proposer. If the proposer is a contract without a receive/fallback function, the ETH transfer fails, reverting the entire claimTribute.

**Impact:** DAO unable to claim tribute. Proposer can still cancel.

**Recommendation:** Consider a pull-based withdrawal pattern for the proposer's payment.

---

### I-08 — Unchecked block in _finalizeFutarchy -- payoutPerUnit truncation silently loses funds as dust

**Severity:** Informational
**Location:** `src/Moloch.sol:612-629` (`_finalizeFutarchy`)

**Description:** The ppu calculation ppu = mulDiv(pool, 1e18, winSupply) truncates. When users claim via cashOutFutarchy, payout = mulDiv(amount, ppu, 1e18) also truncates. The combination of two successive truncating divisions means dust accumulates permanently locked in the contract with no sweep mechanism.

**Impact:** Funds permanently locked as dust in the contract.

**Recommendation:** Add a sweep function or allow the last claimant to receive the remaining pool balance.

---

### I-09 — Ragequit ETH payout callback can invoke non-guarded Moloch functions during payout loop

**Severity:** Informational

**Description:** During ragequit's token payout loop (L780-795), safeTransferETH sends ETH to msg.sender. If msg.sender is a contract, its receive()/fallback() executes. At this point Moloch's transient nonReentrant guard is engaged, blocking re-entry into ragequit, buyShares, spendAllowance, cashOutFutarchy, executeByVotes, and spendPermit. However, several Moloch functions lack nonReentrant: openProposal, castVote, cancelVote, cancelProposal, fundFutarchy, and ERC6909 transfer/transferFrom. The callback can invoke any of these. Notably: (1) fundFutarchy with ETH (already covered by 3A-01 multicall finding but also exploitable here -- callback sends ETH to Moloch increasing address(this).balance for subsequent ragequit loop iterations on other tokens). (2) castVote using historical checkpoint weight (shares were burned in current block but snapshot is block.number-1, so pre-burn weight is used). (3) openProposal to create proposals. None of these affect ragequit's own accounting because shares/loot are already burned and the token payout loop reads each token's balance fresh per iteration. The primary concern is that the callback window allows state mutations (new proposals, votes, futarchy funding) that execute with the DAO in a mid-ragequit state.

**Impact:** Low direct impact on ragequit accounting. The callback window allows state mutations during a mid-ragequit state, but burned shares cannot be double-counted. The interaction with fundFutarchy (ETH deposit back to Moloch) could inflate the balance seen by subsequent iterations for non-ETH tokens, though ETH appears only once in the sorted token array.

**Recommendation:** Defense-in-depth: consider adding nonReentrant to fundFutarchy (which also fixes 3A-01) and openProposal. Alternatively, move ETH to the end of the ragequit token array (user responsibility -- document that ETH should be last in the sorted token list to minimize callback impact).

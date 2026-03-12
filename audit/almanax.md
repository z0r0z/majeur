# [Almanax](https://almanax.ai/) Security Audit

Findings: 5 (1 High, 2 Medium, 2 Low)

## Review Summary

> **Reviewed 2026-03-12. No production blockers identified. Zero novel findings — all 5 findings are duplicates of known issues or design observations.**
>
> - **5 findings total:** 1 High, 2 Medium, 2 Low. Covers Moloch.sol only.
> - **No novel findings.** Every finding maps to a known issue or is a duplicate of findings from prior audits.
> - Finding #1 (High) is a variant of KF#3/KF#11 — auto-futarchy farming is configuration-dependent and mitigated by `proposalThreshold > 0`.
> - Finding #2 (Medium) is a duplicate of KF#3 — overcommitment is intentional earmark-only accounting.
> - Finding #3 (Medium) is a duplicate of KF#18 — already catalogued; funds recoverable via governance.
> - Finding #4 (Low) is a variant of KF#11 / Octane #1 — mitigated by `proposalThreshold > 0` and atomic `castVote` open+vote.
> - Finding #5 (Low) is a duplicate of KF#8 — fee-on-transfer tokens are a known integration concern.

### Finding-by-Finding Evaluation

**HIGH-1 — Auto-futarchy can be farmed for payouts:**
**Duplicate of KF#3 + KF#11.** Found by Octane (#4), Pashov, Forefy, QuillShield, ChatGPT, ChatGPT Pro, Qwen, Grimoire, and Solarizer before this. The described attack — permissionlessly opening proposals to earmark futarchy pools, then resolving NO to cash out — requires `autoFutarchyParam != 0` AND `proposalThreshold == 0`. With `proposalThreshold > 0`, proposal creation is gated behind real stake. For minted rewards (Loot via `address(1007)`), the attack is real in permissionless configurations but is already documented in KF#3 (futarchy pools subordinate to exit rights) and KF#11 (`proposalThreshold == 0` griefing). The recommendation to "require an explicit DAO-authorized proposal registration step" would fundamentally change Moloch's permissionless proposal model. Existing mitigations: `proposalThreshold > 0`, `autoFutarchyCap` (per-proposal bound), governance can zero `autoFutarchyParam` to halt the attack.

**MED-1 — Futarchy pools can be overcommitted across proposals:**
**Duplicate of KF#3 (found by 8+ prior audits including Octane, Pashov, Forefy, QuillShield, Qwen, Grimoire, Solarizer).** The earmark is intentionally accounting-only (L336: `F.pool += amt` with comment "earmark only"). The code reads live balance (L329-333) and caps to actual holdings — concurrent proposals reading the same balance is by design. Futarchy pools are incentive mechanisms subordinate to ragequit; over-commitment is a feature, not a bug. If the DAO's balance is drained by ragequit or a prior cashout, later cashouts fail gracefully — there is no invariant violation because the DAO's treasury backing is never guaranteed against exit rights.

**MED-2 — Funding executed or cancelled futarchy locks funds:**
**Duplicate of KF#18.** Originally discovered by ChatGPT Pro (GPT 5.4 Pro), confirmed by Solarizer. `fundFutarchy` checks `F.resolved` but not `executed[id]`. After cancel/execute, pools can still be funded but never resolved. Funds are not permanently lost — they remain in the DAO contract and can be recovered via governance vote. Impact is limited to futarchy bookkeeping. The recommendation to add `if (executed[id]) revert NotOk()` is valid and is a v2 hardening candidate.

**LOW-1 — Mempool frontrun can tombstone proposal ids:**
**Duplicate of KF#11.** Previously found by Octane (#1), Zellic (#10), DeepSeek, ChatGPT Pro, Solarizer (MED-1), and Grimoire. The attack requires the attacker to call `openProposal(id)` then `cancelProposal(id)` before any votes are cast. Key mitigations: (1) `castVote` auto-opens proposals atomically (L352), so proposers can open+vote in one tx via `multicall` — preventing the cancel window entirely; (2) `proposalThreshold > 0` restricts who can open; (3) auto-futarchy (`autoFutarchyParam > 0`) sets a non-zero pool on open, blocking cancellation at L428 (`F.pool != 0`); (4) the attacker bears gas costs with no financial incentive; (5) proposer can reissue with a new nonce. The recommendation to bind proposer identity into the ID is a valid v2 hardening idea but changes the proposal model.

**LOW-2 — Fee-on-transfer tokens break pool and sales:**
**Duplicate of KF#8.** Previously found by Archethect (via Solodit), Solarizer, and Claudit. Fee-on-transfer accounting is a known integration concern. `fundFutarchy` and `buyShares` use `safeTransferFrom` without balance-before/after checks, so fee-on-transfer tokens would create accounting mismatches. This is explicitly documented in SECURITY.md's Known Findings. The DAO controls which tokens are used — fee-on-transfer tokens should not be configured as `rewardToken` or sale `payToken`. This is a deployment guidance issue, not a contract vulnerability.

### Summary

| Category | Count | Assessment |
|----------|-------|------------|
| Duplicates of known findings | 4 | HIGH-1 (KF#3/KF#11), MED-1 (KF#3), MED-2 (KF#18), LOW-2 (KF#8) |
| Duplicate of prior audit findings | 1 | LOW-1 (KF#11 / Octane #1) |
| Novel findings | 0 | — |

## Findings

### 1. Auto-futarchy can be farmed for payouts — High

**Category:** Logic & Business Rules

When auto-futarchy is enabled, simply opening a proposal pre-allocates a futarchy pool (`F.pool += amt`) without requiring the proposal to ever become meaningful or executable. An attacker can permissionlessly open many arbitrary ids, vote only on the side that will win by expiry (e.g., vote AGAINST and let it expire), then resolve and cash out to extract the entire auto-allocated pool (minting shares/loot if configured, or draining treasury assets if a real token/ETH is used). This enables repeated dilution/treasury drain limited only by gas and (for non-mint rewards) the DAO's live balances.

**Impacted Code:**

```solidity
function openProposal(uint256 id) public {
    ...
    // auto-futarchy earmark
    {
        uint256 p = autoFutarchyParam;
        if (p != 0) {
            address rt = rewardToken;
            rt = (rt == address(0) ? address(1007) : rt);
            FutarchyConfig storage F = futarchy[id];
            if (!F.enabled) {
                F.enabled = true;
                F.rewardToken = rt;
                emit FutarchyOpened(id, rt);
            }
            ...
            if (amt != 0) {
                F.pool += amt; // earmark only
                emit FutarchyFunded(id, address(this), amt);
            }
        }
    }
}
```

**Recommendation (from auditor):** Require an explicit, DAO-authorized proposal registration step, and only auto-fund futarchy for registered proposals. Additionally, prevent resolution/cashout unless quorum/participation conditions are met, and consider gating `openProposal` behind a non-flashable threshold.

---

### 2. Futarchy pools can be overcommitted across proposals — Medium

**Category:** Logic & Business Rules

For reward tokens that are the DAO-held Shares/Loot contracts, `openProposal` caps `amt` to the DAO's current balance but does not reserve/escrow those tokens; multiple proposals can each earmark the same live balance. When multiple futarchy outcomes are later cashed out, early claimers can drain the DAO-held Shares/Loot and later claimers will revert due to insufficient balance.

**Impacted Code:**

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
    emit FutarchyFunded(id, address(this), amt);
}
```

**Recommendation (from auditor):** Track and reserve (escrow) earmarked balances per token, or remove balance-based auto-funding for transfer-based tokens and require explicit funding per proposal.

---

### 3. Funding executed or cancelled futarchy locks funds — Medium

**Category:** Denial of Service (DoS)

`fundFutarchy` does not check `executed[id]`, so users can fund futarchy for a proposal id that is already executed (including cancelled via `cancelProposal`, which sets `executed[id]=true`). Such a futarchy can never be resolved (`resolveFutarchyNo` reverts when `executed[id]` is true, and YES resolution only happens on successful execution), permanently locking the funded ETH/ERC20 in the DAO contract.

**Impacted Code:**

```solidity
function fundFutarchy(uint256 id, address token, uint256 amount) public payable {
    ...
    FutarchyConfig storage F = futarchy[id];
    if (F.resolved) revert NotOk();
    if (snapshotBlock[id] == 0) openProposal(id);
    ...
    F.pool += amount;
}

function cancelProposal(uint256 id) public {
    ...
    executed[id] = true; // tombstone intent id
}

function resolveFutarchyNo(uint256 id) public {
    FutarchyConfig storage F = futarchy[id];
    if (!F.enabled || F.resolved || executed[id]) revert NotOk();
    ...
}
```

**Recommendation (from auditor):** Add `if (executed[id]) revert NotOk();` to `fundFutarchy`. Consider also allowing an emergency refund path for unresolved futarchy pools.

---

### 4. Mempool frontrun can tombstone proposal ids — Low

**Category:** Front-Running & MEV

The first caller to `openProposal(id)` becomes `proposerOf[id]`, and `cancelProposal(id)` lets that proposer permanently tombstone the id by setting `executed[id]=true` as long as no votes have been cast and the futarchy pool is zero. A mempool attacker can frontrun the first `castVote`/`openProposal` for a target id with `openProposal(id)` then `cancelProposal(id)`.

**Impacted Code:**

```solidity
function openProposal(uint256 id) public {
    if (snapshotBlock[id] != 0) return;
    ...
    proposalIds.push(id);
    proposerOf[id] = msg.sender;
}

function cancelProposal(uint256 id) public {
    require(msg.sender == proposerOf[id], Unauthorized());
    ...
    executed[id] = true; // tombstone intent id
}
```

**Recommendation (from auditor):** Require an explicit proposer commitment so the proposer role can't be stolen via frontrunning. Alternatively, remove proposer-only cancellation or restrict cancellation to the original proposer identity committed into the proposal hash.

---

### 5. Fee-on-transfer tokens break pool and sales — Low

**Category:** External Interactions

Both `fundFutarchy` and `buyShares` assume ERC20 `transferFrom` moves the exact requested amount, but fee-on-transfer or rebasing tokens will transfer less than requested. This causes internal accounting (`F.pool` and implied sale proceeds) to overstate actual received funds.

**Impacted Code:**

```solidity
function fundFutarchy(uint256 id, address token, uint256 amount) public payable {
    ...
    } else {
        if (msg.value != 0) revert NotOk();
        safeTransferFrom(rt, amount);
    }
    F.pool += amount;
}

function buyShares(address payToken, uint256 shareAmount, uint256 maxPay) public payable nonReentrant {
    ...
    } else {
        if (msg.value != 0) revert NotOk();
        safeTransferFrom(payToken, cost);
    }
}
```

**Recommendation (from auditor):** Compute `received = balanceAfter - balanceBefore` and use `received` for accounting; for sales, revert unless `received == cost`.

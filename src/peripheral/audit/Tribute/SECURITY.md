# Tribute.sol Security

> **Purpose:** Aggregated security analysis for `Tribute.sol` — the simple OTC tribute
> escrow maker for DAO proposals. This document indexes all audits, tracks known findings,
> and documents mitigations.

---

## Contract Overview

| Property | Value |
|----------|-------|
| **File** | `src/peripheral/Tribute.sol` |
| **Lines** | ~294 |
| **Role** | OTC escrow — proposers lock tribute tokens, DAOs claim via atomic swap |
| **State** | `tributes` mapping (proposer → dao → token → offer), reference arrays for discovery |
| **Access** | `proposeTribute`/`cancelTribute` are proposer-controlled; `claimTribute` is DAO-only (msg.sender = dao) |
| **Dependencies** | ERC20 tokens (via safeTransferFrom/safeTransfer), ETH transfers |

---

## Audit History

| # | Date | Tool / Auditor | Mode | Findings | Report |
|---|------|----------------|------|----------|--------|
| 1 | 2026-03-12 | Cantina Apex | Multi-agent review | 2 (1 Medium, 1 Low-Medium) | [`cantina-20260312.md`](cantina-20260312.md) |
| 2 | 2026-03-15 | Winfunc | Multi-phase deep validation | 3 (1 Medium, 2 Medium) | [`winfunc-20260315.md`](winfunc-20260315.md) |
| 3 | 2026-03-15 | Zellic V12 | Autonomous scan | 2 (1 High → Duplicate, 1 Low → novel) | [`zellic-20260315.md`](zellic-20260315.md) |

**Aggregate: 3 audits, 5 unique findings (all addressed). 0 Critical, 0 High (after dedup), 3 Medium, 1 Low-Medium, 1 Low.**

---

## Known Findings

| # | Finding | Severity | Status | First Found | Also Confirmed By |
|---|---------|----------|--------|-------------|-------------------|
| 1 | Bait-and-switch: proposer cancel+repost with worse terms between DAO approval and claim execution | Medium | Patched | Cantina MAJEUR-10 | — |
| 2 | Counterfactual escrow theft via summon frontrun — pre-deployment tributes to CREATE2 addresses can be claimed by attacker-deployed DAO | Low-Medium | Accepted | Cantina MAJEUR-17 | — |
| 3 | Fake ERC20 funding — `proposeTribute` doesn't verify actual token receipt, enabling undelivered-tribute payout | Medium | Accepted | Winfunc #14 | — |
| 4 | Stale reference arrays cause enumeration DoS — append-only `daoTributeRefs`/`proposerTributeRefs` accumulate unbounded entries | Medium | Accepted | Winfunc #21/23 | Zellic #3 |
| 5 | Fee-on-transfer tribute misaccounting — `tribAmt` recorded without balance-delta check | Low | Accepted | Zellic #1 | — |

### Finding 1 — Assessment & Patch

**Severity: Medium (patched and redeployed).**

Tribute v2 `claimTribute()` now requires all offer terms `(tribAmt, forTkn, forAmt)` to be passed explicitly and verified against stored values via `TermsMismatch` revert, preventing cancel/repost between approval and execution.

### Finding 2 — Assessment

**Severity: Low-Medium (accepted, edge case).**

Requires (a) pre-launch tribute deposits to counterfactual DAO addresses before deployment, (b) a frontrunnable summon transaction, and (c) the attacker to satisfy the tribute's consideration. Extends SafeSummoner KF#2 (CREATE2 salt not bound to `msg.sender`). The practical risk depends on whether pre-launch tribute deposits are actually used.

### Finding 3 — Assessment

**Severity: Medium (accepted, by design).**

Tribute is an OTC escrow — the DAO must actively call `claimTribute()` via governance to accept an offer. The DAO can and should verify the tribute token address is legitimate before accepting. This is a social engineering vector, not a smart contract bug.

### Finding 4 — Assessment

**Severity: Medium (accepted, view-only concern).**

Discovery arrays are append-only logs for convenience views. Stale refs are filtered out by `getActiveDaoTributes()` which checks `offer.tribAmt != 0`. No fund risk — purely a gas/UX concern for very active proposers. Off-chain indexers (events) are the recommended discovery path.

### Finding 5 — Assessment

**Severity: Low (accepted, out-of-scope token class).**

Standard FOT token concern. Tribute is designed for standard ERC20 tokens and ETH. Balance-delta accounting would add ~5200 gas to every `proposeTribute` for the 99.9% case of standard tokens. The proposer using a FOT token harms themselves (cancel returns less). No external value extraction beyond the escrow pool for that specific token.

---

## Design Choices (Documented, Not Findings)

| # | Observation | Status | Source |
|---|-------------|--------|--------|
| DC-1 | `claimTribute` is DAO-only (msg.sender = dao) — ensures only governance can accept tributes | By design | Cantina |
| DC-2 | ETH tributes use msg.value directly, ERC20 tributes use safeTransferFrom | By design | All audits |

---

## Defense Mechanisms

| Defense | Mechanism | What It Prevents |
|---------|-----------|-----------------|
| **Reentrancy guard** | Transient storage `nonReentrant` modifier | Reentrancy on propose/cancel/claim |
| **Terms verification** | `claimTribute` verifies `(tribAmt, forTkn, forAmt)` against stored values | KF#1: bait-and-switch |
| **Overwrite prevention** | `if (offer.tribAmt != 0) revert` in `proposeTribute` | Duplicate offer overwrites |
| **DAO-only claims** | `msg.sender` = dao in `claimTribute` | Unauthorized tribute acceptance |

---

## Invariants

1. **Escrow integrity** — proposed tribute tokens are held by the contract until cancel or claim
2. **Atomic swap** — `claimTribute` transfers both sides in a single transaction
3. **Proposer-only cancel** — only the original proposer can cancel their tribute
4. **Terms binding** — claim must match stored terms exactly (post-KF#1 patch)

---

## Expanding Coverage

To add new audit results:
1. Save the report as `{tool}-{date}.md` in this directory
2. Update the **Audit History** table above
3. Deduplicate new findings into **Known Findings**
4. Update finding statuses as fixes are applied

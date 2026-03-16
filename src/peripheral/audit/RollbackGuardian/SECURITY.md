# RollbackGuardian.sol Security

> **Purpose:** Security audit prompt and tracking document for `RollbackGuardian.sol` — the
> singleton emergency brake for Moloch DAOs. Paste this document along with a copy of
> `src/peripheral/RollbackGuardian.sol` into your AI of choice.

### Instructions

You are a senior Solidity security auditor. Analyze `RollbackGuardian.sol` (~207 lines, 1 contract) — a singleton that lets a designated guardian emergency-bump a DAO's config (invalidating all pending proposals) or kill auto-futarchy. Work in **two rounds**:

**Round 1: Defense Verification.** For each defense mechanism in the table below, verify it works as described by tracing the actual code. Cite specific line numbers. State whether the defense holds or is broken. Then verify each invariant. Produce a conclusion for every defense and every invariant — "Verified" or "Violated" with evidence.

**Round 2: Adversarial Hunt.** Attempt to find vulnerabilities NOT covered by the Known Findings table or the Design Choices table. For each candidate: (1) check against Known Findings — discard if duplicate, (2) check against Design Choices — discard if intentional, (3) attempt disproof, (4) rate confidence 0-100. Only include findings that survive all checks.

**Report format:** For each finding: `[SEVERITY-N] Title`, severity, confidence, location (file:lines), description, attack path, disproof attempt, recommendation.

---

## Contract Overview

| Property | Value |
|----------|-------|
| **File** | `src/peripheral/RollbackGuardian.sol` |
| **Lines** | ~207 |
| **Role** | Singleton emergency brake — guardian can bump DAO config (orphaning all proposals) or kill auto-futarchy via pre-authorized permits |
| **State** | `mapping(dao => Config)` — per-DAO guardian address + expiry timestamp |
| **Access** | `rollback`/`killFutarchy` = guardian only. `configure` = anyone (keyed by `msg.sender`). `setGuardian`/`setExpiry`/`revoke` = DAO only (keyed by `msg.sender`). |
| **Dependencies** | Moloch permit system (`spendPermit`, `setPermit`), Moloch config system (`bumpConfig`, `setAutoFutarchy`) |

---

## Audit History

| # | Date | Tool / Auditor | Mode | Findings | Report |
|---|------|----------------|------|----------|--------|
| — | — | No dedicated audits yet | — | — | — |

**Cross-references:** SafeSummoner audits cover the `_buildCalls` wiring that generates RollbackGuardian permits. SafeSummoner KF#7 (`rollbackGuardian requires rollbackSingleton`) validates the deploy-time config check.

---

## Known Findings

| # | Finding | Severity | Status | First Found |
|---|---------|----------|--------|-------------|
| — | No findings yet | — | — | — |

---

## Design Choices (Intentional — Do Not Flag)

| # | Observation | Why It's Not a Bug |
|---|-------------|-------------------|
| DC-1 | `configure` is permissionless — anyone can call it | Keyed by `msg.sender`. Only the DAO itself (via governance proposal or initCalls) would call `configure` to set its own guardian. A random caller configuring themselves as a "DAO" has no permit to spend. |
| DC-2 | `rollback` is inherently one-shot — config bump invalidates the permit ID | By design. Permit IDs include `config` in their hash. After `bumpConfig()`, the old permit ID no longer matches. DAO must re-authorize via governance. |
| DC-3 | `killFutarchy` uses a separate nonce/permit from `rollback` | By design. Allows the guardian to kill futarchy (lighter intervention) without invalidating all proposals. Each is independently one-shot. |
| DC-4 | No reentrancy guard | Not needed. No external calls besides `spendPermit` (which is on the trusted DAO). No state changes after the external call. No ETH handling. |
| DC-5 | `setGuardian`/`setExpiry`/`revoke` have no access control beyond `msg.sender` keying | Same pattern as all peripherals. Only the DAO (calling via governance proposal) would call these on its own mapping slot. |
| DC-6 | `expiry == 0` means no expiry | By design. Allows permanent guardians. DAO can always `revoke()` via governance. |
| DC-7 | Guardian can be set to any address including EOA or contract | By design. Multisig guardians are the expected use case. DAO controls the appointment. |

---

## Defense Mechanisms

| Defense | Mechanism | What It Prevents |
|---------|-----------|-----------------|
| **Guardian-only emergency actions** | `msg.sender != c.guardian` check in `rollback`/`killFutarchy` | Unauthorized emergency bumps |
| **Expiry enforcement** | `c.expiry != 0 && block.timestamp > c.expiry` check | Guardian acting after their mandate expires |
| **One-shot permits** | `setPermit(..., count=1)` — permit consumed on first spend | Double-rollback / repeated emergency actions |
| **Config-hash invalidation** | `bumpConfig()` changes `config`, invalidating the permit ID hash | Rollback permit cannot be reused after it fires (self-invalidating) |
| **msg.sender keying** | `configure`/`setGuardian`/`setExpiry`/`revoke` all key to `msg.sender` | Only the DAO can manage its own guardian config |
| **NotConfigured guard** | `c.guardian == address(0)` check on all actions | Actions on unconfigured DAOs |
| **Zero-guardian prevention** | `configure` reverts if `guardian == address(0)` | Misconfigured guardian |

---

## Invariants

1. **Guardian-only emergency actions** — only `configs[dao].guardian` can call `rollback(dao)` or `killFutarchy(dao)`
2. **DAO-only management** — only the DAO (via `msg.sender`) can call `setGuardian`, `setExpiry`, `revoke` on its own config
3. **One-shot rollback** — `rollback()` can succeed at most once per permit authorization (config bump invalidates permit)
4. **One-shot killFutarchy** — `killFutarchy()` can succeed at most once per permit authorization
5. **Expiry respected** — no emergency action succeeds after `expiry` (when `expiry != 0`)
6. **Revocation is total** — `revoke()` deletes the entire config, disabling all guardian actions

---

## Critical Code Paths (Priority Order)

1. **`rollback(dao)`** — Guardian spends the bumpConfig permit. Self-invalidating. Most impactful action (orphans all proposals).
2. **`killFutarchy(dao)`** — Guardian spends the setAutoFutarchy permit. Lighter intervention.
3. **`configure(guardian, expiry)`** — Sets guardian + expiry. Called during DAO init.
4. **`setGuardian`/`setExpiry`/`revoke`** — DAO governance management of guardian config.
5. **`initCalls`/`rollbackPermitCall`/`futarchyPermitCall`** — View helpers for generating deploy-time permit setup calls.

---

## False Positive Patterns (Do NOT Flag These)

| Pattern | Why It's Not a Bug |
|---------|-------------------|
| "Anyone can call configure to set a guardian for any DAO" | `configure` keys to `msg.sender`. The caller sets a guardian for themselves, not for an arbitrary DAO. Without a matching permit, the guardian config is inert. |
| "No reentrancy guard on rollback/killFutarchy" | No state changes after the `spendPermit` external call. No ETH handling. No callback surface. CEI is trivially satisfied. |
| "Guardian is a single point of failure / centralization risk" | The guardian is appointed by DAO governance and can be revoked at any time. The permit is one-shot and self-invalidating. This is strictly less centralized than an admin key. |
| "Expiry can be set to 0 (no expiry)" | By design. DAO can always revoke via governance. Zero-expiry enables long-lived guardians for DAOs that want persistent emergency coverage. |
| "rollback orphans all proposals including legitimate ones" | That's the point — it's an emergency brake. The DAO re-authorizes the guardian via governance after using it. |

---

## Expanding Coverage

To add new audit results:
1. Save the report as `{tool}-{date}.md` in this directory
2. Update the **Audit History** table above
3. Deduplicate new findings into **Known Findings**
4. Update finding statuses as fixes are applied

Recommended scans:
- [ ] Pashov Skills or Grimoire audit of RollbackGuardian.sol
- [ ] Cross-module scan: RollbackGuardian + SafeSummoner permit wiring
- [ ] Verify permit ID hash computation matches Moloch's `_intentHashId`

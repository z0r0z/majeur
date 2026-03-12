# Apex Report - Quick Scan: z0r0z/majeur / majeur

## Table of contents

- [High](#high)
  - [MAJEUR-19 — Custom token validation executes arbitrary HTML/JS from ERC20 names and symbols in the summon UI](#finding-majeur-19)
  - [MAJEUR-15 — Raw proposal IDs let attackers pre-stage next-config proposals and bypass bumpConfig invalidation](#finding-majeur-15)
  - [MAJEUR-10 — Approved Tribute claim can be bait-and-switched to a smaller tribute](#finding-majeur-10)
  - [MAJEUR-6 — Stored XSS in sale discovery lets a badge-holder hijack wallets viewing active custom-token sales](#finding-majeur-6)
- [Medium](#medium)
  - [MAJEUR-24 — Majeur renders supported-network DAICO sales but executes purchases on an unsupported wallet chain](#finding-majeur-24)
  - [MAJEUR-23 — Malicious DAO symbols execute HTML inside the internal-sale proposal builder and preview flow](#finding-majeur-23)
  - [MAJEUR-22 — DAICO deep links turn fake DAO claimTap revert reasons into frontend-origin XSS](#finding-majeur-22)
  - [MAJEUR-21 — Public voting on permit IDs lets any shareholder drain permit futarchy pools via NO-resolution](#finding-majeur-21)
  - [MAJEUR-20 — Internal custom-wrap launches underprice governance sales for >18-decimal ERC20s](#finding-majeur-20)
  - [MAJEUR-18 — Official dapp bypasses SafeSummoner and still ships the exact forbidden launch states](#finding-majeur-18)
  - [MAJEUR-17 — Counterfactual Tribute escrows can be stolen during DAO birth via summon frontrun and initCall-based claim](#finding-majeur-17)
  - [MAJEUR-16 — WalletConnect deep-link switch failures let DAICO read one chain's sale and buy the same seller address on another chain](#finding-majeur-16)
  - [MAJEUR-14 — Forged SALE decimals make DAICO and tap helpers sign attacker-sized governance parameters](#finding-majeur-14)
  - [MAJEUR-13 — DAICO discovery page executes JavaScript from quoted metadata.image URLs](#finding-majeur-13)
  - [MAJEUR-12 — Deep-link fallback calls nonexistent sharesToken()/lootToken() getters and sells loot as shares](#finding-majeur-12)
  - [MAJEUR-11 — DAICO UI labels arbitrary treasury ERC20 sales as voting shares](#finding-majeur-11)
  - [MAJEUR-9 — Forged SALE decimals make treasury transfer proposals encode attacker-sized token amounts](#finding-majeur-9)
  - [MAJEUR-8 — Deep-link fallback opens arbitrary attacker contracts as DAO sales and routes tribute to them](#finding-majeur-8)
  - [MAJEUR-7 — Exact-in drift cap underestimates the LP leg and leaks extra sale inventory once the pool trades above OTC](#finding-majeur-7)
  - [MAJEUR-5 — Metadata text and attributes are rendered as raw HTML in wallet-adjacent modals and cards](#finding-majeur-5)
  - [MAJEUR-4 — Stored governance-UI XSS via unescaped PROPOSAL_DATA calldata gives badge holders arbitrary control of connected members' execution flow](#finding-majeur-4)
  - [MAJEUR-3 — Metadata image fields are interpolated into img tags without escaping, enabling zero-click XSS](#finding-majeur-3)
  - [QUIC-2 — Tribute offer rendering is vulnerable to arbitrary token-symbol XSS](#finding-quic-2)
  - [QUIC-1 — Malicious DAO names and symbols execute HTML in the auto-rendered sales interface](#finding-quic-1)

---

## Review Summary

> **Reviewed 2026-03-12. No production blockers identified. The most productive audit in the series — first to systematically cover the frontend and peripheral contracts (Tribute, DAICO).**
>
> - **24 findings total:** 4 High, 20 Medium. Covers both smart contracts (Moloch core, Tribute, DAICO) and the frontend dapp (`Majeur.html`, `DAICO.html`).
> - **No production blockers.** All 5 novel smart contract findings are configuration-dependent, peripheral-contract scoped, or require attacker preconditions that limit immediate exploitability. All are V2 hardening candidates. The frontend findings are fixable with one systematic `innerHTML` → `textContent` pass and do not affect deployed contracts.
> - **5 novel smart contract findings** — the highest count from any single audit:
>   - **MAJEUR-15 (Medium):** `bumpConfig` emergency brake bypass — lifecycle functions accept raw IDs without config validation, letting a coalition pre-stage proposals across namespace bumps. Not a blocker: the coalition already has enough votes to propose directly; the finding shows `bumpConfig` doesn't deliver its documented guarantee. Extends KF#10. V2 hardening candidate.
>   - **MAJEUR-10 (Medium):** Tribute bait-and-switch — escrow keyed by `(proposer, dao, tribTkn)` without binding settlement terms. Proposer can cancel and repost with smaller tribute between approval and execution. Not a blocker: requires malicious proposer acting against their own tribute, and the timelock window allows detection. V2 fix: bind `claimTribute` to expected terms or use offer nonces.
>   - **MAJEUR-21 (Medium):** Permit IDs enter the proposal/futarchy lifecycle — `openProposal`, `castVote`, `fundFutarchy`, `resolveFutarchyNo` never check `isPermitReceipt[id]`, allowing a shareholder to drain futarchy pools via NO-resolution on permit hashes. Not a blocker: requires the intersection of active permits + auto-futarchy enabled + attacker passing proposal threshold. Extends KF#10. V2 fix: add `if (isPermitReceipt[id]) revert` guards.
>   - **MAJEUR-7 (Low):** DAICO LP drift cap uses `tribForLP` instead of `totalTrib` — the comment cites the correct formula but the code uses the wrong variable, shifting tokens from LP to buyer when pool spot > OTC rate. Not a blocker: (1) buyer still pays full price — no free tokens, DAO treasury receives full payment either way; (2) the drift condition is self-correcting via arbitrage incentives, making the buggy path transient; (3) UIs typically hide the pool until sale completion, further limiting the window. Impact is reduced LP depth, not theft. V2 hardening candidate.
>   - **MAJEUR-17 (Low-Medium):** Counterfactual Tribute theft via summon frontrun — `proposeTribute` accepts undeployed DAO addresses, and `summon` salt excludes `initCalls`, enabling frontrun-based escrow theft. Not a blocker: requires pre-launch tribute deposits to counterfactual addresses — a very specific and uncommon scenario. Extends KF#9.
> - **~15 novel frontend findings** covering XSS via `innerHTML` (10 findings sharing one root cause) and frontend logic bugs (chain mismatch, wrong ABI, mislabeling, trust boundary bypasses). These represent an entirely new attack surface not covered by any prior audit. Not production blockers for deployed contracts — the wallet still requires user signing confirmation for all transactions.
> - **1 finding is a configuration/deployment duplicate:** MAJEUR-18 (SafeSummoner bypass) relates to KF#11, KF#17, KF#2 — the dapp ships the exact configurations SafeSummoner was designed to prevent.
> - **Severity adjustments:** MAJEUR-15 and MAJEUR-10 are rated High by Cantina. We accept them as valid but adjust to **Medium** — MAJEUR-15 requires a coalition with enough votes (who could propose directly), and MAJEUR-10 requires a malicious proposer acting against their own tribute with a timelock window for detection. Both are real design gaps warranting V2 fixes, not production emergencies.
> - **Frontend XSS class:** All 10 XSS findings share a single root cause (`innerHTML` with untrusted data instead of `textContent`/DOM APIs). Individually valid, but the fix is one systematic pass through the dapp replacing `innerHTML` sinks. Grouped as a single remediation item.
> - **Overall assessment:** Cantina's Apex scanner is the first tool to breach the frontend boundary, and the peripheral contract coverage (Tribute, DAICO) surfaced bugs no prior audit found. The 5 novel smart contract findings — more than any other single audit — validate the value of covering the full application surface rather than just the core governance contract.

---

## Smart Contract Findings — Core Moloch

### MAJEUR-15 — Raw proposal IDs let attackers pre-stage next-config proposals and bypass bumpConfig invalidation

> **Review: Valid novel finding. Severity adjusted to Medium.** Code-verified: `openProposal` (L278), `castVote` (L347), `state` (L433), and `queue` (L482) all accept raw `uint256 id` without validating against the current `config` namespace. Only `executeByVotes` (L500) and `proposalId` (L269) derive IDs via `_intentHashId` which includes `config` (L972). The attack path is sound: a coalition computes the future-config proposal ID, opens and votes on it under the current config, then after `bumpConfig`, `executeByVotes` re-derives the same ID and executes the pre-passed proposal.
>
> **Severity adjustment rationale:** The attack requires a coalition with enough voting power to both pass the proposal AND survive quorum. A coalition this powerful could simply propose the same action again after the bump. The finding's value is in demonstrating that `bumpConfig` doesn't deliver its documented guarantee as an emergency brake — defenders cannot rely on it to invalidate proposals from a hostile coalition. This is a governance-safety design gap, not an immediate funds-at-risk exploit.
>
> **Extends KF#10** (permit/proposal namespace overlap) — KF#10 noted the shared namespace as astronomically unlikely to collide. This finding shows the shared namespace has practical governance consequences beyond collision probability.
>
> **V2 hardening:** Store the originating `config` when a proposal is first opened and reject lifecycle actions where stored config ≠ current config. Alternatively, include `config` in all lifecycle function inputs.

### MAJEUR-21 — Public voting on permit IDs lets any shareholder drain permit futarchy pools via NO-resolution

> **Review: Valid novel finding. Medium severity accepted.** Code-verified: `setPermit` (L642) correctly sets `isPermitReceipt[tokenId] = true`, but `openProposal` (L278), `castVote` (L347), `fundFutarchy` (L530), and `resolveFutarchyNo` (L573) never check this flag. A shareholder can treat any permit ID as a regular proposal: open it, vote on it, attach futarchy pools (auto-funded if `autoFutarchyParam > 0`), let it expire, resolve NO, and cash out.
>
> **Practical constraints:** Requires (a) active permits, (b) auto-futarchy enabled, and (c) attacker passing the proposal threshold. In DAOs with all three conditions, this is a concrete drain path.
>
> **Extends KF#10** — the permit/proposal namespace overlap enables a specific theft path through futarchy.
>
> **V2 fix (minimal):** Add `if (isPermitReceipt[id]) revert Unauthorized();` to `openProposal`, `castVote`, `fundFutarchy`, and `resolveFutarchyNo`.

---

## Smart Contract Findings — Peripheral Contracts (Tribute, DAICO)

### MAJEUR-10 — Approved Tribute claim can be bait-and-switched to a smaller tribute

> **Review: Valid novel finding. Severity adjusted to Medium.** Code-verified: `tributes` mapping (L37-39) is keyed by `(proposer, dao, tribTkn)` only — the amounts `tribAmt`, `forAmt`, and `forTkn` are stored in the struct, not the key. `cancelTribute` (L112) deletes the slot, allowing immediate repost with different amounts. `claimTribute` (L132-165) reads whatever is currently stored — its signature `(address proposer, address tribTkn)` includes no expected-amount parameters.
>
> **Severity adjustment rationale:** The proposer must act maliciously against their own tribute offer. The attack window is between proposal passage and execution — the timelock delay gives the DAO time to detect a cancel/repost. Additionally, the ERC20 consideration path requires the DAO to have pre-approved `Tribute` for the `forTkn`, which adds a constraint. Still a valid design gap: the escrow identity should bind the settlement terms.
>
> **V2 fix:** Add a nonce to `TributeOffer` and require `claimTribute` to assert expected `(tribAmt, forTkn, forAmt, nonce)`, or derive an `offerId = keccak256(proposer, dao, tribTkn, tribAmt, forTkn, forAmt, nonce)` and key claims by that hash.

### MAJEUR-7 — Exact-in drift cap underestimates the LP leg and leaks extra sale inventory once the pool trades above OTC

> **Review: Valid novel finding. Severity adjusted to Low.** Code-verified: `_initLP` (L426-432) comment says `tribLPUsed ≤ totalTrib * spot / (2*spot - rate)` but line 430 computes `capTrib = (tribForLP * spotX18) / denom` — using `tribForLP` (the LP portion, e.g. 50% of `payAmt`) instead of `totalTrib` (the buyer's full payment). `_quoteLPUsed` (L759-763) mirrors the same bug. When the pool spot rate exceeds the OTC rate, the cap is underestimated by the LP split factor, and `buyAmt = grossBuyAmt - forTknLPUsed` transfers more sale tokens than the configured `lpBps` haircut allows.
>
> **Severity adjustment rationale:** (1) The buyer pays full price in all cases — no free tokens. The DAO treasury receives full payment whether it routes through LP or direct transfer. The effect is reduced LP depth, not theft. (2) The drift condition (spot > OTC) is self-correcting: rational arbitrageurs buy cheap from the DAICO and sell into the pool, pushing spot back toward OTC. The buggy code path is therefore transient by nature. (3) UIs typically hide the pool until sale completion, further limiting the practical window. Impact is a misallocation between LP depth and buyer token allocation, bounded at ~33% extra in worst case. V2 hardening candidate. Fix: replace `tribForLP` with total tribute in `_initLP` and `_quoteLPUsed`.

### MAJEUR-17 — Counterfactual Tribute escrows can be stolen during DAO birth via summon frontrun and initCall-based claim

> **Review: Valid novel finding. Severity: Low-Medium.** Code-verified: `proposeTribute` (L75) only checks `dao != address(0)` — no deployed-contract check. `summon` (L2078) computes `_salt = keccak256(abi.encode(initHolders, initShares, salt))` — `initCalls` is excluded from the salt. During `init` (L243-246), every `initCall` executes as the DAO via raw `.call`.
>
> **The attack chain is technically valid but requires a specific scenario:** (a) someone deposits a Tribute escrow to a counterfactual DAO address before deployment, (b) the summon transaction is frontrunnable, and (c) the attacker can satisfy the tribute's consideration (e.g., mint shares during init). The "ETH for future shares" flow described in the docs is the realistic case.
>
> **Extends KF#9** — CREATE2 salt not bound to `msg.sender`. KF#9 was rated Info with "No fund loss." This finding escalates it to concrete asset theft when combined with Tribute. The practical risk depends on whether pre-launch tribute deposits are actually used.
>
> **V2 fix:** Include `initCalls` in the salt: `keccak256(abi.encode(msg.sender, initHolders, initShares, salt, keccak256(abi.encode(initCalls))))`. Alternatively, require `proposeTribute` to verify the DAO exists (`address(dao).code.length > 0`).

---

## Configuration/Deployment Finding

### MAJEUR-18 — Official dapp bypasses SafeSummoner and still ships the exact forbidden launch states

> **Review: Valid observation. Duplicate of configuration concerns (KF#11, KF#17, KF#2).** The finding correctly identifies that the production dapp calls `Summoner.summon()` directly instead of `SafeSummoner.safeSummon()`, and that the UI leaves `proposalThreshold` and `proposalTTL` optional while offering no `setQuorumAbsolute` path. This means the dapp can produce exactly the unsafe configurations SafeSummoner was designed to prevent.
>
> **Context:** SafeSummoner was added as hardening *after* the known findings were catalogued. The dapp not using it is a deployment-level gap, not a smart contract bug. The underlying configuration risks are already documented as KF#11 (threshold=0 griefing), KF#17 (zero-quorum futarchy freeze), and KF#2 (minting sale + dynamic quorum).
>
> **Recommendation accepted:** Route the dapp through `safeSummon()` or replicate its guards in the UI submission path. This is a V2 deployment fix.

---

## Frontend Findings — XSS Class (Single Root Cause)

> **Overview:** 10 findings (MAJEUR-19, MAJEUR-6, MAJEUR-23, MAJEUR-22, MAJEUR-13, MAJEUR-5, MAJEUR-4, MAJEUR-3, QUIC-2, QUIC-1) share a single root cause: the dapp uses `innerHTML` with untrusted data (token metadata, DAO metadata, chat content, error messages, revert strings) instead of `textContent` or DOM APIs. These are all novel — no prior audit covered the frontend — and all valid.
>
> **Severity context:** The dapp is a wallet-connected governance interface, so XSS is more impactful than in a typical web app. However, final economic harm still requires the victim to sign a wallet transaction. The wallet confirmation provides a last line of defense, though an attacker controlling the dapp origin can stage convincing phishing flows.
>
> **Grouped remediation:** One systematic pass through `Majeur.html` and `DAICO.html` replacing all `innerHTML` sinks with `textContent`/`createElement` for untrusted data. The dapp already has an `escapeHtml()` helper — the issue is inconsistent application.

### MAJEUR-19 — Custom token validation executes arbitrary HTML/JS from ERC20 names and symbols in the summon UI

> **Review: Valid.** Four separate `innerHTML` sinks in custom-token validators (`fetchAndShowCustomToken`, `validateCustomPaymentToken`, `validateCustomSaleToken`, and the internal-sale validator) render `name()` and `symbol()` from arbitrary ERC20 contracts without escaping. Pasting a malicious token address triggers immediate XSS. Severity: Medium (requires victim to paste a specific address, but the flows are explicitly designed for arbitrary ERC20 inspection).

### MAJEUR-6 — Stored XSS in sale discovery lets a badge-holder hijack wallets viewing active custom-token sales

> **Review: Valid.** `renderSalesInfo()` parses `<<<SALE ... >>>` tags from chat messages and trusts the embedded `symbol` field. A badge-holder can post a forged SALE tag with XSS payload in the symbol. The payload persists on-chain and executes for every viewer. Severity: Medium (requires badge-holder access and an active custom-token sale).

### MAJEUR-4 — Stored governance-UI XSS via unescaped PROPOSAL_DATA calldata

> **Review: Valid.** `decodeProposalMessage()` accepts arbitrary JSON from chat and `renderChatroom()` interpolates `proposalData.data` into an `<a href="...">` attribute via `innerHTML` without escaping. A badge-holder can break out of the attribute and inject script. This is the most impactful XSS finding because it executes automatically when any member opens the chatroom. Severity: Medium-High within the frontend context.

### MAJEUR-3 — Metadata image fields enable zero-click XSS via gallery

> **Review: Valid.** `toGatewayUrl()` returns non-IPFS strings unchanged, and multiple render paths insert `metadata.image` into `<img src="${imageUrl}">` via `innerHTML`. A malicious DAO's `orgURI` metadata can contain `x" onerror="..."` to achieve zero-click XSS on the All DAOs gallery. This is the widest-blast-radius XSS finding since it requires no user interaction beyond opening the browse page.

### MAJEUR-23, MAJEUR-22, MAJEUR-13, MAJEUR-5, QUIC-2, QUIC-1 — Additional innerHTML XSS vectors

> **Review: All valid, same root cause.** These cover additional `innerHTML` sinks across: DAO symbols in the proposal builder (MAJEUR-23), DAICO revert strings (MAJEUR-22), DAICO metadata images (MAJEUR-13), NFT/badge/permit metadata (MAJEUR-5), Tribute token symbols (QUIC-2), and DAO names in the sales interface (QUIC-1). All share the same fix: replace `innerHTML` with DOM APIs for untrusted data.

---

## Frontend Findings — Logic Bugs

### MAJEUR-24 — Cross-chain DAICO purchase on unsupported wallet chain

> **Review: Valid.** The dapp creates a live `signer` even on unsupported chains, reads via `withRpcFallback()` from supported-network public RPCs, but writes via the unsupported-chain signer. For ETH sales, this can degenerate into a plain value transfer to `DAICO_ADDRESS` on a chain where that address has no code. Severity: Medium — requires user to proceed past the unsupported-network warning.
>
> **V2 fix:** Hard-block all transactional flows when signer chain ≠ `currentNetwork`. Refuse to keep a live signer on unsupported chains.

### MAJEUR-16 — WalletConnect deep-link chain split

> **Review: Valid.** `promptNetworkSwitch()` mutates `currentNetwork` and re-runs `handleDeepLink()` even when `wallet_switchEthereumChain` fails. For WalletConnect users, reads bypass the connected provider and use public RPCs for the new chain, while writes still use the old-chain signer. Severity: Medium — requires WalletConnect + failed chain switch + attacker with same EOA on both chains.

### MAJEUR-12 — Deep-link fallback wrong ABI (sharesToken/lootToken vs shares/loot)

> **Review: Valid.** `fetchAndOpenDAO` uses `sharesToken()` and `lootToken()` selectors that don't exist on the deployed Moloch (which exposes `shares()` and `loot()`). With `allowFailure: true`, both reads silently fail, leaving `daoData.lootToken` unset. All loot sales are then mislabeled as shares. Severity: Medium — deterministic mislabeling on the deep-link path.
>
> **Fix:** Change the ABI to `shares()` / `loot()`.

### MAJEUR-11 — DAICO UI labels arbitrary ERC20 sales as voting shares

> **Review: Valid.** The binary classification `isLoot ? 'Loot' : 'Shares'` means any non-loot `forTkn` — including arbitrary worthless ERC20s — is labeled as governance shares. The UI never checks `sale.forTkn == daoData.sharesToken`. Severity: Medium — an attacker can market a worthless token as governance shares through the official UI.
>
> **Fix:** Three-way classification: `sharesToken` → Shares, `lootToken` → Loot, otherwise → "Unverified ERC20" with the actual token address.

### MAJEUR-8 — Deep-link fallback opens arbitrary attacker contracts as DAO sales

> **Review: Valid.** `fetchAndOpenDAO()` bypasses the Summoner trust boundary for deep links. Since `DAICO.setSale()` is keyed by `msg.sender` with no Summoner provenance check, any attacker contract can register a sale and be opened in the trusted purchase modal via a crafted deep link. Severity: Medium — turns a convenience fallback into an arbitrary-seller injection primitive.
>
> **Fix:** Reject deep links for addresses not in the Summoner registry, or label non-Summoner sellers as untrusted.

### MAJEUR-20 — Internal custom-wrap mispricing for >18-decimal tokens

> **Review: Valid but low practical impact.** The internal summon path hardcodes `pricePerShare = 1n` without verifying the custom token has 18 decimals. For >18-decimal tokens, shares are sold at a fraction of the displayed price. Severity: Low — tokens with >18 decimals are extremely rare, and the UI already labels the flow as "Custom Token (18 decimals)."
>
> **Fix:** Validate `decimals() == 18` at submit time, matching the check in other sale builders.

### MAJEUR-14, MAJEUR-9 — Forged SALE decimals in governance helpers

> **Review: Valid.** Chat-derived `<<<SALE>>>` tag decimals are used not just for display but for encoding governance proposal calldata (`setSale`, `setTapRate`, treasury transfers). A badge-holder can poison the decimal count and cause members to sign proposals with wrong raw amounts. Severity: Medium — the fix is the same as the XSS class: don't trust chat-derived metadata for actionable flows. Resolve decimals from the token contract.

---

## Findings Summary

### Novel Smart Contract Findings (5)

| # | Finding | Severity | Category | Extends |
|---|---------|----------|----------|---------|
| MAJEUR-15 | bumpConfig namespace bypass | Medium | Governance safety | KF#10 |
| MAJEUR-10 | Tribute bait-and-switch | Medium | Escrow integrity | New |
| MAJEUR-21 | Permit ID futarchy drain | Medium | Namespace confusion | KF#10 |
| MAJEUR-7 | DAICO LP drift cap math bug | Low | Arithmetic | New |
| MAJEUR-17 | Counterfactual Tribute theft | Low-Medium | CREATE2 frontrun | KF#9 |

### Configuration Duplicate (1)

| # | Finding | Relates To |
|---|---------|-----------|
| MAJEUR-18 | SafeSummoner bypass in dapp | KF#11, KF#17, KF#2 |

### Novel Frontend Findings (~18)

| Category | Findings | Root Cause | Remediation |
|----------|----------|------------|-------------|
| XSS (10 findings) | MAJEUR-19, -6, -23, -22, -13, -5, -4, -3, QUIC-2, QUIC-1 | `innerHTML` with untrusted data | Single systematic pass: `textContent`/DOM APIs |
| Chain mismatch (2) | MAJEUR-24, -16 | Signer chain ≠ read chain | Hard-block on chain mismatch |
| Trust boundary bypass (2) | MAJEUR-8, -22 | Deep-link bypasses Summoner registry | Require Summoner provenance |
| Mislabeling (2) | MAJEUR-12, -11 | Wrong ABI / binary classification | Fix ABI, three-way token classification |
| Decimal poisoning (2) | MAJEUR-14, -9 | Chat-derived metadata in calldata | Resolve decimals from contract |
| Token validation (1) | MAJEUR-20 | Missing 18-decimal check | Validate at submit time |

### Comparison to Prior Audits

| Metric | Cantina | Best Prior (ChatGPT Pro) | Average |
|--------|---------|--------------------------|---------|
| Novel smart contract findings | 5 | 1 | 0.2 |
| Total findings | 24 | 3 | 3.5 |
| Frontend coverage | Full | None | None |
| Peripheral contract coverage | Tribute + DAICO | Core only | Core only |

---

## V2 Hardening Recommendations (from this audit)

**Smart contract fixes:**
- Store originating `config` on proposal open; reject lifecycle actions on stale-config proposals (MAJEUR-15)
- Add `if (isPermitReceipt[id]) revert` to `openProposal`, `castVote`, `fundFutarchy`, `resolveFutarchyNo` (MAJEUR-21)
- Bind `claimTribute` to expected settlement terms via nonce/hash (MAJEUR-10)
- Fix drift cap: replace `tribForLP` with total tribute in `_initLP` and `_quoteLPUsed` (MAJEUR-7)
- Include `initCalls` in `summon` salt, or require `proposeTribute` to verify DAO exists (MAJEUR-17)

**Frontend fixes:**
- Systematic `innerHTML` → `textContent`/DOM API pass for all untrusted data sinks (all XSS findings)
- Hard-block transactional flows on chain mismatch (MAJEUR-24, -16)
- Require Summoner provenance for deep-link DAOs (MAJEUR-8, -22)
- Fix `fetchAndOpenDAO` ABI to `shares()`/`loot()` (MAJEUR-12)
- Three-way token classification: shares / loot / unverified (MAJEUR-11)
- Resolve token decimals from contract, not chat tags (MAJEUR-14, -9)
- Route dapp summon through `SafeSummoner.safeSummon()` (MAJEUR-18)

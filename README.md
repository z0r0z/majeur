# Moloch (Majeur) DAO Framework

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Solidity](https://img.shields.io/badge/solidity-%5E0.8.30-black)](https://docs.soliditylang.org/en/v0.8.30/)
[![Foundry](https://img.shields.io/badge/Built%20with-Foundry-000000.svg)](https://getfoundry.sh/)

[![IPFS Image](https://content.wrappr.wtf/ipfs/bafybeih2mxprvjigedatwn5tdgjx6mcpktfd75t736kkrpjfepcll2n3o4)](https://content.wrappr.wtf/ipfs/bafybeih2mxprvjigedatwn5tdgjx6mcpktfd75t736kkrpjfepcll2n3o4)

**Opinionated DAO governance** — members can always exit with their share of the treasury. Built-in futarchy, weighted delegation, and soulbound badges.

## Why Majeur?

| Feature | Majeur | Governor (OZ) | Aragon OSx |
|---------|--------|---------------|------------|
| Ragequit (exit with treasury share) | Yes | No | No |
| Futarchy (prediction markets on votes) | Yes | No | No |
| Split delegation (60% Alice, 40% Bob) | Yes | No | No |
| Fully on-chain metadata (SVG) | Yes | No | No |
| Single-contract deployment | Yes | Multi-contract | Plugin system |
| DUNA legal wrapper support | Yes | No | No |

**Majeur is for DAOs that prioritize member protection.** Ragequit means no one can be trapped — if you disagree with the majority, burn your shares and leave with your proportional treasury. Futarchy rewards voters who bet correctly on outcomes, not just those who show up. Split delegation lets you diversify representation instead of all-or-nothing.

## Deployments

All contracts are deployed at the same CREATE2 addresses across supported networks.

| Contract | Address | Description |
|----------|---------|-------------|
| Summoner | [`0x0000000000330B8df9E3bc5E553074DA58eE9138`](https://contractscan.xyz/contract/0x0000000000330B8df9E3bc5E553074DA58eE9138) | Factory for deploying new DAOs |
| Renderer | [`0x000000000011C799980827F52d3137b4abD6E654`](https://contractscan.xyz/contract/0x000000000011C799980827F52d3137b4abD6E654) | On-chain SVG metadata renderer |
| MolochViewHelper | [`0x00000000006631040967E58e3430e4B77921a2db`](https://contractscan.xyz/contract/0x00000000006631040967E58e3430e4B77921a2db) | Batch read helper for dApps |
| Tribute | [`0x000000000066524fcf78Dc1E41E9D525d9ea73D0`](https://contractscan.xyz/contract/0x000000000066524fcf78Dc1E41E9D525d9ea73D0) | OTC escrow for tribute proposals |
| DAICO | [`0x000000000033e92DB97B4B3beCD2c255126C60aC`](https://contractscan.xyz/contract/0x000000000033e92DB97B4B3beCD2c255126C60aC) | Token sale with tap mechanism |

## Dapps

> [zfi.wei/dao](https://zfi.wei.is/dao/)

> [majeurdao.eth](https://majeurdao.eth.limo/)

> [daicowtf.eth](https://daicowtf.eth.limo/)

## At a Glance

```
Vote with shares → Split delegation → Futarchy markets → Ragequit exit
     ↓                    ↓                  ↓                ↓
Execute any         60% Alice          Reward correct    Leave with your
on-chain action     40% Bob            predictions       treasury share
```

## Token System

| Token | Standard | Purpose |
|-------|----------|---------|
| **Shares** | ERC-20 | Voting power + economic rights (delegatable) |
| **Loot** | ERC-20 | Economic rights only — no voting |
| **Receipts** | ERC-6909 | Vote receipts for futarchy payouts |
| **Badges** | ERC-721 | Soulbound NFTs for top 256 shareholders |

All tokens are deployed as separate contracts via minimal proxy clones. The DAO controls minting, burning, and transfer locks.

## Architecture

![Majeur Architecture](./assets/architecture.svg)

## Core Concepts

### Ragequit
The defining feature of Moloch-style DAOs: **members can always exit**.

Burn your shares/loot → receive your proportional share of the treasury. Own 10% of shares? Claim 10% of every treasury token. This creates a floor price for membership and protects minorities from majority tyranny.

*Limitation: You can only claim external tokens (ETH, USDC, etc.) — not the DAO's own shares, loot, or badges.*

### Futarchy
Skin-in-the-game governance through prediction markets:

1. Anyone funds a reward pool for a proposal
2. Vote YES, NO, or ABSTAIN → receive receipt tokens
3. Proposal passes → YES voters split the pool; fails → NO voters win
4. Burn your receipts to claim winnings

This shifts incentives from "vote with the crowd" to "vote for what you believe will actually succeed."

### Split Delegation
Distribute voting power across multiple delegates:

```
Traditional:  100% → Alice
Split:        60% → Alice, 40% → Bob, or any combination
```

Useful when you trust different people for different expertise, or want to hedge your representation.

### Badges
Soulbound NFTs automatically minted for the top 256 shareholders. They update in real-time as balances change and gate access to member-only features like on-chain chat.

## Proposal Lifecycle

![Proposal Lifecycle](./assets/proposal-lifecycle.svg)

```
Unopened → Active → Succeeded → Queued (if timelock) → Executed
                 ↘ Defeated
                 ↘ Expired (TTL)
```

**Pass conditions** (all must be true):
- Quorum reached (absolute or percentage)
- FOR > AGAINST (ties fail)
- Minimum YES threshold met (if configured)
- Not expired

## Visual Card Examples

### DAO Contract Card
![DAO Contract Card](./assets/dao-contract-card.svg)

### Proposal Card
![Proposal Card](./assets/proposal-card.svg)

### Vote Receipt Cards
![Vote Receipt Cards](./assets/vote-receipt-cards.svg)

### Permit Card
![Permit Card](./assets/permit-card.svg)

### Badge Card (Top 256 Holders)
![Badge Card](./assets/badge-card.svg)



## Quick Start

### Deploy a DAO

```solidity
// Deploy via Summoner factory
Summoner summoner = new Summoner();

address[] memory holders = [alice, bob, charlie];
uint256[] memory shares = [100e18, 50e18, 50e18];

Moloch dao = summoner.summon(
    "MyDAO",           // name
    "MYDAO",          // symbol
    "",               // URI (metadata)
    5000,             // 50% quorum (basis points)
    true,             // ragequittable
    address(0),       // renderer (0 = default on-chain SVG)
    bytes32(0),       // salt (for deterministic addresses)
    holders,          // initial holders
    shares,           // initial shares
    new Call[](0)     // init calls (optional setup actions)
);
```

### Create & Vote on Proposals

```solidity
// 1. Create proposal ID (anyone can compute this)
uint256 proposalId = dao.proposalId(
    0,                    // op: 0=call, 1=delegatecall
    target,               // contract to call
    value,                // ETH to send
    data,                 // calldata
    nonce                 // unique nonce
);

// 2. Open and vote (auto-opens on first vote)
dao.castVote(proposalId, 1);  // support: 0=AGAINST, 1=FOR, 2=ABSTAIN

// 3. Execute when passed
dao.executeByVotes(0, target, value, data, nonce);
```

### Weighted Delegation (Split Voting Power)

```solidity
// Split delegation: 60% to alice, 40% to bob
address[] memory delegates = [alice, bob];
uint32[] memory bps = [6000, 4000];  // must sum to 10000
dao.shares().setSplitDelegation(delegates, bps);

// Clear split (return to single delegate)
dao.shares().clearSplitDelegation();
```

### Futarchy Markets

```solidity
// Fund a prediction market for a proposal
dao.fundFutarchy(
    proposalId,
    address(0),  // 0 = ETH, or token address
    1 ether      // amount
);

// After resolution, claim winnings
uint256 receiptId = dao._receiptId(proposalId, 1); // 1=YES
dao.cashOutFutarchy(proposalId, myReceiptBalance);
```

### Token Sales

```solidity
// DAO enables share sales (governance action)
dao.setSale(
    address(0),  // payment token (0=ETH, or ERC-20 address)
    0.01 ether,  // price per share (in payment token units)
    1000e18,     // cap (max shares that can be sold)
    true,        // mint new shares (false = transfer from DAO treasury)
    true,        // active (enable sales)
    false        // isLoot (false = shares, true = loot)
);

// Users can buy shares
dao.buyShares{value: 1 ether}(
    address(0),  // payment token (must match the sale config)
    100e18,      // shares to buy
    1 ether      // max payment willing to spend (slippage protection)
);
// Payment goes to DAO treasury, buyer receives shares/loot
```

### Ragequit

```solidity
// Exit with proportional share of treasury
address[] memory tokens = [weth, usdc, dai];
dao.ragequit(
    tokens,      // tokens to claim
    myShares,    // shares to burn
    myLoot       // loot to burn
);
```

## Advanced Features

### Pre-Authorized Permits

DAOs can issue permits allowing specific addresses to execute actions without voting:

```solidity
// DAO issues permit
dao.setPermit(op, target, value, data, nonce, alice, 1);

// Alice spends permit
dao.spendPermit(op, target, value, data, nonce);
```

### Timelock Configuration

```solidity
dao.setTimelockDelay(2 days);  // Delay between queue and execute
dao.setProposalTTL(7 days);     // Proposal expiry time
```

### Member Chat (Badge-Gated)

```solidity
// Only badge holders (top 256) can chat
dao.chat("Hello DAO members!");
```

## Integration Examples

### Reading DAO State

```javascript
// Web3.js/Ethers.js
const shares = await dao.shares();
const totalSupply = await shares.totalSupply();
const myBalance = await shares.balanceOf(account);
const myVotes = await shares.getVotes(account);

// Check proposal state
const state = await dao.state(proposalId);
// States: 0=Unopened, 1=Active, 2=Queued, 3=Succeeded, 4=Defeated, 5=Expired, 6=Executed

// Get vote tally
const tally = await dao.tallies(proposalId);
console.log(`FOR: ${tally.forVotes}, AGAINST: ${tally.againstVotes}`);
```

### Monitoring Events

```javascript
// Key events to watch
dao.on("Opened", (id, snapshot, supply) => {
    console.log(`Proposal ${id} opened at block ${snapshot}`);
});

dao.on("Voted", (id, voter, support, weight) => {
    console.log(`${voter} voted ${support} with ${weight} votes`);
});

dao.on("Executed", (id, executor, op, target, value) => {
    console.log(`Proposal ${id} executed by ${executor}`);
});
```

## Features

### Governance
| Feature | Description |
|---------|-------------|
| Snapshot voting | Block N-1 snapshot prevents vote buying after proposal opens |
| Flexible quorum | Absolute (e.g., 1000 votes) or percentage (e.g., 20%) |
| Timelocks | Configurable delay between passing and execution |
| Proposal TTL | Auto-expire stale proposals |
| Vote/proposal cancellation | Change your mind before execution |

### Economics
| Feature | Description |
|---------|-------------|
| Ragequit | Exit with proportional treasury share |
| Token sales | Built-in share/loot sales at configurable price |
| DAICO | External sale contract with tap mechanism (controlled fund release) |
| Tribute | OTC escrow for membership trades |
| Futarchy | Prediction markets reward correct voters |

### Technical
| Feature | Description |
|---------|-------------|
| Split delegation | Divide voting power across multiple delegates |
| ERC-6909 receipts | Gas-efficient multi-token for vote tracking |
| Clone pattern | ~80% deployment gas savings |
| Transient storage | EIP-1153 reentrancy guards |
| On-chain SVG | Fully decentralized metadata — no IPFS, no servers |

## Wyoming DUNA

Majeur supports Wyoming's **Decentralized Unincorporated Nonprofit Association (DUNA)** — a legal entity that exists purely through smart contracts (Wyoming Statute 17-32-101).

| DUNA Benefit | How Majeur Implements It |
|--------------|--------------------------|
| Limited liability | On-chain legal covenant in metadata |
| Member registry | Top-256 badge system |
| Governance records | All votes stored permanently on-chain |
| Exit rights | Ragequit (legal self-help remedy) |
| No admin burden | No filings, meetings, or formalities |

A DUNA lets your DAO sign real-world agreements, own property, and shield members from personal liability — without incorporating.

## Contract Architecture

```
Summoner (Factory)
└── Deploys via CREATE2 + minimal proxy clones
    │
    ├── Moloch (Main DAO Contract)
    │   ├── Governance logic (proposals, voting, execution)
    │   ├── ERC-6909 receipts (multi-token vote receipts)
    │   ├── Futarchy markets
    │   ├── Ragequit mechanism
    │   └── Token sales
    │
    ├── Shares (Separate ERC-20 + ERC-20Votes Clone)
    │   ├── Voting power tokens
    │   ├── Transferable/Lockable (DAO-controlled)
    │   ├── Single delegation or split delegation
    │   └── Checkpoint-based vote tracking
    │
    ├── Loot (Separate ERC-20 Clone)
    │   ├── Non-voting economic tokens
    │   └── Transferable/Lockable (DAO-controlled)
    │
    └── Badges (Separate ERC-721 Clone)
        ├── Soulbound (non-transferable) NFTs
        ├── Automatically minted for top 256 shareholders
        └── Auto-updated as balances change

Renderer (Singleton)
├── On-chain SVG generation
├── DUNA covenant display
├── DAO contract metadata
├── Proposal cards
├── Vote receipt cards
├── Permit cards
└── Badge cards
```

## Peripheral Contracts

### Tribute (OTC Escrow)

Simple escrow for "tribute proposals" — trade external assets for DAO membership:

```solidity
// 1. Proposer locks tribute (e.g., 10 ETH for 1000 shares)
tribute.proposeTribute{value: 10 ether}(
    dao,           // target DAO
    address(0),    // tribTkn (ETH)
    0,             // tribAmt (use msg.value for ETH)
    sharesToken,   // forTkn (what proposer wants)
    1000e18        // forAmt (how much)
);

// 2. DAO votes to accept, then claims (executes the swap)
// DAO receives tribute, proposer receives shares
dao.executeByVotes(...); // calls tribute.claimTribute(proposer, tribTkn)
```

**Key functions:**
- `proposeTribute()` - Lock assets and create offer
- `cancelTribute()` - Proposer withdraws (before DAO claims)
- `claimTribute()` - DAO accepts and executes swap
- `getActiveDaoTributes()` - View all pending tributes for a DAO

### DAICO (Token Sale + Tap)

Inspired by Vitalik's DAICO concept — controlled fundraising with investor protection:

```solidity
// 1. DAO configures a sale
dao.executeByVotes(...); // calls DAICO.setSaleWithTap(...)

// 2. Users buy shares/loot
daico.buy(dao, address(0), 1 ether, minShares);  // exact-in
daico.buyExactOut(dao, address(0), 1000e18, maxPay);  // exact-out

// 3. Ops team claims vested funds via tap
daico.claimTap(dao);  // anyone can trigger, funds go to ops
```

**Sale Features:**
- Fixed-price OTC sales (tribAmt:forAmt ratio)
- Optional deadline expiry
- Optional LP integration with ZAMM (auto-adds liquidity)
- Drift protection prevents buyer underflow when spot > OTC price

**Tap Mechanism:**
- `ratePerSec` - Funds release rate (smallest units/second)
- `ops` - Beneficiary address (can be updated by DAO)
- Rate changes are non-retroactive (prevents gaming)
- Dynamically caps to min(owed, allowance, balance) — respects ragequits

**Summon Helpers:**
```solidity
// Deploy DAO with pre-configured DAICO sale
daico.summonDAICO(summonConfig, "MyDAO", "DAO", ..., daicoConfig);
daico.summonDAICOWithTap(..., tapConfig);  // includes tap
```

### MolochViewHelper (Batch Reader)

Gas-efficient view contract for dApp frontends:

```solidity
// Fetch full state for multiple DAOs in one call
DAOLens[] memory daos = helper.getDAOsFullState(
    0,      // daoStart
    10,     // daoCount
    0,      // proposalStart
    5,      // proposalCount
    0,      // messageStart
    10,     // messageCount
    tokens  // treasury tokens to check
);

// User portfolio: find all DAOs where user is a member
UserMemberView[] memory myDaos = helper.getUserDAOs(
    user, 0, 100, tokens
);

// DAICO scanner: find all DAOs with active sales
DAICOView[] memory sales = helper.scanDAICOs(0, 100, tribTokens);
```

**Returned Data:**
- `DAOLens` - Full DAO state (meta, config, supplies, members, proposals, messages, treasury)
- `MemberView` - Account balances, seat ID, voting power, delegation splits
- `ProposalView` - Tallies, state, voters, futarchy config
- `SaleView` - Active DAICO sale terms, remaining supply, LP config
- `TapView` - Tap config, claimable amount, treasury balance

## Quick Reference

### Essential Functions

| Function | Purpose | Who Can Call |
|----------|---------|--------------|
| `summon()` | Deploy new DAO | Anyone |
| `castVote()` | Vote on proposal | Share holders |
| `executeByVotes()` | Execute passed proposal | Anyone |
| `ragequit()` | Exit with treasury share | Share/Loot holders |
| `delegate()` | Delegate voting power | Share holders |
| `setSplitDelegation()` | Split delegation | Share holders |
| `buyShares()` | Purchase shares during sale | Anyone (if sale active) |
| `fundFutarchy()` | Add to prediction market | Anyone |
| `cashOutFutarchy()` | Claim futarchy rewards | Receipt holders |
| `chat()` | Post in member chat | Badge holders |

### Governance Functions (DAO Only)

| Function | Purpose |
|----------|---------|
| `setSale()` | Enable built-in token sales |
| `setPermit()` | Issue execution permits |
| `setAllowance()` | Set treasury spending allowance |
| `setTimelockDelay()` | Set execution delay |
| `setQuorumBps()` | Set quorum percentage |
| `setRagequittable()` | Enable/disable ragequit |
| `setTransfersLocked()` | Lock/unlock share/loot transfers |
| `setAutoFutarchy()` | Configure auto-funded futarchy |
| `bumpConfig()` | Invalidate old proposals |

### Tribute Contract Functions

| Function | Purpose | Who Can Call |
|----------|---------|--------------|
| `proposeTribute()` | Lock assets, create offer | Anyone |
| `cancelTribute()` | Withdraw locked tribute | Original proposer |
| `claimTribute()` | Accept and execute swap | DAO (via proposal) |
| `getActiveDaoTributes()` | View pending tributes | Anyone (view) |

### DAICO Contract Functions

| Function | Purpose | Who Can Call |
|----------|---------|--------------|
| `setSale()` | Configure token sale | DAO |
| `setSaleWithTap()` | Sale + tap in one call | DAO |
| `setLPConfig()` | Configure LP auto-add | DAO |
| `setTapOps()` | Update tap beneficiary | DAO |
| `setTapRate()` | Adjust tap rate | DAO |
| `buy()` | Exact-in purchase | Anyone |
| `buyExactOut()` | Exact-out purchase | Anyone |
| `claimTap()` | Release vested funds | Anyone (funds go to ops) |
| `quoteBuy()` | Preview exact-in | Anyone (view) |
| `quotePayExactOut()` | Preview exact-out | Anyone (view) |

## Who Is This For?

**DAO Members** — Vote, delegate (even split across multiple people), buy shares, ragequit, chat with top holders.

**Proposal Creators** — Submit proposals, fund futarchy markets, set timelocks, cancel before votes are cast.

**Developers** — Monitor events, build delegation UIs, create futarchy dashboards, display on-chain SVGs. Use `MolochViewHelper` for efficient batch reads.

## Common Pitfalls & Solutions

### 🚫 Pitfall: Forgetting to sort tokens in ragequit
```solidity
// ❌ Wrong - will revert if not sorted
address[] memory tokens = [dai, weth, usdc];
dao.ragequit(tokens, shares, loot);

// ✅ Correct - tokens sorted by address
address[] memory tokens = [dai, usdc, weth]; // sorted ascending
dao.ragequit(tokens, shares, loot);
```

### 🚫 Pitfall: Voting after proposal expiry
```solidity
// Check proposal state before voting
if (dao.state(proposalId) == ProposalState.Active) {
    dao.castVote(proposalId, 1);
}
```

### 🚫 Pitfall: Wrong basis points in delegation
```solidity
// ❌ Wrong - doesn't sum to 10000
uint32[] memory bps = [6000, 3000]; // 90% total

// ✅ Correct - must sum to exactly 10000
uint32[] memory bps = [6000, 4000]; // 100% total
```

## Development

### Build & Test

```bash
# Install Foundry
curl -L https://foundry.paradigm.xyz | bash
foundryup

# Build
forge build

# Run all tests
forge test

# Run with verbosity
forge test -vvv

# Run specific test file
forge test --match-path test/Moloch.t.sol

# Run specific test
forge test --match-test test_Ragequit

# Gas snapshot
forge snapshot
```

### Test Suite

| File | Coverage |
|------|----------|
| `Moloch.t.sol` | Core governance: voting, delegation, execution, ragequit, futarchy, badges |
| `DAICO.t.sol` | Token sales, tap mechanism, LP config, summon helpers |
| `Tribute.t.sol` | OTC escrow: propose, cancel, claim tributes |
| `MolochViewHelper.t.sol` | Batch read functions for dApps |
| `ContractURI.t.sol` | On-chain metadata and DUNA covenant |
| `URIVisualization.t.sol` | SVG rendering for cards |
| `Bytecodesize.t.sol` | Contract size limits |

**Key test scenarios:**
- Proposal lifecycle (open → vote → queue → execute)
- Split delegation with multiple delegates
- Futarchy funding and payout
- Ragequit with multiple tokens
- Badge auto-updates on balance changes
- DAICO tap claims and rate changes
- Tribute propose/cancel/claim flows

### Deploy

```bash
forge script script/Deploy.s.sol --rpc-url $RPC_URL --broadcast
```

## Security Model

| Protection | Mechanism |
|------------|-----------|
| Flash loan attacks | Snapshot at block N-1 |
| Reentrancy | Transient storage guards (EIP-1153) |
| Majority tyranny | Ragequit — minorities can exit with their share |
| Malicious proposals | Timelocks give time to ragequit; `bumpConfig()` invalidates all pending |
| Token reentrancy | Ragequit requires sorted token arrays |

## Audits

Moloch.sol has been scanned by twenty-four independent audit tools. Reports with per-finding review notes are in [`/audit`](./audit/). Formal verification specs and harnesses are in [`/certora`](./certora/).

| Auditor | Type | Findings | Report |
|---------|------|----------|--------|
| [Zellic V12](./audit/zellic.md) | [Vulnerability scan](https://v12.zellic.io/) | 24 (all false positive, design tradeoff, or low-confidence) | No production blockers |
| [Plainshift AI](./audit/plainshift.md) | [Vulnerability scan](https://hackmd.io/@ileakalpha/SJn2083tWg) | 3 (2 High, 1 Medium — all design tradeoffs) | No production blockers |
| [Octane](./audit/octane.md) | [Vulnerability scan](https://app.octane.security/) | 26 vulns + 23 warnings | 4 valid observations, no production blockers |
| [Pashov Skills](./audit/pashov.md) | [Vulnerability scan (deep)](https://github.com/pashov/skills) | 13 (deduplicated from 5 agents) | 2 novel findings, 1 false positive, no production blockers |
| [Trail of Bits Skills](./audit/trailofbits.md) | [Sharp edges + maturity](https://github.com/trailofbits/skills) | 20 footguns + 9-category scorecard (2.67/4.0) | Validates config guidance, no production blockers |
| [Cyfrin Solskill](./audit/cyfrin.md) | [Development standards](https://github.com/Cyfrin/solskill) | 32 standards evaluated (21 compliant, 5 partial, 3 non-compliant by design, 3 N/A) | Strong adherence, 2 trivial actionable items |
| [SCV Scan](./audit/scvscan.md) | [Vulnerability scan (36 classes)](https://github.com/kadenzipfel/scv-scan) | 3 confirmed (2 Low, 1 Informational) from 36 classes | All duplicates of prior findings, no production blockers |
| [QuillShield](./audit/quillshield.md) | [Multi-layer audit (8 plugins)](https://github.com/quillai-network/qs_skills) | 8 findings (3 Medium, 3 Low, 2 Info) | All duplicates or design tradeoffs, no production blockers |
| [Archethect SC-Auditor](./audit/archethect.md) | [Map-Hunt-Attack + MCP tools (Slither, Aderyn, Solodit, Cyfrin checklist)](https://github.com/Archethect/sc-auditor) | 0 novel (8 spots falsified, 397 Slither + 21 Aderyn findings triaged, 1 KF#8 duplicate via Solodit) | V2 re-run with full MCP integration validates V1 manual results, no production blockers |
| [HackenProof Triage](./audit/hackenproof.md) | [Bug bounty triage (severity re-classification)](https://github.com/hackenproof-public/skills) | 14 triaged: 0 Critical, 0 High, 2 Medium, 5 Low, 5 OOS | No Critical/High under bounty standards |
| [Forefy](./audit/forefy.md) | [Multi-expert audit (10 fv-sol categories + governance context)](https://github.com/forefy/.context) | 8 Low (1 valid, 2 questionable, 5 dismissed) | All duplicates, no novel findings, no production blockers |
| [Claudit (Solodit)](./audit/claudit.md) | [Prior art cross-reference (20k+ real findings)](https://github.com/marchev/claudit) | 12 patterns searched, 0 novel | Validates defenses against Nouns/Olympus/PartyDAO exploits |
| [Auditmos](./audit/auditmos.md) | [Multi-skill checklist (6 of 14 skills applied)](https://github.com/auditmos/skills) | 2 Low, 1 Informational | All duplicates, no production blockers |
| [EVM MCP Tools](./audit/evmtools.md) | [Regex heuristic scan (5 checks)](https://github.com/0xGval/evm-mcp-tools) | 0 confirmed (1 informational) | Tool too basic for governance contracts, no production blockers |
| [Claude (Opus 4.6)](./audit/claude.md) | [3-round AI audit (systematic → economic → triager)](./SECURITY.md) | 1 Medium, 1 Low, 1 Informational | 1 novel observation (post-queue voting — by design), no production blockers |
| [Gemini (Gemini 3)](./audit/gemini.md) | [3-round AI audit (2 passes)](https://gemini.google.com/) | Pass 1: 1 Low (false positive), 1 Info; Pass 2: 5 items (all known/design) | No novel findings across either pass, no production blockers |
| [ChatGPT (GPT 5.4)](./audit/chatgpt.md) | [3-round AI audit (systematic → economic → triager)](https://chat.openai.com/) | 1 Medium (novel), 1 Low (duplicate) | 1 novel finding (public futarchy freeze), no production blockers |
| [DeepSeek (V3.2 Speciale)](./audit/deepseek.md) | [3-round AI audit (systematic → economic → triager)](https://chat.deepseek.com/) | 1 Low (duplicate) | Front-run cancel is KF#11, no production blockers |
| [ZeroSkills Slot Sleuth](./audit/zeroskills.md) | [EVM storage-safety scan (5-phase)](https://github.com/zerocoolailabs/ZeroSkills) | 0 | No storage-safety vulnerabilities; no manual slot arithmetic, no upgradeable proxies, no lost writes |
| [Qwen](./audit/qwen.md) | [3-round AI audit (Qwen3.5-Plus)](https://chat.qwen.ai/) | 1 Medium, 1 Low, 1 Info (all duplicates) | No novel findings, competent methodology compliance |
| [ChatGPT Pro (GPT 5.4 Pro)](./audit/chatgptpro.md) | [3-round AI audit (systematic → economic → triager)](https://chat.openai.com/) | 1 Medium (novel), 1 Low, 1 Info (2 duplicates) | 1 novel finding (dead futarchy pools on executed IDs), no production blockers |
| [Certora FV](./audit/certora.md) | [Formal verification (142 properties, 7 contracts)](./certora/) | 1 Low, 2 Informational (all acknowledged, by design) | 126 invariants verified; L-01 tap forfeiture is intentional Moloch exit-rights design |
| [Grimoire](./audit/grimoire.md) | [Agentic audit (4 sigils + 3 familiars)](https://github.com/JoranHonig/grimoire) | 10 confirmed (1 High, 4 Medium, 5 Low, 2 Info — all duplicates) | 0 novel; adversarial triage dismissed 3 false positives, reentrancy surface fully clean |
| [Cantina Apex](./audit/cantina.md) | [Quick scan (smart contracts + frontend)](https://cantina.xyz/) | 4 High, 20 Medium (5 novel SC findings + ~18 novel frontend findings) | First to cover frontend and peripherals; most novel findings of any single audit; no production blockers |
| [Solarizer](./audit/solarizer.md) | [AI multi-phase security engine (static + semantic + cross-contract)](https://solarizer.io/) | 1 High, 3 Medium, 15 Low, 5 Info, 5 Gas (0 novel) | All duplicates, false positives, or design observations; "D" security grade is misleading (HIGH-1 is intentional post-queue voting); 3 false positives (multicall access control, checkpoint asymmetry, proposerOf hijack); no production blockers |

**No production blockers were identified across any audit.** Ten novel smart contract findings were surfaced across twenty-five scans (5 from prior audits + 5 from Cantina covering peripheral contracts and namespace issues). Cantina additionally identified ~18 novel frontend findings (XSS and logic bugs) — the first audit to cover the dapp. Configuration-dependent concerns are enforced by [`SafeSummoner`](./src/peripheral/SafeSummoner.sol); code-level issues are candidates for v2 hardening.

**Novel smart contract findings (10):**
1. Vote receipt transferability breaks `cancelVote` (Pashov — Low, design tradeoff)
2. Zero-winner futarchy pool lockup (Pashov — Low, funds remain in DAO treasury)
3. Post-queue voting can flip timelocked proposals (Claude Opus 4.6/SECURITY.md — by design, timelock is a last-objection window)
4. Public `fundFutarchy` + zero-quorum `state()` enables permanent proposal freeze via premature NO-resolution (ChatGPT (GPT 5.4) — Medium, configuration-dependent, enforced by SafeSummoner)
5. `fundFutarchy` accepts executed/cancelled proposal IDs, creating permanently stuck futarchy pools (ChatGPT Pro (GPT 5.4 Pro) — Medium, missing `executed[id]` check)
6. `bumpConfig` emergency brake bypass — lifecycle functions accept raw IDs without config validation (Cantina — Medium, extends KF#10)
7. Tribute bait-and-switch — escrow settlement terms not bound to claim key (Cantina — Medium, Tribute.sol)
8. Permit IDs enter proposal/futarchy lifecycle — missing `isPermitReceipt` guards enable futarchy pool drain (Cantina — Medium, extends KF#10)
9. DAICO LP drift cap uses wrong variable (`tribForLP` vs `totalTrib`) — shifts tokens from LP to buyer when pool spot > OTC. Buyer pays full price; drift is self-correcting via arb; UIs hide pool until sale completion. Impact is reduced LP depth, not theft (Cantina — Low, DAICO.sol, V2 hardening candidate)
10. Counterfactual Tribute theft via summon frontrun — `initCalls` excluded from salt + Tribute accepts undeployed DAOs (Cantina — Low-Medium, extends KF#9)

**Tool ranking by signal quality:**
- **Cantina Apex** produced the most novel smart contract findings (5) of any single audit, plus ~18 novel frontend findings — the first tool to systematically cover the dapp and peripheral contracts (Tribute, DAICO). The bumpConfig bypass (MAJEUR-15), Tribute bait-and-switch (MAJEUR-10), permit futarchy drain (MAJEUR-21), and DAICO LP math bug (MAJEUR-7) are all code-verified. The frontend XSS findings share a single root cause (`innerHTML` without escaping) but are individually valid. Signal-to-noise: 5 novel SC findings from 24 total (21%).
- **ChatGPT (GPT 5.4)** produced the single highest-impact finding (KF#17, Medium) with the best signal-to-noise ratio (1 novel from 2 total findings, 50%). Its architecture assessment — identifying the boundary between live governance state and prediction-market settlement — is the clearest articulation of the futarchy design tension.
- **ChatGPT Pro (GPT 5.4 Pro)** surfaced the 5th novel finding (KF#18, Medium) — `fundFutarchy` missing `executed[id]` check creates permanently stuck pools on dead proposals. Signal-to-noise: 1 novel from 3 findings (33%). The reentrancy inventory in Category 1 is the most thorough across all 24 audits. LOW-2 (tombstoning) is KF#11 and INFORMATIONAL-3 (auto-futarchy overcommit) was found by 6 prior audits.
- **Pashov Skills** surfaced 2 novel findings via 5 parallel agents with adversarial reasoning. Higher noise (12 findings, 17% novel rate) but broader coverage.
- **Claude (Opus 4.6)** identified a subtle design observation (post-queue voting) that no other tool found, plus the `spendPermit` missing `executed[id]` check (a sharper angle on KF#10, later catalogued as KF#16).
- **Trail of Bits** and **Cyfrin** provided unique non-vulnerability value: maturity scoring (2.67/4.0) and standards compliance (21/32 compliant), respectively.
- **Claudit** validated defenses against real-world exploits (Nouns, Olympus, PartyDAO) — unique cross-reference approach.
- **Octane** produced the most raw findings (49) with 4 valid observations. While none were first-ever novel, Octane provided the most detailed early articulation of the auto-futarchy minted-reward farming vector (vuln #4) — later confirmed by Pashov, Forefy, QuillShield, ChatGPT, ChatGPT Pro, and Qwen. High volume with broad surface coverage — useful for exhaustive first-pass scanning.
- **Gemini (Gemini 3)** and **DeepSeek (V3.2 Speciale)** used the same SECURITY.md prompt as ChatGPT (GPT 5.4) and ChatGPT Pro (GPT 5.4 Pro) but produced zero novel findings, demonstrating that prompt quality alone is insufficient — model capability is the dominant factor.
- **Archethect** ran the full Map-Hunt-Attack methodology with MCP tool integration (Slither v0.11.5, Aderyn v0.1.9, Solodit search, Cyfrin checklist). Triaged 397 Slither + 21 Aderyn findings (0 true positives), ran 11 Solodit cross-reference queries, and evaluated 8 suspicious spots. All falsified. The Solodit cross-reference confirmed KF#8 (fee-on-transfer) as the only surviving finding — a duplicate. Zero novel findings, zero false positives escaped the devil's advocate protocol.
- **ZeroSkills Slot Sleuth** ran a 5-phase EVM storage-safety analysis (lost writes, attacker-influenced slots, upgrade collisions, storage semantics). Clean pass — Moloch.sol avoids the vulnerability patterns this detector targets (no assembly `SSTORE`, no manual slot arithmetic, no upgradeable proxies). Useful for confirming architectural hygiene.
- **Forefy**, **QuillShield**, **SCV Scan**, and **Auditmos** each independently confirmed subsets of the known findings, adding cross-validation confidence without novel discoveries. **EVM MCP Tools** was too basic for governance contracts (regex heuristics only).
- **Solarizer** produced the highest volume of findings (29) but zero novel discoveries. Notable for 3 clear false positives: LOW-4 (claims `multicall` bypasses `onlyDAO` — incorrect, `delegatecall` to `address(this)` preserves caller's `msg.sender`), LOW-9 (claims burn/mint checkpoint asymmetry — code is actually symmetric), and MED-1 (claims `proposerOf` hijack enables cancel DOS — blocked by auto-futarchy and re-submittable with different nonce). The "D" security grade and "HIGH" risk rating are driven by HIGH-1, which is the documented intentional post-queue voting design (KF#15). Signal-to-noise: 0 novel from 29 total (0%).

- **Qwen (Qwen3.5-Plus)** used the same SECURITY.md prompt as ChatGPT, Gemini 3, and DeepSeek V3.2 Speciale. All 3 findings are duplicates (KF#5, auto-futarchy overcommit, KF#1), with an inflated self-assessment claiming 2 novel. Competent category sweep and methodology compliance, but zero novel findings — similar depth to DeepSeek V3.2 Speciale and Gemini 3.

- **Grimoire** uses a two-pass agentic workflow — 4 parallel Sigil agents (hypothesis-driven hunters) followed by 3 parallel Familiar agents (adversarial verifiers that try to disprove each finding). Similar to Pashov Skills' multi-agent approach but with an explicit adversarial triage pass. Covered 10 of 18 known findings (56%) with zero false positives after triage. The reentrancy surface was thoroughly cleared. The Familiar pass correctly dismissed 3 false positives and adjusted severity on 2 findings. No novel findings, but the highest false-positive rejection rate of any tool.

- **Certora FV** is the only formal verification engagement. 142 properties across 7 contracts provide mathematical proofs for critical invariants (sum-of-balances, state machine monotonicity, write-once fields, access control, split delegation constraints, ragequit payout bounds). The L-01 tap forfeiture finding is confirmed via intentional violation (D-L1a) and reachability witness (D-L1b) — a novel angle on ragequit interaction with DAICO, but acknowledged as intentional Moloch exit-rights design. The two informational findings (unbounded Tribute arrays, `mulDiv` phantom overflow) are both known tradeoffs.

Cross-referencing across all twenty-four scans — ten independent novel smart contract findings (plus ~18 novel frontend findings from Cantina), twenty-three catalogued known findings (KF#1–23), consistent duplicate confirmation across tools, and 142 formally verified invariants — increases confidence that the known findings represent the full smart contract attack surface. Cantina's coverage of the frontend and peripheral contracts (Tribute, DAICO) opened a new surface area not previously audited.

### SafeSummoner

[`SafeSummoner.sol`](./src/peripheral/SafeSummoner.sol) is a wrapper around the deployed [Summoner](https://contractscan.xyz/contract/0x0000000000330B8df9E3bc5E553074DA58eE9138) that enforces audit-derived configuration guardrails at deployment time. Instead of hand-encoding raw `initCalls` calldata, deployers fill in a typed `SafeConfig` struct and the contract validates + builds the calls automatically.

| Guard | Finding | What it prevents |
|-------|---------|------------------|
| `proposalThreshold > 0` required | KF#11 | Front-run cancel, proposal spam, minted futarchy farming |
| `proposalTTL > 0` required | Config | Proposals lingering indefinitely |
| `proposalTTL > timelockDelay` | Config | Proposals expiring while queued |
| `quorumBps ≤ 10000` | KF#12 | `init()` skips this range check |
| Non-zero quorum if futarchy enabled | KF#17 | Premature NO-resolution proposal freeze |
| Block minting sale + dynamic-only quorum | KF#2 | Supply manipulation via buy → ragequit |

DAOs deployed through `SafeSummoner.safeSummon()` cannot hit the configuration footguns identified across the twenty-four audits. The `previewCalls()` function lets frontends inspect exactly which `initCalls` will execute, and `predictDAO()` returns the deterministic address before deployment. An `extraCalls` escape hatch preserves full flexibility for advanced setups (DAICO, custom allowances, etc.).

### Configuration Guidance for Deployers

Several audit findings highlight configuration combinations that require care. DAOs deploying through [`SafeSummoner`](./src/peripheral/SafeSummoner.sol) get these enforced automatically. For direct Summoner users:

- **Set `proposalThreshold > 0`** — A non-zero threshold gates proposal creation behind real stake, preventing permissionless griefing (front-run cancel, mass proposal opening for minted futarchy rewards).
- **Be thoughtful with minted futarchy rewards** — When `autoFutarchyParam` is set with minted reward tokens (`rewardToken = 0` → minted Loot), the per-proposal `autoFutarchyCap` limits individual proposals but not aggregate exposure across many proposals. Prefer non-minted reward tokens (ETH, or shares/loot held by the DAO) which have natural balance caps.
- **Set a non-zero quorum if futarchy is enabled** — When both `quorumAbsolute` and `quorumBps` are zero, `state()` returns `Defeated` immediately with zero votes. Since `fundFutarchy` is public, an attacker can attach a 1-wei futarchy pool and call `resolveFutarchyNo` to permanently freeze any proposal before voting begins. Any non-zero quorum prevents this because `state()` returns `Active` until quorum is met.
- **Avoid futarchy in concentrated DAOs** — Futarchy is designed to energize broad participation. In DAOs where a small coalition can reach quorum quickly, early NO voters can resolve futarchy and freeze voting before a FOR comeback. Futarchy adds little value in these cases and should not be enabled. Additionally, a majority NO coalition can repeatedly defeat proposals and collect auto-funded futarchy pools — this is by design (NO voters are rewarded for correct governance predictions), but in concentrated DAOs it becomes extractive. The `autoFutarchyCap` bounds per-proposal exposure, and `proposalThreshold > 0` limits who can trigger the earmark cycle.
- **Ragequit is the nuclear exit** — Ragequit gives pro-rata of all DAO-held assets by design, including ETH earmarked for futarchy pools. Futarchy pools are incentive mechanisms subordinate to governance, not restrictive escrows. This is intentional — if excluded from ragequit, a hostile majority could shield treasury via futarchy funding.
- **Sale cap is a soft guardrail** — The `cap` in `setSale` correctly blocks buys exceeding the remaining cap and decrements on each purchase, but uses `0` as the sentinel for both "unlimited" and "exhausted." After exact sell-out (`shareAmount == cap`), the cap resets to 0 and the sale becomes unlimited. This only matters for minting sales where the cap is the sole supply constraint — for non-minting sales, the DAO's held share balance is the real hard cap regardless. Buyers always pay `pricePerShare` so there are no free tokens. The DAO can deactivate the sale at any time via `setSale(..., active: false)`, and `SaleUpdated` events enable off-chain monitoring. V2 hardening candidate: use `type(uint256).max` as the "unlimited" sentinel instead of `0`.
- **Dynamic quorum + minting sale + ragequit** — When all three are enabled, an attacker can inflate supply via `buyShares`, then ragequit after the snapshot, manipulating the quorum denominator. This is economically constrained but worth noting. Consider using absolute quorum (`quorumAbsolute`) instead of percentage-based (`quorumBps`) if minting sales are active.
- **Post-queue voting is intentional** — When `timelockDelay > 0`, voting remains open during the timelock period. This is by design: the timelock serves as a last-objection window where holders who didn't vote during the Active period can register late opposition. A late AGAINST vote with sufficient weight can flip a Succeeded proposal to Defeated after the delay elapses. This is asymmetric — `cancelVote` requires Active state, so existing voters cannot undo votes post-queue. DAOs that prefer Compound-style frozen timelocks should note this behavior.

### v2 Hardening Candidates

Identified through audit review for future contract versions:

- Add `executed[id]` check to `fundFutarchy` — prevents dead futarchy pools on cancelled/executed proposals (KF#18)
- Global aggregate cap on auto-futarchy earmarks (or restrict minted rewards to require `proposalThreshold > 0`)
- Decouple futarchy resolution from voting freeze, or require `Expired` only (not `Defeated`) in `resolveFutarchyNo` — prevents premature NO-resolution on live proposals with zero quorum
- Snapshot total supply at proposal creation for quorum calculation (or add cooldown between share purchase and ragequit)
- Bind CREATE2 salt to `msg.sender` in Summoner
- Snapshot loot supply for futarchy earmark basis
- Namespace separation for permit and proposal IDs
- Optional `freezeOnQueue` flag to disable post-queue voting for DAOs that prefer Compound-style frozen timelocks
- Store originating `config` on proposal open; reject lifecycle actions on stale-config proposals (Cantina MAJEUR-15)
- Add `if (isPermitReceipt[id]) revert` guards to `openProposal`, `castVote`, `fundFutarchy`, `resolveFutarchyNo` (Cantina MAJEUR-21)
- Bind `claimTribute` to expected settlement terms via nonce/hash (Cantina MAJEUR-10)
- Fix DAICO drift cap: replace `tribForLP` with total tribute in `_initLP` and `_quoteLPUsed` (Cantina MAJEUR-7)
- Include `initCalls` in Summoner `summon` salt (Cantina MAJEUR-17)
- Systematic `innerHTML` → `textContent`/DOM API pass in dapp for all untrusted data sinks (Cantina XSS class)

## Complete Workflow Example

### Full DAO Lifecycle
```solidity
// 1. Deploy DAO
Summoner summoner = new Summoner();
Moloch dao = summoner.summon("MyDAO", "DAO", "", 5000, true, address(0), 
    bytes32(0), [alice, bob], [100e18, 100e18], new Call[](0));

// 2. Alice delegates 70% to expert1, 30% to expert2
Shares shares = dao.shares();
shares.setSplitDelegation([expert1, expert2], [7000, 3000]);

// 3. Create and vote on treasury proposal
bytes memory data = abi.encodeWithSignature(
    "transfer(address,uint256)", charlie, 10 ether
);
uint256 id = dao.proposalId(0, weth, 0, data, bytes32("prop1"));
dao.castVote(id, 1); // Vote FOR

// 4. Wait for voting period...

// 5. Execute if passed
if (dao.state(id) == ProposalState.Succeeded) {
    dao.executeByVotes(0, weth, 0, data, bytes32("prop1"));
}

// 6. Charlie can ragequit if unhappy
address[] memory tokens = getSortedTreasuryTokens();
dao.ragequit(tokens, myShares, 0);
```

## Gas Optimization

| Technique | Savings | Details |
|-----------|---------|---------|
| Clone pattern | ~80% deployment | Minimal proxy clones for Shares, Loot, Badges |
| Transient storage | ~5k/call | EIP-1153 for reentrancy guards |
| Badge bitmap | ~20k/update | 256 holders in single storage slot |
| Packed structs | ~20k/write | Tallies fit in one slot (3 × uint96) |

## FAQ

### Q: Can I change my vote after voting?
**A:** Yes! Use `cancelVote(proposalId)` before the proposal is executed. You'll get your vote receipt back and can vote again.

### Q: What happens to badges when someone's balance changes?
**A:** Badges automatically update. If you fall out of top 256, you lose the badge. If you enter top 256, you get one instantly.

### Q: Can I delegate to myself?
**A:** Yes, and it's the default. Your votes stay with you unless you explicitly delegate.

### Q: What's the difference between `call` and `delegatecall` in proposals?
**A:** 
- `call` (op=0): Execute from DAO's context (normal)
- `delegatecall` (op=1): Execute in DAO's storage (upgrades/modules)

### Q: Can I partially ragequit?
**A:** Yes! Specify how many shares/loot to burn. You don't have to exit completely.

### Q: How are proposal IDs generated?
**A:** Deterministically from: `keccak256(dao, op, to, value, data, nonce, config)`. Anyone can compute it.

### Q: What prevents vote buying?
**A:** Snapshots at block N-1. You can't buy tokens after seeing a proposal and vote.

### Q: Can the DAO upgrade itself?
**A:** Yes, through proposals with `delegatecall` or by deploying new contracts.

### Q: What's the `config` parameter?
**A:** A version number that's part of every proposal ID. The DAO can increment it via `bumpConfig()` to invalidate all old/pending proposal IDs and permits. This is a governance "emergency brake" if malicious proposals were created.

### Q: Can I build a front-end for this?
**A:** Yes! All metadata is on-chain (including SVGs). Use MolochViewHelper for batch reads.

### Q: What's the difference between built-in sales and DAICO?
**A:** Built-in `setSale()` is simpler — direct minting at a fixed price. DAICO adds tap mechanisms (controlled fund release), optional LP initialization, and operates as an external escrow contract for investor protection.

### Q: How does the tap mechanism protect investors?
**A:** The tap limits how fast the ops team can withdraw raised funds. DAO members can vote to lower the rate (or freeze it) if they lose confidence. If members ragequit, the tap auto-adjusts to the reduced treasury.

### Q: Can I offer assets in exchange for DAO membership?
**A:** Yes, use the Tribute contract. Lock your assets, propose the trade to the DAO, and if they vote to accept, the swap executes atomically.

## Disclaimer

*These contracts have been reviewed by twenty-four auditors (see [Audits](#audits)) but have not undergone a formal manual audit. No production blockers were identified, but use at your own risk. No warranties or guarantees provided.*

## License

MIT
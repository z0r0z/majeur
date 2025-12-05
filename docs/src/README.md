# Moloch (Majeur) DAO Framework

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Solidity](https://img.shields.io/badge/solidity-%5E0.8.30-black)](https://docs.soliditylang.org/en/v0.8.30/)
[![Foundry](https://img.shields.io/badge/Built%20with-Foundry-000000.svg)](https://getfoundry.sh/)

[![IPFS Image](https://content.wrappr.wtf/ipfs/bafybeih2mxprvjigedatwn5tdgjx6mcpktfd75t736kkrpjfepcll2n3o4)](https://content.wrappr.wtf/ipfs/bafybeih2mxprvjigedatwn5tdgjx6mcpktfd75t736kkrpjfepcll2n3o4)

**A minimal yet feature-rich DAO governance framework** — Wyoming DUNA-protected, futarchy-enabled membership organizations with weighted delegation and soulbound top-256 badges.

## Deployments

Summoner: [`0x0000000000330B8df9E3bc5E553074DA58eE9138`](https://contractscan.xyz/contract/0x0000000000330B8df9E3bc5E553074DA58eE9138)

Renderer: [`0x000000000011C799980827F52d3137b4abD6E654`](https://contractscan.xyz/contract/0x000000000011C799980827F52d3137b4abD6E654)

MolochViewHelper: [`0x00000000006631040967E58e3430e4B77921a2db`](https://contractscan.xyz/contract/0x00000000006631040967E58e3430e4B77921a2db)

DAICO: [`0x000000000033e92DB97B4B3beCD2c255126C60aC`](https://contractscan.xyz/contract/0x000000000033e92DB97B4B3beCD2c255126C60aC)

## Dapps

> [majeurdao.eth](https://majeurdao.eth.limo/)

> [daicowtf.eth](https://daicowtf.eth.limo/)

## TL;DR

Moloch (Majeur) is a DAO framework where:
- **Members vote** with shares (tokens) on proposals that can execute any on-chain action
- **Delegation can be split** between multiple people (e.g., 60% voting power to Alice, 40% to Bob)
- **Prediction markets** can be attached to proposals, rewarding voters on the winning side (futarchy)
- **Members can exit** anytime with their proportional share of the treasury (ragequit)
- **Top 256 shareholders** get automatic badges that unlock exclusive features like member chat
- **Everything is on-chain** including visual metadata (on-chain SVG rendering)

## Overview

Moloch (Majeur) is a comprehensive DAO framework that manages multiple token systems:
- **ERC-20 Shares** (separate contract): Voting power tokens with delegation and split delegation support
- **ERC-20 Loot** (separate contract): Non-voting economic tokens for profit sharing
- **ERC-6909 Receipts** (within Moloch): Multi-token vote receipts that become redeemable in futarchy markets
- **ERC-721 Badges** (separate contract): Soulbound (non-transferable) badges automatically issued to top 256 shareholders
- **Advanced Governance**: Snapshot voting, timelocks, pre-authorized permits, token sales, and ragequit functionality

## Architecture

![Majeur Architecture](./assets/architecture.svg)

## Core Concepts (Simplified)

### 🗳️ What are Shares vs Loot?
- **Shares**: Your voting power AND economic rights (like stock with voting)
- **Loot**: Just economic rights, no voting (like non-voting preferred stock)
- **Why both?**: Some members may want profits without governance responsibility

### 🎯 What is Futarchy?
Think of it as "prediction markets for governance":
1. Anyone can fund a reward pool for a proposal (using ETH, shares, or loot)
2. When you vote (YES, NO, or ABSTAIN), you get a receipt token
3. After the proposal resolves:
   - If it **passes** → YES voters share the reward pool proportionally
   - If it **fails** → NO voters share the reward pool proportionally
   - ABSTAIN voters never claim rewards
4. You burn your receipt tokens to claim your share
5. This incentivizes voting for outcomes you genuinely believe will happen

### 🏃 What is Ragequit?
Your "exit door" from the DAO:
- Burn your shares and/or loot → Get your proportional share of the treasury
- Example: You own 10% of shares → Burn them to claim 10% of each treasury token
- **Important**: You can only claim external tokens (like ETH, USDC, etc.)
- You **cannot** ragequit internal DAO tokens (shares, loot, or badges themselves)

### 👥 What is Split Delegation?
Instead of "all-or-nothing" delegation:
- Traditional: 100% of your votes → Alice
- Split: 60% → Alice, 40% → Bob
- Useful for diversifying representation

### 🏅 What are Badges?
- Automatic NFTs for top 256 shareholders
- Soulbound (non-transferable)
- Unlocks features like member chat
- Updates automatically as balances change

## Core Concepts (Technical)

### 1. Token System

The Majeur framework uses a multi-token architecture:

```solidity
// Token types and their roles:
shares   // Voting + economic rights (delegatable)
loot     // Economic rights only (non-voting)  
badges   // Top 256 holder badges (soulbound NFTs)
receipts // Vote receipts (ERC-6909 for futarchy)
```

### 2. Proposal Lifecycle

![Proposal Lifecycle](./assets/proposal-lifecycle.svg)

**How Proposals Pass:**
A proposal succeeds when ALL of these conditions are met:
- Quorum is reached (either absolute count or percentage of supply, whichever is configured)
- `FOR` votes **exceed** `AGAINST` votes (ties fail)
- Minimum YES votes threshold is met (if configured)
- Proposal hasn't expired (TTL not exceeded)

If a proposal succeeds and timelocks are enabled, it moves to `Queued` state before becoming executable.

### 3. Futarchy Markets

Proposals can have optional prediction markets where YES/NO voters compete:
- Anyone can fund a reward pool for any active proposal
- Reward pool can be in ETH, shares, loot, or other tokens
- When the proposal executes (passes), YES voters win
- When the proposal is defeated/expired, NO voters win
- Winners split the pool proportionally based on their vote weight
- Voters burn their vote receipt tokens to claim rewards

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

## Key Features

### Wyoming DUNA Compliance

The framework includes built-in support for Wyoming's **Decentralized Unincorporated Nonprofit Association (DUNA)** structure, providing legal recognition for DAOs.

#### What is a DUNA?
A DUNA (Wyoming Statute 17-32-101) is a legal entity that:
- Exists purely through smart contracts—no paperwork or incorporation process
- Grants **limited liability** to members (like an LLC)
- Operates as a nonprofit (but can still hold treasury and issue tokens)
- Is recognized by Wyoming law as a legal person

#### Why This Matters for Your DAO:
✅ **Legal protection**: Members aren't personally liable for DAO actions
✅ **Real-world contracts**: Your DAO can legally sign agreements and own property
✅ **Treasury ownership**: The DAO legally owns its funds, not individual members
✅ **On-chain governance**: All votes and actions are permanent records
✅ **Exit rights**: Ragequit provides a legal self-help remedy for members
✅ **No admin burden**: No annual filings, board meetings, or traditional corporate formalities

#### How Majeur Supports DUNA:
Every DAO deployed through Majeur includes:
- An on-chain **legal covenant** displayed in the DAO's metadata (see DAO Contract Card above)
- **Member registry** through the top-256 badge system
- **Permanent governance records** (all votes stored on-chain forever)
- **Exit mechanism** via ragequit
- **Full transparency** of all DAO actions on the blockchain

### Advanced Governance
- **Snapshot voting** at block N-1 prevents vote buying after proposals open
- **Flexible quorum**: Can set absolute thresholds (e.g., 1000 votes minimum) or percentage-based (e.g., 20% of supply)
- **Timelocks** for high-impact decisions—configurable delay between passing and execution
- **Proposal expiry** (TTL) prevents old proposals from being executed unexpectedly
- **Vote cancellation** allows voters to change their mind before execution
- **Proposal cancellation** by proposer if no votes have been cast yet

### Economic Features
- **Ragequit** - Exit with proportional treasury share
- **Token sales** - Fundraising with price discovery
- **Futarchy markets** - Prediction markets on proposals
- **Split economics** - Shares (voting) vs Loot (non-voting)

### Technical Innovation
- **Weighted delegation** - Split voting power across multiple delegates
- **ERC-6909 receipts** - Efficient multi-token for vote tracking
- **Clones pattern** - Gas-efficient deployment
- **Transient storage** - Optimized reentrancy guards
- **On-chain SVG** - Fully decentralized metadata

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
| `setSale()` | Enable token sales |
| `setPermit()` | Issue execution permits |
| `setTimelockDelay()` | Set execution delay |
| `setQuorumBps()` | Set quorum percentage |
| `setRagequittable()` | Enable/disable ragequit |
| `bumpConfig()` | Invalidate old proposals |

## User Stories

### As a DAO Member
- **Vote on proposals** with your shares (voting power)
- **Delegate voting power** to trusted members (even split between multiple delegates)
- **Buy more shares** during token sales
- **Ragequit** to exit with your proportional share of treasury
- **Chat** with other top holders (if you have a badge)

### As a Proposal Creator
- **Submit proposals** for DAO actions (treasury, governance, operations)
- **Fund futarchy markets** to incentivize participation
- **Set timelocks** for important decisions
- **Cancel proposals** you created (before votes cast)

### As an App Developer
- **Monitor governance** via events
- **Build delegation UIs** for split voting interfaces
- **Create futarchy dashboards** showing market predictions
- **Integrate chat features** for badge holders
- **Display on-chain SVGs** for proposals, receipts, and badges

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

## Deployment

```bash
# Install Foundry
curl -L https://foundry.paradigm.xyz | bash
source ~/.bashrc
foundryup

# Build
forge build

# Test
forge test

# Deploy
forge script script/Deploy.s.sol --rpc-url $RPC_URL --broadcast
```

## Security Considerations

- **Snapshot voting** (block N-1): Voting power determined at the block before proposal opens, preventing vote buying/flash loans
- **Reentrancy protection**: Uses transient storage (EIP-1153) for gas-efficient reentrancy guards on all financial operations
- **Timelock delays**: Configurable delay between proposal success and execution gives members time to ragequit if they disagree
- **Ragequit protection**: Members can always exit with their treasury share, preventing 51% attacks on funds
- **Config versioning**: DAO can invalidate all pending proposals via `bumpConfig()` in emergencies
- **Sorted token arrays**: Ragequit requires tokens in ascending address order to prevent reentrancy via malicious token contracts

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

The framework uses several optimization techniques:

### Clone Pattern
- **Deployment cost**: ~500k gas (vs ~3M for individual contracts)
- **How**: Minimal proxy clones for Shares, Loot, Badges
- **Savings**: ~80% on deployment

### Transient Storage (EIP-1153)
- **Reentrancy guards**: Uses `TSTORE`/`TLOAD`
- **Savings**: ~5k gas per guarded function

### Bitmap for Badges
- **Storage**: 256 holders in single storage slot
- **Operations**: O(1) updates using bit manipulation
- **Savings**: ~20k gas per badge update

### Packed Structs
```solidity
struct Tally {
    uint96 forVotes;      // Packed into
    uint96 againstVotes;  // single
    uint96 abstainVotes;  // storage slot
}
```

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
**A:** Yes! All metadata is on-chain (including SVGs). No external dependencies needed.

## Disclaimer

*These contracts are unaudited. Use at your own risk. No warranties or guarantees provided.*

## License

MIT
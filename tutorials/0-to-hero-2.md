# Tutorial: List Unvoted Proposals & Claim Futarchy Rewards

In this tutorial, you'll write a script that:
1. Connects to the Sepolia network
2. Fetches all proposals from a DAO
3. Filters to show only ACTIVE proposals that you haven't voted on
4. Checks if you have any claimable futarchy rewards
5. Claims those rewards if available

## What You'll Learn

- How ethers.js connects to Ethereum
- The difference between Providers, Signers, and Wallets
- How to read contract state using ABIs
- How the simplified futarchy system that's currently implemented in Majeur works

---

## Step 1: Project Setup

Create a new file `check-proposals.js`:

```javascript
// check-proposals.js
import 'dotenv/config';
import { ethers } from 'ethers';
```

To run this script, use:

```bash
node check-proposals.js
```

Make sure you have Node.js installed and that you've created a `.env` file in the same directory with your `PRIVATE_KEY` and `RPC_URL` (as described in the previous tutorial).

> **Note**: We're using ES modules (import syntax). Add `"type": "module"` to your `package.json` to enable this:
> ```json
> {
>   "type": "module",
>   "dependencies": { ... }
> }
> ```

### ES Modules vs CommonJS

There are two ways to import modules in Node.js:

**ES Modules (what we use):**
```javascript
import 'dotenv/config';
import { ethers } from 'ethers';
import Moloch from './Moloch.json' with { type: 'json' };
```

**CommonJS (the older way):**
```javascript
require('dotenv/config');
const { ethers } = require('ethers');
const Moloch = require('./Moloch.json');
```

Key differences:

| Feature | ES Modules (`import`) | CommonJS (`require`) |
|---------|----------------------|---------------------|
| Loading | Static, at parse time | Dynamic, at runtime |
| Top-level await | ✅ Supported | ❌ Not supported |
| Tree shaking | ✅ Yes | ❌ No |
| JSON imports | Needs `with { type: 'json' }` | Works directly |
| File extension | Often `.mjs` or `"type": "module"` | `.js` or `.cjs` |

We use ES modules because:
- **Top-level await**: We can use `await` outside of functions, which makes scripts cleaner
- **Modern standard**: ES modules are the JavaScript standard, CommonJS is Node-specific
- **Better tooling**: Bundlers and IDEs work better with static imports

If you see older tutorials using `require()`, the concepts are the same—just the syntax differs.

---

## Step 2: Environment Variables & Constants

First, let's add a helper function to validate that required environment variables are set:

```javascript
// Helper function to validate required environment variables
const requireEnv = (key) => {
  const value = process.env[key];
  if (!value) {
    console.error(`${key} not found in .env`);
    process.exit(1);
  }
  return value;
};

const RPC_URL = requireEnv('RPC_URL');
const PRIVATE_KEY = requireEnv('PRIVATE_KEY');
const VIEW_HELPER_ADDRESS = "0x00000000006631040967E58e3430e4B77921a2db";
const DAO_ADDRESS = "0x7a45e6764eCfF2F0eea245ca14a75d6d3d6053b7";
```

This helper stops the script immediately with a clear error message if any required variable is missing—much better than cryptic errors later.

**RPC_URL**: Your Sepolia RPC endpoint from the `.env` file.

**PRIVATE_KEY**: Your wallet's private key from the `.env` file.

**VIEW_HELPER_ADDRESS**: The MolochViewHelper contract. Same address on all networks.

**DAO_ADDRESS**: The "Elite Coders Union" DAO we're working with.

> **Important**: To vote on proposals, you need voting shares in this DAO. If you're following along with the Elite Coders Union DAO, visit [majeurdao.eth.limo](https://majeurdao.eth.limo/) and use some Sepolia ETH to buy shares through its DAICO. If you already have shares in a different DAO, change the `DAO_ADDRESS` constant to that DAO's address instead.

---

## Step 3: Import ABIs

ABIs (Application Binary Interfaces) tell ethers.js how to encode/decode function calls. When you compile contracts with Foundry (`forge build`), ABIs are generated in the `out/` directory:

- `out/Moloch.sol/Moloch.json` — The DAO contract ABI
- `out/MolochViewHelper.sol/MolochViewHelper.json` — The view helper ABI

Copy these JSON files to your script directory, then import them:

```javascript
import Moloch from './Moloch.json' with { type: 'json' };
import MolochViewHelper from './MolochViewHelper.json' with { type: 'json' };
```

> **Note**: The `with { type: 'json' }` syntax is how ES modules import JSON files. Each JSON file has an `abi` field containing the complete ABI array. We'll access it as `Moloch.abi` when creating contracts.

---

## Step 4: Connect to the Network

```javascript
// Setup provider and wallet
const provider = new ethers.JsonRpcProvider(RPC_URL);
const wallet = new ethers.Wallet(PRIVATE_KEY, provider);
console.log('Connected to Sepolia');
console.log(`Wallet: ${wallet.address}\n`);
```

**Provider**: A connection to the Ethereum network. It can only *read* data, not send transactions.

**Wallet**: A Signer backed by a private key. It can sign and send transactions.

The key difference:
- **Provider** = Read-only access
- **Signer** = Can sign transactions (but might not have a private key directly, e.g., MetaMask)
- **Wallet** = A Signer with a private key

---

## Step 5: Create Contract Instances

```javascript
// Create contracts (using ABIs directly)
const viewHelper = new ethers.Contract(VIEW_HELPER_ADDRESS, MolochViewHelper.abi, provider);
const dao = new ethers.Contract(DAO_ADDRESS, Moloch.abi, wallet);
```

When you create a `Contract` with a provider, you can only call `view` functions. When you create it with a signer, you can also call state-changing functions.

---

## Step 6: Fetch DAO State

```javascript
// Fetch and display DAO state
const state = await viewHelper.getDAOFullState(
  DAO_ADDRESS,
  0,      // proposalStart - start from first proposal
  1000,   // proposalCount - contract caps at actual total
  0,      // messageStart
  1000,   // messageCount - contract caps at actual total
  []      // treasuryTokens - empty array, we don't need treasury info
);

console.log(`DAO: ${state.meta.name} (${state.meta.symbol})`);
console.log(`Ragequit enabled: ${state.gov.ragequittable}`);
console.log(`Total proposals: ${state.proposals.length}\n`);
```

The `getDAOFullState` function returns everything about the DAO in one call. This is more efficient than making many separate calls.

> **Note**: If you need the exact proposal count first, you can call `dao.getProposalCount()` before fetching state. The view helper will automatically cap the count at the actual total.

### Your Code So Far

At this point, your complete `check-proposals.js` should look like this:

```javascript
import 'dotenv/config';
import { ethers } from 'ethers';
import Moloch from './Moloch.json' with { type: 'json' };
import MolochViewHelper from './MolochViewHelper.json' with { type: 'json' };

// Helper function to validate required environment variables
const requireEnv = (key) => {
  const value = process.env[key];
  if (!value) {
    console.error(`${key} not found in .env`);
    process.exit(1);
  }
  return value;
};

const RPC_URL = requireEnv('RPC_URL');
const PRIVATE_KEY = requireEnv('PRIVATE_KEY');
const VIEW_HELPER_ADDRESS = "0x00000000006631040967E58e3430e4B77921a2db";
const DAO_ADDRESS = "0x7a45e6764eCfF2F0eea245ca14a75d6d3d6053b7";

// Setup provider and wallet
const provider = new ethers.JsonRpcProvider(RPC_URL);
const wallet = new ethers.Wallet(PRIVATE_KEY, provider);
console.log('Connected to Sepolia');
console.log(`Wallet: ${wallet.address}\n`);

// Create contracts (using ABIs directly)
const viewHelper = new ethers.Contract(VIEW_HELPER_ADDRESS, MolochViewHelper.abi, provider);
const dao = new ethers.Contract(DAO_ADDRESS, Moloch.abi, wallet);

// Fetch and display DAO state
const state = await viewHelper.getDAOFullState(DAO_ADDRESS, 0, 1000, 0, 1000, []);

console.log(`DAO: ${state.meta.name} (${state.meta.symbol})`);
console.log(`Ragequit enabled: ${state.gov.ragequittable}`);
console.log(`Total proposals: ${state.proposals.length}\n`);
```

Try running it:

```bash
node check-proposals.js
```

Expected output:
```
Connected to Sepolia
Wallet: 0x...

DAO: Elite Coders Union (1337)
Ragequit enabled: true
Total proposals: 3
```

---

## Step 7: Find Active Unvoted Proposals

```javascript
// Understanding proposal states:
// - Unopened (0): A proposal ID that can be computed deterministically from parameters
//   (op, to, value, data, nonce, config) but hasn't been opened yet. Proposal IDs are
//   hashes, so you can know the ID before creating the proposal. This enables off-chain
//   coordination, UI building, and verification. A proposal becomes "opened" when:
//   - openProposal(id) is called explicitly, OR
//   - The first vote is cast (which auto-opens it)
//   Once opened, the proposal gets a snapshot block (block.number - 1) for voting power,
//   is added to the proposalIds registry, and transitions to Active state. Unopened
//   proposals cannot be voted on until opened.
// - Active (1): The proposal is open for voting. This is the only state where voting is allowed.
// - Queued (2): The proposal has passed and is waiting for the timelock delay to expire.
// - Succeeded (3): The proposal has passed all checks (quorum, FOR > AGAINST) but hasn't been executed yet.
// - Defeated (4): The proposal failed (FOR <= AGAINST or didn't meet minimum YES votes).
// - Expired (5): The proposal exceeded its TTL (time-to-live) without passing.
// - Executed (6): The proposal has been executed and can no longer be modified.

// Find active proposals you haven't voted on
console.log("=== Active Proposals You Haven't Voted On ===\n");

const unvotedProposals = [];

for (const proposal of state.proposals) {
  // Check if user has voted on this proposal
  // The voters array contains all voters for this proposal
  const userVote = proposal.voters.find(
    v => v.voter.toLowerCase() === wallet.address.toLowerCase()
  );

  // We only need to know about Active proposals (state 1) that are voteable
  const isVoteable = proposal.state === 1n;

  if (!userVote && isVoteable) {
    unvotedProposals.push(proposal);

    console.log(`Proposal ID: ${proposal.id}`);
    console.log(`  Votes - For: ${ethers.formatUnits(proposal.forVotes, 18)}, Against: ${ethers.formatUnits(proposal.againstVotes, 18)}`);
    console.log(`  Created: ${new Date(Number(proposal.createdAt) * 1000).toISOString()}\n`);
  }
}

if (unvotedProposals.length === 0) {
  console.log("No active proposals need your vote!\n");
}
```

Notice we compare `proposal.state === 1n`. The `n` suffix indicates a BigInt, which ethers.js uses for large numbers. Proposal state 1 is "Active" — the only state where voting is allowed. By filtering on both conditions, we only see proposals we can actually act on.

---

## Step 8: Check for Claimable Futarchy Rewards

**What is Futarchy?** Futarchy (as implemented in Majeur) is a prediction market mechanism where voters receive "receipt" tokens when they vote on a proposal. When the proposal resolves (either by passing or being defeated), the winning side's receipt holders can burn their receipts to claim a proportional share of the reward pool.

Here's how it works:
1. **When you vote**: You automatically receive receipt tokens equal to your voting weight (your share balance at the proposal's snapshot block). If you vote FOR, you get FOR receipts. If you vote AGAINST, you get AGAINST receipts.
2. **Reward pool**: A pool of tokens is set aside for futarchy rewards (this can be ETH, DAO shares, loot, or another ERC20 token).
3. **Resolution**: When the proposal passes (executes) or is defeated/expires, the futarchy resolves. If FOR wins (proposal passes), only FOR receipts can be redeemed. If AGAINST wins (proposal is defeated), only AGAINST receipts can be redeemed.
4. **Claiming**: Winners can burn their receipts to claim a proportional share: `payout = (yourReceipts / totalWinningReceipts) × rewardPool`

**Receipt tokens** are ERC-6909 multi-tokens. Each unique receipt token ID is computed deterministically from the proposal ID and vote side using: `keccak256("Moloch:receipt" + proposalId + support)`, where `support` is 0 (Against), 1 (For), or 2 (Abstain).

```javascript
// Check for claimable futarchy rewards
console.log('=== Checking Futarchy Rewards ===\n');

let hasClaimableRewards = false;

for (const proposal of state.proposals) {
  const futarchy = proposal.futarchy;

  // Skip proposals that don't have futarchy enabled or haven't resolved yet
  // - futarchy.enabled: true if this proposal has a reward pool
  // - futarchy.resolved: true if the proposal outcome has been determined
  //   (either passed and executed, or defeated/expired)
  if (!futarchy.enabled || !futarchy.resolved) {
    continue;
  }

  // The winner field is set when futarchy resolves:
  // - winner === 1 means FOR side won (proposal passed/executed)
  // - winner === 0 means AGAINST side won (proposal was defeated or expired)
  const winner = futarchy.winner;
  const winnerSide = winner === 1 ? 'FOR' : 'AGAINST';

  // Compute the receipt token ID for the winning side
  // The contract uses this exact formula to generate receipt IDs when you vote:
  // keccak256(abi.encodePacked("Moloch:receipt", proposalId, support))
  //
  // Since we only care about the winning side, we use the winner value (0 or 1)
  // as the support parameter. This gives us the token ID for the winning receipts.
  //
  // ethers.solidityPacked mimics Solidity's abi.encodePacked - it concatenates
  // the values tightly without padding, exactly as Solidity does for keccak256.
  const receiptId = ethers.keccak256(
    ethers.solidityPacked(
      ['string', 'uint256', 'uint8'],  // Types: string, uint256 (proposal id), uint8 (winner: 0 or 1)
      ['Moloch:receipt', proposal.id, winner]
    )
  );

  // Check if your wallet holds any receipts for the winning side
  // balanceOf(address, tokenId) is the ERC-6909 function to check token balance
  // If you voted on the winning side, you'll have a balance > 0
  const receiptBalance = await dao.balanceOf(wallet.address, receiptId);

  if (receiptBalance > 0n) {
    hasClaimableRewards = true;

    // Calculate your expected payout from the reward pool
    //
    // payoutPerUnit is pre-calculated when futarchy resolves as:
    //   payoutPerUnit = (rewardPool × 1e18) / totalWinningReceiptSupply
    //
    // It's stored scaled by 1e18 to maintain precision. So to get your payout:
    //   yourPayout = (yourReceiptBalance × payoutPerUnit) / 1e18
    //
    // Example: If the pool has 1000 tokens, total winning receipts are 5000,
    //          and you have 100 receipts:
    //          payoutPerUnit = (1000 × 1e18) / 5000 = 200000000000000000 (0.2 × 1e18)
    //          yourPayout = (100 × 200000000000000000) / 1e18 = 20 tokens
    const expectedPayout = (receiptBalance * futarchy.payoutPerUnit) / BigInt(1e18);

    console.log(`Proposal ${proposal.id}:`);
    console.log(`  Winner: ${winnerSide}`);
    console.log(`  Your receipts: ${ethers.formatUnits(receiptBalance, 18)}`);
    console.log(`  Expected payout: ${ethers.formatUnits(expectedPayout, 18)} tokens`);
    console.log(`  Reward token: ${futarchy.rewardToken}\n`);
```

To test the functionality until now, add two curly brackets at the end `} }`, otherwise continue to the next step.

**Key points about receipt tokens:**
- Receipts are minted automatically when you vote (you don't need to do anything special)
- The receipt amount equals your voting weight (your share balance at the proposal's snapshot block)
- Receipts are non-transferable (SBTs - Soul Bound Tokens) to prevent gaming
- Only the winning side's receipts can be redeemed after resolution
- If you voted on the losing side, your receipts become worthless (but don't need to be burned)

---

## Step 9: Claim the Rewards

```javascript
    // Claim the rewards
    console.log('  Claiming rewards...');

    try {
      const tx = await dao.cashOutFutarchy(proposal.id, receiptBalance);
      console.log(`  Transaction sent: ${tx.hash}`);

      // Wait for confirmation
      const receipt = await tx.wait();
      console.log(`  Confirmed in block ${receipt.blockNumber}\n`);
    } catch (error) {
      console.log(`  Error claiming: ${error.message}\n`);
    }
  }
}

if (!hasClaimableRewards) {
  console.log('No claimable futarchy rewards found.\n');
}
```

The `tx.wait()` call blocks until the transaction is mined. The returned receipt contains the block number and other transaction details.

---

## Complete Script

Here's the full script in one piece:

```javascript
// check-proposals.js
import 'dotenv/config';
import { ethers } from 'ethers';
import Moloch from './Moloch.json' with { type: 'json' };
import MolochViewHelper from './MolochViewHelper.json' with { type: 'json' };

const requireEnv = (key) => {
  const value = process.env[key];
  if (!value) {
    console.error(`${key} not found in .env`);
    process.exit(1);
  }
  return value;
};

const RPC_URL = requireEnv('RPC_URL');
const PRIVATE_KEY = requireEnv('PRIVATE_KEY');
const VIEW_HELPER_ADDRESS = "0x00000000006631040967E58e3430e4B77921a2db";
const DAO_ADDRESS = "0x7a45e6764eCfF2F0eea245ca14a75d6d3d6053b7";

// Setup provider and wallet
const provider = new ethers.JsonRpcProvider(RPC_URL);
const wallet = new ethers.Wallet(PRIVATE_KEY, provider);
console.log('Connected to Sepolia');
console.log(`Wallet: ${wallet.address}\n`);

// Create contracts
const viewHelper = new ethers.Contract(VIEW_HELPER_ADDRESS, MolochViewHelper.abi, provider);
const dao = new ethers.Contract(DAO_ADDRESS, Moloch.abi, wallet);

// Fetch DAO state
const state = await viewHelper.getDAOFullState(
  DAO_ADDRESS,
  0,      // proposalStart
  1000,   // proposalCount
  0,      // messageStart
  1000,   // messageCount
  []      // treasuryTokens
);

console.log(`DAO: ${state.meta.name} (${state.meta.symbol})`);
console.log(`Ragequit enabled: ${state.gov.ragequittable}`);
console.log(`Total proposals: ${state.proposals.length}\n`);

// Find active proposals you haven't voted on
console.log("=== Active Proposals You Haven't Voted On ===\n");

const unvotedProposals = [];

for (const proposal of state.proposals) {
  const userVote = proposal.voters.find(
    v => v.voter.toLowerCase() === wallet.address.toLowerCase()
  );

  const isVoteable = proposal.state === 1n;

  if (!userVote && isVoteable) {
    unvotedProposals.push(proposal);

    console.log(`Proposal ID: ${proposal.id}`);
    console.log(`  Votes - For: ${ethers.formatUnits(proposal.forVotes, 18)}, Against: ${ethers.formatUnits(proposal.againstVotes, 18)}`);
    console.log(`  Created: ${new Date(Number(proposal.createdAt) * 1000).toISOString()}\n`);
  }
}

if (unvotedProposals.length === 0) {
  console.log("No active proposals need your vote!\n");
}

// Check futarchy rewards
console.log('=== Checking Futarchy Rewards ===\n');

let hasClaimableRewards = false;

for (const proposal of state.proposals) {
  const futarchy = proposal.futarchy;

  if (!futarchy.enabled || !futarchy.resolved) {
    continue;
  }

  const winner = futarchy.winner;
  const winnerSide = winner === 1 ? 'FOR' : 'AGAINST';

  const receiptId = ethers.keccak256(
    ethers.solidityPacked(
      ['string', 'uint256', 'uint8'],
      ['Moloch:receipt', proposal.id, winner]
    )
  );

  const receiptBalance = await dao.balanceOf(wallet.address, receiptId);

  if (receiptBalance > 0n) {
    hasClaimableRewards = true;

    const expectedPayout = (receiptBalance * futarchy.payoutPerUnit) / BigInt(1e18);

    console.log(`Proposal ${proposal.id}:`);
    console.log(`  Winner: ${winnerSide}`);
    console.log(`  Your receipts: ${ethers.formatUnits(receiptBalance, 18)}`);
    console.log(`  Expected payout: ${ethers.formatUnits(expectedPayout, 18)} tokens`);
    console.log(`  Reward token: ${futarchy.rewardToken}\n`);

    console.log('  Claiming rewards...');

    try {
      const tx = await dao.cashOutFutarchy(proposal.id, receiptBalance);
      console.log(`  Transaction sent: ${tx.hash}`);

      const receipt = await tx.wait();
      console.log(`  Confirmed in block ${receipt.blockNumber}\n`);
    } catch (error) {
      console.log(`  Error claiming: ${error.message}\n`);
    }
  }
}

if (!hasClaimableRewards) {
  console.log('No claimable futarchy rewards found.\n');
}
```

---

## Key Takeaways

1. **Provider vs Wallet**: Use Provider for reads, Wallet (with private key) for writes
2. **ABIs are contracts**: They describe what functions exist and their parameters
3. **BigInt for numbers**: Ethereum uses 256-bit integers, JavaScript uses BigInt (`123n`)
4. **ERC-6909 receipts**: Vote receipts are multi-tokens with computed IDs
5. **Batch reads**: `getDAOFullState` fetches everything in one call

---

**Next**: [Submit & Execute Proposals →](0-to-hero-3.md)

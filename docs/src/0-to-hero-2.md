# Tutorial: List Unvoted Proposals & Claim Futarchy Rewards

In this tutorial, you'll write a script that:
1. Connects to the Sepolia network
2. Fetches all proposals from a DAO
3. Filters to show only proposals you haven't voted on
4. Checks if you have any claimable futarchy rewards
5. Claims those rewards if available

## What You'll Learn

- How ethers.js connects to Ethereum
- The difference between Providers, Signers, and Wallets
- How to read contract state using ABIs
- How the futarchy reward system works

---

## Step 1: Project Setup

Create a new file `check-proposals.js`:

```javascript
// check-proposals.js
require('dotenv').config();
const { ethers } = require('ethers');
```

The `dotenv` package loads your private key from the `.env` file we created earlier.

---

## Step 2: Define Constants

```javascript
// Network and contract addresses
const RPC_URL = "https://ethereum-sepolia-rpc.publicnode.com";
const VIEW_HELPER_ADDRESS = "0x00000000006631040967E58e3430e4B77921a2db";
const DAO_ADDRESS = "0x7a45e6764eCfF2F0eea245ca14a75d6d3d6053b7";
```

**RPC_URL**: A public endpoint to communicate with Sepolia. In production, use a dedicated provider like Alchemy or Infura.

**VIEW_HELPER_ADDRESS**: The MolochViewHelper contract. Same address on all networks.

**DAO_ADDRESS**: The "Elite Coders Union" DAO we're working with.

> **Important**: To vote on proposals, you need voting shares in this DAO. If you're following along with the Elite Coders Union DAO, visit [majeurdao.eth.limo](https://majeurdao.eth.limo/) and use some Sepolia ETH to buy shares through its DAICO. If you already have shares in a different DAO, change the `DAO_ADDRESS` constant to that DAO's address instead.

---

## Step 3: Define ABIs

ABIs (Application Binary Interfaces) tell ethers.js how to encode/decode function calls. We only need the functions we'll actually use:

```javascript
// Minimal ABI for MolochViewHelper
const VIEW_HELPER_ABI = [
  {
    "inputs": [
      { "name": "dao", "type": "address" },
      { "name": "proposalStart", "type": "uint256" },
      { "name": "proposalCount", "type": "uint256" },
      { "name": "messageStart", "type": "uint256" },
      { "name": "messageCount", "type": "uint256" },
      { "name": "treasuryTokens", "type": "address[]" }
    ],
    "name": "getDAOFullState",
    "outputs": [
      {
        "components": [
          { "name": "dao", "type": "address" },
          {
            "components": [
              { "name": "name", "type": "string" },
              { "name": "symbol", "type": "string" },
              { "name": "contractURI", "type": "string" },
              { "name": "sharesToken", "type": "address" },
              { "name": "lootToken", "type": "address" },
              { "name": "badgesToken", "type": "address" },
              { "name": "renderer", "type": "address" }
            ],
            "name": "meta",
            "type": "tuple"
          },
          {
            "components": [
              { "name": "proposalThreshold", "type": "uint96" },
              { "name": "minYesVotesAbsolute", "type": "uint96" },
              { "name": "quorumAbsolute", "type": "uint96" },
              { "name": "proposalTTL", "type": "uint64" },
              { "name": "timelockDelay", "type": "uint64" },
              { "name": "quorumBps", "type": "uint16" },
              { "name": "ragequittable", "type": "bool" },
              { "name": "autoFutarchyParam", "type": "uint256" },
              { "name": "autoFutarchyCap", "type": "uint256" },
              { "name": "rewardToken", "type": "address" }
            ],
            "name": "gov",
            "type": "tuple"
          },
          {
            "components": [
              { "name": "sharesTotalSupply", "type": "uint256" },
              { "name": "lootTotalSupply", "type": "uint256" },
              { "name": "sharesHeldByDAO", "type": "uint256" },
              { "name": "lootHeldByDAO", "type": "uint256" }
            ],
            "name": "supplies",
            "type": "tuple"
          },
          {
            "components": [
              {
                "components": [
                  { "name": "token", "type": "address" },
                  { "name": "balance", "type": "uint256" }
                ],
                "name": "balances",
                "type": "tuple[]"
              }
            ],
            "name": "treasury",
            "type": "tuple"
          },
          {
            "components": [
              { "name": "account", "type": "address" },
              { "name": "shares", "type": "uint256" },
              { "name": "loot", "type": "uint256" },
              { "name": "seatId", "type": "uint16" },
              { "name": "votingPower", "type": "uint256" },
              { "name": "delegates", "type": "address[]" },
              { "name": "delegatesBps", "type": "uint32[]" }
            ],
            "name": "members",
            "type": "tuple[]"
          },
          {
            "components": [
              { "name": "id", "type": "uint256" },
              { "name": "proposer", "type": "address" },
              { "name": "state", "type": "uint8" },
              { "name": "snapshotBlock", "type": "uint48" },
              { "name": "createdAt", "type": "uint64" },
              { "name": "queuedAt", "type": "uint64" },
              { "name": "supplySnapshot", "type": "uint256" },
              { "name": "forVotes", "type": "uint96" },
              { "name": "againstVotes", "type": "uint96" },
              { "name": "abstainVotes", "type": "uint96" },
              {
                "components": [
                  { "name": "enabled", "type": "bool" },
                  { "name": "rewardToken", "type": "address" },
                  { "name": "pool", "type": "uint256" },
                  { "name": "resolved", "type": "bool" },
                  { "name": "winner", "type": "uint8" },
                  { "name": "finalWinningSupply", "type": "uint256" },
                  { "name": "payoutPerUnit", "type": "uint256" }
                ],
                "name": "futarchy",
                "type": "tuple"
              },
              {
                "components": [
                  { "name": "voter", "type": "address" },
                  { "name": "support", "type": "uint8" },
                  { "name": "weight", "type": "uint256" }
                ],
                "name": "voters",
                "type": "tuple[]"
              }
            ],
            "name": "proposals",
            "type": "tuple[]"
          },
          {
            "components": [
              { "name": "index", "type": "uint256" },
              { "name": "text", "type": "string" }
            ],
            "name": "messages",
            "type": "tuple[]"
          }
        ],
        "name": "out",
        "type": "tuple"
      }
    ],
    "stateMutability": "view",
    "type": "function"
  }
];

// Minimal ABI for Moloch DAO contract
const MOLOCH_ABI = [
  {
    "inputs": [{ "name": "id", "type": "uint256" }, { "name": "voter", "type": "address" }],
    "name": "hasVoted",
    "outputs": [{ "type": "uint8" }],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [{ "name": "owner", "type": "address" }, { "name": "id", "type": "uint256" }],
    "name": "balanceOf",
    "outputs": [{ "type": "uint256" }],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [{ "name": "id", "type": "uint256" }, { "name": "amount", "type": "uint256" }],
    "name": "cashOutFutarchy",
    "outputs": [{ "name": "payout", "type": "uint256" }],
    "stateMutability": "nonpayable",
    "type": "function"
  }
];
```

This looks like a lot, but you're just describing the shape of the data. In production, you'd typically import ABIs from a JSON file.

---

## Step 4: Connect to the Network

```javascript
async function main() {
  // Create a Provider - this is a read-only connection to the network
  const provider = new ethers.JsonRpcProvider(RPC_URL);
  console.log("Connected to Sepolia\n");
```

**Provider**: A connection to the Ethereum network. It can only *read* data, not send transactions.

```javascript
  // Create a Wallet - this is a Signer that can send transactions
  const wallet = new ethers.Wallet(process.env.PRIVATE_KEY, provider);
  console.log("Your address:", wallet.address);
```

**Wallet**: A Signer backed by a private key. It can sign and send transactions.

The key difference:
- **Provider** = Read-only access
- **Signer** = Can sign transactions (but might not have a private key directly, e.g., MetaMask)
- **Wallet** = A Signer with a private key

---

## Step 5: Create Contract Instances

```javascript
  // Create contract instances
  // For read-only, we use the provider
  const viewHelper = new ethers.Contract(VIEW_HELPER_ADDRESS, VIEW_HELPER_ABI, provider);

  // For transactions, we use the wallet (signer)
  const dao = new ethers.Contract(DAO_ADDRESS, MOLOCH_ABI, wallet);
```

When you create a `Contract` with a provider, you can only call `view` functions. When you create it with a signer, you can also call state-changing functions.

---

## Step 6: Fetch DAO State

```javascript
  // Fetch DAO state
  // Parameters: (dao, proposalStart, proposalCount, messageStart, messageCount, treasuryTokens)
  // Use 0,0 for start/count to get ALL proposals and messages
  console.log("Fetching DAO state...\n");

  const state = await viewHelper.getDAOFullState(
    DAO_ADDRESS,
    0,    // proposalStart - start from first proposal
    0,    // proposalCount - 0 means fetch ALL proposals
    0,    // messageStart
    0,    // messageCount - 0 means fetch ALL messages
    []    // treasuryTokens - empty array, we don't need treasury info
  );

  console.log("DAO:", state.meta.name, `(${state.meta.symbol})`);
  console.log("Ragequit enabled:", state.gov.ragequittable);
  console.log("Total proposals:", state.proposals.length);
  console.log("");
```

The `getDAOFullState` function returns everything about the DAO in one call. This is more efficient than making many separate calls.

---

## Step 7: Find Unvoted Proposals

```javascript
  // Proposal states
  const STATE_NAMES = ['Unopened', 'Active', 'Queued', 'Succeeded', 'Defeated', 'Expired', 'Executed'];

  // Find proposals you haven't voted on
  console.log("=== Proposals You Haven't Voted On ===\n");

  const unvotedProposals = [];

  for (const proposal of state.proposals) {
    // Check if user has voted on this proposal
    // The voters array contains all voters for this proposal
    const userVote = proposal.voters.find(
      v => v.voter.toLowerCase() === wallet.address.toLowerCase()
    );

    if (!userVote) {
      unvotedProposals.push(proposal);

      // Only show Active proposals (state 1) as voteable
      const isVoteable = proposal.state === 1n;

      console.log(`Proposal ID: ${proposal.id}`);
      console.log(`  State: ${STATE_NAMES[Number(proposal.state)]}${isVoteable ? ' (can vote!)' : ''}`);
      console.log(`  Votes - For: ${ethers.formatUnits(proposal.forVotes, 18)}, Against: ${ethers.formatUnits(proposal.againstVotes, 18)}`);
      console.log(`  Created: ${new Date(Number(proposal.createdAt) * 1000).toISOString()}`);
      console.log("");
    }
  }

  if (unvotedProposals.length === 0) {
    console.log("You've voted on all proposals!\n");
  }
```

Notice we compare `proposal.state === 1n`. The `n` suffix indicates a BigInt, which ethers.js uses for large numbers. Proposal state 1 is "Active" — the only state where voting is allowed.

---

## Step 8: Check for Claimable Futarchy Rewards

Futarchy is a prediction market on proposals. When you vote, you receive "receipt" tokens. If your side wins, you can burn those receipts to claim a share of the reward pool.

```javascript
  // Check for claimable futarchy rewards
  console.log("=== Checking Futarchy Rewards ===\n");

  let hasClaimableRewards = false;

  for (const proposal of state.proposals) {
    const futarchy = proposal.futarchy;

    // Only check proposals with resolved futarchy
    if (!futarchy.enabled || !futarchy.resolved) {
      continue;
    }

    // The winner is 0 (Against won) or 1 (For won)
    const winner = futarchy.winner;
    const winnerSide = winner === 1 ? "FOR" : "AGAINST";

    // Compute the receipt ID for the winning side
    // Formula: keccak256(abi.encodePacked("Moloch:receipt", proposalId, winner))
    const receiptId = ethers.keccak256(
      ethers.solidityPacked(
        ["string", "uint256", "uint8"],
        ["Moloch:receipt", proposal.id, winner]
      )
    );

    // Check if user has any winning receipts
    const receiptBalance = await dao.balanceOf(wallet.address, receiptId);

    if (receiptBalance > 0n) {
      hasClaimableRewards = true;

      // Calculate expected payout
      // payoutPerUnit is scaled by 1e18
      const expectedPayout = (receiptBalance * futarchy.payoutPerUnit) / BigInt(1e18);

      console.log(`Proposal ${proposal.id}:`);
      console.log(`  Winner: ${winnerSide}`);
      console.log(`  Your receipts: ${ethers.formatUnits(receiptBalance, 18)}`);
      console.log(`  Expected payout: ${ethers.formatUnits(expectedPayout, 18)} tokens`);
      console.log(`  Reward token: ${futarchy.rewardToken}`);
      console.log("");
```

**Receipt tokens** are ERC-6909 multi-tokens. Each proposal+vote combination has a unique token ID. When futarchy resolves, only the winning side's receipts are redeemable.

---

## Step 9: Claim the Rewards

```javascript
      // Ask user if they want to claim
      console.log("  Claiming rewards...");

      try {
        const tx = await dao.cashOutFutarchy(proposal.id, receiptBalance);
        console.log(`  Transaction sent: ${tx.hash}`);

        // Wait for confirmation
        const receipt = await tx.wait();
        console.log(`  Confirmed in block ${receipt.blockNumber}`);
        console.log("");
      } catch (error) {
        console.log(`  Error claiming: ${error.message}`);
        console.log("");
      }
    }
  }

  if (!hasClaimableRewards) {
    console.log("No claimable futarchy rewards found.\n");
  }
}

// Run the script
main().catch(console.error);
```

The `tx.wait()` call blocks until the transaction is mined. The returned receipt contains the block number and other transaction details.

---

## Complete Script

Here's the full script in one piece:

```javascript
// check-proposals.js
require('dotenv').config();
const { ethers } = require('ethers');

// Constants
const RPC_URL = "https://ethereum-sepolia-rpc.publicnode.com";
const VIEW_HELPER_ADDRESS = "0x00000000006631040967E58e3430e4B77921a2db";
const DAO_ADDRESS = "0x7a45e6764eCfF2F0eea245ca14a75d6d3d6053b7";

// ABIs (shortened for display - use the full versions from above)
const VIEW_HELPER_ABI = [/* ... full ABI from Step 3 ... */];
const MOLOCH_ABI = [/* ... full ABI from Step 3 ... */];

const STATE_NAMES = ['Unopened', 'Active', 'Queued', 'Succeeded', 'Defeated', 'Expired', 'Executed'];

async function main() {
  const provider = new ethers.JsonRpcProvider(RPC_URL);
  const wallet = new ethers.Wallet(process.env.PRIVATE_KEY, provider);

  console.log("Connected to Sepolia");
  console.log("Your address:", wallet.address, "\n");

  const viewHelper = new ethers.Contract(VIEW_HELPER_ADDRESS, VIEW_HELPER_ABI, provider);
  const dao = new ethers.Contract(DAO_ADDRESS, MOLOCH_ABI, wallet);

  console.log("Fetching DAO state...\n");
  const state = await viewHelper.getDAOFullState(DAO_ADDRESS, 0, 0, 0, 0, []);

  console.log("DAO:", state.meta.name, `(${state.meta.symbol})`);
  console.log("Total proposals:", state.proposals.length, "\n");

  // Find unvoted proposals
  console.log("=== Proposals You Haven't Voted On ===\n");
  let unvotedCount = 0;

  for (const proposal of state.proposals) {
    const userVote = proposal.voters.find(
      v => v.voter.toLowerCase() === wallet.address.toLowerCase()
    );

    if (!userVote) {
      unvotedCount++;
      const isVoteable = proposal.state === 1n;
      console.log(`Proposal ${proposal.id}`);
      console.log(`  State: ${STATE_NAMES[Number(proposal.state)]}${isVoteable ? ' (voteable)' : ''}`);
      console.log(`  For: ${ethers.formatUnits(proposal.forVotes, 18)}, Against: ${ethers.formatUnits(proposal.againstVotes, 18)}\n`);
    }
  }

  if (unvotedCount === 0) console.log("You've voted on all proposals!\n");

  // Check futarchy rewards
  console.log("=== Checking Futarchy Rewards ===\n");
  let claimed = false;

  for (const proposal of state.proposals) {
    if (!proposal.futarchy.enabled || !proposal.futarchy.resolved) continue;

    const winner = proposal.futarchy.winner;
    const receiptId = ethers.keccak256(
      ethers.solidityPacked(["string", "uint256", "uint8"], ["Moloch:receipt", proposal.id, winner])
    );

    const balance = await dao.balanceOf(wallet.address, receiptId);
    if (balance > 0n) {
      claimed = true;
      const payout = (balance * proposal.futarchy.payoutPerUnit) / BigInt(1e18);
      console.log(`Claiming from proposal ${proposal.id}: ${ethers.formatUnits(payout, 18)} tokens`);

      const tx = await dao.cashOutFutarchy(proposal.id, balance);
      await tx.wait();
      console.log(`Claimed! Tx: ${tx.hash}\n`);
    }
  }

  if (!claimed) console.log("No claimable rewards.\n");
}

main().catch(console.error);
```

---

## Run It

```bash
node check-proposals.js
```

Expected output:
```
Connected to Sepolia
Your address: 0x...

Fetching DAO state...

DAO: Elite Coders Union (ECU)
Total proposals: 3

=== Proposals You Haven't Voted On ===

Proposal 1234...
  State: Active (voteable)
  For: 100.0, Against: 50.0

=== Checking Futarchy Rewards ===

No claimable rewards.
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

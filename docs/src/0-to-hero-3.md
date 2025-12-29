# Tutorial: Submit & Execute a Ragequit Toggle Proposal

In this tutorial, you'll write a script that:
1. Checks the current ragequit status
2. Computes the proposal ID *before* submitting (it's deterministic!)
3. Creates a proposal to toggle ragequit
4. Casts a vote on it
5. Executes it if conditions are met

## What You'll Learn

- How proposal IDs are computed deterministically
- How to encode function calls for governance
- The proposal state machine
- How voting and execution work

---

## How Proposals Work

In Majeur, proposals are **not stored on-chain until voted on**. Instead:

1. Anyone can compute a proposal ID from its parameters
2. The first vote "opens" the proposal (creates on-chain state)
3. Members vote FOR, AGAINST, or ABSTAIN
4. After voting ends, anyone can execute if it passed

The proposal ID is a hash of:
- DAO address
- Operation type (0=call, 1=delegatecall)
- Target contract
- ETH value
- Calldata hash
- Nonce (for uniqueness)
- Config version

---

## Step 1: Setup

Create `toggle-ragequit.js`:

```javascript
// toggle-ragequit.js
import 'dotenv/config';
import { ethers } from 'ethers';

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

> **Important**: To submit proposals and vote, you need voting shares in this DAO. If you're following along with the Elite Coders Union DAO, visit [majeurdao.eth.limo](https://majeurdao.eth.limo/) and use some Sepolia ETH to buy shares through its DAICO. If you already have shares in a different DAO, change the `DAO_ADDRESS` constant to that DAO's address instead.

---

## Step 2: Define ABIs

We need more functions this time:

```javascript
// View helper ABI (same as tutorial 2, but we only need gov config)
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
          { "name": "supplies", "type": "tuple" },
          { "name": "treasury", "type": "tuple" },
          { "name": "members", "type": "tuple[]" },
          { "name": "proposals", "type": "tuple[]" },
          { "name": "messages", "type": "tuple[]" }
        ],
        "name": "out",
        "type": "tuple"
      }
    ],
    "stateMutability": "view",
    "type": "function"
  }
];

// Moloch ABI - functions we need
const MOLOCH_ABI = [
  // Read current config version
  {
    "inputs": [],
    "name": "config",
    "outputs": [{ "type": "uint256" }],
    "stateMutability": "view",
    "type": "function"
  },
  // Get proposal state
  {
    "inputs": [{ "name": "id", "type": "uint256" }],
    "name": "state",
    "outputs": [{ "type": "uint8" }],
    "stateMutability": "view",
    "type": "function"
  },
  // Cast vote
  {
    "inputs": [
      { "name": "id", "type": "uint256" },
      { "name": "support", "type": "uint8" }
    ],
    "name": "castVote",
    "outputs": [],
    "stateMutability": "nonpayable",
    "type": "function"
  },
  // Execute proposal
  {
    "inputs": [
      { "name": "op", "type": "uint8" },
      { "name": "to", "type": "address" },
      { "name": "value", "type": "uint256" },
      { "name": "data", "type": "bytes" },
      { "name": "nonce", "type": "bytes32" }
    ],
    "name": "executeByVotes",
    "outputs": [],
    "stateMutability": "payable",
    "type": "function"
  },
  // The function we're calling via governance
  {
    "inputs": [{ "name": "on", "type": "bool" }],
    "name": "setRagequittable",
    "outputs": [],
    "stateMutability": "payable",
    "type": "function"
  }
];
```

---

## Step 3: Connect and Read Current State

```javascript
const STATE_NAMES = ['Unopened', 'Active', 'Queued', 'Succeeded', 'Defeated', 'Expired', 'Executed'];

// Setup provider and wallet
const provider = new ethers.JsonRpcProvider(RPC_URL);
const wallet = new ethers.Wallet(PRIVATE_KEY, provider);
console.log('Connected to Sepolia');
console.log(`Wallet: ${wallet.address}\n`);

const viewHelper = new ethers.Contract(VIEW_HELPER_ADDRESS, VIEW_HELPER_ABI, provider);
const dao = new ethers.Contract(DAO_ADDRESS, MOLOCH_ABI, wallet);

// Fetch current state
const state = await viewHelper.getDAOFullState(DAO_ADDRESS, 0, 0, 0, 0, []);

const currentRagequit = state.gov.ragequittable;
console.log(`Current ragequit status: ${currentRagequit}`);
console.log(`We will toggle it to: ${!currentRagequit}\n`);
```

---

## Step 4: Encode the Function Call

To call `setRagequittable(bool)` via governance, we need to encode it as calldata:

```javascript
// Create an Interface to encode function calls
const iface = new ethers.Interface(MOLOCH_ABI);

// Encode the function call: setRagequittable(!currentRagequit)
const data = iface.encodeFunctionData('setRagequittable', [!currentRagequit]);

console.log(`Encoded calldata: ${data}`);
// This will be something like: 0x12345678...
```

**Interface** is ethers.js's way to work with ABIs. `encodeFunctionData` converts a function name and arguments into the bytes that the EVM expects.

---

## Step 5: Compute the Proposal ID

This is the key insight: **proposal IDs are deterministic**. You can compute them before any transaction:

```javascript
// Proposal parameters
const op = 0;           // 0 = CALL (normal execution)
const to = DAO_ADDRESS; // Target is the DAO itself (calling its own function)
const value = 0n;       // No ETH being sent

// Nonce makes each proposal unique
// Using timestamp ensures we don't collide with existing proposals
const nonce = ethers.id('toggle-ragequit-' + Date.now());

// Get current config version (proposals include this to prevent replay)
const config = await dao.config();

console.log('Proposal parameters:');
console.log(`  op: ${op}`);
console.log(`  to: ${to}`);
console.log(`  value: ${value}`);
console.log(`  data: ${data}`);
console.log(`  nonce: ${nonce}`);
console.log(`  config: ${config}\n`);
```

Now compute the ID:

```javascript
// Compute proposal ID
// Formula: keccak256(abi.encode(dao, op, to, value, keccak256(data), nonce, config))
const proposalId = ethers.keccak256(
  ethers.AbiCoder.defaultAbiCoder().encode(
    ['address', 'uint8', 'address', 'uint256', 'bytes32', 'bytes32', 'uint256'],
    [DAO_ADDRESS, op, to, value, ethers.keccak256(data), nonce, config]
  )
);

console.log(`Computed proposal ID: ${proposalId}`);
console.log('(This ID exists before we submit any transaction!)\n');
```

The formula in Solidity is:
```solidity
keccak256(abi.encode(address(this), op, to, value, keccak256(data), nonce, config))
```

We replicate it exactly in JavaScript.

---

## Step 6: Cast Your Vote

In Majeur, the first vote automatically "opens" the proposal:

```javascript
// Check current proposal state
let proposalState = await dao.state(proposalId);
console.log(`Current proposal state: ${STATE_NAMES[Number(proposalState)]}`);

// Cast vote FOR (support = 1)
// Support values: 0 = AGAINST, 1 = FOR, 2 = ABSTAIN
console.log('\nCasting vote FOR the proposal...');

try {
  const voteTx = await dao.castVote(proposalId, 1);
  console.log(`Transaction sent: ${voteTx.hash}`);

  const receipt = await voteTx.wait();
  console.log(`Confirmed in block ${receipt.blockNumber}`);
} catch (error) {
  if (error.message.includes('AlreadyVoted')) {
    console.log("You've already voted on this proposal!");
  } else {
    throw error;
  }
}
```

If you're the first voter, the proposal is now "Active". If you don't have enough voting power to meet the threshold, you'll get an error.

---

## Step 7: Check If Executable

After voting, check if the proposal has passed:

```javascript
// Re-check proposal state
proposalState = await dao.state(proposalId);
console.log(`\nProposal state after voting: ${STATE_NAMES[Number(proposalState)]}`);
```

The proposal state machine:

| State | Value | Meaning |
|-------|-------|---------|
| Unopened | 0 | Not yet voted on |
| Active | 1 | Voting in progress |
| Queued | 2 | Passed, waiting for timelock |
| Succeeded | 3 | Ready to execute |
| Defeated | 4 | Failed (more AGAINST than FOR, or quorum not met) |
| Expired | 5 | TTL passed without enough votes |
| Executed | 6 | Already executed |

---

## Step 8: Execute If Ready

```javascript
// If succeeded, try to execute
if (proposalState === 3n) {  // Succeeded
  console.log('\nProposal passed! Executing...');

  try {
    const executeTx = await dao.executeByVotes(op, to, value, data, nonce);
    console.log(`Transaction sent: ${executeTx.hash}`);

    const receipt = await executeTx.wait();
    console.log(`Executed in block ${receipt.blockNumber}`);

    // Verify the change
    const newState = await viewHelper.getDAOFullState(DAO_ADDRESS, 0, 0, 0, 0, []);
    console.log(`\nRagequit is now: ${newState.gov.ragequittable}`);

  } catch (error) {
    console.log(`Execution failed: ${error.message}`);
  }
} else if (proposalState === 1n) {  // Still Active
  console.log('\nProposal is still active. Needs more votes or time to pass.');
  console.log('Try running this script again later, or have other members vote.');
} else if (proposalState === 2n) {  // Queued
  console.log('\nProposal is queued. Waiting for timelock to expire.');
  console.log(`Timelock delay: ${state.gov.timelockDelay} seconds`);
} else {
  console.log('\nProposal cannot be executed in current state.');
}
```

**executeByVotes** takes the same parameters used to compute the proposal ID. The contract verifies that:
1. The hash matches an existing proposal
2. The proposal state is Succeeded
3. Any timelock has passed

---

## Complete Script

```javascript
// toggle-ragequit.js
import 'dotenv/config';
import { ethers } from 'ethers';

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

const VIEW_HELPER_ABI = [/* ... from above ... */];
const MOLOCH_ABI = [/* ... from above ... */];

const STATE_NAMES = ['Unopened', 'Active', 'Queued', 'Succeeded', 'Defeated', 'Expired', 'Executed'];

// Setup provider and wallet
const provider = new ethers.JsonRpcProvider(RPC_URL);
const wallet = new ethers.Wallet(PRIVATE_KEY, provider);
console.log('Connected to Sepolia');
console.log(`Wallet: ${wallet.address}\n`);

const viewHelper = new ethers.Contract(VIEW_HELPER_ADDRESS, VIEW_HELPER_ABI, provider);
const dao = new ethers.Contract(DAO_ADDRESS, MOLOCH_ABI, wallet);

// Get current state
const state = await viewHelper.getDAOFullState(DAO_ADDRESS, 0, 0, 0, 0, []);
const currentRagequit = state.gov.ragequittable;
console.log(`Current ragequit: ${currentRagequit} -> toggling to: ${!currentRagequit}\n`);

// Encode the governance call
const iface = new ethers.Interface(MOLOCH_ABI);
const data = iface.encodeFunctionData('setRagequittable', [!currentRagequit]);

// Proposal parameters
const op = 0;
const to = DAO_ADDRESS;
const value = 0n;
const nonce = ethers.id('toggle-ragequit-' + Date.now());
const config = await dao.config();

// Compute proposal ID
const proposalId = ethers.keccak256(
  ethers.AbiCoder.defaultAbiCoder().encode(
    ['address', 'uint8', 'address', 'uint256', 'bytes32', 'bytes32', 'uint256'],
    [DAO_ADDRESS, op, to, value, ethers.keccak256(data), nonce, config]
  )
);
console.log(`Proposal ID: ${proposalId}`);

// Cast vote
console.log('Casting vote FOR...');
try {
  const voteTx = await dao.castVote(proposalId, 1);
  await voteTx.wait();
  console.log(`Vote cast! Tx: ${voteTx.hash}`);
} catch (e) {
  console.log(`Vote error: ${e.reason || e.message}`);
}

// Check state and maybe execute
const proposalState = await dao.state(proposalId);
console.log(`State: ${STATE_NAMES[Number(proposalState)]}`);

if (proposalState === 3n) {
  console.log('Executing...');
  const execTx = await dao.executeByVotes(op, to, value, data, nonce);
  await execTx.wait();
  console.log(`Executed! Tx: ${execTx.hash}`);

  const newState = await viewHelper.getDAOFullState(DAO_ADDRESS, 0, 0, 0, 0, []);
  console.log(`Ragequit is now: ${newState.gov.ragequittable}`);
}
```

---

## Run It

```bash
node toggle-ragequit.js
```

Expected output:
```
Connected to Sepolia
Wallet: 0x...

Current ragequit: true -> toggling to: false

Proposal ID: 0x1234...
Casting vote FOR...
Vote cast! Tx: 0xabcd...
State: Active

(If you have enough votes to pass immediately)
State: Succeeded
Executing...
Executed! Tx: 0xefgh...
Ragequit is now: false
```

---

## Why This Matters

Understanding deterministic proposal IDs unlocks powerful patterns:

1. **Pre-computed verification**: Users can verify proposal effects before voting
2. **Off-chain coordination**: Share proposal IDs before on-chain submission
3. **Multi-sig workflows**: Compute ID, collect signatures, then submit
4. **Frontend UX**: Show users what will happen before they sign

---

## Key Takeaways

1. **Proposals are deterministic**: ID = hash(dao, op, to, value, dataHash, nonce, config)
2. **First vote opens**: No separate "propose" transaction needed
3. **Config prevents replay**: The `config` parameter lets DAOs invalidate old proposals
4. **Encode with Interface**: `iface.encodeFunctionData()` creates calldata
5. **State machine matters**: Only "Succeeded" proposals can execute

---

## Next Steps

You now know enough to:
- Read any DAO's state
- Check your votes and rewards
- Submit governance proposals
- Execute passed proposals

For more advanced topics, explore the [main README](../../README.md) which covers:
- Split delegation
- Futarchy funding
- Token sales
- Ragequit mechanics
- Tribute proposals

Happy DAOing!

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

## CALL vs DELEGATECALL

Proposals specify an **operation type** (`op`):

| Op | Name | What it does |
|----|------|--------------|
| 0 | CALL | Ask the target contract to do something |
| 1 | DELEGATECALL | Borrow the target's code and run it as if it were the DAO's own |

> **Analogy**: CALL is like mailing a letter asking someone to do a task for you. DELEGATECALL is like borrowing their recipe book and cooking in your own kitchen—the recipe runs, but your ingredients get used.

**When to use which:**
- **CALL (op=0)**: Most governance actions—calling the DAO's own functions, sending ETH, interacting with external contracts
- **DELEGATECALL (op=1)**: Advanced use cases like upgrades or plugins where external code needs to modify the DAO's storage directly

In this tutorial, we use CALL because the DAO is simply calling its own `setRagequittable` function.

---

## Step 1: Setup

Create `toggle-ragequit.js`. The setup code is identical to the previous tutorial through Step 3:

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

## Step 2: Import ABIs

Like in the previous tutorial, import the ABI JSON files:

```javascript
import Moloch from './Moloch.json' with { type: 'json' };
import MolochViewHelper from './MolochViewHelper.json' with { type: 'json' };
```

### New Functions We'll Use

We'll use `getDAOFullState` again (same as tutorial 2). Here are the **new** Moloch functions:

| Function | Inputs | Output | Purpose |
|----------|--------|--------|---------|
| `config()` | none | `uint256` | Current config version (for proposal ID computation) |
| `state(id)` | `uint256` | `uint8` | Proposal state (0-6) |
| `castVote(id, support)` | `uint256`, `uint8` | none | Vote on a proposal |
| `executeByVotes(op, to, value, data, nonce)` | `uint8`, `address`, `uint256`, `bytes`, `bytes32` | none | Execute a passed proposal |
| `setRagequittable(on)` | `bool` | none | Toggle ragequit (the function we're calling via governance) |

---

## Step 3: Connect and Read Current State

```javascript
const STATE_NAMES = ['Unopened', 'Active', 'Queued', 'Succeeded', 'Defeated', 'Expired', 'Executed'];

// Setup provider and wallet
const provider = new ethers.JsonRpcProvider(RPC_URL);
const wallet = new ethers.Wallet(PRIVATE_KEY, provider);
console.log('Connected to Sepolia');
console.log(`Wallet: ${wallet.address}\n`);

const viewHelper = new ethers.Contract(VIEW_HELPER_ADDRESS, MolochViewHelper.abi, provider);
const dao = new ethers.Contract(DAO_ADDRESS, Moloch.abi, wallet);

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
const iface = new ethers.Interface(Moloch.abi);

// Encode the function call: setRagequittable(!currentRagequit)
const data = iface.encodeFunctionData('setRagequittable', [!currentRagequit]);

console.log(`Encoded calldata: ${data}`);
// This will be something like: 0x12345678...
```

**Interface** is ethers.js's way to work with ABIs. `encodeFunctionData` converts a function name and arguments into the bytes that the EVM expects.

> **Analogy**: Think of encoding as writing a machine-readable instruction. The first 4 bytes are the "subject line" (which function to call), and the rest is the "body" (the arguments). Contracts only understand this packed byte format.

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
```

**What is `ethers.id()`?** It's shorthand for `keccak256(toUtf8Bytes(text))`. It takes a string, converts it to bytes, and hashes it. We use it here to generate a unique 32-byte nonce from a human-readable string.

```javascript
// Get current config version
const config = await dao.config();
```

**What does "config version" do?** The `config` is a counter the DAO can increment via `bumpConfig()`. Since `config` is part of the proposal ID hash, bumping it invalidates all previously computed (but not yet submitted) proposal IDs. This is useful when the DAO wants to "reset"—for example, after changing governance rules—so old pending proposals can't be submitted under the new regime.

```javascript
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

**What is `keccak256`?** It's the cryptographic hash function used throughout Ethereum (sometimes called SHA-3, though technically different). Given any input, it produces a fixed 32-byte output. Key properties:
- **Deterministic**: Same input always produces the same output
- **One-way**: You can't reverse-engineer the input from the output
- **Collision-resistant**: It's practically impossible to find two different inputs with the same output

`ethers.keccak256()` takes bytes (like encoded data) and returns the hash. Combined with `AbiCoder.encode()`, it produces the same result as Solidity's `keccak256(abi.encode(...))`.

> **Analogy**: The proposal ID is like a fingerprint—computable before the proposal "exists" on-chain. This fingerprint combines: the DAO address, operation type (CALL), target, value, calldata hash, nonce, and config version. Anyone with the same inputs gets the same ID.

---

## Step 5.5: Post Proposal Description (Optional)

When you create a proposal through the Majeur dapp, it automatically posts a message to the DAO's on-chain chatroom with the proposal details. This allows the dapp to show a human-readable description and mark the proposal as "verified."

If you submit a proposal via script without posting this message, the dapp will show it as **"⚠ Unverified"**—the proposal works fine, but the dapp can't display what it does.

**The chat message format:**
```
<<<PROPOSAL_DATA
{"type":"PROPOSAL","description":"...","op":0,"to":"...","value":"...","data":"...","nonce":"..."}
PROPOSAL_DATA>>>
```

The dapp parses this, recomputes the proposal ID, and matches it to verify the proposal's integrity.

**Badge requirement:** Posting to the DAO chat requires a **badge**—an SBT (Soul-Bound Token) automatically minted to the top 256 shareholders. If you're not in the top 256, this step will fail (which is fine—your proposal still works).

```javascript
// Optional: Post proposal description to DAO chat
const description = `Toggle ragequit from ${currentRagequit} to ${!currentRagequit}`;
const proposalMessage = `<<<PROPOSAL_DATA
${JSON.stringify({
  type: 'PROPOSAL',
  description,
  op,
  to,
  value: value.toString(),
  data,
  nonce
})}
PROPOSAL_DATA>>>`;

try {
  const chatTx = await dao.chat(proposalMessage);
  await chatTx.wait();
  console.log('Proposal description posted to chat');
} catch (e) {
  // This fails if you don't have a badge (not in top 256 shareholders)
  console.log('Could not post to chat (badge required):', e.reason || e.message);
}
```

> **Note**: This step is optional. Your proposal will execute successfully either way—the chat message just helps the dapp display a nice description instead of "Unverified."

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

> **Analogy**: Voting is like signing a petition. The first signature "opens" the petition (creates on-chain state). Your voting power equals your share balance at the snapshot block—a frozen moment in time that prevents manipulation.

---

## Step 7: Check If Executable

After voting, check if the proposal has passed:

```javascript
// Re-check proposal state
proposalState = await dao.state(proposalId);
console.log(`\nProposal state after voting: ${STATE_NAMES[Number(proposalState)]}`);
```

For a refresher on proposal states, see [Tutorial 2](0-to-hero-2.md#step-7-find-active-unvoted-proposals).

> **Analogy**: Think of proposals like bills in a legislature: Unopened (not yet introduced), Active (floor debate), Queued (waiting period), Succeeded (approved), Defeated (rejected), Expired (ran out of time), Executed (now law).

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

> **Analogy**: Execution is the DAO "doing" what it voted on. Since we used CALL, the DAO calls `setRagequittable` on itself—like sending yourself a formal letter that you then act on. The contract's `onlyDAO` check passes because the DAO is the one making the call.

---

## Complete Script

```javascript
// toggle-ragequit.js
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

const STATE_NAMES = ['Unopened', 'Active', 'Queued', 'Succeeded', 'Defeated', 'Expired', 'Executed'];

// Setup provider and wallet
const provider = new ethers.JsonRpcProvider(RPC_URL);
const wallet = new ethers.Wallet(PRIVATE_KEY, provider);
console.log('Connected to Sepolia');
console.log(`Wallet: ${wallet.address}\n`);

const viewHelper = new ethers.Contract(VIEW_HELPER_ADDRESS, MolochViewHelper.abi, provider);
const dao = new ethers.Contract(DAO_ADDRESS, Moloch.abi, wallet);

// Get current state
const state = await viewHelper.getDAOFullState(DAO_ADDRESS, 0, 0, 0, 0, []);
const currentRagequit = state.gov.ragequittable;
console.log(`Current ragequit: ${currentRagequit} -> toggling to: ${!currentRagequit}\n`);

// Encode the governance call
const iface = new ethers.Interface(Moloch.abi);
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

// Optional: Post proposal description to chat (requires badge)
const description = `Toggle ragequit from ${currentRagequit} to ${!currentRagequit}`;
const proposalMessage = `<<<PROPOSAL_DATA
${JSON.stringify({ type: 'PROPOSAL', description, op, to, value: value.toString(), data, nonce })}
PROPOSAL_DATA>>>`;

try {
  const chatTx = await dao.chat(proposalMessage);
  await chatTx.wait();
  console.log('Proposal posted to chat');
} catch (e) {
  console.log('Chat post skipped (badge required)');
}

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
Proposal posted to chat       (or "Chat post skipped" if no badge)
Casting vote FOR...
Vote cast! Tx: 0xabcd...
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

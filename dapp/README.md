# Moloch Majeur dApp

A single-page HTML dApp for DAO governance, designed to be pinned to IPFS and hosted on ENS.

## Development

### Quick Start

Install live-server (one-time setup):
```bash
npm install -g live-server
```

Start the development server with hot reload:
```bash
cd dapp
live-server --port=8080 --host=0.0.0.0 --open=Majeur.html
```

The server will automatically reload your browser whenever you save changes to `Majeur.html`.

### Alternative: Python Server

If you prefer a simple server without auto-reload:
```bash
cd dapp
python3 -m http.server 8080
```

Then open http://localhost:8080/Majeur.html in your browser.

## Deployment

This dApp is designed to be deployed to IPFS and accessed via ENS. The entire application is contained in a single HTML file for simplicity and portability.

## Features

### DAO Gallery & Dashboard Integration

The dApp includes a complete DAO management system that integrates with the View Helper contract deployed at `0x000000000066317bd3662A649D8901c076268Df9` on Ethereum Mainnet.

#### 1. DAO Gallery View
- **Automatic Discovery**: When you connect your wallet, the dApp automatically fetches all DAOs where you are a member (have shares or loot)
- **Tile Display**: Shows each DAO as a clickable tile with:
  - DAO name and symbol
  - Your shares and loot balance
  - Number of proposals
  - Number of messages
- **Smart Detection**: Uses the View Helper's `getUserDAOsFullState` function with default parameters (10 DAOs, 10 proposals, 10 messages)

#### 2. DAO Dashboard
Click any DAO tile to open its dedicated dashboard with two main panels:

**Chatroom Panel:**
- Message display with proposal highlighting
- Send new messages to the DAO
- Auto-scroll to latest messages
- Tagged proposal messages are visually distinct

**Proposals Panel:**
- **Create Proposals**: Fill in operation type, target address, value, calldata, nonce, and description
  - System automatically computes proposal ID using Moloch's `_intentHashId` logic
  - Encodes proposal data as tagged message
  - Uses `multicall()` to atomically: post message to chat AND open proposal
  - Verifies on-chain proposal ID matches computed ID
  - Shows verification result after creation
- **View Proposals**: Display all proposals with state, vote counts, and descriptions
  - Each proposal shows verification badge (✓ Verified) if its ID matches the hash computed from tagged message data
  - Proposals without matching tagged messages are shown without verification
- **Vote**: Submit votes (For/Against/Abstain)
- **Execute**: Execute succeeded/queued proposals

#### 3. Proposal Message Tagging System

**Why Messages Store Proposal Data:**

Moloch.sol uses an efficient design where proposals are identified by a hash (proposal ID) rather than storing full call data. This saves gas but requires a way to track what each proposal actually does. The solution: **chat messages as proposal receipts**.

**Message Format:**
```
<<<PROPOSAL_DATA
{
  "type": "PROPOSAL",
  "op": 0,
  "to": "0x...",
  "value": "1000000000000000000",
  "data": "0x...",
  "nonce": "0x...",
  "description": "Send 1 ETH to treasury multisig"
}
PROPOSAL_DATA>>>
```

**How It Works:**

1. **Proposal ID = Hash(dao, op, to, value, keccak256(data), nonce, config)**
   - Only the ID is stored on-chain in Moloch.sol
   - No call data stored = massive gas savings

2. **Chat Message = Source of Truth**
   - Contains all parameters needed to execute
   - Human-readable (raw JSON, not encoded)
   - Permanently on-chain in the same contract

3. **Verification**
   - UI re-hashes the parameters from the message
   - Compares to on-chain proposal ID
   - Shows ✓ badge if they match

4. **Execution**
   - Extract parameters from tagged message
   - Call `executeByVotes(op, to, value, data, nonce)`
   - On-chain verification ensures hash matches

**Benefits:**
- **Gas Efficient**: Moloch.sol doesn't store redundant call data
- **Transparent**: Anyone can read proposals directly in chat
- **Auditable**: All proposal details are on-chain and verifiable
- **Self-Contained**: No need for external indexers or databases

**What You See in the Chat:**

Proposal messages appear with a collapsible details section:

```
[PROPOSAL]
Send 1 ETH to treasury multisig

▼ View execution data
{
  "op": 0,
  "to": "0x1234...",
  "value": "1000000000000000000",
  "data": "0x",
  "nonce": "0xabc..."
}
```

Anyone can verify the proposal by:
1. Copy the execution data from chat
2. Hash it locally: `keccak256(abi.encode(dao, op, to, value, keccak256(data), nonce, config))`
3. Compare to the proposal ID

#### Workflow

1. **Connect Wallet** → Automatically fetches your DAOs
2. **Select DAO** → Opens dashboard with chatroom and proposals
3. **Create Proposal** → Fill form → System multicalls (chat + openProposal) → Verifies hash match
4. **Vote** → Click vote button → Submit transaction
5. **Execute** → When proposal succeeds → Click execute → System extracts parameters and executes

#### Key Features

1. **Transfer Lock Initialization**: Only includes `setTransfersLocked` call in init if user explicitly enables transfers. Default behavior (locked) requires no self-call.

2. **Atomic Proposal Creation**: Uses `multicall()` to combine chat message and proposal opening into a single transaction, ensuring:
   - Tagged message and proposal are created together atomically
   - No possibility of message/proposal mismatch
   - Reduced gas costs and transaction complexity

3. **Verification System**:
   - Computes proposal ID locally before submission
   - Verifies on-chain ID matches computed ID after transaction
   - Displays verification badge on each proposal in the UI
   - Recomputes hash from tagged message data to confirm integrity

4. **Raw JSON Encoding**: Uses human-readable JSON with delimiters instead of base64:
   - **Transparent**: Anyone can read proposal parameters directly in chat
   - **Gas Efficient**: ~33% smaller than base64-encoded messages
   - **Auditable**: No decoding needed to verify what a proposal does
   - **Debug Friendly**: Easier to troubleshoot and verify manually

#### Technical Details

**Contracts Integrated:**
- View Helper: `0x000000000066317bd3662A649D8901c076268Df9`
- Summoner: `0x0000000000330B8df9E3bc5E553074DA58eE9138`

**Key Functions:**
- `getUserDAOsFullState()` - Fetches complete DAO state
- `multicall(bytes[])` - Executes multiple calls atomically (used for chat + openProposal)
- `chat(message)` - Posts message to DAO
- `openProposal(id)` - Opens proposal for voting
- `vote(id, support)` - Submits vote
- `executeByVotes(op, to, value, data, nonce)` - Executes proposal
- `intentHashId(op, to, value, data, nonce)` - Computes proposal ID
- `config()` - Returns DAO configuration hash used in proposal ID computation

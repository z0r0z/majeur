# Majeur dApp

Single-page HTML dApps for DAO governance. No build step, no dependencies — just HTML files you can pin to IPFS and serve from ENS.

**Live:**
- [majeurdao.eth](https://majeurdao.eth.limo/) — DAO governance interface
- [daicowtf.eth](https://daicowtf.eth.limo/) — Token sale interface

## Quick Start

```bash
# Development with hot reload
npm install -g live-server
cd dapp && live-server --port=8080 --open=Majeur.html

# Or simple Python server
cd dapp && python3 -m http.server 8080
```

## Architecture

Each dApp is a self-contained HTML file that:
- Connects via WalletConnect or injected provider
- Reads state from `MolochViewHelper` (batch reads, no indexer needed)
- Writes directly to DAO contracts
- Works on any chain where contracts are deployed
- "Hide Intro" toggle in navbar persists via localStorage for returning users

## Keyboard Hotkeys

Press `0` to show the hotkeys modal. Available shortcuts:

| Key | Action |
|-----|--------|
| 0 | Show hotkeys modal |
| 1 | Focus Summon section |
| 2 | Focus "Your DAOs" |
| 3 | Focus "All DAOs" |
| 4 | Open GitHub / Focus DAO info |
| 5 | Focus Chatroom |
| 6 | Focus Treasury |
| 7 | Focus Active Sales |
| 8 | Focus Proposals |
| Backspace | Go back (Ctrl/Cmd+B) |

*Hotkeys are disabled when typing in input fields.*

## Contracts

| Contract | Address |
|----------|---------|
| MolochViewHelper | `0x00000000006631040967E58e3430e4B77921a2db` |
| Summoner | `0x0000000000330B8df9E3bc5E553074DA58eE9138` |
| DAICO | `0x000000000033e92DB97B4B3beCD2c255126C60aC` |

## Features

### DAO Gallery
Connect wallet → automatically discovers all DAOs where you hold shares or loot. Each DAO shows your balance, proposal count, and message count.

### Dashboard
Click a DAO to open its dashboard:

| Panel | Features |
|-------|----------|
| Chatroom | Read/send messages, proposal tags highlighted |
| Proposals | Create, vote, execute, verify |

### Proposal System

**The Problem:** Storing full calldata on-chain is expensive.

**The Solution:** Moloch stores only a proposal ID (hash). The dApp posts execution parameters to on-chain chat as a tagged JSON message, then verifies the hash matches.

```
<<<PROPOSAL_DATA
{
  "op": 0,
  "to": "0x...",
  "value": "1000000000000000000",
  "data": "0x...",
  "nonce": "0x...",
  "description": "Send 1 ETH to treasury"
}
PROPOSAL_DATA>>>
```

**Workflow:**
1. Fill proposal form
2. dApp computes `proposalId(op, to, value, data, nonce)`
3. `multicall()` atomically posts chat message + opens proposal
4. Anyone can verify: re-hash the chat JSON, compare to on-chain ID
5. Execute: dApp extracts params from chat, calls `executeByVotes()`

**Benefits:**
- Gas efficient — no calldata stored in contract
- Transparent — anyone can read proposals in chat
- Self-contained — no external indexer needed
- Verifiable — ✓ badge shows when ID matches

### Proposal Types

The "Self" button in CREATE PROPOSAL auto-fills the DAO address and offers these governance actions:

| Category | Action | Description |
|----------|--------|-------------|
| **Metadata** | Set Metadata | Update DAO name, symbol, description, image |
| | Change Renderer | Set custom NFT renderer contract |
| **Voting** | Set Quorum (BPS) | Minimum turnout as basis points (e.g., 1000 = 10%) |
| | Set Absolute Quorum | Minimum total votes required (works with BPS) |
| | Set Min YES Votes | Absolute minimum FOR votes to pass |
| | Set Vote Threshold | Shares required to create proposals |
| **Timing** | Set Proposal TTL | How long proposals stay open |
| | Set Timelock Delay | Delay before execution after passing |
| **Tokens** | Toggle Ragequit | Enable/disable member exit with funds |
| | Toggle Transferability | Lock/unlock shares and loot transfers |
| **Futarchy** | Configure Auto-Futarchy | Set prediction market parameters |
| | Set Futarchy Reward Token | Default token for pool rewards |

For custom actions, use "Just fill address" and manually specify calldata.

## DAO Metadata

DAOs can store metadata as a JSON URI (IPFS, HTTPS, or data URI). The METADATA tab displays and allows updating this info.

See [`assets/dao-metadata-example.json`](../assets/dao-metadata-example.json) for a complete example:

```json
{
  "name": "My DAO",
  "symbol": "MYDAO",
  "description": "A description of the DAO",
  "image": "ipfs://... or data:image/svg+xml;base64,...",
  "treasury_tokens": [
    { "symbol": "USDC", "address": "0x..." },
    { "symbol": "WETH", "address": "0x..." }
  ]
}
```

**Fields:**
- `name`, `symbol`, `description` — Basic info shown in gallery and dashboard
- `image` — Avatar (IPFS, HTTPS, or base64 data URI)
- `treasury_tokens` — Custom tokens to display in Treasury (ETH is always first automatically)

## Key Functions

### Moloch DAO
| Function | Purpose |
|----------|---------|
| `multicall(bytes[])` | Batch calls (chat + openProposal) |
| `chat(message)` | Post to chatroom |
| `castVote(id, support)` | Vote (0=Against, 1=For, 2=Abstain) |
| `executeByVotes(op, to, value, data, nonce)` | Execute passed proposal |
| `proposalId(op, to, value, data, nonce)` | Compute proposal hash |

### MolochViewHelper
| Function | Purpose |
|----------|---------|
| `getUserDAOsFullState(user, ...)` | All DAOs where user is member |
| `getDAOFullState(dao, ...)` | Complete state for one DAO |
| `getDAOMessages(dao, start, count)` | Paginated chat |
| `scanDAICOs(...)` | Find active token sales |

## Deployment

Pin to IPFS, set as ENS contenthash. That's it.

```bash
# Example with ipfs-car
ipfs-car pack Majeur.html > majeur.car
# Upload car to web3.storage or similar
# Set ENS contenthash to ipfs://Qm...
```

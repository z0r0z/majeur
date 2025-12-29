# Repository Structure

This guide explains every folder and file in the Majeur repository, with notes on when and what you might want to modify.

## Overview

```
majeur/
├── src/                    # Smart contracts (Solidity)
├── scripts/                # Helper scripts (JavaScript/TypeScript)
├── test/                   # Test suite (Foundry)
├── dapp/                   # Frontend applications (HTML)
├── docs/                   # Documentation (mdBook)
├── assets/                 # SVG diagrams and examples
├── lib/                    # Git submodule dependencies
├── foundry.toml            # Foundry configuration
├── README.md               # Main documentation
└── LICENSE                 # MIT license
```

---

## Root Files

### `foundry.toml`
Foundry project configuration. Contains:
- Solidity compiler version (0.8.30)
- Optimization settings (245 runs, via_ir enabled)
- Remappings for dependencies
- RPC endpoints for different networks

**When to modify**: Add new network RPC URLs, change compiler settings, or add new remappings.

### `README.md`
Comprehensive documentation covering:
- Feature comparison with other DAO frameworks
- Contract addresses (all networks)
- Core concepts (ragequit, futarchy, split delegation)
- Quick start code examples
- Complete API reference

**When to modify**: Update after adding new features or changing APIs.

### `LICENSE`
MIT license. Copyright z0r0z.

### `.gitmodules`
Defines git submodule dependencies:
- `solady` — Optimized Solidity utilities
- `forge-std` — Foundry testing framework
- `ZAMM` — AMM/liquidity protocol for DAICO LP features

**When to modify**: Add new dependencies or update versions.

---

## `src/` — Smart Contracts

This is the core of the project. All Solidity contracts live here.

### `src/Moloch.sol`
**The main DAO contract** (~2100 lines). Contains:

| Contract | Purpose |
|----------|---------|
| `Moloch` | Governance logic, voting, execution, ragequit, futarchy, token sales, badges, chat |
| `Shares` | ERC-20 voting token with split delegation (deployed as separate clone) |
| `Loot` | ERC-20 non-voting economic token (deployed as separate clone) |
| `Badges` | ERC-721 soulbound NFTs for top 256 shareholders (deployed as separate clone) |
| `Summoner` | Factory that deploys new DAOs via CREATE2 |

**Key functions you'll interact with**:
- `castVote(id, support)` — Vote on a proposal
- `executeByVotes(op, to, value, data, nonce)` — Execute a passed proposal
- `ragequit(tokens, shares, loot)` — Exit with treasury share
- `proposalId(op, to, value, data, nonce)` — Compute proposal ID
- `state(id)` — Get proposal state
- `hasVoted(id, voter)` — Check if address has voted

**When to modify**: Rarely. This is audited core logic. Fork if you need different governance mechanics.

### `src/Renderer.sol`
On-chain SVG metadata generator. Creates visual cards for:
- DAO contracts
- Proposals
- Vote receipts
- Permits
- Badges

Includes the Wyoming DUNA legal covenant text.

**When to modify**: Customize the visual appearance of NFT metadata.

### `src/peripheral/MolochViewHelper.sol`
**Batch reader for dApps**. This is what you'll use to efficiently read DAO state.

Key function:
```solidity
function getDAOFullState(
    address dao,
    uint256 proposalStart,
    uint256 proposalCount,
    uint256 messageStart,
    uint256 messageCount,
    address[] calldata treasuryTokens
) external view returns (DAOLens memory)
```

Returns a `DAOLens` struct containing:
- `meta` — Name, symbol, token addresses, renderer
- `gov` — Governance config (thresholds, quorum, TTL, timelock, ragequit status)
- `supplies` — Token supply information
- `treasury` — Token balances
- `members` — All members with shares, loot, voting power, delegates
- `proposals` — Proposals with tallies, voters, futarchy data
- `messages` — Chat messages

**When to modify**: Add new view functions for custom dApp needs.

### `src/peripheral/DAICO.sol`
Token sale contract with tap mechanism (Vitalik's DAICO concept):
- Fixed-price OTC sales
- Tap mechanism for controlled fund release
- Optional LP integration with ZAMM

**Key functions**:
- `buy(dao, tribTkn, payAmt, minBuyAmt)` — Purchase tokens
- `claimTap(dao)` — Release vested funds to ops team
- `setSale(...)` — Configure a sale (DAO only)

**When to modify**: Add new sale mechanics or integrate with different AMMs.

### `src/peripheral/Tribute.sol`
OTC escrow for membership trades. Users lock assets and propose a trade to the DAO.

**Key functions**:
- `proposeTribute(...)` — Lock assets, create offer
- `cancelTribute(...)` — Withdraw locked tribute
- `claimTribute(...)` — DAO accepts and executes swap

**When to modify**: Add support for different asset types or trade structures.

---

## `scripts/` — Helper Scripts

### `scripts/scripts-for-beginners/get-dao-info.js`
Example script that reads DAO state using `MolochViewHelper`. Shows:
- How to connect to an RPC
- How to use the view helper ABI
- How to parse returned data

**When to use**: Reference implementation for reading DAO state.

### `scripts/scripts-for-beginners/set-dao-metadata.js`
Interactive script that generates proposal data for setting DAO metadata.

**When to use**: Template for building proposal generation tools.

### `scripts/create2-predictor.ts`
TypeScript implementation for predicting DAO addresses before deployment. Uses minimal proxy bytecode calculation.

**When to use**: Build UIs that show users their DAO address before they deploy.

### `scripts/simple-create2-predictor.js`
Minimal JavaScript version of the CREATE2 predictor. Browser-compatible.

### `scripts/get-implementations.js`
Fetches implementation addresses from the deployed Summoner contract.

---

## `test/` — Test Suite

Foundry test files. Run with `forge test`.

| File | Coverage |
|------|----------|
| `Moloch.t.sol` | Core governance, voting, delegation, execution, ragequit, futarchy, badges |
| `DAICO.t.sol` | Token sales, tap mechanism, LP config |
| `Tribute.t.sol` | OTC escrow flows |
| `MolochViewHelper.t.sol` | Batch read functions |
| `ContractURI.t.sol` | On-chain metadata, DUNA covenant |
| `URIVisualization.t.sol` | SVG rendering |
| `Bytecodesize.t.sol` | Contract size limits |

**When to modify**: Add tests for new features or edge cases.

---

## `dapp/` — Frontend Applications

### `dapp/Majeur.html`
**Main governance UI**. A single HTML file with no build step. Features:
- DAO gallery and discovery
- Proposal management and voting
- Member chat (badge-gated)
- Treasury tracking
- Delegation management

Uses ethers.js from CDN. Connects via WalletConnect or injected provider (MetaMask).

**When to modify**: Customize the UI, add new features, change styling.

### `dapp/DAICO.html`
Token sale interface. Browse sales, buy tokens, track tap claims.

### `dapp/README.md`
Documentation for the dApp. Development setup, architecture, deployment.

---

## `docs/` — Documentation

Auto-generated contract documentation using mdBook.

| File | Purpose |
|------|---------|
| `book.toml` | mdBook configuration |
| `book.css` | Custom styling |
| `solidity.min.js` | Syntax highlighting for Solidity |
| `src/` | Markdown files (auto-generated from contracts) |

**When to modify**: Usually auto-generated. Manual edits to `book.toml` for config changes.

---

## `assets/` — Visual Assets

SVG diagrams and examples:
- `architecture.svg` — System architecture diagram
- `proposal-lifecycle.svg` — Proposal state machine
- `dao-contract-card.svg` — Example DAO card
- `proposal-card.svg` — Example proposal card
- `vote-receipt-cards.svg` — Vote receipt examples
- `badge-card.svg` — Badge NFT card
- `permit-card.svg` — Permit card
- `dao-metadata-example.json` — Template for DAO metadata

**When to modify**: Update diagrams when architecture changes, add new examples.

---

## `lib/` — Dependencies

Git submodules. Don't modify directly.

| Submodule | Purpose |
|-----------|---------|
| `solady` | Gas-optimized Solidity utilities (ERC20, ERC721, etc.) |
| `forge-std` | Foundry testing framework |
| `ZAMM` | AMM/liquidity protocol |

**To update**: `git submodule update --remote lib/solady`

---

## Contract Addresses

All contracts use CREATE2, so they have the **same address on every network**:

| Contract | Address |
|----------|---------|
| Summoner | `0x0000000000330B8df9E3bc5E553074DA58eE9138` |
| Renderer | `0x000000000011C799980827F52d3137b4abD6E654` |
| MolochViewHelper | `0x00000000006631040967E58e3430e4B77921a2db` |
| Tribute | `0x000000000066524fcf78Dc1E41E9D525d9ea73D0` |
| DAICO | `0x000000000033e92DB97B4B3beCD2c255126C60aC` |

---

**Next**: [Unvoted Proposals & Rewards →](0-to-hero-2.md)

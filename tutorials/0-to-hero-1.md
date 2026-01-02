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
├── tutorials/              # Zero to Hero tutorial series
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

### `README.md`
- Obvious. You should read this.

### `LICENSE`
MIT license. Copyright z0r0z.

### `.gitmodules`
Defines git submodule dependencies:
- `solady` — Optimized Solidity utilities
- `forge-std` — Foundry testing framework
- `ZAMM` — AMM/liquidity protocol, also created by z0r0z: <https://github.com/z0r0z/ZAMM>

---

## `src/` — Smart Contracts

This is the core of the project. All Solidity contracts live here.

### `src/Moloch.sol`
**The main DAO contract** (~2100 lines). Contains:

| Contract | Purpose |
|----------|---------|
| `Moloch` | Governance logic, voting, execution, ragequit, futarchy, token sales, badges, chat |
| `Shares` | ERC-20 voting token with split delegation |
| `Loot` | ERC-20 non-voting economic token |
| `Badges` | ERC-721 soulbound NFTs for top 256 shareholders |
| `Summoner` | Factory that deploys new DAOs via CREATE2

When the Moloch implementation is created, it deploys full implementation contracts for Shares, Badges, and Loot. When a new DAO is created, it creates minimal proxy clones for Shares, Badges, and Loot. Each clone is ~54 bytes and delegates all calls to the shared implementation. Each clone maintains its own balances, supply, etc. Cloning is cheaper than deploying full contracts. Using CREATE2, the clone addresses are predictable based on the DAO's address (used as the salt).

**Key functions you'll interact with**:
- `castVote(id, support)` — Vote on a proposal
- `executeByVotes(op, to, value, data, nonce)` — Execute a passed proposal
- `ragequit(tokens, shares, loot)` — Exit with treasury share
- `proposalId(op, to, value, data, nonce)` — Compute proposal ID
- `state(id)` — Get proposal state
- `hasVoted(id, voter)` — Check if address has voted

### `src/Renderer.sol`
On-chain SVG metadata generator. Creates visual cards for:
- DAO contracts
- Proposals
- Vote receipts
- Permits
- Badges

Includes the Wyoming DUNA legal covenant text.

SVG (Scalable Vector Graphics) is a web-friendly, XML-based file format for creating two-dimensional vector images that can be infinitely scaled without losing quality.

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

### `scripts/scripts-for-beginners/set-dao-metadata.js`
Interactive script that generates proposal data for setting DAO metadata. It helps you understand the different ways in which metadata could be provided.

### `scripts/create2-predictor.ts`
TypeScript implementation for predicting DAO addresses before deployment. Uses minimal proxy bytecode calculation.

### `scripts/simple-create2-predictor.js`
Minimal JavaScript version of the CREATE2 predictor. Browser-compatible.

### `scripts/get-implementations.js`
Fetches implementation addresses from the deployed Summoner contract.

### `scripts/DeploymentPredictor.sol`
Helper contract to predict Moloch DAO and token clone deployment addresses. Can be used on-chain or off-chain via eth_call.

### etc. (some help files)

---

## `test/` — Test Suite

Foundry test files. To run all tests, use `forge test`.

> **Tip:** If you don't have `forge` installed globally, you can install it via Foundryup:
>
> ```bash
> curl -L https://foundry.paradigm.xyz | bash
> foundryup
> ```
>
> This makes the `forge`, `cast`, and `anvil` commands available system-wide.

| File | Coverage |
|------|----------|
| `Moloch.t.sol` | Core governance, voting, delegation, execution, ragequit, futarchy, badges |
| `DAICO.t.sol` | Token sales, tap mechanism, LP config |
| `Tribute.t.sol` | OTC escrow flows |
| `MolochViewHelper.t.sol` | Batch read functions |
| `ContractURI.t.sol` | On-chain metadata, DUNA covenant |
| `URIVisualization.t.sol` | SVG rendering |
| `Bytecodesize.t.sol` | Contract size limits |

---

## `dapp/` — Frontend Applications

### `dapp/Majeur.html`
**Main governance UI**. A single HTML file with no build step. Features:
- DAO gallery and discovery
- Proposal management and voting
- Member chat (badge-gated)
- Treasury tracking
- Delegation management

Uses ethers.js from CDN. Connects via WalletConnect or injected provider (MetaMask, OKX, etc.).

**When to modify**: Customize the UI, add new features, change styling, maybe even make your own for your particular DAO starting from this one.

### `dapp/DAICO.html`
Token sale interface. Browse sales, buy tokens, track tap claims.

### `dapp/README.md`
Documentation for the dApps. Development setup, architecture, deployment.

---

## `tutorials/` — Zero to Hero Tutorial Series

Step-by-step tutorials for learning Majeur, from beginner to expert.

| File | Topic |
|------|-------|
| `0-to-hero-0.md` | Introduction — Course overview and setup |
| `0-to-hero-1.md` | Repository Structure — Understanding every folder and file (you are here!) |
| `0-to-hero-2.md` | Unvoted Proposals & Rewards — Reading DAO state and claiming futarchy rewards |
| `0-to-hero-3.md` | Submit & Execute Proposals — Creating governance proposals and voting |

These tutorials are the source files. They're also symlinked into `docs/src/` so they appear in the mdBook alongside the contract documentation.

---

## `docs/` — Documentation

Auto-generated contract documentation using mdBook. The book combines:
- **Contract docs** — Auto-generated from Solidity source via `forge doc`
- **Tutorials** — Linked from `/tutorials/` via symlinks (single source of truth)

| File/Folder | Purpose |
|-------------|---------|
| `book.toml` | mdBook configuration |
| `book.css` | Custom styling |
| `solidity.min.js` | Syntax highlighting for Solidity |
| `src/SUMMARY.md` | Book structure and navigation |
| `src/src/` | Auto-generated contract documentation |
| `src/README.md` | Symlink → `../../README.md` |
| `src/tutorials/` | Symlink → `../../tutorials/` |
| `src/assets/` | Symlink → `../../assets/` |

**Why symlinks?** The tutorials and README exist once at the repo root for GitHub viewing, but are also included in the mdBook via symlinks. This avoids duplication and keeps a single source of truth.

**Generating the documentation**:

0. **Install Rust and mdBook** (if needed):
    ```bash
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
    source $HOME/.cargo/env
    cargo install mdbook
    ```

1. **Generate contract documentation** (from Solidity source):
   ```bash
   forge doc
   ```
   This generates markdown files in `docs/src/src/` from the contract source code.

2. **Build the mdBook**:
   ```bash
   cd docs && mdbook build
   ```
   This creates the HTML output in `docs/book/`.

3. **Preview locally** (optional):
   ```bash
   cd docs && mdbook serve
   ```
   Serves the documentation at `http://localhost:3000` with live reload.

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

---

## `lib/` — Dependencies

Git submodules. Don't modify directly.

| Submodule | Purpose |
|-----------|---------|
| `solady` | Gas-optimized Solidity utilities (ERC20, ERC721, etc.) |
| `forge-std` | Foundry testing framework |
| `ZAMM` | AMM/liquidity protocol |

**To update all submodules**: `git submodule update --remote`

**To update a specific submodule**: `git submodule update --remote lib/solady`

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

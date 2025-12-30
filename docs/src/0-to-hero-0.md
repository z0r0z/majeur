# Zero to Hero: Majeur DAO Framework

Welcome to the Majeur DAO tutorial series. By the end of this course, you'll understand how this repository works, be able to write scripts that interact with the smart contracts, and maybe even update the smart contracts for your specific needs. *You will be a hero instead of the majeour newb that you are now.*

## Who This Is For

You should have:
- **Ethereum fundamentals**: You understand accounts, transactions, gas, and how smart contracts work
- **Programming experience**: You're comfortable with programming concepts, though not necessarily JavaScript
- **Basic Solidity awareness**: You can read simple Solidity code, even if you don't write it

You don't need:
- Prior experience with ethers.js or web3.js
- Knowledge of this specific DAO framework
- Frontend development experience

## What You'll Learn

— What each folder and file does, and when you might want to modify them
- Interacting with the DAOs programatically
— How the smart contracts work
- ... and more!

## Setup

Create a new project folder and install dependencies:

```bash
mkdir majeur-scripts
cd majeur-scripts
npm init -y
npm install ethers dotenv
```

Create a `.env` file for your private key and RPC endpoint:

```bash
# .env
PRIVATE_KEY=your_private_key_here
RPC_URL=https://ethereum-sepolia-rpc.publicnode.com
```

> **Security Note**: Never commit `.env` to version control. If you `git init`, then also add it to `.gitignore`. For these tutorials, use a dedicated test wallet with only Sepolia testnet ETH.

## The DAO We'll Work With

Throughout these tutorials, we'll interact with a real DAO on Sepolia testnet:

| Property | Value |
|----------|-------|
| **Name** | Elite Coders Union |
| **Address** | `0x7a45e6764eCfF2F0eea245ca14a75d6d3d6053b7` |
| **Network** | Sepolia (Chain ID: 11155111) |

You can view this DAO at [majeurdao.eth.limo](https://majeurdao.eth.limo/).

## Course Structure

| Tutorial | Topic |
|----------|-------|
| [1. Repository Structure](0-to-hero-1.md) | Understanding every folder and file |
| [2. Unvoted Proposals & Rewards](0-to-hero-2.md) | Reading DAO state and claiming futarchy rewards |
| [3. Submit & Execute Proposals](0-to-hero-3.md) | Creating governance proposals and voting |

## Key Concepts Preview

### The Moloch Pattern
Majeur DAOs can be configured to be "Moloch-style", which is a type of DAO where members can **ragequit** — burn their shares + loot and leave with their proportional percentage of the treasury. This protects minorities from majority tyranny.

### Deterministic Addresses
All contracts use CREATE2, so they have the **same address on every network** (Ethereum, Sepolia, Base, Arbitrum, etc.). This makes scripts portable.

### On-Chain Everything
No external indexers or databases. All state is read directly from the blockchain using the `MolochViewHelper` contract, which batches reads efficiently.

---

**Next**: [Repository Structure →](0-to-hero-1.md)

#!/bin/bash
set -e

# Reset local Anvil and deploy V2 contracts + test DAOs
# Usage: ./scripts/reset-local.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

# Always use localhost for local Anvil (ignore RPC_URL env var)
LOCAL_RPC="http://localhost:8545"
FORK_URL="${FORK_URL:-https://eth-sepolia.g.alchemy.com/v2/${ALCHEMY_API_KEY:-GGvud8iu8sJI2fF2SEKQ3}}"

# Test users
USER1_KEY="0xc4382ae42dfc444c62f678d6e7b480d468fe9a97018e922ac4cf47ba028d4048"
USER2_KEY="0x40887c48a0c3d55639b0a133bfc757ad0f61540ade8882fa6dc636af8634a752"
USER1_ADDR="0x1475E6FB0Df57Be4D8E9Cb0496e686e95347bb90"
USER2_ADDR="0x4A81cBd1f0AF714F19AF819757Fb688DEf24AA24"

# V2 Contract addresses (deterministic via CREATE2)
SUMMONER="0xC1fE5F7163A3fe20b40f0410Dbdea1D0e4AE0d2A"
VIEW_HELPER="0x851D78aeE76329A0e8E0B8896214976A4059B37c"
# Impl addresses are fetched dynamically from contracts in the report section

echo "╔══════════════════════════════════════════════════════════════════════════════╗"
echo "║                      MAJEUR LOCAL ENVIRONMENT RESET                          ║"
echo "╚══════════════════════════════════════════════════════════════════════════════╝"
echo ""
echo "  Project:  $PROJECT_DIR"
echo "  Local:    $LOCAL_RPC"
echo "  Fork:     Sepolia"
echo ""

# 1. Restart Anvil in tmux dev:1
echo "┌──────────────────────────────────────────────────────────────────────────────┐"
echo "│  [1/4] Restarting Anvil                                                      │"
echo "└──────────────────────────────────────────────────────────────────────────────┘"
tmux send-keys -t dev:1 C-c
sleep 1
tmux send-keys -t dev:1 "anvil --fork-url $FORK_URL --code-size-limit 50000 --chain-id 31337" Enter

echo -n "  Waiting for Anvil"
for i in {1..30}; do
    if cast chain-id --rpc-url "$LOCAL_RPC" &>/dev/null; then
        echo " ✓ (ready)"
        break
    fi
    echo -n "."
    sleep 0.5
done

if ! cast chain-id --rpc-url "$LOCAL_RPC" &>/dev/null; then
    echo " ✗ FAILED"
    exit 1
fi

echo ""

# Common forge flags
FORGE_FLAGS="--rpc-url $LOCAL_RPC --broadcast --code-size-limit 50000"

# 2. Deploy V2 contracts
echo "┌──────────────────────────────────────────────────────────────────────────────┐"
echo "│  [2/4] Deploying V2 Contracts                                                │"
echo "└──────────────────────────────────────────────────────────────────────────────┘"
forge script script/DeployV2.s.sol $FORGE_FLAGS 2>&1 | grep -E "(Summoner|ViewHelper|===)" | sed 's/^/  /'
echo ""

# 3. Deploy test DAOs (Phase 1)
echo "┌──────────────────────────────────────────────────────────────────────────────┐"
echo "│  [3/4] Creating Test DAOs (Phase 1)                                          │"
echo "└──────────────────────────────────────────────────────────────────────────────┘"
forge script script/CreateTestDAOs.s.sol --sig "runPhase1()" $FORGE_FLAGS 2>&1 | grep -E "(DAO [0-9]|User|messages|Phase)" | sed 's/^/  /'
echo ""

# 4. Mine a block
echo "┌──────────────────────────────────────────────────────────────────────────────┐"
echo "│  [4/4] Mining Block for Checkpoint                                           │"
echo "└──────────────────────────────────────────────────────────────────────────────┘"
cast rpc anvil_mine --rpc-url "$LOCAL_RPC" >/dev/null
echo "  Block mined ✓"
echo ""

# ══════════════════════════════════════════════════════════════════════════════════
# FINAL REPORT
# ══════════════════════════════════════════════════════════════════════════════════

echo ""
echo "╔══════════════════════════════════════════════════════════════════════════════╗"
echo "║                           DEPLOYMENT REPORT                                  ║"
echo "╚══════════════════════════════════════════════════════════════════════════════╝"
echo ""

# Fetch implementation addresses from contracts
MOLOCH_IMPL=$(cast call $SUMMONER "molochImpl()(address)" --rpc-url "$LOCAL_RPC")
SHARES_IMPL=$(cast call $MOLOCH_IMPL "sharesImpl()(address)" --rpc-url "$LOCAL_RPC")
BADGES_IMPL=$(cast call $MOLOCH_IMPL "badgesImpl()(address)" --rpc-url "$LOCAL_RPC")
LOOT_IMPL=$(cast call $MOLOCH_IMPL "lootImpl()(address)" --rpc-url "$LOCAL_RPC")

# V2 Contracts
echo "┌──────────────────────────────────────────────────────────────────────────────┐"
echo "│  V2 CONTRACT ADDRESSES                                                       │"
echo "├──────────────────────────────────────────────────────────────────────────────┤"
echo "│  Summoner:      $SUMMONER                │"
echo "│  ViewHelper:    $VIEW_HELPER                │"
echo "├──────────────────────────────────────────────────────────────────────────────┤"
echo "│  Moloch Impl:   $MOLOCH_IMPL                │"
echo "│  Shares Impl:   $SHARES_IMPL                │"
echo "│  Badges Impl:   $BADGES_IMPL                │"
echo "│  Loot Impl:     $LOOT_IMPL                │"
echo "└──────────────────────────────────────────────────────────────────────────────┘"
echo ""

# Test Users
echo "┌──────────────────────────────────────────────────────────────────────────────┐"
echo "│  TEST USERS                                                                  │"
echo "├──────────────────────────────────────────────────────────────────────────────┤"
echo "│                                                                              │"
echo "│  USER 1 (Deployer)                                                           │"
echo "│  ├─ Address:     $USER1_ADDR                │"
echo "│  └─ Private Key: $USER1_KEY  │"
echo "│                                                                              │"
echo "│  USER 2                                                                      │"
echo "│  ├─ Address:     $USER2_ADDR                │"
echo "│  └─ Private Key: $USER2_KEY  │"
echo "│                                                                              │"
echo "└──────────────────────────────────────────────────────────────────────────────┘"
echo ""

# Get DAO addresses
DAO1=$(cast call $SUMMONER "daos(uint256)(address)" 0 --rpc-url "$LOCAL_RPC")
DAO2=$(cast call $SUMMONER "daos(uint256)(address)" 1 --rpc-url "$LOCAL_RPC")
DAO3=$(cast call $SUMMONER "daos(uint256)(address)" 2 --rpc-url "$LOCAL_RPC")
DAO4=$(cast call $SUMMONER "daos(uint256)(address)" 3 --rpc-url "$LOCAL_RPC")
DAO5=$(cast call $SUMMONER "daos(uint256)(address)" 4 --rpc-url "$LOCAL_RPC")

# Helper function to get shares balance in human readable format
get_shares() {
    local dao=$1
    local user=$2
    local shares_addr=$(cast call $dao "shares()(address)" --rpc-url "$LOCAL_RPC")
    local bal=$(cast call $shares_addr "balanceOf(address)(uint256)" $user --rpc-url "$LOCAL_RPC")
    # Convert wei to ether and format
    echo $bal | awk '{printf "%.0f", $1/1e18}'
}

# DAO Details
echo "┌──────────────────────────────────────────────────────────────────────────────┐"
echo "│  DEPLOYED DAOs                                                               │"
echo "└──────────────────────────────────────────────────────────────────────────────┘"
echo ""

# DAO 1: Alpha DAO
U1_BAL=$(get_shares $DAO1 $USER1_ADDR)
U2_BAL=$(get_shares $DAO1 $USER2_ADDR)
echo "  ┌────────────────────────────────────────────────────────────────────────────┐"
echo "  │  1. ALPHA DAO                                                              │"
echo "  ├────────────────────────────────────────────────────────────────────────────┤"
echo "  │  Address: $DAO1                              │"
echo "  │                                                                            │"
echo "  │  Settings:                                                                 │"
echo "  │    • Quorum: 50% (5000 BPS)                                                │"
echo "  │    • Proposal TTL: 7 days                                                  │"
echo "  │    • Timelock Delay: 1 day                                                 │"
echo "  │    • Ragequit: Enabled                                                     │"
echo "  │    • Ragequit Timelock: 7 days (default)                                   │"
echo "  │                                                                            │"
printf "  │  Shares:  User 1: %-6s  │  User 2: %-6s                               │\n" "$U1_BAL" "$U2_BAL"
echo "  │                                                                            │"
echo "  │  Activity:                                                                 │"
echo "  │    ★ Users 1 & 2 held a conversation of 40 chat messages                   │"
echo "  │      (alternating senders, testing the SBT-gated chat feature)             │"
echo "  └────────────────────────────────────────────────────────────────────────────┘"
echo ""

# DAO 2: Beta Collective
U1_BAL=$(get_shares $DAO2 $USER1_ADDR)
U2_BAL=$(get_shares $DAO2 $USER2_ADDR)
echo "  ┌────────────────────────────────────────────────────────────────────────────┐"
echo "  │  2. BETA COLLECTIVE                                                        │"
echo "  ├────────────────────────────────────────────────────────────────────────────┤"
echo "  │  Address: $DAO2                              │"
echo "  │                                                                            │"
echo "  │  Settings:                                                                 │"
echo "  │    • Quorum: 25% (2500 BPS)                                                │"
echo "  │    • Proposal TTL: 3 days                                                  │"
echo "  │    • Timelock Delay: None                                                  │"
echo "  │    • Ragequit: Disabled                                                    │"
echo "  │                                                                            │"
printf "  │  Shares:  User 1: %-6s  │  User 2: %-6s                              │\n" "$U1_BAL" "$U2_BAL"
echo "  │                                                                            │"
echo "  │  Activity (after Phase 2):                                                 │"
echo "  │    ★ 15 governance proposals covering ALL proposal types:                  │"
echo "  │      Set Metadata, Change Renderer, Set Quorum (BPS & Absolute),           │"
echo "  │      Set Min YES Votes, Set Vote Threshold, Set Proposal TTL,              │"
echo "  │      Set Timelock Delay, Toggle Ragequit, Toggle Transferability,          │"
echo "  │      Configure Auto-Futarchy, Set Futarchy Reward Token,                   │"
echo "  │      Slash Member (burn shares), DAICO Sale, Set Ragequit Timelock         │"
echo "  │    ★ Users voted on proposals 13-15: FOR, AGAINST, and ABSTAIN             │"
echo "  └────────────────────────────────────────────────────────────────────────────┘"
echo ""

# DAO 3: Solo DAO
U1_BAL=$(get_shares $DAO3 $USER1_ADDR)
U2_BAL=$(get_shares $DAO3 $USER2_ADDR)
echo "  ┌────────────────────────────────────────────────────────────────────────────┐"
echo "  │  3. SOLO DAO                                                               │"
echo "  ├────────────────────────────────────────────────────────────────────────────┤"
echo "  │  Address: $DAO3                              │"
echo "  │                                                                            │"
echo "  │  Settings:                                                                 │"
echo "  │    • Quorum: 100% (10000 BPS) — all members must vote                      │"
echo "  │    • Proposal TTL: 14 days                                                 │"
echo "  │    • Proposal Threshold: 100 shares (~6.7% of supply)                      │"
echo "  │    • Ragequit: Enabled                                                     │"
echo "  │                                                                            │"
printf "  │  Shares:  User 1: %-6s  │  User 2: %-6s                              │\n" "$U1_BAL" "$U2_BAL"
echo "  │                                                                            │"
echo "  │  Activity: None (pristine DAO for testing strict governance)               │"
echo "  └────────────────────────────────────────────────────────────────────────────┘"
echo ""

# DAO 4: Gamma Guild
U1_BAL=$(get_shares $DAO4 $USER1_ADDR)
U2_BAL=$(get_shares $DAO4 $USER2_ADDR)
echo "  ┌────────────────────────────────────────────────────────────────────────────┐"
echo "  │  4. GAMMA GUILD                                                            │"
echo "  ├────────────────────────────────────────────────────────────────────────────┤"
echo "  │  Address: $DAO4                              │"
echo "  │                                                                            │"
echo "  │  Settings:                                                                 │"
echo "  │    • Quorum: 10% (1000 BPS)                                                │"
echo "  │    • Proposal TTL: 5 days                                                  │"
echo "  │    • Timelock Delay: 12 hours                                              │"
echo "  │    • Ragequit: Enabled                                                     │"
echo "  │    • Auto-Futarchy: 0.1% of supply, capped at 5 LOOT per proposal          │"
echo "  │                                                                            │"
printf "  │  Shares:  User 1: %-6s  │  User 2: %-6s                              │\n" "$U1_BAL" "$U2_BAL"
echo "  │                                                                            │"
echo "  │  Activity: None (pristine DAO for testing futarchy features)               │"
echo "  └────────────────────────────────────────────────────────────────────────────┘"
echo ""

# DAO 5: Delta Protocol
U1_BAL=$(get_shares $DAO5 $USER1_ADDR)
U2_BAL=$(get_shares $DAO5 $USER2_ADDR)
echo "  ┌────────────────────────────────────────────────────────────────────────────┐"
echo "  │  5. DELTA PROTOCOL                                                         │"
echo "  ├────────────────────────────────────────────────────────────────────────────┤"
echo "  │  Address: $DAO5                              │"
echo "  │                                                                            │"
echo "  │  Settings:                                                                 │"
echo "  │    • Quorum: 1% (100 BPS)                                                  │"
echo "  │    • Proposal TTL: 1 day (fast governance)                                 │"
echo "  │    • Timelock Delay: 1 hour                                                │"
echo "  │    • Ragequit: Enabled                                                     │"
echo "  │                                                                            │"
printf "  │  Shares:  User 1: %-6s  │  User 2: %-6s                                 │\n" "$U1_BAL" "$U2_BAL"
echo "  │                                                                            │"
echo "  │  Note: User 2 is NOT a member. Second member is 0x5555...5555              │"
echo "  │  Activity: None (pristine DAO for testing fast governance)                 │"
echo "  └────────────────────────────────────────────────────────────────────────────┘"
echo ""

# Next Steps
echo "┌──────────────────────────────────────────────────────────────────────────────┐"
echo "│  NEXT STEPS                                                                  │"
echo "├──────────────────────────────────────────────────────────────────────────────┤"
echo "│                                                                              │"
echo "│  Run Phase 2 to create governance proposals in Beta Collective:              │"
echo "│                                                                              │"
echo "│    forge script script/CreateTestDAOs.s.sol --sig 'runPhase2()' \\           │"
echo "│      --rpc-url http://localhost:8545 --broadcast --code-size-limit 50000     │"
echo "│                                                                              │"
echo "│  Or use the frontend:                                                        │"
echo "│    http://localhost:8080/Majeur.html                                         │"
echo "│                                                                              │"
echo "└──────────────────────────────────────────────────────────────────────────────┘"
echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "                          LOCAL ENVIRONMENT READY ✓"
echo "═══════════════════════════════════════════════════════════════════════════════"

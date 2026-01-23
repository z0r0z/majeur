#!/bin/bash
set -e

# Reset local Anvil and deploy V2 contracts + test DAOs
# Usage: ./scripts/reset-local.sh [--network <network>]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

# Network selection helper
get_rpc_url() {
    local network="${1:-local}"
    case "$network" in
        local|localhost) echo "http://localhost:8545" ;;
        sepolia)   echo "https://eth-sepolia.g.alchemy.com/v2/${ALCHEMY_API_KEY}" ;;
        ethereum|mainnet) echo "https://eth-mainnet.g.alchemy.com/v2/${ALCHEMY_API_KEY}" ;;
        arbitrum)  echo "https://arb-mainnet.g.alchemy.com/v2/${ALCHEMY_API_KEY}" ;;
        base)      echo "https://base-mainnet.g.alchemy.com/v2/${ALCHEMY_API_KEY}" ;;
        unichain)  echo "https://unichain-mainnet.g.alchemy.com/v2/${ALCHEMY_API_KEY}" ;;
        *) echo "$network" ;;  # Custom RPC URL
    esac
}

# Parse --network flag
NETWORK="${NETWORK:-local}"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --network|-n) NETWORK="$2"; shift 2 ;;
        *) shift ;;
    esac
done

LOCAL_RPC="${RPC_URL:-$(get_rpc_url "$NETWORK")}"
FORK_URL="${FORK_URL:-https://eth-sepolia.g.alchemy.com/v2/${ALCHEMY_API_KEY:-GGvud8iu8sJI2fF2SEKQ3}}"

# Ensure tmux is installed
if ! command -v tmux &>/dev/null; then
    echo "tmux not found. Installing..."
    if command -v apt-get &>/dev/null; then
        sudo apt-get update && sudo apt-get install -y tmux
    elif command -v brew &>/dev/null; then
        brew install tmux
    elif command -v pacman &>/dev/null; then
        sudo pacman -S --noconfirm tmux
    elif command -v dnf &>/dev/null; then
        sudo dnf install -y tmux
    else
        echo "Error: Cannot install tmux. Please install it manually."
        exit 1
    fi
fi

# Ensure tmux 'dev' session exists with required windows
if ! tmux has-session -t dev 2>/dev/null; then
    echo "Creating tmux session 'dev'..."
    tmux new-session -d -s dev -n anvil
    tmux new-window -t dev -n server
    tmux new-window -t dev -n dapps
    echo "  Created windows: anvil (1), server (2), dapps (3)"
fi

# Test users
USER1_KEY="0xc4382ae42dfc444c62f678d6e7b480d468fe9a97018e922ac4cf47ba028d4048"
USER2_KEY="0x40887c48a0c3d55639b0a133bfc757ad0f61540ade8882fa6dc636af8634a752"
USER1_ADDR="0x1475E6FB0Df57Be4D8E9Cb0496e686e95347bb90"
USER2_ADDR="0x4A81cBd1f0AF714F19AF819757Fb688DEf24AA24"

# V2 Contract addresses (deterministic via CREATE2)
SUMMONER="0xdB9aDc369424f08bBd2300571801A0ADAD0B4410"
VIEW_HELPER="0xe4022b04c55ca03ED91B0B666015bA29437B7026"
# Impl addresses are fetched dynamically from contracts in the report section

echo "╔══════════════════════════════════════════════════════════════════════════════╗"
echo "║                      MAJEUR LOCAL ENVIRONMENT RESET                          ║"
echo "╚══════════════════════════════════════════════════════════════════════════════╝"
echo ""
echo "  Project:  $PROJECT_DIR"
echo "  Network:  $NETWORK"
echo "  RPC:      $LOCAL_RPC"
echo "  Fork:     Sepolia"
echo ""

# 1. Restart Anvil in tmux dev:1
echo "┌──────────────────────────────────────────────────────────────────────────────┐"
echo "│  [1/5] Restarting Anvil                                                      │"
echo "└──────────────────────────────────────────────────────────────────────────────┘"

# Kill existing Anvil and wait for port to be free
tmux send-keys -t dev:1 C-c
echo -n "  Stopping old Anvil"
STOPPED=false
for i in {1..20}; do
    if ! ss -tln | grep -q ':8545 '; then
        echo " ✓"
        STOPPED=true
        break
    fi
    echo -n "."
    sleep 0.25
done
[ "$STOPPED" = false ] && echo ""

# Start new Anvil
tmux send-keys -t dev:1 "anvil --fork-url $FORK_URL --code-size-limit 50000 --chain-id 31337 --block-time 1" Enter

# Wait for Anvil to respond to RPC
echo -n "  Waiting for RPC"
for i in {1..30}; do
    if cast chain-id --rpc-url "$LOCAL_RPC" &>/dev/null; then
        echo " ✓"
        break
    fi
    echo -n "."
    sleep 0.5
done

if ! cast chain-id --rpc-url "$LOCAL_RPC" &>/dev/null; then
    echo " ✗ FAILED"
    exit 1
fi

# Verify fork is fully operational (requires fetching remote state)
echo -n "  Verifying fork"
for i in {1..10}; do
    # eth_getBalance on a known Sepolia address forces fork state fetch
    if cast balance 0x0000000000000000000000000000000000000001 --rpc-url "$LOCAL_RPC" &>/dev/null; then
        echo " ✓ (ready)"
        break
    fi
    echo -n "."
    sleep 0.5
done

echo ""

# Common forge flags
FORGE_FLAGS="--rpc-url $LOCAL_RPC --broadcast --code-size-limit 50000"

# Helper: run forge script with retries on transient failures
run_forge() {
    local script="$1"
    local sig="$2"
    local max_retries=3
    local output
    for attempt in $(seq 1 $max_retries); do
        if [ -n "$sig" ]; then
            output=$(forge script "$script" --sig "$sig" $FORGE_FLAGS 2>&1) && { echo "$output"; return 0; }
        else
            output=$(forge script "$script" $FORGE_FLAGS 2>&1) && { echo "$output"; return 0; }
        fi
        if [ $attempt -lt $max_retries ] && echo "$output" | grep -qE "(timed out|connection refused)"; then
            echo "  ⟳ Retry $attempt/$max_retries (transient error)" >&2
            sleep 2
        else
            echo "$output"
            return 1
        fi
    done
}

# 2. Deploy V2 contracts (skip if already deployed on fork)
echo "┌──────────────────────────────────────────────────────────────────────────────┐"
echo "│  [2/5] Deploying V2 Contracts                                                │"
echo "└──────────────────────────────────────────────────────────────────────────────┘"
SUMMONER_CODE=$(cast codesize "$SUMMONER" --rpc-url "$LOCAL_RPC" 2>/dev/null || echo "0")
if [ "$SUMMONER_CODE" != "0" ]; then
    echo "  ✓ Contracts already deployed on fork (Summoner has $SUMMONER_CODE bytes)"
    echo "    Summoner: $SUMMONER"
    echo "    ViewHelper: $VIEW_HELPER"
else
    DEPLOY_OUTPUT=$(run_forge script/DeployV2.s.sol) || {
        echo "  ✗ Deployment failed!"
        echo "$DEPLOY_OUTPUT" | sed 's/^/  /'
        exit 1
    }
    echo "$DEPLOY_OUTPUT" | grep -E "(Summoner|ViewHelper|===)" | sed 's/^/  /'
fi
echo ""

# 3. Deploy test DAOs (Phase 1)
echo "┌──────────────────────────────────────────────────────────────────────────────┐"
echo "│  [3/5] Creating Test DAOs (Phase 1)                                          │"
echo "└──────────────────────────────────────────────────────────────────────────────┘"
DAO_OUTPUT=$(run_forge script/CreateTestDAOs.s.sol "runPhase1()") || {
    echo "  ✗ DAO creation failed!"
    echo "$DAO_OUTPUT" | sed 's/^/  /'
    exit 1
}
echo "$DAO_OUTPUT" | grep -E "(DAO [0-9]|User|messages|Phase)" | sed 's/^/  /'
echo ""

# 4. Mine a block
echo "┌──────────────────────────────────────────────────────────────────────────────┐"
echo "│  [4/5] Mining Block for Checkpoint                                           │"
echo "└──────────────────────────────────────────────────────────────────────────────┘"
cast rpc anvil_mine --rpc-url "$LOCAL_RPC" >/dev/null
echo "  Block mined ✓"
echo ""

# 5. Create governance proposals (Phase 2)
echo "┌──────────────────────────────────────────────────────────────────────────────┐"
echo "│  [5/5] Creating Governance Proposals (Phase 2)                               │"
echo "└──────────────────────────────────────────────────────────────────────────────┘"
PHASE2_OUTPUT=$(run_forge script/CreateTestDAOs.s.sol "runPhase2()") || {
    echo "  ✗ Phase 2 failed!"
    echo "$PHASE2_OUTPUT" | sed 's/^/  /'
    exit 1
}
echo "$PHASE2_OUTPUT" | grep -E "(proposal created|Voting|Phase|votes)" | sed 's/^/  /'
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

# DAO 1: 40 messages
U1_BAL=$(get_shares $DAO1 $USER1_ADDR)
U2_BAL=$(get_shares $DAO1 $USER2_ADDR)
echo "  ┌────────────────────────────────────────────────────────────────────────────┐"
echo "  │  1. 40 MESSAGES                                                            │"
echo "  ├────────────────────────────────────────────────────────────────────────────┤"
printf "  │  Address: %-65s│\n" "$DAO1"
echo "  │                                                                            │"
echo "  │  Settings:                                                                 │"
echo "  │    • Quorum: 50% (5000 BPS)                                                │"
echo "  │    • Proposal TTL: 7 days                                                  │"
echo "  │    • Timelock Delay: 1 day                                                 │"
echo "  │    • Ragequit: Enabled                                                     │"
echo "  │    • Ragequit Timelock: 7 days (default)                                   │"
echo "  │                                                                            │"
printf "  │  Shares:  User 1: %-6s  User 2: %-6s                                   │\n" "$U1_BAL" "$U2_BAL"
echo "  │                                                                            │"
echo "  │  Activity:                                                                 │"
echo "  │    ★ 40 chat messages with dark jokes (alternating senders)                │"
echo "  │    ★ Sale: ~1 ETH = 2,000,000 SHARES (Moloch built-in, very cheap!)        │"
echo "  └────────────────────────────────────────────────────────────────────────────┘"
echo ""

# DAO 2: All gov proposals
U1_BAL=$(get_shares $DAO2 $USER1_ADDR)
U2_BAL=$(get_shares $DAO2 $USER2_ADDR)
echo "  ┌────────────────────────────────────────────────────────────────────────────┐"
echo "  │  2. ALL GOV PROPOSALS                                                      │"
echo "  ├────────────────────────────────────────────────────────────────────────────┤"
printf "  │  Address: %-65s│\n" "$DAO2"
echo "  │                                                                            │"
echo "  │  Settings:                                                                 │"
echo "  │    • Quorum: 25% (2500 BPS)                                                │"
echo "  │    • Proposal TTL: 3 days                                                  │"
echo "  │    • Timelock Delay: None                                                  │"
echo "  │    • Ragequit: Disabled                                                    │"
echo "  │                                                                            │"
printf "  │  Shares:  User 1: %-6s  User 2: %-6s                                   │\n" "$U1_BAL" "$U2_BAL"
echo "  │                                                                            │"
echo "  │  Activity (after Phase 2):                                                 │"
echo "  │    ★ 24 governance proposals covering ALL proposal types                   │"
echo "  │    ★ Users voted on proposals 13-15, 22-24 with varied patterns            │"
echo "  │    ★ Sale: 3 USDF = 1 LOOT (Moloch built-in, 1000 LOOT cap)                │"
echo "  └────────────────────────────────────────────────────────────────────────────┘"
echo ""

# DAO 3: Various tributes
U1_BAL=$(get_shares $DAO3 $USER1_ADDR)
U2_BAL=$(get_shares $DAO3 $USER2_ADDR)
echo "  ┌────────────────────────────────────────────────────────────────────────────┐"
echo "  │  3. VARIOUS TRIBUTES                                                       │"
echo "  ├────────────────────────────────────────────────────────────────────────────┤"
printf "  │  Address: %-65s│\n" "$DAO3"
echo "  │                                                                            │"
echo "  │  Settings:                                                                 │"
echo "  │    • Quorum: 100% (10000 BPS) — all members must vote                      │"
echo "  │    • Proposal TTL: 14 days                                                 │"
echo "  │    • Proposal Threshold: 100 shares (~6.7% of supply)                      │"
echo "  │    • Ragequit: Enabled                                                     │"
echo "  │                                                                            │"
printf "  │  Shares:  User 1: %-6s  User 2: %-6s                                   │\n" "$U1_BAL" "$U2_BAL"
echo "  │                                                                            │"
echo "  │  Activity:                                                                 │"
echo "  │    ★ 3 tribute offers (2 from User1, 1 from User2):                        │"
echo "  │      • 0.1 ETH → 20 WETH (absurd ask)                                      │"
echo "  │      • 100 USDF → 1 ETH                                                    │"
echo "  │      • 0.5 ETH → 1000 USDF (lowballer special)                             │"
echo "  │    ★ DAICO Sale: 1 ETH = 1,000,000 SHARES (no LP, no tap)                  │"
echo "  └────────────────────────────────────────────────────────────────────────────┘"
echo ""

# DAO 4: DAICO Loot Sale
U1_BAL=$(get_shares $DAO4 $USER1_ADDR)
U2_BAL=$(get_shares $DAO4 $USER2_ADDR)
echo "  ┌────────────────────────────────────────────────────────────────────────────┐"
echo "  │  4. DAICO LOOT SALE                                                        │"
echo "  ├────────────────────────────────────────────────────────────────────────────┤"
printf "  │  Address: %-65s│\n" "$DAO4"
echo "  │                                                                            │"
echo "  │  Settings:                                                                 │"
echo "  │    • Quorum: 10% (1000 BPS)                                                │"
echo "  │    • Proposal TTL: 5 days                                                  │"
echo "  │    • Timelock Delay: 12 hours                                              │"
echo "  │    • Ragequit: Enabled                                                     │"
echo "  │    • Auto-Futarchy: 0.1% of supply, capped at 5 LOOT per proposal          │"
echo "  │                                                                            │"
printf "  │  Shares:  User 1: %-6s  User 2: %-6s                                   │\n" "$U1_BAL" "$U2_BAL"
echo "  │                                                                            │"
echo "  │  Activity:                                                                 │"
echo "  │    ★ DAICO: 1 USDF = 3 LOOT, 70% LP, 5% slippage, 30-day deadline          │"
echo "  │    ★ Tap: User1 ops, ~100 USDF/day, 10k USDF budget                        │"
echo "  └────────────────────────────────────────────────────────────────────────────┘"
echo ""

# DAO 5: Full DAICO Test
U1_BAL=$(get_shares $DAO5 $USER1_ADDR)
U2_BAL=$(get_shares $DAO5 $USER2_ADDR)
echo "  ┌────────────────────────────────────────────────────────────────────────────┐"
echo "  │  5. FULL DAICO TEST                                                        │"
echo "  ├────────────────────────────────────────────────────────────────────────────┤"
printf "  │  Address: %-65s│\n" "$DAO5"
echo "  │                                                                            │"
echo "  │  Settings:                                                                 │"
echo "  │    • Quorum: 1% (100 BPS)                                                  │"
echo "  │    • Proposal TTL: 1 day (fast governance)                                 │"
echo "  │    • Timelock Delay: 1 hour                                                │"
echo "  │    • Ragequit: Enabled                                                     │"
echo "  │                                                                            │"
printf "  │  Shares:  User 1: %-6s  User 2: %-6s                                   │\n" "$U1_BAL" "$U2_BAL"
echo "  │                                                                            │"
echo "  │  Note: Both User1 and User2 are members                                    │"
echo "  │  Activity:                                                                 │"
echo "  │    ★ DAICO: 0.001 ETH = 1000 SHARES, 30% LP, 1% slippage, no deadline      │"
echo "  │    ★ Tap: User2 ops, ~0.001 ETH/day, 5 ETH budget                          │"
echo "  └────────────────────────────────────────────────────────────────────────────┘"
echo ""

echo "═══════════════════════════════════════════════════════════════════════════════"
echo "                          LOCAL ENVIRONMENT READY ✓"
echo "═══════════════════════════════════════════════════════════════════════════════"
echo ""
echo "  TMUX SESSION: dev"
echo "  ─────────────────────────────────────────────────────────────────────────────"
echo "  • Attach to session:     tmux attach -t dev"
echo "  • View Anvil logs:       tmux select-window -t dev:1  (or Ctrl-b 1)"
echo "  • Switch windows:        Ctrl-b <window-number>  (1=anvil, 2=server, 3=dapps)"
echo "  • Detach from session:   Ctrl-b d"
echo ""

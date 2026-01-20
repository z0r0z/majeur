#!/bin/bash
set -e

# Deploy individual DAOs or all DAOs with multi-network support
# Usage: ./scripts/deploy-dao.sh [--network <network>] <dao-number|all>

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

usage() {
    echo "Usage: $0 [--network <network>] <dao-number|all>"
    echo ""
    echo "Options:"
    echo "  --network <n>  Network: local, sepolia, ethereum, arbitrum, base, unichain, or custom RPC"
    echo ""
    echo "DAO Numbers:"
    echo "  1     DAO 1: 40 messages + cheap ETH shares sale (~1 ETH = 2M shares)"
    echo "  2     DAO 2: All gov proposals + USDF loot sale (3 USDF = 1 loot)"
    echo "  3     DAO 3: Various tributes + DAICO (1 ETH = 1M shares)"
    echo "  4     DAO 4: DAICO Loot Sale (1 USDF = 3 loot, 70% LP, tap)"
    echo "  5     DAO 5: Full DAICO Test (0.001 ETH = 1000 shares, 30% LP, tap)"
    echo "  all   Deploy all 5 DAOs + chat messages + tributes + proposals"
    echo ""
    echo "Networks:"
    echo "  local      http://localhost:8545 (default)"
    echo "  sepolia    Ethereum Sepolia testnet"
    echo "  ethereum   Ethereum mainnet"
    echo "  arbitrum   Arbitrum One"
    echo "  base       Base mainnet"
    echo "  unichain   Unichain mainnet"
    echo ""
    echo "Examples:"
    echo "  $0 1                      # Deploy DAO 1 to localhost"
    echo "  $0 --network sepolia 4    # Deploy DAO 4 to Sepolia"
    echo "  $0 all                    # Deploy all DAOs to localhost"
    echo ""
    echo "Environment Variables:"
    echo "  ALCHEMY_API_KEY  Required for non-local networks"
    echo "  RPC_URL          Override network selection with custom RPC"
    echo "  NETWORK          Default network if --network not specified"
    exit 1
}

# Parse arguments
NETWORK="${NETWORK:-local}"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --network|-n) NETWORK="$2"; shift 2 ;;
        -h|--help) usage ;;
        *) break ;;
    esac
done

[ $# -ne 1 ] && usage
DAO_NUM="$1"

# Validate non-local network has API key
if [[ "$NETWORK" != "local" && "$NETWORK" != "localhost" && -z "$ALCHEMY_API_KEY" && -z "$RPC_URL" ]]; then
    echo "Error: ALCHEMY_API_KEY required for network '$NETWORK'"
    echo "Set it via: export ALCHEMY_API_KEY=your_key"
    exit 1
fi

# Build RPC URL
RPC_URL="${RPC_URL:-$(get_rpc_url "$NETWORK")}"
FORGE_FLAGS="--rpc-url $RPC_URL --broadcast --code-size-limit 50000"

echo "╔══════════════════════════════════════════════════════════════════════════════╗"
echo "║                           DEPLOY DAO                                         ║"
echo "╚══════════════════════════════════════════════════════════════════════════════╝"
echo ""
echo "  Network: $NETWORK"
echo "  RPC:     $RPC_URL"
echo "  Target:  DAO $DAO_NUM"
echo ""

case "$DAO_NUM" in
    1)
        echo "Deploying DAO 1: 40 messages + cheap ETH shares sale..."
        forge script script/CreateTestDAOs.s.sol --sig "deployDAO1()" $FORGE_FLAGS
        ;;
    2)
        echo "Deploying DAO 2: All gov proposals + USDF loot sale..."
        forge script script/CreateTestDAOs.s.sol --sig "deployDAO2()" $FORGE_FLAGS
        ;;
    3)
        echo "Deploying DAO 3: Various tributes + DAICO sale..."
        forge script script/CreateTestDAOs.s.sol --sig "deployDAO3()" $FORGE_FLAGS
        ;;
    4)
        echo "Deploying DAO 4: DAICO Loot Sale with LP and tap..."
        forge script script/CreateTestDAOs.s.sol --sig "deployDAO4()" $FORGE_FLAGS
        ;;
    5)
        echo "Deploying DAO 5: Full DAICO Test with LP and tap..."
        forge script script/CreateTestDAOs.s.sol --sig "deployDAO5()" $FORGE_FLAGS
        ;;
    all)
        echo "Deploying all DAOs + chat messages + tributes..."
        forge script script/CreateTestDAOs.s.sol --sig "runPhase1()" $FORGE_FLAGS
        ;;
    *)
        echo "Error: Invalid DAO number '$DAO_NUM'"
        usage
        ;;
esac

echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "                              DEPLOYMENT COMPLETE ✓"
echo "═══════════════════════════════════════════════════════════════════════════════"

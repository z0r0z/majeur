#!/bin/bash
set -e

# Run Phase 2 to create governance proposals on existing DAOs
# Usage: ./scripts/populate-proposals.sh [--network <network>]

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

RPC_URL="${RPC_URL:-$(get_rpc_url "$NETWORK")}"
FORGE_FLAGS="--rpc-url $RPC_URL --broadcast --code-size-limit 50000"

# DAO2 is the "All gov proposals" DAO
DAO2="0x8FA70236Fe8Bd6E7a22c55Fa12247DdC25407799"

echo "╔══════════════════════════════════════════════════════════════════════════════╗"
echo "║                     POPULATE GOVERNANCE PROPOSALS                            ║"
echo "╚══════════════════════════════════════════════════════════════════════════════╝"
echo ""
echo "  Network:  $NETWORK"
echo "  RPC:      $RPC_URL"
echo "  DAO2:     $DAO2"
echo ""

# Check current proposal count
PROPOSAL_COUNT=$(cast call $DAO2 "getProposalCount()(uint256)" --rpc-url "$RPC_URL" 2>/dev/null || echo "0")
echo "  Current proposal count: $PROPOSAL_COUNT"

if [ "$PROPOSAL_COUNT" != "0" ]; then
    echo "  DAO2 already has proposals. Skipping Phase 2."
    exit 0
fi

echo ""
echo "  Running Phase 2..."
echo ""

forge script script/CreateTestDAOs.s.sol --sig "runPhase2()" $FORGE_FLAGS

echo ""
# Verify new proposal count
NEW_COUNT=$(cast call $DAO2 "getProposalCount()(uint256)" --rpc-url "$RPC_URL" 2>/dev/null || echo "0")
echo "  ✓ Phase 2 complete. DAO2 now has $NEW_COUNT proposals."

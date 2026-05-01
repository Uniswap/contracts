#!/bin/bash

# Mine an aggregator hook address by searching with incrementing salt offsets

show_help() {
    echo "Mine an aggregator hook address by searching with incrementing salt offsets"
    echo ""
    echo "Usage: $0 <constructor_args> <protocol_id> [max_attempts] [deployer_address]"
    echo ""
    echo "Arguments:"
    echo "  constructor_args   Hex-encoded constructor arguments (e.g., 0x000000000000000000000000...)"
    echo "  protocol_id        Protocol identifier for the hook type:"
    echo "                       0xC1 - StableSwap"
    echo "                       0xC2 - StableSwap-NG"
    echo "                       0xF1 - FluidDexT1"
    echo "                       0xF2 - FluidDexV2 (not yet implemented)"
    echo "                       0xF3 - FluidDexLite"
    echo "  max_attempts       Optional. Maximum mining attempts (default: 500)"
    echo "  deployer_address   Optional. Address that will deploy the hook."
    echo "                     Use factory address for factory deploys, wallet address for self-deploys."
    echo "                     (default: CREATE2_DEPLOYER 0x4e59b44847b379578588920cA78FbF26c0B4956C)"
    echo ""
    echo "Examples:"
    echo "  # Mine with default CREATE2_DEPLOYER"
    echo "  $0 0x00000000... 0xF3"
    echo ""
    echo "  # Mine with factory as deployer"
    echo "  $0 0x00000000... 0xF3 500 0xYourFactoryAddress"
    echo ""
    echo "  # Mine with wallet as deployer (for self-deploy)"
    echo "  $0 0x00000000... 0xF3 500 0xYourWalletAddress"
    echo ""
    echo "Options:"
    echo "  -h, --help         Show this help message and exit"
}

# Check for help flag
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    show_help
    exit 0
fi

if [ $# -lt 2 ]; then
    echo "Error: Missing required arguments"
    echo ""
    show_help
    exit 1
fi

CONSTRUCTOR_ARGS=$1
PROTOCOL_ID=$2
MAX_ATTEMPTS=${3:-500}  # Default to 500 attempts
DEPLOYER_ADDRESS=${4:-0x4e59b44847b379578588920cA78FbF26c0B4956C}  # Default to CREATE2_DEPLOYER
SALT_INCREMENT=160444  # Must match MAX_LOOP in AggregatorHookMiner.sol

# Validate DEPLOYER_ADDRESS format (0x + 40 hex chars)
if ! [[ "$DEPLOYER_ADDRESS" =~ ^0x[0-9a-fA-F]{40}$ ]]; then
    echo "Error: Invalid DEPLOYER_ADDRESS '$DEPLOYER_ADDRESS'"
    echo "Expected format: 0x followed by 40 hex characters (e.g., 0x4e59b44847b379578588920cA78FbF26c0B4956C)"
    exit 1
fi

# Random base offset (0 to 1 quadrillion) so each run searches a different salt region.
# Avoids createCollision when redeploying pools with the same constructor args.
# Use 4 bytes (not 8): bash uses signed 64-bit; od -tu8 can overflow to negative, breaking Solidity's uint256 env parsing and causing the same salts to be searched repeatedly.
RANDOM_BASE=$(($(LC_ALL=C od -An -N4 -tu4 /dev/urandom 2>/dev/null || echo $RANDOM) % 1000000000000000))
[ -z "$RANDOM_BASE" ] && RANDOM_BASE=0

echo "Starting aggregator hook mining..."
echo "Random base offset: $RANDOM_BASE (avoids collisions on redeploy)"
echo "Constructor args: $CONSTRUCTOR_ARGS"
echo "Protocol ID: $PROTOCOL_ID"
echo "Deployer address: $DEPLOYER_ADDRESS"
echo "Max attempts: $MAX_ATTEMPTS"
echo "Salt increment per attempt: $SALT_INCREMENT"
echo ""

# Run from contracts/ directory (where this script lives)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [ ! -f "lib/v4-hooks-public/script/MineAggregatorHook.s.sol" ]; then
    echo "Error: MineAggregatorHook.s.sol not found at lib/v4-hooks-public/script/MineAggregatorHook.s.sol"
    echo "Add v4-hooks-public and checkout main:"
    echo "  git submodule add -b main https://github.com/Uniswap/v4-hooks-public lib/v4-hooks-public"
    echo "  cd lib/v4-hooks-public && git fetch origin main && git checkout main"
    echo "  git submodule update --init --recursive"
    exit 1
fi

for ((i=0; i<MAX_ATTEMPTS; i++)); do
    OFFSET=$((RANDOM_BASE + i * SALT_INCREMENT))
    echo "Attempt $((i + 1))/$MAX_ATTEMPTS - Salt offset: $OFFSET"
    
    # Run the forge script and capture output (--gas-limit needed: miner does ~160k keccak iterations)
    # FORGE_VERBOSE=1 from createPools.ts --verbose adds -vvvv for detailed logging
    VERBOSE_FLAG=""
    [ "$FORGE_VERBOSE" = "1" ] && VERBOSE_FLAG="-vvvv"
    
    FORGE_OUTPUT=$(mktemp)
    START_SEC=$(date +%s)
    SALT_OFFSET=$OFFSET CONSTRUCTOR_ARGS=$CONSTRUCTOR_ARGS PROTOCOL_ID=$PROTOCOL_ID DEPLOYER=$DEPLOYER_ADDRESS forge script lib/v4-hooks-public/script/MineAggregatorHook.s.sol:MineAggregatorHookScript --gas-limit 30000000000 $VERBOSE_FLAG > "$FORGE_OUTPUT" 2>&1 &
    FORGE_PID=$!
    
    # Heartbeat: update same line every 15s so user knows it's still running
    ELAPSED=0
    while kill -0 $FORGE_PID 2>/dev/null; do
        printf "\r  ... still searching (Attempt %d/%d, %ds elapsed)   " $((i + 1)) $MAX_ATTEMPTS $ELAPSED
        sleep 15
        ELAPSED=$((ELAPSED + 15))
    done
    printf "\r%-70s\r" ""  # clear the heartbeat line
    wait $FORGE_PID 2>/dev/null
    FORGE_EXIT=$?
    DURATION=$(( $(date +%s) - START_SEC ))
    OUTPUT=$(cat "$FORGE_OUTPUT")
    rm -f "$FORGE_OUTPUT"
    
    # Check if we found a valid salt (look for "Hook Address" in output)
    if echo "$OUTPUT" | grep -q "Hook Address:"; then
        echo ""
        echo "SUCCESS! Found valid salt."
        echo ""
        echo "$OUTPUT" | grep -A 10 "=== Aggregator Hook Mining Results ==="
        exit 0
    fi
    
    # Check if it was a "could not find salt" error (expected, continue searching)
    if echo "$OUTPUT" | grep -q "could not find salt"; then
        echo "  No match found in this range (forge exit=$FORGE_EXIT, ${DURATION}s), continuing..."
        continue
    fi
    
    # Some other error occurred
    echo "  Unexpected error (forge exit=$FORGE_EXIT, ${DURATION}s):"
    echo "$OUTPUT"
    exit 1
done

echo ""
echo "FAILED: Could not find valid salt after $MAX_ATTEMPTS attempts"
echo "Total salts searched: $((MAX_ATTEMPTS * SALT_INCREMENT))"
exit 1

#!/bin/bash

# Check if RPC URL is provided
if [ -z "$1" ]; then
  echo "Usage: ./deploy_precheck.sh <RPC_URL>"
  exit 1
fi

RPC_URL=$1

# Helper function to check for RPC errors in response
# Returns: 0 = success, 1 = rate limit, 2 = connection error, 3 = other error
check_rpc_error() {
  local response="$1"

  # Check for rate limit errors
  if [[ $response == *"429"* ]] || [[ $response == *"rate limit"* ]] || [[ $response == *"exceeded"* ]] || [[ $response == *"too many request"* ]]; then
    return 1
  fi

  # Check for connection errors
  if [[ $response == *"connection"* ]] || [[ $response == *"timeout"* ]] || [[ $response == *"ETIMEDOUT"* ]] || [[ $response == *"ECONNREFUSED"* ]]; then
    return 2
  fi

  # Check for other RPC errors (but not execution reverts which are expected for unsupported opcodes)
  if [[ $response == *"Error"* ]] && [[ $response != *"execution reverted"* ]] && [[ $response != *"invalid opcode"* ]]; then
    return 3
  fi

  return 0
}

# Helper function to print result based on error type
print_rpc_error() {
  local error_code=$1
  local response="$2"
  case $error_code in
    1) echo "⚠️  RATE LIMITED" ;;
    2) echo "⚠️  CONNECTION ERROR" ;;
    3) echo "⚠️  RPC ERROR" ;;
  esac
  # Print the actual error message (extract just the error part)
  if [[ -n "$response" ]]; then
    # Try to extract error message, or print full response if short enough
    local error_msg=$(echo "$response" | grep -oE '"message":"[^"]*"' | head -1 | sed 's/"message":"//;s/"$//')
    if [[ -z "$error_msg" ]]; then
      error_msg=$(echo "$response" | grep -oE 'data: "[^"]*"' | head -1)
    fi
    if [[ -z "$error_msg" ]]; then
      error_msg="$response"
    fi
    echo "                            → $error_msg"
  fi
}

echo "---------------------------------------"
echo "Testing Deployment Compatibility for:"
echo "$RPC_URL"
echo "---------------------------------------"

# 1. Test PUSH0 (Shanghai - Solc 0.8.20+)
# Bytecode: 5f (PUSH0) 5f (PUSH0) f3 (RETURN)
# We use --create to simulate a deployment
echo -n "Testing PUSH0 (Shanghai)... "
PUSH0_RES=$(cast call --rpc-url "$RPC_URL" --create 0x5f5ff3 2>&1)

check_rpc_error "$PUSH0_RES"
PUSH0_ERR=$?

if [[ $PUSH0_ERR -ne 0 ]]; then
  print_rpc_error $PUSH0_ERR "$PUSH0_RES"
elif [[ $PUSH0_RES == *"0x"* ]]; then
  echo "✅ SUPPORTED"
else
  echo "❌ UNSUPPORTED"
fi

# 2. Test TSTORE (Cancun - Solc 0.8.24+)
# Bytecode: 5f5f5d (PUSH0, PUSH0, TSTORE) 5f5f (PUSH0, PUSH0) f3 (RETURN)
# We push two 0s to satisfy TSTORE's stack requirements (key, value)
echo -n "Testing TSTORE (Cancun)...  "
CANCUN_RES=$(cast call --rpc-url "$RPC_URL" --create 0x5f5f5d5f5ff3 2>&1)

check_rpc_error "$CANCUN_RES"
CANCUN_ERR=$?

if [[ $CANCUN_ERR -ne 0 ]]; then
  print_rpc_error $CANCUN_ERR "$CANCUN_RES"
elif [[ $CANCUN_RES == *"0x"* ]]; then
  echo "✅ SUPPORTED"
else
  echo "❌ UNSUPPORTED"
fi

# 3. Check Deterministic Deployment Proxy
echo -n "Deterministic Deployer...   "
DEPLOYER_CODE=$(cast code --rpc-url "$RPC_URL" 0x4e59b44847b379578588920ca78fbf26c0b4956c 2>&1)
EXPECTED_CODE="0x7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe03601600081602082378035828234f58015156039578182fd5b8082525050506014600cf3"

check_rpc_error "$DEPLOYER_CODE"
DEPLOYER_ERR=$?

if [[ $DEPLOYER_ERR -ne 0 ]]; then
  print_rpc_error $DEPLOYER_ERR "$DEPLOYER_CODE"
elif [[ $DEPLOYER_CODE == "$EXPECTED_CODE" ]]; then
  echo "✅ DEPLOYED"
elif [[ $DEPLOYER_CODE == "0x" || $DEPLOYER_CODE != 0x* ]]; then
  echo "❌ NOT DEPLOYED"
else
  echo "❌ BYTECODE MISMATCH"
fi

# 4. Check Permit2
echo -n "Permit2...                  "
PERMIT2_CODE=$(cast code --rpc-url "$RPC_URL" 0x000000000022D473030F116dDEE9F6B43aC78BA3 2>&1)

check_rpc_error "$PERMIT2_CODE"
PERMIT2_ERR=$?

if [[ $PERMIT2_ERR -ne 0 ]]; then
  print_rpc_error $PERMIT2_ERR "$PERMIT2_CODE"
elif [[ $PERMIT2_CODE != "0x" && $PERMIT2_CODE == 0x* ]]; then
  echo "✅ DEPLOYED"
else
  echo "❌ NOT DEPLOYED"
fi

# 5. Get Chain ID and Native Currency Info
echo -n "Fetching Chain ID...        "
CHAIN_ID=$(cast chain-id --rpc-url "$RPC_URL" 2>&1)

check_rpc_error "$CHAIN_ID"
CHAIN_ID_ERR=$?

if [[ $CHAIN_ID_ERR -ne 0 ]]; then
  print_rpc_error $CHAIN_ID_ERR "$CHAIN_ID"
elif [[ $CHAIN_ID =~ ^[0-9]+$ ]]; then
  echo "✅ $CHAIN_ID"

  # Fetch chain info from chainlist.org
  echo -n "Fetching Native Currency... "
  CHAINLIST_JSON=$(curl -s "https://chainlist.org/rpcs.json")

  if [[ -n "$CHAINLIST_JSON" ]]; then
    # Use jq to find the chain and extract native currency info
    NATIVE_CURRENCY=$(echo "$CHAINLIST_JSON" | jq -r --argjson cid "$CHAIN_ID" '
      .[] | select(.chainId == $cid) | .nativeCurrency |
      "\(.name) (\(.symbol)), \(.decimals) decimals"
    ' 2>/dev/null)

    if [[ -n "$NATIVE_CURRENCY" && "$NATIVE_CURRENCY" != "null" ]]; then
      echo "✅ $NATIVE_CURRENCY"

      # Also export individual values for use by other scripts
      NATIVE_NAME=$(echo "$CHAINLIST_JSON" | jq -r --argjson cid "$CHAIN_ID" '.[] | select(.chainId == $cid) | .nativeCurrency.name')
      NATIVE_SYMBOL=$(echo "$CHAINLIST_JSON" | jq -r --argjson cid "$CHAIN_ID" '.[] | select(.chainId == $cid) | .nativeCurrency.symbol')
      NATIVE_DECIMALS=$(echo "$CHAINLIST_JSON" | jq -r --argjson cid "$CHAIN_ID" '.[] | select(.chainId == $cid) | .nativeCurrency.decimals')
    else
      echo "❌ Chain ID $CHAIN_ID not found in chainlist"
    fi
  else
    echo "❌ Failed to fetch chainlist.org"
  fi

  # 6. Check Etherscan Support
  echo -n "Etherscan Support...        "
  ETHERSCAN_JSON=$(curl -s "https://api.etherscan.io/v2/chainlist")

  if [[ -n "$ETHERSCAN_JSON" ]]; then
    # Use jq to find the chain (chainid is a string in this API)
    ETHERSCAN_RESULT=$(echo "$ETHERSCAN_JSON" | jq -r --arg cid "$CHAIN_ID" '
      .result[] | select(.chainid == $cid) | .blockexplorer
    ' 2>/dev/null)

    if [[ -n "$ETHERSCAN_RESULT" && "$ETHERSCAN_RESULT" != "null" ]]; then
      echo "✅ $ETHERSCAN_RESULT"
      ETHERSCAN_URL="$ETHERSCAN_RESULT"
    else
      echo "❌ Not supported"
    fi
  else
    echo "❌ Failed to fetch etherscan chainlist"
  fi
else
  echo "❌ FAILED ($CHAIN_ID)"
fi

echo ""
echo "---------------------------------------"
echo "Gas Measurements (init code execution)"
echo "---------------------------------------"

# Ethereum mainnet baseline values (measured via eth_estimateGas)
ETH_BASELINE_GAS=53943 # NOPs only baseline
ETH_SSTORE_GAS=22176   # cold SSTORE new value
ETH_SLOAD_GAS=2097     # cold SLOAD
ETH_TSTORE_GAS=89      # transient store
ETH_TLOAD_GAS=89       # transient load

# All init codes are exactly 10 bytes and return empty (deploy 0-byte contract)
# This ensures calldata cost and deployment cost are identical

# Baseline: 5 JUMPDESTs (NOPs) then RETURN(0,0)
# 5b 5b 5b 5b 5b 60 00 60 00 f3
echo -n "Baseline (NOPs only)...     "
BASELINE_GAS=$(cast estimate --rpc-url "$RPC_URL" --create 0x5b5b5b5b5b60006000f3 2>&1)
if [[ $BASELINE_GAS =~ ^[0-9]+$ ]]; then
  echo "$BASELINE_GAS gas"
  echo "                            (Ethereum baseline: ≈$ETH_BASELINE_GAS gas)"
else
  echo "❌ Failed ($BASELINE_GAS)"
  BASELINE_GAS=0
fi

# SSTORE: PUSH1 1, PUSH1 0, SSTORE, PUSH1 0, PUSH1 0, RETURN
# 60 01 60 00 55 60 00 60 00 f3
echo -n "SSTORE (cold, new value)... "
SSTORE_GAS=$(cast estimate --rpc-url "$RPC_URL" --create 0x600160005560006000f3 2>&1)
if [[ $SSTORE_GAS =~ ^[0-9]+$ ]]; then
  if [[ $BASELINE_GAS -gt 0 ]]; then
    SSTORE_DIFF=$((SSTORE_GAS - BASELINE_GAS))
    echo "≈$SSTORE_DIFF gas"
    echo "                            (Ethereum baseline: ≈$ETH_SSTORE_GAS gas, $SSTORE_GAS gas total)"
  else
    echo "$SSTORE_GAS gas total"
  fi
else
  echo "❌ Failed ($SSTORE_GAS)"
fi

# SLOAD: JUMPDEST, PUSH1 0, SLOAD, POP, PUSH1 0, PUSH1 0, RETURN
# 5b 60 00 54 50 60 00 60 00 f3
echo -n "SLOAD (cold)...             "
SLOAD_GAS=$(cast estimate --rpc-url "$RPC_URL" --create 0x5b6000545060006000f3 2>&1)
if [[ $SLOAD_GAS =~ ^[0-9]+$ ]]; then
  if [[ $BASELINE_GAS -gt 0 ]]; then
    SLOAD_DIFF=$((SLOAD_GAS - BASELINE_GAS))
    echo "≈$SLOAD_DIFF gas"
    echo "                            (Ethereum baseline: ≈$ETH_SLOAD_GAS gas, $SLOAD_GAS gas total)"
  else
    echo "$SLOAD_GAS gas total"
  fi
else
  echo "❌ Failed ($SLOAD_GAS)"
fi

# TSTORE: PUSH1 1, PUSH1 0, TSTORE(0x5d), PUSH1 0, PUSH1 0, RETURN
# 60 01 60 00 5d 60 00 60 00 f3
echo -n "TSTORE (transient)...       "
TSTORE_GAS=$(cast estimate --rpc-url "$RPC_URL" --create 0x600160005d60006000f3 2>&1)
if [[ $TSTORE_GAS =~ ^[0-9]+$ ]]; then
  if [[ $BASELINE_GAS -gt 0 ]]; then
    TSTORE_DIFF=$((TSTORE_GAS - BASELINE_GAS))
    echo "≈$TSTORE_DIFF gas"
    echo "                            (Ethereum baseline: ≈$ETH_TSTORE_GAS gas, $TSTORE_GAS gas total)"
  else
    echo "$TSTORE_GAS gas total"
  fi
else
  echo "❌ Not supported or failed"
fi

# TLOAD: JUMPDEST, PUSH1 0, TLOAD(0x5c), POP, PUSH1 0, PUSH1 0, RETURN
# 5b 60 00 5c 50 60 00 60 00 f3
echo -n "TLOAD (transient)...        "
TLOAD_GAS=$(cast estimate --rpc-url "$RPC_URL" --create 0x5b60005c5060006000f3 2>&1)
if [[ $TLOAD_GAS =~ ^[0-9]+$ ]]; then
  if [[ $BASELINE_GAS -gt 0 ]]; then
    TLOAD_DIFF=$((TLOAD_GAS - BASELINE_GAS))
    echo "≈$TLOAD_DIFF gas"
    echo "                            (Ethereum baseline: ≈$ETH_TLOAD_GAS gas, $TLOAD_GAS gas total)"
  else
    echo "$TLOAD_GAS gas total"
  fi
else
  echo "❌ Not supported or failed"
fi

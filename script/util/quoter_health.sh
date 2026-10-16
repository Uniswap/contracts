#!/usr/bin/env bash
# Quoter health check: confirms a deployed V4Quoter (or MixedRouteQuoterV2) is the current
# briefcase build. Usage:
#   quoter_health.sh <chainId> <rpc> <quoter> [poolManager] [v3Factory v2Factory]
# Env: KIND=v4 (default) | mrq2. CONTRACTS_DIR defaults to the repo root this script lives in.
# Exit codes: 1 no code, 2 msgSender() reverts or non-zero, 3 poolManager mismatch, 4 runtime
# bytecode differs from the briefcase initcode run with the same constructor args.
set -u
CHAIN=${1:?chainId}; RPC=${2:?rpc}; Q=${3:?quoter}; PM=${4:-}
KIND=${KIND:-v4}
CONTRACTS_DIR=${CONTRACTS_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}
JSON="$CONTRACTS_DIR/deployments/json/$CHAIN.json"

if [ -z "$PM" ] && [ -f "$JSON" ]; then PM=$(jq -r '.latest.PoolManager.address // empty' "$JSON"); fi
lc() { tr '[:upper:]' '[:lower:]'; }

code=$(cast code "$Q" --rpc-url "$RPC" 2>/dev/null)
if [ -z "$code" ] || [ "$code" = "0x" ]; then echo "$CHAIN $Q: NO CODE"; exit 1; fi

ms=$(cast call "$Q" "msgSender()(address)" --rpc-url "$RPC" 2>&1)
if [ "$(echo "$ms" | lc)" != "0x0000000000000000000000000000000000000000" ]; then echo "$CHAIN $Q: msgSender() -> $ms"; exit 2; fi

pm_on=$(cast call "$Q" "poolManager()(address)" --rpc-url "$RPC" 2>/dev/null)
if [ -n "$PM" ] && [ "$(echo "$pm_on" | lc)" != "$(echo "$PM" | lc)" ]; then echo "$CHAIN $Q: poolManager $pm_on != $PM"; exit 3; fi

if [ "$KIND" = "mrq2" ]; then
  DEPLOYER="$CONTRACTS_DIR/src/briefcase/deployers/mixed-quoter/MixedRouteQuoterV2Deployer.sol"
  V3=${5:-$(jq -r '.latest.UniswapV3Factory.address // empty' "$JSON")}
  V2=${6:-$(jq -r '.latest.UniswapV2Factory.address // empty' "$JSON")}
  ARGS=$(cast abi-encode "f(address,address,address)" "$pm_on" "$V3" "$V2")
else
  DEPLOYER="$CONTRACTS_DIR/src/briefcase/deployers/v4-periphery/V4QuoterDeployer.sol"
  ARGS=$(cast abi-encode "f(address)" "$pm_on")
fi
IC=$(grep -o "hex'[0-9a-f]*'" "$DEPLOYER" | sed "s/^hex'//; s/'$//")
# Run the initcode as a creation call on the target chain: the returned runtime already has the
# immutables filled in, so it can be hashed against the live code without masking.
exp=$(cast rpc eth_call "{\"data\":\"0x${IC}${ARGS#0x}\"}" latest --rpc-url "$RPC" 2>/dev/null | tr -d '"')
if [ -z "$exp" ] || [ "$exp" = "0x" ]; then echo "$CHAIN $Q: could not simulate briefcase initcode"; exit 4; fi
h_live=$(cast keccak "$code"); h_exp=$(cast keccak "$exp")
if [ "$h_live" != "$h_exp" ]; then echo "$CHAIN $Q: runtime hash $h_live != briefcase $h_exp"; exit 4; fi

echo "$CHAIN $Q: OK (msgSender, poolManager=$pm_on, runtime matches briefcase initcode)"

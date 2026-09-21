#!/usr/bin/env bash
# Verify every HyperEVM deploy contract on BOTH explorers, driven by deployments/json/<chain>.json:
#   1. hyperevmscan.io  (Etherscan v2 API, chainid 999; needs ETHERSCAN_API_KEY in .env)
#   2. Sourcify          (sourcify.dev, chain 999 supported; keyless, feeds hl.eco / other explorers)
# hyperscan.com (Blockscout) now redirects to hl.eco, which exposes no verification API; it consumes Sourcify.
#
# Prereqs: source submodules checked out (git submodule update --init --recursive src/pkgs/...), and
# Compile settings per contract come from the briefcase deployer headers; UR + PermissionsAdapterFactory only
# reproduce at the briefcase-era submodule pins, which this script checks out and restores.
#
# Usage: script/hyperevm/verify.sh [chain=999] [etherscan|sourcify|both=both] [ContractName ...]
set -euo pipefail
cd "$(dirname "$0")/../.."
CHAIN=${1:-999}; MODE=${2:-both}; shift 2 2>/dev/null || shift $# ; ONLY=("$@")
for e in .env ../contracts/.env; do [ -f "$e" ] && source "$e" && break; done; true
: "${ETHERSCAN_API_KEY:?set ETHERSCAN_API_KEY (or put it in .env) before running verify}"
export TENDERLY_PUBLIC_RPC_URL=${TENDERLY_PUBLIC_RPC_URL:-http://localhost:1} TENDERLY_ACCESS_KEY=${TENDERLY_ACCESS_KEY:-dummy}
J=deployments/json/$CHAIN.json; T=$(ls script/deploy/tasks/$CHAIN/task-1*.json | sort | tail -1)
# always restore the two briefcase-pinned submodules, whatever happens below
PINNED=0
restore() { if [[ $PINNED == 1 ]]; then pin src/pkgs/universal-router HEAD; pin src/pkgs/v4-periphery HEAD; fi; }
trap restore EXIT
a() { jq -r ".latest.$1.address" $J; }
OWNER=$(jq -r '.protocols.v3.contracts.UniswapV3Factory.params.initialOwner.value' $T)
WETH=$(jq -r '.dependencies.weth.value' $T)
USDC=$(jq -r '.protocols["util-contracts"].contracts.FeeCollector.params.feeToken.value' $T)
FC_OWNER=$(jq -r '.protocols["util-contracts"].contracts.FeeCollector.params.owner.value' $T)
SPOKE=$(jq -r '.protocols["universal-router"].contracts.UniversalRouter.params.acrossSpokePool.value' $T)
LABEL=0x$(printf 'HYPE' | xxd -p)$(printf '0%.0s' $(seq 56))   # "HYPE" right-padded to bytes32
PERMIT2=0x000000000022D473030F116dDEE9F6B43aC78BA3
V2F=$(a UniswapV2Factory); V3F=$(a UniswapV3Factory); NPM=$(a NonfungiblePositionManager); PM=$(a PoolManager)
POSM=$(a PositionManager); UR=$(a UniversalRouter); PAF=$(a PermissionsAdapterFactory)
NFTD=$(a NonfungibleTokenPositionDescriptor); NFTD_IMPL=$(jq -r .latest.NonfungibleTokenPositionDescriptor.implementation $J)
NFTD_ADMIN=$(jq -r .latest.NonfungibleTokenPositionDescriptor.proxyAdmin $J)
PD=$(a PositionDescriptor); PD_IMPL=$(jq -r .latest.PositionDescriptor.implementation $J); PD_ADMIN=$(jq -r .latest.PositionDescriptor.proxyAdmin $J)
NFTLIB=0x2E9D45Bb7b30549F5216813aDA9a6b7982C5B3ED
enc() { cast abi-encode "$@"; }
FAILED=()

v() { # v <Name> <addr> <fqn> <solc> <runs> <evm> <viair:yes|no> [constructor-args-hex] [libraries]
  local name=$1 addr=$2 fqn=$3 solc=$4 runs=$5 evm=$6 viair=$7 args=${8:-} libs=${9:-}
  [[ ${#ONLY[@]} -gt 0 && ! " ${ONLY[*]} " =~ " $name " ]] && return
  local common=(--chain-id $CHAIN --compiler-version "$solc" --num-of-optimizations "$runs" --evm-version "$evm")
  [[ $viair == yes ]] && common+=(--via-ir); [[ $viair == profile:* ]] && common+=(--compilation-profile "${viair#profile:}")
  [[ -n $args ]] && common+=(--constructor-args "$args"); [[ -n $libs ]] && common+=(--libraries "$libs")
  # FORCE=1 resubmits even if the explorer already shows a (possibly fork-named "similar match") source
  [[ ${FORCE:-0} == 1 ]] && common+=(--skip-is-verified-check)
  echo; echo "########## $name @ $addr"
  if [[ $MODE != sourcify ]]; then
    forge verify-contract "$addr" "$fqn" "${common[@]}" --verifier etherscan --etherscan-api-key "$ETHERSCAN_API_KEY" --watch \
      || { FAILED+=("etherscan:$name"); true; }
  fi
  if [[ $MODE != etherscan ]]; then
    forge verify-contract "$addr" "$fqn" "${common[@]}" --verifier sourcify --verifier-url https://sourcify.dev/server/ \
      || { FAILED+=("sourcify:$name"); true; }
  fi
}

# ---- v2 (solc 0.5.16 / 0.6.6, 999999 runs)
v UniswapV2Factory $V2F src/pkgs/v2-core/contracts/UniswapV2Factory.sol:UniswapV2Factory 0.5.16 999999 istanbul no "$(enc 'constructor(address)' $OWNER)"
v UniswapV2Router02 $(a UniswapV2Router02) src/pkgs/v2-periphery/contracts/UniswapV2Router02.sol:UniswapV2Router02 0.6.6 999999 istanbul no "$(enc 'constructor(address,address)' $V2F $WETH)"
# ---- v3 core / periphery (solc 0.7.6, istanbul)
v UniswapV3Factory $V3F src/pkgs/v3-core/contracts/UniswapV3Factory.sol:UniswapV3Factory 0.7.6 800 istanbul no
v UniswapInterfaceMulticall $(a UniswapInterfaceMulticall) src/pkgs/v3-periphery/contracts/lens/UniswapInterfaceMulticall.sol:UniswapInterfaceMulticall 0.7.6 1000000 istanbul no
v QuoterV2 $(a QuoterV2) src/pkgs/v3-periphery/contracts/lens/QuoterV2.sol:QuoterV2 0.7.6 1000000 istanbul no "$(enc 'constructor(address,address)' $V3F $WETH)"
v TickLens $(a TickLens) src/pkgs/v3-periphery/contracts/lens/TickLens.sol:TickLens 0.7.6 1000000 istanbul no
v NFTDescriptor $NFTLIB src/pkgs/v3-periphery/contracts/libraries/NFTDescriptor.sol:NFTDescriptor 0.7.6 1000 istanbul no
v NonfungibleTokenPositionDescriptorImpl $NFTD_IMPL src/pkgs/v3-periphery/contracts/NonfungibleTokenPositionDescriptor.sol:NonfungibleTokenPositionDescriptor 0.7.6 1000 istanbul no \
  "$(enc 'constructor(address,bytes32)' $WETH $LABEL)" "src/pkgs/v3-periphery/contracts/libraries/NFTDescriptor.sol:NFTDescriptor:$NFTLIB"
v NonfungibleTokenPositionDescriptorProxy $NFTD lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol:TransparentUpgradeableProxy 0.8.26 200 cancun no "$(enc 'constructor(address,address,bytes)' $NFTD_IMPL $OWNER 0x)"
v NonfungibleTokenPositionDescriptorProxyAdmin $NFTD_ADMIN lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol:ProxyAdmin 0.8.26 200 cancun no "$(enc 'constructor(address)' $OWNER)"
v NonfungiblePositionManager $NPM src/pkgs/v3-periphery/contracts/NonfungiblePositionManager.sol:NonfungiblePositionManager 0.7.6 2000 istanbul no "$(enc 'constructor(address,address,address)' $V3F $WETH $NFTD)"
v V3Migrator $(a V3Migrator) src/pkgs/v3-periphery/contracts/V3Migrator.sol:V3Migrator 0.7.6 1000000 istanbul no "$(enc 'constructor(address,address,address)' $V3F $WETH $NPM)"
v SwapRouter $(a SwapRouter) src/pkgs/v3-periphery/contracts/SwapRouter.sol:SwapRouter 0.7.6 1000000 istanbul no "$(enc 'constructor(address,address)' $V3F $WETH)"
# ---- v4 (solc 0.8.26, via-ir, cancun)
v PoolManager $PM src/pkgs/v4-core/src/PoolManager.sol:PoolManager 0.8.26 44444444 cancun yes "$(enc 'constructor(address)' $OWNER)"
v PositionDescriptorImpl $PD_IMPL src/pkgs/v4-periphery/src/PositionDescriptor.sol:PositionDescriptor 0.8.26 1 cancun yes "$(enc 'constructor(address,address,bytes32)' $PM $WETH $LABEL)"
v PositionDescriptorProxy $PD lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol:TransparentUpgradeableProxy 0.8.26 200 cancun no "$(enc 'constructor(address,address,bytes)' $PD_IMPL $OWNER 0x)"
v PositionDescriptorProxyAdmin $PD_ADMIN lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol:ProxyAdmin 0.8.26 200 cancun no "$(enc 'constructor(address)' $OWNER)"
v PositionManager $POSM src/pkgs/v4-periphery/src/PositionManager.sol:PositionManager 0.8.26 500 cancun yes "$(enc 'constructor(address,address,uint256,address,address)' $PM $PERMIT2 300000 $PD $WETH)"
v V4Quoter $(a V4Quoter) src/pkgs/v4-periphery/src/lens/V4Quoter.sol:V4Quoter 0.8.26 44444444 cancun yes "$(enc 'constructor(address)' $PM)"
v StateView $(a StateView) src/pkgs/v4-periphery/src/lens/StateView.sol:StateView 0.8.26 44444444 cancun yes "$(enc 'constructor(address)' $PM)"
v ReservesLens $(a ReservesLens) src/pkgs/v4-periphery/src/lens/ReservesLens.sol:ReservesLens 0.8.26 44444444 cancun profile:v4
# ---- quoters / routers / utils
v Quoter $(a Quoter) src/pkgs/view-quoter-v3/contracts/Quoter.sol:Quoter 0.7.6 200 istanbul no "$(enc 'constructor(address)' $V3F)"
v MixedRouteQuoterV2 $(a MixedRouteQuoterV2) src/pkgs/mixed-quoter/src/MixedRouteQuoterV2.sol:MixedRouteQuoterV2 0.8.26 200 cancun yes "$(enc 'constructor(address,address,address)' $PM $V3F $V2F)"
v SwapRouter02 $(a SwapRouter02) src/pkgs/swap-router-contracts/contracts/SwapRouter02.sol:SwapRouter02 0.7.6 1000000 istanbul no "$(enc 'constructor(address,address,address,address)' $V2F $V3F $NPM $WETH)"
v FeeOnTransferDetector $(a FeeOnTransferDetector) src/pkgs/util-contracts/src/FeeOnTransferDetector.sol:FeeOnTransferDetector 0.8.19 200 paris no "$(enc 'constructor(address)' $V2F)"
v FeeCollector $(a FeeCollector) src/pkgs/util-contracts/src/FeeCollector.sol:FeeCollector 0.8.19 200 paris no "$(enc 'constructor(address,address,address,address)' $FC_OWNER $UR $PERMIT2 $USDC)"

# ---- briefcase-pinned sources: UR + PermissionsAdapterFactory only reproduce at the briefcase-era submodule pins
pin() { local sm=$1 ref=$2; local t; t=$(git ls-tree $ref $sm | awk '{print $3}')
        (cd $sm && git checkout -q $t && git submodule update --init --recursive -q) || { echo "!! failed to pin $sm to ${t:0:8}"; return 1; }
        echo "$sm -> ${t:0:8}"; }
BRIEFCASE_REGEN=84aca41
if [[ ${#ONLY[@]} -eq 0 || " ${ONLY[*]} " =~ " UniversalRouter " || " ${ONLY[*]} " =~ " PermissionsAdapterFactory " ]]; then
  PINNED=1; pin src/pkgs/universal-router $BRIEFCASE_REGEN; pin src/pkgs/v4-periphery $BRIEFCASE_REGEN; forge build --skip '*/node_modules/*' >/dev/null
  v PermissionsAdapterFactory $PAF src/pkgs/v4-periphery/src/hooks/permissionedPools/PermissionsAdapterFactory.sol:PermissionsAdapterFactory 0.8.26 44444444 cancun yes "$(enc 'constructor(address)' $PM)"
  echo "UniversalRouter $UR is built from the Uniswap/universal-router repo (tag 2.2.0 re-cut); verify it from that repo at tag 2.2.0 with script/deployParameters/DeployHyperEVM.s.sol (universal-router#517; 2.1.x copy in #518). See README."
  restore; PINNED=0
fi

# ---- SwapProxy: frozen canonical CREATE2 initcode, identical on every chain. Etherscan usually links it by
# bytecode match once any chain is verified; otherwise verify from .swapproxy-deploy/ standard-json (see
# references/deterministic-create-deploy.md in the uniswap-new-chain-deploy skill).
echo; echo "SwapProxy $(a SwapProxy): check https://hyperevmscan.io/address/$(a SwapProxy)#code (bytecode-match), else standard-json upload."

echo; echo "Post-check (all should be verified):"
for n in UniswapV2Factory UniswapV2Router02 UniswapV3Factory UniswapInterfaceMulticall QuoterV2 TickLens NonfungibleTokenPositionDescriptor NonfungiblePositionManager V3Migrator SwapRouter PoolManager PositionDescriptor PositionManager V4Quoter StateView ReservesLens PermissionsAdapterFactory Quoter MixedRouteQuoterV2 SwapRouter02 UniversalRouter SwapProxy FeeOnTransferDetector FeeCollector; do
  A=$(a $n); R=$(curl -s "https://api.etherscan.io/v2/api?chainid=$CHAIN&module=contract&action=getsourcecode&address=$A&apikey=$ETHERSCAN_API_KEY" | jq -r '.result[0].ContractName // "-"')
  S=$(curl -s "https://sourcify.dev/server/v2/contract/$CHAIN/$A" | jq -r '.match // "none"')
  printf '%-36s %s etherscan=%-32s sourcify=%s\n' $n $A "$R" "$S"
done
[[ ${#FAILED[@]} -eq 0 ]] && echo "ALL SUBMITTED" || { echo "FAILED: ${FAILED[*]}"; exit 1; }

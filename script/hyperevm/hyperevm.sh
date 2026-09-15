#!/usr/bin/env bash
# HyperEVM (chain 999 / testnet 998) Uniswap deploy driver.
# Every step that signs uses `--account $ACCOUNT` so forge/cast prompt for the keystore password;
# no key material is ever written to disk or passed on the command line.
#
#   ./script/hyperevm/hyperevm.sh <step> [mainnet|testnet]      (default: mainnet)
#
# steps: probe | core-seed | bigblocks-on | bigblocks-off | bigblocks-status | dry-run | deploy |
#        registry | test | smoke | repro | verify
set -euo pipefail
cd "$(dirname "$0")/../.."

STEP=${1:-help}; NET=${2:-mainnet}
ACCOUNT=${ACCOUNT:-swap-test}
DEPLOYER=${DEPLOYER:-0x9701fb0aDe1E269c8f64Ec0C7b3cfADB31A13A52}
OWNER=0x2d09d0c2f82c59b19b3c65a48ce2c550bf0921f9
if [[ $NET == mainnet ]]; then
  CHAIN=999; RPC=${HYPEREVM_RPC:-https://rpc.hyperliquid.xyz/evm}; HLFLAG=""
else
  CHAIN=998; RPC=${HYPEREVM_TESTNET_RPC:-https://rpcs.chain.link/hyperevm/testnet}; HLFLAG="--testnet"
fi
# load-bearing for foundry.toml parsing even though Tenderly is unused
export TENDERLY_PUBLIC_RPC_URL=${TENDERLY_PUBLIC_RPC_URL:-http://localhost:1} TENDERLY_ACCESS_KEY=${TENDERLY_ACCESS_KEY:-dummy}
SKIP=(--skip '*/node_modules/*')
# maxFee 1 gwei (5-10x current base fee), priority 0 (HyperEVM burns tips; eth_maxPriorityFeePerGas returns 0)
GAS=(--with-gas-price 1000000000 --priority-gas-price 0)
PY=${HL_PYTHON:-python3}

case $STEP in
  probe)
    echo "chain      $(cast chain-id --rpc-url $RPC)   block $(cast block-number --rpc-url $RPC)"
    echo "gasPrice   $(cast gas-price --rpc-url $RPC) wei   bigBlockGasPrice $(cast rpc eth_bigBlockGasPrice --rpc-url $RPC | tr -d '"' | xargs cast --to-dec) wei"
    echo "deployer   $DEPLOYER  balance $(cast balance $DEPLOYER --rpc-url $RPC --ether) HYPE  nonce $(cast nonce $DEPLOYER --rpc-url $RPC)"
    echo "owner      $OWNER  code=$(cast code $OWNER --rpc-url $RPC | wc -c | tr -d ' ')B  wormholeChainId=$(cast call $OWNER 'chainId()(uint16)' --rpc-url $RPC 2>/dev/null || echo n/a)"
    for c in "Permit2 0x000000000022D473030F116dDEE9F6B43aC78BA3" "Multicall3 0xcA11bde05977b3631167028862bE2a173976CA11" "CREATE2 0x4e59b44847b379578588920cA78FbF26c0B4956C" "WHYPE 0x5555555555555555555555555555555555555555"; do
      set -- $c; echo "$1 $2 code=$(cast code $2 --rpc-url $RPC | wc -c | tr -d ' ')B"; done
    echo "PUSH0 $(cast call --rpc-url $RPC --create 0x5f6000526001601ff3)  TSTORE $(cast call --rpc-url $RPC --create 0x60015f5d5f5c6000526001601ff3)";;

  core-seed)   # create the deployer's HyperCore account: send 0.1 HYPE to the HYPE system address
    cast send 0x2222222222222222222222222222222222222222 --value 0.1ether --account $ACCOUNT --rpc-url $RPC --gas-price 1000000000 --priority-gas-price 0;;

  bigblocks-on|bigblocks-off|bigblocks-status)
    MODE=${STEP#bigblocks-}
    if [[ $MODE == status ]]; then PRIVATE_KEY=0x$(openssl rand -hex 32) $PY script/hyperevm/toggle_big_blocks.py status $HLFLAG;
    else PRIVATE_KEY=$(cast wallet private-key --account $ACCOUNT) $PY script/hyperevm/toggle_big_blocks.py $MODE $HLFLAG; fi;;

  dry-run)     # pin the fork block a few behind head: the public RPC is load-balanced and lagging nodes return
               # "invalid block height" mid-simulation otherwise (seen on rpc.hyperliquid.xyz)
    BLK=$(( $(cast block-number --rpc-url $RPC) - 10 ))
    forge script script/deploy/Deploy-all.s.sol --rpc-url $RPC --sig "run()" --sender $DEPLOYER --fork-block-number $BLK "${SKIP[@]}" -vv
    echo; echo "owner arg occurrences in dry-run txs (expect 5): $(jq -r '.transactions[].transaction.input' broadcast/Deploy-all.s.sol/$CHAIN/dry-run/run-latest.json | grep -oic ${OWNER#0x})"
    echo "deployer occurrences in constructor args (expect 0): $(jq -r '.transactions[] | select(.transactionType!="CALL") | .transaction.input' broadcast/Deploy-all.s.sol/$CHAIN/dry-run/run-latest.json | grep -oic ${DEPLOYER#0x})";;

  deploy)      # ~29 txs, --slow waits for each receipt: big blocks land once per minute -> expect ~30-40 min
    forge script script/deploy/Deploy-all.s.sol --rpc-url $RPC --sig "run()" --account $ACCOUNT --sender $DEPLOYER \
      --broadcast --slow "${GAS[@]}" "${SKIP[@]}" -vv;;

  registry)    # forge-chronicles can't run locally; build deployments/json/<chain>.json from the broadcast + onchain checks
    $PY script/hyperevm/build_registry.py $RPC broadcast/Deploy-all.s.sol/$CHAIN/run-latest.json --write;;

  test)        # read-only fork test: ownership + fake pools with swaps on v2/v3/v4 (no gas spent)
    FOUNDRY_SKIP='["src/pkgs/**/audits/**","src/pkgs/**/certora/**","src/pkgs/**/lib/**","src/pkgs/**/test/**","src/pkgs/universal-router/permit2/**","src/pkgs/universal-router/solmate/**","src/pkgs/universal-router-2_0/permit2/**","src/pkgs/universal-router-2_0/solmate/**","src/pkgs/v4-hooks-public/src/aggregator-hooks/**","src/pkgs/**/*.s.sol","*/node_modules/*","test/ReservesLensDeployer.t.sol","test/SwapProxyDeployer.t.sol","test/Dummy.t.sol"]' \
      forge test --match-path test/HyperEVMDeploy.t.sol --fork-url $RPC -vv;;

  smoke)       # real onchain smoke: v2 + v3 + v4 pool create / mint / swap (~20M gas total, ~0.003 HYPE)
    for s in V2SmokeTest V3SmokeTest V4SmokeTest; do
      forge script script/smoke/$s.s.sol:$s --rpc-url $RPC --account $ACCOUNT --sender $DEPLOYER --broadcast --slow --gas-estimate-multiplier 250 "${GAS[@]}" "${SKIP[@]}" -vv
    done;;

  verify)      bash script/hyperevm/verify.sh $CHAIN both;;
  repro)       $PY script/hyperevm/check_reproducibility.py --pin;;

  *) sed -n 2,10p "$0";;
esac

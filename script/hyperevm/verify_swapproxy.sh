#!/usr/bin/env bash
# Verify the canonical SwapProxy (frozen initcode, identical bytecode on every chain) on hyperevmscan + Sourcify by
# re-submitting the exact standard-json that verified it on Base (Etherscan v2 chainid 8453). No recompilation:
# the repo's universal-router profile produces a different build (see deterministic-create-deploy.md).
set -euo pipefail
cd "$(dirname "$0")/../.."
for e in .env ../contracts/.env; do [ -f "$e" ] && source "$e" && break; done; true
: "${ETHERSCAN_API_KEY:?set ETHERSCAN_API_KEY}"
CHAIN=${1:-999}; SRC_CHAIN=8453
ADDR=0x0000000085E102724e78eCd2F45DC9cA239Affad
OUT=$(mktemp -d)
curl -s "https://api.etherscan.io/v2/api?chainid=$SRC_CHAIN&module=contract&action=getsourcecode&address=$ADDR&apikey=$ETHERSCAN_API_KEY" > $OUT/base.json
COMPILER=$(jq -r '.result[0].CompilerVersion' $OUT/base.json); NAME=$(jq -r '.result[0].ContractName' $OUT/base.json)
# SourceCode is a standard-json wrapped in an extra {} pair
jq -r '.result[0].SourceCode' $OUT/base.json | sed 's/^{{/{/; s/}}$/}/' > $OUT/std.json
jq -e '.language and .sources' $OUT/std.json >/dev/null || { echo "unexpected source format"; head -c 300 $OUT/std.json; exit 1; }
CONTRACT_PATH=$(jq -r '.sources | keys[]' $OUT/std.json | grep -i 'SwapProxy.sol$' | head -1)
echo "twin on Base: $NAME $COMPILER, entry $CONTRACT_PATH, $(jq '.sources|length' $OUT/std.json) sources"
echo "local runtime code equal to Base? $( [ "$(cast code $ADDR --rpc-url https://rpc.hyperliquid.xyz/evm)" = "$(cast code $ADDR --rpc-url https://mainnet.base.org)" ] && echo yes || echo NO )"

echo "== hyperevmscan"
R=$(curl -s -X POST "https://api.etherscan.io/v2/api?chainid=$CHAIN" \
  --data-urlencode "apikey=$ETHERSCAN_API_KEY" --data-urlencode "module=contract" --data-urlencode "action=verifysourcecode" \
  --data-urlencode "contractaddress=$ADDR" --data-urlencode "codeformat=solidity-standard-json-input" \
  --data-urlencode "contractname=$CONTRACT_PATH:$NAME" --data-urlencode "compilerversion=$COMPILER" \
  --data-urlencode "sourceCode@$OUT/std.json")
echo "$R"; GUID=$(echo "$R" | jq -r .result)
for i in 1 2 3 4 5 6; do sleep 12; S=$(curl -s "https://api.etherscan.io/v2/api?chainid=$CHAIN&module=contract&action=checkverifystatus&guid=$GUID&apikey=$ETHERSCAN_API_KEY" | jq -r .result); echo "  $S"; [[ $S == Pass* || $S == *lready* ]] && break; done

echo "== sourcify"
curl -s -X POST https://sourcify.dev/server/v2/verify/$CHAIN/$ADDR -H 'content-type: application/json' \
  --data "$(jq -n --slurpfile s $OUT/std.json --arg c "${COMPILER#v}" --arg n "$NAME" --arg p "$CONTRACT_PATH" \
    '{stdJsonInput:$s[0], compilerVersion:$c, contractIdentifier:($p+":"+$n)}')" ; echo
sleep 15; echo "sourcify match: $(curl -s https://sourcify.dev/server/v2/contract/$CHAIN/$ADDR | jq -r '.match // "none"')"
echo "etherscan name: $(curl -s "https://api.etherscan.io/v2/api?chainid=$CHAIN&module=contract&action=getsourcecode&address=$ADDR&apikey=$ETHERSCAN_API_KEY" | jq -r '.result[0].ContractName')"

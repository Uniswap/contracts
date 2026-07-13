#!/bin/bash
# Deploy ReservesLens deterministically via the canonical CREATE2 factory.
# Usage: deploy_reserveslens.sh <chainId> <rpcUrl> <account> <pwFile> [extra cast flags...]
set -uo pipefail
CHAINID=$1; RPC=$2; ACCT=$3; PWFILE=$4; shift 4; EXTRA=("$@")
FAC=0x4e59b44847b379578588920cA78FbF26c0B4956C
EXPECTED=0x0000001b173C3bbF3984D417d8614E3eed34865B
DATA=$(cat "$(dirname "$0")/../../scratchpad-calldata.txt" 2>/dev/null || cat ./scratchpad-calldata.txt)

# already deployed?
code=$(cast code --rpc-url "$RPC" "$EXPECTED" 2>/dev/null)
if [ -n "$code" ] && [ "$code" != "0x" ]; then
  echo "[$CHAINID] already deployed at $EXPECTED (code len ${#code})"; exit 0
fi

echo "[$CHAINID] sending via $ACCT ..."
TXOUT=$(cast send --rpc-url "$RPC" --account "$ACCT" --password-file "$PWFILE" ${EXTRA[@]+"${EXTRA[@]}"} "$FAC" "$DATA" --json 2>&1)
if [ $? -ne 0 ]; then echo "[$CHAINID] SEND FAILED:"; echo "$TXOUT" | tail -5; exit 1; fi
TXHASH=$(echo "$TXOUT" | tail -1 | python3 -c "import sys,json;print(json.load(sys.stdin).get('transactionHash',''))" 2>/dev/null)
echo "[$CHAINID] tx: $TXHASH"

# confirm code landed
code=$(cast code --rpc-url "$RPC" "$EXPECTED" 2>/dev/null)
if [ -n "$code" ] && [ "$code" != "0x" ]; then
  echo "[$CHAINID] OK ReservesLens deployed at $EXPECTED (code len ${#code})"
else
  echo "[$CHAINID] WARNING: no code at $EXPECTED yet (may need to wait for confirmation)"; exit 2
fi

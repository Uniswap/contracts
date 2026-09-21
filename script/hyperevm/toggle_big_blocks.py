#!/usr/bin/env python3
"""Flip the HyperCore `usingBigBlocks` flag for the deployer EOA.

HyperEVM routes a sender's txs to big blocks (30M gas, 1/min) only while this
per-address HyperCore flag is on. Several Uniswap contracts need >3M gas to
deploy (PoolManager, PositionManager, UR, NPM, SwapRouter02 ...), so the flag
must be ON for the deploy and should be switched OFF afterwards.

The flag lives on HyperCore, so the address must already exist as a Core user
(have received any Core spot asset, e.g. send 0.1 HYPE from the EVM to the
system address 0x2222222222222222222222222222222222222222 first).

Usage (the private key never touches disk; it is piped from the cast keystore):
    PRIVATE_KEY=$(cast wallet private-key --account swap-test) \
        python3 script/hyperevm/toggle_big_blocks.py on   [--testnet]
    ... same with `off` after the deploy.
    python3 script/hyperevm/toggle_big_blocks.py status --address <deployer>   # read-only, no key
"""
import argparse
import os
import sys

from eth_account import Account
from hyperliquid.exchange import Exchange
from hyperliquid.info import Info
from hyperliquid.utils import constants


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("state", choices=["on", "off", "status"])
    p.add_argument("--testnet", action="store_true")
    p.add_argument("--address", help="address to inspect for `status` (no key needed)")
    a = p.parse_args()

    url = constants.TESTNET_API_URL if a.testnet else constants.MAINNET_API_URL
    pk = os.environ.get("PRIVATE_KEY")
    if a.state == "status" and a.address:
        acct, address = None, a.address
    else:
        if not pk:
            print("PRIVATE_KEY env var missing (pipe it from `cast wallet private-key --account <name>`)", file=sys.stderr)
            return 2
        acct = Account.from_key(pk)
        address = acct.address
    print(f"network : {'testnet' if a.testnet else 'mainnet'} ({url})")
    print(f"address : {address}")

    info = Info(url, skip_ws=True)
    state = info.spot_user_state(address)
    balances = state.get("balances", [])
    print(f"core spot balances: {balances if balances else 'NONE (address is not a Core user yet)'}")
    if a.state == "status":
        return 0
    if not balances:
        print(
            "\nThis address is not a HyperCore user, so evmUserModify will be rejected.\n"
            "Fix: send ~0.1 HYPE on HyperEVM to 0x2222222222222222222222222222222222222222\n"
            "     (cast send 0x2222222222222222222222222222222222222222 --value 0.1ether --account <name> --rpc-url <rpc>)\n"
            "then re-run this script.",
            file=sys.stderr,
        )
        return 3

    ex = Exchange(acct, url)
    res = ex.use_big_blocks(a.state == "on")
    print("evmUserModify result:", res)
    ok = isinstance(res, dict) and res.get("status") == "ok"
    print("BIG BLOCKS", "ENABLED" if (ok and a.state == "on") else "DISABLED" if ok else "UNCHANGED (error above)")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())

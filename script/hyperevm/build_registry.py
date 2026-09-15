#!/usr/bin/env python3
"""Build deployments/json/<chainId>.json from a Deploy-all broadcast file.

forge-chronicles cannot run locally (needs a forge build without --skip), so this
maps the broadcast's CREATE/CREATE2 txs onto contract names using the fixed
deploy order of Deploy-all.s.sol for the chain-999 task file, then sanity-checks
each address onchain (owner()/factory()/poolManager() ...) before writing.

Usage:
    python3 script/hyperevm/build_registry.py <rpc-url> [broadcast-json] [--write]
Defaults to broadcast/Deploy-all.s.sol/999/run-latest.json and dry-run (prints).
"""
import json
import subprocess
import sys
import time

ORDER = [  # non-CALL txs in Deploy-all order for the 999 task file
    "UniswapV2Factory", "UniswapV2Router02", "UniswapV3Factory", "UniswapInterfaceMulticall",
    "QuoterV2", "TickLens", "NFTDescriptor", "NonfungibleTokenPositionDescriptor#impl",
    "NonfungibleTokenPositionDescriptor", "NonfungiblePositionManager", "V3Migrator", "SwapRouter",
    "PoolManager", "PositionDescriptor#impl", "PositionDescriptor", "PositionManager", "V4Quoter",
    "StateView", "ReservesLens", "PermissionsAdapterFactory", "Quoter", "MixedRouteQuoterV2",
    "SwapRouter02", "UniversalRouter", "SwapProxy", "FeeOnTransferDetector", "FeeCollector",
]
PROXIES = {"NonfungibleTokenPositionDescriptor", "PositionDescriptor"}
# (function, expected-key) checks: expected-key resolves to another contract's address or a literal
CHECKS = {
    "UniswapV2Factory": ("feeToSetter()(address)", "OWNER"),
    "UniswapV2Router02": ("factory()(address)", "UniswapV2Factory"),
    "UniswapV3Factory": ("owner()(address)", "OWNER"),
    "QuoterV2": ("factory()(address)", "UniswapV3Factory"),
    "NonfungiblePositionManager": ("factory()(address)", "UniswapV3Factory"),
    "V3Migrator": ("factory()(address)", "UniswapV3Factory"),
    "SwapRouter": ("factory()(address)", "UniswapV3Factory"),
    "PoolManager": ("owner()(address)", "OWNER"),
    "PositionManager": ("poolManager()(address)", "PoolManager"),
    "V4Quoter": ("poolManager()(address)", "PoolManager"),
    "StateView": ("poolManager()(address)", "PoolManager"),
    "PermissionsAdapterFactory": ("POOL_MANAGER()(address)", "PoolManager"),
    "Quoter": ("factory()(address)", "UniswapV3Factory"),
    "SwapRouter02": ("factoryV2()(address)", "UniswapV2Factory"),
    # FeeOnTransferDetector: factoryV2 is an internal immutable, no getter; presence checked via code size below
    "FeeCollector": ("owner()(address)", "FEE_COLLECTOR_OWNER"),
}


def cast(*args):
    return subprocess.run(["cast", *args], capture_output=True, text=True, check=True).stdout.strip()


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    write = "--write" in sys.argv
    rpc = args[0]
    path = args[1] if len(args) > 1 else "broadcast/Deploy-all.s.sol/999/run-latest.json"
    b = json.load(open(path))
    chain = str(b["chain"])
    task = json.load(open(f"script/deploy/tasks/{chain}/task-pending.json"))
    P = task["protocols"]
    literals = {
        "OWNER": P["v3"]["contracts"]["UniswapV3Factory"]["params"]["initialOwner"]["value"],
        "FEE_COLLECTOR_OWNER": P["util-contracts"]["contracts"]["FeeCollector"]["params"]["owner"]["value"],
    }
    creates = [t for t in b["transactions"] if t["transactionType"] != "CALL"]
    # drop contracts the task file did not deploy (e.g. ReservesLens already at its canonical address on 998)
    order = [n for n in ORDER if not (n == "ReservesLens" and not P["v4"]["contracts"]["ReservesLens"]["deploy"])]
    receipts = {r["transactionHash"]: r for r in b["receipts"]}
    if len(creates) != len(order):
        sys.exit(f"expected {len(order)} create txs, found {len(creates)} - deploy order changed, update ORDER")
    commit = subprocess.run(["git", "rev-parse", "--short", "HEAD"], capture_output=True, text=True).stdout.strip()
    latest, impls = {}, {}
    for name, t in zip(order, creates):
        addr = t["contractAddress"].lower()
        rcpt = receipts[t["hash"]]
        ts = int(cast("block", cast("--to-dec", rcpt["blockNumber"]), "-f", "timestamp", "--rpc-url", rpc)) * 1000
        if name.endswith("#impl"):
            impls[name.split("#")[0]] = addr
            continue
        entry = {"address": addr, "proxy": False, "deploymentTxn": t["hash"], "timestamp": ts, "commitHash": commit}
        if name in PROXIES:
            entry = {"implementation": impls[name], **entry, "proxy": True, "proxyType": "TransparentUpgradeableProxy"}
            admin = [a for a in t.get("additionalContracts", []) if a["transactionType"] == "CREATE"]
            if admin:
                entry["proxyAdmin"] = admin[0]["address"].lower()
        if t["transactionType"] == "CREATE":
            entry["initcodeHash"] = cast("keccak", t["transaction"]["input"])[2:]
        latest[name] = entry
    # onchain sanity checks
    bad = 0
    for name, (sig, key) in CHECKS.items():
        got = cast("call", latest[name]["address"], sig, "--rpc-url", rpc).lower()
        exp = (literals.get(key) or latest[key]["address"]).lower()
        ok = got == exp
        bad += not ok
        print(f"{'OK ' if ok else 'BAD'} {name:36s} {sig.split('(')[0]:14s} {got} {'' if ok else '!= ' + exp}")
    for name in ("NonfungibleTokenPositionDescriptor", "PositionDescriptor"):
        admin = latest[name]["proxyAdmin"]
        got = cast("call", admin, "owner()(address)", "--rpc-url", rpc).lower()
        ok = got == literals["OWNER"].lower()
        bad += not ok
        print(f"{'OK ' if ok else 'BAD'} {name + ' ProxyAdmin':36s} owner          {got}")
    if bad:
        sys.exit(f"{bad} sanity checks failed, not writing")
    latest["Permit2"] = {"address": P["permit2"]["contracts"]["Permit2"]["address"], "proxy": False,
                         "note": "pre-existing canonical Permit2; not deployed by this run"}
    out = {"chainId": int(chain), "latest": latest,
           "history": [{"contracts": latest, "timestamp": int(time.time() * 1000), "commitHash": commit}]}
    if write:
        p = f"deployments/json/{chain}.json"
        json.dump(out, open(p, "w"), indent=2)
        open(p, "a").write("\n")
        print("wrote", p)
    else:
        print(json.dumps({k: v["address"] for k, v in latest.items()}, indent=2))


if __name__ == "__main__":
    main()

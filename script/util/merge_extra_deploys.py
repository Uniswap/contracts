#!/usr/bin/env python3
"""Merge contracts forge-chronicles cannot record into deployments/json/<chain>.json, as listed in a per-chain
extra-deploys config (e.g. script/hyperevm/extra-deploys.json).

Run AFTER `node lib/forge-chronicles Deploy-all.s.sol -c <chain>` has written the JSON for every broadcast.
For each extra entry it fetches the creation tx, computes initcodeHash exactly like chronicles (keccak of the
full creation input) and the block timestamp, sanity-checks any declared view call, and adds the entry to
`latest` and to a history entry per deploy run. commitHash values that are not on origin/main (branch commits, which any
squash or rebase-merge rewrites) are replaced with the pinned base commit, the main commit the branch was based on
when those runs happened. That matches chronicles' own convention, where commitHash is the code the deploy
ran from and never the record commit, and it survives every merge mode.

The base commit is pinned in the config (base_commit) so reruns after merge do not rewrite it. An extra built from
another repository (a router from Uniswap/universal-router, a factory from Uniswap/v4-periphery) can instead cite that
repository's commit with its own "commitHash"; it is kept as is. "aliases" points extra latest keys at an existing
one (e.g. the unversioned UniversalRouter key at UniversalRouter#v2.1.2).

Usage: merge_extra_deploys.py <rpc-url> <chainId> <extra-deploys.json>
"""
import json, os, subprocess, sys


def sh(*a):
    return subprocess.run(a, capture_output=True, text=True, check=True).stdout.strip()


def cast_json(*a):
    j = json.loads(sh("cast", *a, "--json"))
    return j["data"] if "schema_version" in j else j  # newer cast wraps --json output in an envelope


def on_main(c):
    return bool(c) and subprocess.run(["git", "merge-base", "--is-ancestor", c, "origin/main"], capture_output=True).returncode == 0


if len(sys.argv) != 4:
    sys.exit(__doc__)
rpc, chain, cfg_path = sys.argv[1:4]
if subprocess.run(["git", "rev-parse", "--verify", "-q", "origin/main"], capture_output=True).returncode != 0:
    sys.exit("origin/main not available; fetch it first")
path = f"deployments/json/{chain}.json"
reg = json.load(open(path))
cfg = json.load(open(cfg_path))
commit = os.environ.get("COMMIT") or cfg["base_commit"]
if not on_main(commit):
    sys.exit(f"base commit {commit} is not on origin/main; the registry may only cite main commits")

# idempotent: strip anything a previous run of this script added before re-adding it
extra_addrs = {x["address"].lower() for x in cfg["extra"]}
extra_runs = {x["run"] for x in cfg["extra"] if x.get("run") != "deploy-all"}
for k in [k for k, e in reg["latest"].items() if e["address"].lower() in extra_addrs]:
    del reg["latest"][k]
for k in cfg.get("aliases", {}):
    reg["latest"].pop(k, None)
reg["history"] = [hh for hh in reg["history"] if hh.get("note") not in extra_runs]
for hh in reg["history"]:
    for k in [k for k, e in hh["contracts"].items() if e["address"].lower() in extra_addrs]:
        del hh["contracts"][k]

runs = {}
own_commits = set()  # commits of other repositories, cited as is
for x in cfg["extra"]:
    addr, tx = x["address"], x["deploymentTxn"]
    rc = cast_json("receipt", tx, "--rpc-url", rpc)
    created = (rc.get("contractAddress") or "").lower()
    if not created:  # CREATE2 through the deterministic factory: derive keccak(0xff ++ factory ++ salt ++ keccak(initcode))
        txj = cast_json("tx", tx, "--rpc-url", rpc)
        data = txj["input"]
        salt, initcode = "0x" + data[2:66], "0x" + data[66:]
        init_hash = sh("cast", "keccak", initcode)[2:]
        created = "0x" + sh("cast", "keccak", "0xff" + txj["to"][2:] + salt[2:] + init_hash)[-40:].lower()
    if created != addr.lower():
        sys.exit(f"{x['name']}: tx {tx} created {created}, not {addr}")
    if sh("cast", "code", addr, "--rpc-url", rpc) == "0x":
        sys.exit(f"{x['name']}: no code at {addr}")
    ts = int(sh("cast", "block", str(int(rc["blockNumber"], 16)), "-f", "timestamp", "--rpc-url", rpc)) * 1000
    # chronicles hashes the implementation's creation input for proxies, the contract's own otherwise
    hash_tx = x.get("implementationTxn", tx)
    h = sh("cast", "keccak", sh("cast", "tx", hash_tx, "input", "--rpc-url", rpc))[2:]
    e = {"address": addr, "proxy": bool(x.get("proxy")), "deploymentTxn": tx, "initcodeHash": h}
    if x.get("proxy"):
        e = {"implementation": x["implementation"], **e, "proxyType": x["proxyType"], "proxyAdmin": x["proxyAdmin"]}
    if "check" in x:
        sig, exp = x["check"]
        got = sh("cast", "call", addr, sig, "--rpc-url", rpc)
        if got.lower() != exp.lower():
            sys.exit(f"{x['name']}: {sig} returned {got}, expected {exp}")
        print(f"OK  {x['name']:36s} {sig.split('(')[0]} {got}")
    latest = {**e, "timestamp": ts}
    hist = {**e, "input": x["input"]}
    if x.get("run") == "deploy-all":  # belongs to the original Deploy-all history entry and cites its commit
        target = next(hh for hh in reg["history"] if hh["timestamp"] == cfg["deploy_all_run_timestamp"])
        target["contracts"][x["name"]] = hist
        latest["commitHash"] = target["commitHash"]
        latest["timestamp"] = target["timestamp"]  # chronicles stamps latest with the run timestamp
    else:
        if x.get("commitHash"):
            latest["commitHash"] = x["commitHash"]
            own_commits.add(x["commitHash"])
        elif not x.get("nocommit"):
            latest["commitHash"] = commit
        latest["note"] = x.get("note", x["run"])
    reg["latest"][x["name"]] = latest
    if x.get("run") == "deploy-all":
        continue
    r = runs.setdefault(x["run"], {"contracts": {}, "timestamp": 0, "nocommit": x.get("nocommit", False), "commit": x.get("commitHash", commit)})
    r["contracts"][x["name"]] = hist
    r["timestamp"] = max(r["timestamp"], ts)

for label, r in runs.items():
    for k in r["contracts"]:  # latest and history carry the same run timestamp, as chronicles does
        reg["latest"][k]["timestamp"] = r["timestamp"]
    h = {"contracts": r["contracts"], "timestamp": r["timestamp"], "note": label}
    if not r["nocommit"]:
        h["commitHash"] = r["commit"]
    reg["history"].append(h)

# rewrite any commitHash not reachable from origin/main (branch was rewritten) to the tooling commit
for e in list(reg["latest"].values()) + reg["history"]:
    c = e.get("commitHash")
    if c and not on_main(c) and c != commit and c not in own_commits:
        print(f"note: commit {c} not on origin/main, citing {commit} instead")
        e["commitHash"] = commit
for alias, name in cfg.get("aliases", {}).items():
    reg["latest"][alias] = dict(reg["latest"][name])
for name, note in cfg.get("latest_notes", {}).items():
    if name in reg["latest"]:
        reg["latest"][name]["note"] = note

# constructor args chronicles could not decode from the broadcast (forge recorded arguments: null)
for name, inp in cfg.get("patch_inputs", {}).items():
    for hh in reg["history"]:
        for k, e in hh["contracts"].items():
            if k.split("#")[0] == name and not e.get("input", {}).get("constructor"):
                e["input"] = inp
                print(f"note: patched constructor input for {k}")

drop = {a.lower() for a in cfg.get("drop_addresses", [])}
for hh in reg["history"]:
    for k in [k for k, e in hh["contracts"].items() if e["address"].lower() in drop]:
        print(f"note: dropping superseded {k} from history (extra-deploys.json drop_addresses)")
        del hh["contracts"][k]
    for e in hh["contracts"].values():
        e.pop("commitHash", None)
for k in [k for k, e in reg["latest"].items() if e["address"].lower() in drop]:
    del reg["latest"][k]
reg["history"].sort(key=lambda hh: -hh["timestamp"])
json.dump(reg, open(path, "w"), indent=2); open(path, "a").write("\n")
print("merged", len(cfg["extra"]), "entries into", path)

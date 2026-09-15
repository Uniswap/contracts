#!/usr/bin/env python3
"""Prove every briefcase initcode we deploy on HyperEVM can be reproduced from source with the recorded compile
settings, BEFORE deploying. Equal keccak => explorer verification (hyperevmscan / Sourcify) will be an exact match.

    python3 script/hyperevm/check_reproducibility.py            # current submodule pins
    python3 script/hyperevm/check_reproducibility.py --pin      # also checks out the briefcase-era pins for
                                                                # universal-router + v4-periphery (UR, PAF) and restores

Result 2026-09-15: 22/24 match at HEAD pins; UniversalRouter + PermissionsAdapterFactory match only at the
briefcase pins (universal-router 020e1b78, v4-periphery 363226d9), which is what verify.sh does for those two.
SwapProxy uses a frozen canonical initcode (not in this check; same bytecode as every other chain).
"""
import os, subprocess, sys

ENV = {**os.environ, "TENDERLY_PUBLIC_RPC_URL": "http://localhost:1", "TENDERLY_ACCESS_KEY": "dummy"}
BRIEFCASE_REGEN = "84aca41"  # git log -1 --format=%h -- src/briefcase/deployers/universal-router/UniversalRouterDeployer.sol
PINNED = ["src/pkgs/universal-router", "src/pkgs/v4-periphery"]
FQ = {
    "UniswapV2Factory": "src/pkgs/v2-core/contracts/UniswapV2Factory.sol:UniswapV2Factory",
    "UniswapV2Router02": "src/pkgs/v2-periphery/contracts/UniswapV2Router02.sol:UniswapV2Router02",
    "UniswapV3Factory": "src/pkgs/v3-core/contracts/UniswapV3Factory.sol:UniswapV3Factory",
    "UniswapInterfaceMulticall": "src/pkgs/v3-periphery/contracts/lens/UniswapInterfaceMulticall.sol:UniswapInterfaceMulticall",
    "QuoterV2": "src/pkgs/v3-periphery/contracts/lens/QuoterV2.sol:QuoterV2",
    "TickLens": "src/pkgs/v3-periphery/contracts/lens/TickLens.sol:TickLens",
    "NFTDescriptor": "src/pkgs/v3-periphery/contracts/libraries/NFTDescriptor.sol:NFTDescriptor",
    "NonfungiblePositionManager": "src/pkgs/v3-periphery/contracts/NonfungiblePositionManager.sol:NonfungiblePositionManager",
    "V3Migrator": "src/pkgs/v3-periphery/contracts/V3Migrator.sol:V3Migrator",
    "SwapRouter": "src/pkgs/v3-periphery/contracts/SwapRouter.sol:SwapRouter",
    "PoolManager": "src/pkgs/v4-core/src/PoolManager.sol:PoolManager",
    "PositionDescriptor": "src/pkgs/v4-periphery/src/PositionDescriptor.sol:PositionDescriptor",
    "PositionManager": "src/pkgs/v4-periphery/src/PositionManager.sol:PositionManager",
    "V4Quoter": "src/pkgs/v4-periphery/src/lens/V4Quoter.sol:V4Quoter",
    "StateView": "src/pkgs/v4-periphery/src/lens/StateView.sol:StateView",
    "ReservesLens": "src/pkgs/v4-periphery/src/lens/ReservesLens.sol:ReservesLens",
    "PermissionsAdapterFactory": "src/pkgs/v4-periphery/src/hooks/permissionedPools/PermissionsAdapterFactory.sol:PermissionsAdapterFactory",
    "Quoter": "src/pkgs/view-quoter-v3/contracts/Quoter.sol:Quoter",
    "MixedRouteQuoterV2": "src/pkgs/mixed-quoter/src/MixedRouteQuoterV2.sol:MixedRouteQuoterV2",
    "SwapRouter02": "src/pkgs/swap-router-contracts/contracts/SwapRouter02.sol:SwapRouter02",
    "UniversalRouter": "src/pkgs/universal-router/contracts/UniversalRouter.sol:UniversalRouter",
    "FeeOnTransferDetector": "src/pkgs/util-contracts/src/FeeOnTransferDetector.sol:FeeOnTransferDetector",
    "FeeCollector": "src/pkgs/util-contracts/src/FeeCollector.sol:FeeCollector",
}


def sh(*a, **k):
    return subprocess.run(a, capture_output=True, text=True, env=ENV, **k).stdout.strip()


def briefcase_hashes():
    out = sh("forge", "script", "script/hyperevm/BriefcaseHashes.s.sol", "--skip", "*/node_modules/*")
    return {l.split()[0]: l.split()[1] for l in out.splitlines() if l.strip().split() and l.split()[1].startswith("0x")}


def local_hash(fq):
    code = sh("forge", "inspect", fq, "bytecode", "--skip", "*/node_modules/*").splitlines()
    code = code[-1] if code else ""
    return (sh("cast", "keccak", code) if code.startswith("0x") else None), (len(code) - 2) // 2


def pin(to_briefcase: bool):
    for sm in PINNED:
        target = sh("git", "ls-tree", BRIEFCASE_REGEN if to_briefcase else "HEAD", sm).split()[2]
        subprocess.run(["git", "checkout", "-q", target], cwd=sm, check=True)
        subprocess.run(["git", "submodule", "update", "--init", "--recursive", "-q"], cwd=sm, check=True)
        print(f"  {sm} -> {target[:8]}")


def run(names, ref):
    sh("forge", "build", "--skip", "*/node_modules/*")
    bad = []
    for n in names:
        lh, ln = local_hash(FQ[n])
        ok = lh == ref[n]
        bad += [] if ok else [n]
        print(f"{'MATCH' if ok else 'DIFF '} {n:30s} len={ln}")
    return bad


def main():
    ref = briefcase_hashes()
    print(f"briefcase initcodes: {len(ref)}")
    bad = run([n for n in FQ if n in ref], ref)
    if "--pin" in sys.argv and bad:
        print("\nre-checking mismatches at the briefcase-era submodule pins")
        try:
            pin(True)
            bad = run(bad, ref)
        finally:
            print("restoring HEAD pins"); pin(False)
    print("\nALL REPRODUCIBLE" if not bad else f"\nNOT REPRODUCIBLE: {bad}")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()

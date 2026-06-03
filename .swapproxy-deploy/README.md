# SwapProxy — deterministic CREATE2 deployment

This directory is the **source of truth** for deploying `SwapProxy` to one deterministic
address on every chain via CREATE2, so any funded key (not a specific privileged EOA) can
deploy it.

## Canonical values

| Field                     | Value                                                                                         |
| ------------------------- | --------------------------------------------------------------------------------------------- |
| CREATE2 factory           | `0x4e59b44847b379578588920cA78FbF26c0B4956C` (Arachnid, same address on all supported chains) |
| Salt                      | `0xd00319ff7795e528cc1ccd28bd6e08e46a42130d69ab4992d656773ba5fb323c` (vanity-mined)           |
| Initcode hash             | `0x342d83f4d7400dd603e2a6829db9cb032e7f62a2dda94746f2acd4e7e881bb2f`                          |
| **Deterministic address** | **`0x0000000085E102724e78eCd2F45DC9cA239Affad`**                                              |

The salt is vanity-mined for a 4-leading-zero-byte address, matching the Uniswap singleton
convention (Permit2 `0x000000000022…`, CaliburEntry `0x000000009b1d…`). Since the Arachnid
factory uses the salt raw (no `msg.sender` mixing), this address is identical on every chain
from any deployer key.

The full record is in [`create2.json`](./create2.json); the raw initcode is in
[`canonical-initcode.hex`](./canonical-initcode.hex).

## Why we pin the contract, not the Universal Router

The CREATE2 address is `keccak256(0xff ++ factory ++ salt ++ keccak256(initcode))[12:]`. It
depends only on the factory, the salt, and the **initcode** — never on the deployer key or its
nonce.

`SwapProxy`'s entire compile closure is five files:

```
SwapProxy.sol
├─ interfaces/ISwapProxy.sol       → imports IUniversalRouter.sol
├─ interfaces/IUniversalRouter.sol → imports nothing (standalone interface)
├─ solmate/src/tokens/ERC20.sol
└─ solmate/src/utils/SafeTransferLib.sol
```

It calls the router only through the `IUniversalRouter` **interface**, which fixes the
`execute(bytes,bytes[],uint256)` selector at compile time and embeds **zero** router bytecode.
So the Universal Router implementation can keep shipping new versions and this address never
moves. We therefore deploy the **frozen initcode** in this directory rather than recompiling
from the live `src/pkgs/universal-router` submodule.

The only things that can change the address:

1. changing the `execute` selector in `IUniversalRouter.sol`,
2. editing the solmate files in the closure, or
3. changing compiler settings.

## Initcode provenance

`canonical-initcode.hex` is the frozen creation bytecode of the mainnet-verified, 1005-byte
`SwapProxy` runtime, built with:

```
solc 0.8.26+commit.8a97fa7a, evmVersion cancun, optimizer on, runs 4444, viaIR true, bytecodeHash ipfs
```

Note this differs from the repo's `universal-router` foundry profile (`optimizer_runs = 1`,
`bytecode_hash = "none"`), which produces a different 964-byte build. Deploying the frozen
initcode makes every chain converge on the same canonical bytecode.

To reproduce or re-verify, use the standard-JSON input fetched from any chain where the
canonical SwapProxy is already verified (see `reference_swapproxy_canonical_deploy`).

## Deploy

```bash
forge script script/DeploySwapProxyCreate2.s.sol \
  --rpc-url <RPC> --broadcast
```

The script is **idempotent** (no-op if SwapProxy already exists at the canonical address) and
self-checking: it reverts if the frozen initcode hash or the predicted address does not match
the pinned constants.

## Relationship to the legacy address

The pre-CREATE2 deployments live at `0x02e5be68d46dac0b524905bff209cf47ee6db2a9` (plain CREATE
at nonce 0 of `0xb259…aC87`). `SwapProxy` is immutable and ownerless, so those instances stay
on-chain; consumers migrate to the CREATE2 address above. There is no salt/initcode that
reproduces the legacy address via CREATE2 — the two opcodes use different address formulas.

# Uniswap on HyperEVM (chain 999) deployment runbook

Status 2026-09-17: **deployed and verified on mainnet.** 27 contracts live (see `deployments/json/999.json`),
all verified on hyperevmscan + Sourcify, fork test 7/7 and v2/v3/v4 smoke swaps passed onchain. PR: Uniswap/contracts#164.

The canonical UniversalRouter on HyperEVM is the **re-cut 2.2.0 release** (`0x9aFe3C497e19501DB228F28CdBdD29bC98F65DBa`,
tag 2.2.0 @ `64027f3`, includes the #499 permissioned-sweep fix; v4-periphery `a7af5b34` carries the #564 exact-output fix, while #584
(hook-funded exact-output input) was reverted upstream in #601 and is not included), deployed
2026-09-18 from Uniswap/universal-router `script/deployParameters/DeployHyperEVM.s.sol` (universal-router#517;
the 2.1.x copy used for the 2.1.2 router is #518) with the Across SpokePool and
PermissionsAdapterFactory wired. FeeCollector was redeployed the same day pointing at it
(`0xf8a6dee153dfe5c43f66564252b6df7885fa6165`). The first-cut 2.2.0 router and FeeCollector that Deploy-all created on
2026-09-15 are superseded and intentionally not recorded (`extra-deploys.json`, agreed with the reviewer); their txs remain in the
original broadcast file. Never add that first-cut router (`0x0549…492A`) to a permissioned hook allowlist. The 2.1.2 router from 2026-09-17 stays recorded as `UniversalRouter#v2.1.2`.

Companion research: Notion "HyperEVM Security & Deployment Risk Review (Aug 2026)".

## Chain facts (all probed onchain, not assumed)

| Item                                   | Value                                                                                                                                                                                                                    |
| -------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Chain id / gas token                   | 999 / HYPE (18 dec). Testnet 998.                                                                                                                                                                                        |
| RPC                                    | `https://rpc.hyperliquid.xyz/evm` (public, load-balanced, lags: pin blocks). Fallback `https://hyperliquid.drpc.org`. Testnet: `https://rpcs.chain.link/hyperevm/testnet` (the official testnet URL resets connections). |
| Blocks                                 | small: 1s / 3M gas. big: 60s / 30M gas, opt-in per sender via HyperCore `evmUserModify{usingBigBlocks}`.                                                                                                                 |
| Fees                                   | EIP-1559, base ~0.1-0.2 gwei, `eth_maxPriorityFeePerGas` = 0, tips are burned. `eth_bigBlockGasPrice` = 0.1 gwei.                                                                                                        |
| EVM                                    | Cancun without blobs. PUSH0 + TSTORE confirmed. No EIP-7702, so no Calibur / ERC7914Detector.                                                                                                                            |
| WHYPE (WETH9 role)                     | `0x5555555555555555555555555555555555555555`                                                                                                                                                                             |
| Native USDC (Circle)                   | `0xb88339CB7199b77E23DB6E890353E22632Ba630f` (6 dec). Testnet `0x2B3370eE501B4a559b57D449569354196457D8Ab`.                                                                                                              |
| Permit2 / Multicall3 / CREATE2 factory | all present at canonical addresses (pre-seeded in the task file)                                                                                                                                                         |
| Across SpokePool                       | `0x35E63eA3eb0fb7A3bc543C71FB66412e1F6B0E04` (chainId()=999, wrappedNativeToken()=WHYPE)                                                                                                                                 |
| Canonical v3 factory address           | squatted by an unrelated contract. We deploy fresh addresses (like Ink).                                                                                                                                                 |
| Explorer                               | hyperevmscan.io (Etherscan v2, chainid 999, `ETHERSCAN_API_KEY` works). Blockscout: hyperscan.com                                                                                                                        |

## Ownership (baked into the deploy, deployer never owns anything)

Governance owner = `0x2d09d0c2f82c59b19b3c65a48ce2c550bf0921f9`, verified as `UniswapWormholeMessageReceiver`
(hyperevmscan exact-match verified; wormhole chainId 47; ETHEREUM_CHAIN_ID 2; messageSender = canonical
`0xf5F4496219F31CDCBa6130B5402873624585615a`; wormhole core `0x7C0f…3aB3` answers chainId 47,
governanceChainId 1, guardian set 7).

| Contract                                              | How the owner is set                                                                                             |
| ----------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------- |
| UniswapV2Factory.feeToSetter                          | constructor arg                                                                                                  |
| UniswapV3Factory.owner                                | `setOwner(owner)` two txs after creation in the same script run (after `enableFeeAmount(100,1)`)                 |
| PoolManager.owner                                     | constructor arg                                                                                                  |
| ProxyAdmin (v3 NFT descriptor, v4 PositionDescriptor) | TransparentUpgradeableProxy constructor arg                                                                      |
| FeeCollector.owner                                    | `0xbE84D31B2eE049DCb1d8E7c798511632b44d1b55` (ops AWS-KMS EOA, same as every other chain; sweeps need a hot key) |

`test/HyperEVMDeploy.t.sol` asserts all of the above and that the deployer owns nothing.

## What gets deployed (one task file, one broadcast, 29 txs / 27 contracts)

v2 Factory + Router02 · v3 Factory, Multicall, QuoterV2, TickLens, NFTDescriptor lib, NFT descriptor (proxy),
NPM, V3Migrator, SwapRouter · v4 PoolManager, PositionDescriptor (proxy), PositionManager, V4Quoter, StateView,
ReservesLens (canonical CREATE2), PermissionsAdapterFactory · view Quoter v3 · MixedRouteQuoterV2 · SwapRouter02 ·
UniversalRouter (see status: the recorded router is the re-cut 2.2.0 from the universal-router repo) · SwapProxy (canonical CREATE2) · FeeOnTransferDetector · FeeCollector.

Off: Calibur/ERC7914Detector (no 7702), hooks, UR 2.0, UnsupportedProtocol (Across exists), Permit2 (pre-existing).

## Gas and funding

|                           | gas   | at 0.15 gwei           | at 1 gwei (worst case cap) |
| ------------------------- | ----- | ---------------------- | -------------------------- |
| Deploy (measured on fork) | 72.2M | 0.011 HYPE             | 0.072 HYPE                 |
| Smoke scripts v2+v3+v4    | ~20M  | 0.003 HYPE             | 0.02 HYPE                  |
| Core-account seed         |       | 0.1 HYPE (recoverable) |                            |

**Bring 1 HYPE (~$77 at $77/HYPE).** Realistic spend is ~0.02 HYPE; 1 HYPE is a ~10x buffer over the 1 gwei
cap plus the Core seed. Absolute floor 0.3 HYPE.

Gas is HYPE, not USDC. Across only delivers USDC/USDT to HyperEVM, so either:

1. Across → destination "Hyperliquid" (HyperCore) with USDC, buy HYPE on Core spot, "Transfer to EVM". This also
   creates the Core account the big-block flag needs. Recommended.
2. Across → HyperEVM USDC, swap to HYPE on a HyperEVM DEX, then run `core-seed` (0.1 HYPE to `0x2222…2222`).

## Runbook (David runs every signing step; `--account swap-test` prompts for the keystore password)

```bash
cd ~/dev/contracts-hyperevm                 # worktree on branch david/hyperevm-deploy
python3 -m venv .venv && .venv/bin/pip install -r script/hyperevm/requirements.txt
export HL_PYTHON=$PWD/.venv/bin/python
H=./script/hyperevm/hyperevm.sh

$H probe                 # balance, nonce, owner code, predeploys, PUSH0/TSTORE
$H bigblocks-status      # is 0x9701… a Core user yet?
$H core-seed             # only if not: 0.1 HYPE -> 0x2222…2222 (skip if funded via Core)
$H bigblocks-on          # evmUserModify usingBigBlocks=true (key piped from cast, never on disk)
$H dry-run               # expect 5 owner-arg hits, 0 deployer hits, ~97M est gas
$H deploy                # --slow: one big block per minute -> ~30-40 min. Don't Ctrl-C mid-way.
$H registry              # writes deployments/json/999.json with onchain owner/wiring checks
$H test                  # read-only fork test against mainnet, 7 tests
$H smoke                 # optional real swaps (v2/v3/v4), ~0.003 HYPE
$H bigblocks-off         # flip the flag back so normal txs land in 1s blocks
$H verify                # hyperevmscan via Etherscan v2 (needs source submodules, see verify.sh header)
```

Deployed addresses (full list in `deployments/json/999.json`): v2 Factory `0x89e5DB8B5aA49aA85AC63f691524311AEB649eba`,
v3 Factory `0xf0db7b58379503491d857dB50AC9ece64c653918`, PoolManager `0x12D4Fd9C5DeDd00ab8a0bCe2CF0167bbf94b6B1F`,
PositionManager `0x0d7Ab5B3db668128Aff6F70C4eBC71D7d4DA9bf9`, UniversalRouter `0x9aFe3C497e19501DB228F28CdBdD29bC98F65DBa` (2.2.0 re-cut), FeeCollector `0xf8a6dee153dfe5c43f66564252b6df7885fa6165`,
UnsupportedProtocol `0xEEE3Aa3c0d6D6f4E702748DeAcb42991A0094BcF`,

Lessons from the real run: smoke txs need `--gas-estimate-multiplier 250` (the simulation has warm state, each real
tx lands in its own cold big block, the first v2 swap ran out of gas); the public RPC can drop a broadcast setup with
`invalid block height` (retry on drpc); Etherscan refuses to re-verify addresses it already "similar-matched", so
UniswapInterfaceMulticall and PositionManager show fork labels (Huskey/Claw) there, byte-identical code.

### If the broadcast halts midway

Do not restart from scratch. Mark each landed contract `deploy:false` + `address` in the task file, then rerun
`$H deploy`. Big blocks: the mempool holds max 8 pending nonces per address and drops txs after 24h, another reason
for `--slow`. Two traps:

- **UniswapV3Factory**: the factory creation is followed by two more txs in the same run, `enableFeeAmount(100, 1)`
  and `setOwner(owner)`. Marking the factory `deploy:false` skips both. If the run died between them, the deployer is
  still the v3 owner and the 1bp tier is missing. Check `owner()` and `feeAmountTickSpacing(100)` first and send those
  two calls by hand before continuing.
- **Protocol-level flags**: every single-contract protocol (`swap-router-contracts`, `view-quoter-v3`, `mixed-quoter`,
  `universal-router`, `swap-proxy`) returns early on its protocol flag and ignores the per-contract one, so set the
  protocol flag to `false` once that contract has landed or it deploys again.

### Registry

Prerequisites: `git submodule update --init --recursive` for the `src/pkgs/*` packages (chronicles needs every
package's build artifacts) and `git fetch origin main`. Note `src/pkgs/v4-hooks-public` does not compile at its
current pin on a full recursive checkout (missing nested OpenZeppelin file, pre-existing on `main`); leave it
uninitialised or `git submodule deinit` it. The step checks these, backs up the committed JSON, and restores it if
anything fails.

`$H registry` runs forge-chronicles over each Deploy-all broadcast (oldest first), then
`merge_extra_deploys.py` adds what chronicles cannot see (`extra-deploys.json`): the v3 NFT descriptor proxy
(its impl tx is unnamed because of the library link), SwapProxy (canonical CREATE2, unnamed), Permit2
(pre-existing), and the routers deployed from the universal-router repo. It also drops the superseded first-cut
FeeCollector from history (agreed in review) and re-renders `deployments/999.md`.

`commitHash` follows chronicles' convention: the commit of this repo the deploy ran from, never the record commit.
The original Deploy-all run cites `e34ba78` (forge's recorded commit). The later runs were deployed from branch
commits, which any squash or rebase-merge rewrites, so `merge_extra_deploys.py` cites the `main` commit the branch is
based on instead (same contract code; the task files that differed are committed here) and refuses any `COMMIT` that
is not on `origin/main`. No entry cites a branch commit, so the links survive every merge mode.

### Testnet (998)

The driver accepts `testnet` as the second arg. A 998 task file is not committed; derive one from 999 with testnet
USDC `0x2B3370eE501B4a559b57D449569354196457D8Ab`, zero SpokePool, and ReservesLens `deploy:false` (already at its
canonical address there). Dry-run was confirmed passing during prep.

## Explorer verification plan (all 27 contracts, both explorers)

Explorers: **hyperevmscan.io** (Etherscan v2, chainid 999, `ETHERSCAN_API_KEY` works) and **Sourcify** (chain 999 +
998 supported, keyless). hyperscan.com (the old Blockscout) now redirects to hl.eco, which has no verification API
and reads Sourcify, so Sourcify is the second target. Testnet 998: Sourcify only (no Etherscan instance).

Compile settings per contract live in each briefcase deployer's header (solc, runs, via-ir, evm). `verify.sh`
carries them; UniversalRouter and PermissionsAdapterFactory only reproduce at the briefcase-era submodule pins
(`universal-router@020e1b78`, `v4-periphery@363226d9`), which `verify.sh` checks out and restores.

**Step 1, after deploy:** `$H verify` (= `script/hyperevm/verify.sh 999 both`) submits every address from
`deployments/json/999.json` to both explorers with constructor args derived from the task file, then prints a
post-check table (Etherscan ContractName + Sourcify match). Filter with `verify.sh 999 etherscan PoolManager`.

| Group           | Contracts                                                                                                                        | Settings                              | Notes                                                                                |
| --------------- | -------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------- | ------------------------------------------------------------------------------------ |
| v2              | Factory, Router02                                                                                                                | 0.5.16 / 0.6.6, 999999 runs, istanbul |                                                                                      |
| v3              | Factory (800), Multicall/QuoterV2/TickLens/Migrator/SwapRouter (1000000), NPM (2000), NFTDescriptor lib + descriptor impl (1000) | 0.7.6, istanbul                       | descriptor impl links the lib at `0x2E9D…B3ED` via `--libraries`                     |
| proxies         | 2× TransparentUpgradeableProxy, 2× ProxyAdmin                                                                                    | 0.8.26, 200, cancun                   | Etherscan needs "Is this a proxy?" clicked on the UI afterwards to show the impl ABI |
| v4              | PoolManager/V4Quoter/StateView/ReservesLens/PAF (44444444), PositionDescriptor (1), PositionManager (500)                        | 0.8.26, via-ir, cancun                | PositionManager is 500 runs, not 30000 as older notes say                            |
| routers/quoters | SwapRouter02 (0.7.6/1000000), Quoter (0.7.6/200), MixedRouteQuoterV2 (0.8.26/200/via-ir), UR v2.2 (0.8.26/1/via-ir)              |                                       | UR constructor is one RouterParameters struct (11 fields)                            |
| utils           | FeeOnTransferDetector, FeeCollector                                                                                              | 0.8.19, 200, paris                    | FeeCollector args = deploy-time owner (KMS EOA), UR, Permit2, USDC                   |
| canonical       | SwapProxy, ReservesLens                                                                                                          | frozen / via-ir                       | Etherscan links by bytecode match once verified on any chain                         |

Sourcify reports a **partial match** for everything compiled from this repo, because `foundry.toml` sets
`bytecode_hash = none` and there is no metadata hash to match. That is the expected ceiling, not a drift signal;
only SwapProxy (compiled elsewhere with metadata) shows `exact_match`.
Fallbacks: indexer lag (wait 60s, rerun with the contract name filter); `--guess-constructor-args` if an arg is
wrong; `FORCE=1` resubmits an address hyperevmscan already "similar-matched" (needs the Etherscan account whitelisted).
Exercised on the real deploy: 27/27 verified on both explorers. SwapProxy was verified by re-submitting the standard-json that verified it on Base (Etherscan v2 `getsourcecode` on 8453 → `verifysourcecode` on 999); proxies were linked via the `verifyproxycontract` API.

## Superseded deployments (not in the registry)

Deploy-all's first run on 2026-09-15 also created a first-cut UR 2.2.0 and a FeeCollector pointing at it. Both are
live and verified but superseded; they are intentionally left out of `deployments/json/999.json` (agreed in review)
and only their txs remain in `broadcast/Deploy-all.s.sol/999/run-1789501501114.json`.

| Contract                                          | Address                                      | Why not to use                                                                                                   |
| ------------------------------------------------- | -------------------------------------------- | ---------------------------------------------------------------------------------------------------------------- |
| UniversalRouter (first-cut 2.2.0, tag `020e1b78`) | `0x05498c32f8F4825BCD4e5c6325134431B12d492A` | lacks the #499 permissioned-sweep fix and the #564 exact-output fix. **Never allowlist in a permissioned hook.** |
| FeeCollector (first)                              | `0xda7030C3A45EdF79421E8e7F8CcF4d7A3Fa4EeA3` | points at the router above; replaced by `0xf8a6…6165`                                                            |

## Files

- `script/deploy/tasks/999/task-<ts>.json`: the task files as deployed (Deploy-all reads `task-pending.json`; write it
  deliberately from a copy, the driver refuses to guess; the deploy run archives it back as `task-<ts>.json`)
- `script/hyperevm/hyperevm.sh`: step driver · `toggle_big_blocks.py`: HyperCore big-block flag ·
  `merge_extra_deploys.py` + `extra-deploys.json`: registry entries chronicles cannot produce · `verify.sh`:
  both-explorer verification
- `test/HyperEVMDeploy.t.sol`: fork test (ownership, wiring, fake-token pools + swaps on v2/v3/v4 via routers and UR)
- `src/briefcase/deployers/v3-periphery/NFTDescriptorDeployer.sol`: library deploy made idempotent (CREATE2
  collision on 998 where the lib already existed)
- `foundry.toml`: skips `src/pkgs/**/node_modules/**` so a local yarn install inside a submodule cannot break forge

## After deploy

PR stack: base deploy (this branch) → follow-ups. Permit2 is recorded via `extra-deploys.json`.
No ownership handover needed: governance owns everything from block one. Post a Foundation forum note that the
canonical v3 factory address is squatted on HyperEVM and integrators must use the registry address.

# Uniswap on HyperEVM (chain 999) deployment runbook

Status 2026-09-15: plan rehearsed end to end on an Anvil fork of HyperEVM mainnet (full Deploy-all broadcast,
registry build, 7/7 fork tests, v2/v3/v4 smoke scripts). Dry-run also passes against the live mainnet and
testnet (998) RPCs. Not yet broadcast anywhere real.

Companion research: Notion "HyperEVM Security & Deployment Risk Review (Aug 2026)".

## Chain facts (all probed onchain, not assumed)

| Item | Value |
|---|---|
| Chain id / gas token | 999 / HYPE (18 dec). Testnet 998. |
| RPC | `https://rpc.hyperliquid.xyz/evm` (public, load-balanced, lags: pin blocks). Fallback `https://hyperliquid.drpc.org`. Testnet: `https://rpcs.chain.link/hyperevm/testnet` (the official testnet URL resets connections). |
| Blocks | small: 1s / 3M gas. big: 60s / 30M gas, opt-in per sender via HyperCore `evmUserModify{usingBigBlocks}`. |
| Fees | EIP-1559, base ~0.1-0.2 gwei, `eth_maxPriorityFeePerGas` = 0, tips are burned. `eth_bigBlockGasPrice` = 0.1 gwei. |
| EVM | Cancun without blobs. PUSH0 + TSTORE confirmed. No EIP-7702, so no Calibur / ERC7914Detector. |
| WHYPE (WETH9 role) | `0x5555555555555555555555555555555555555555` |
| Native USDC (Circle) | `0xb88339CB7199b77E23DB6E890353E22632Ba630f` (6 dec). Testnet `0x2B3370eE501B4a559b57D449569354196457D8Ab`. |
| Permit2 / Multicall3 / CREATE2 factory | all present at canonical addresses (pre-seeded in the task file) |
| Across SpokePool | `0x35E63eA3eb0fb7A3bc543C71FB66412e1F6B0E04` (chainId()=999, wrappedNativeToken()=WHYPE) |
| Canonical v3 factory address | squatted by an unrelated contract. We deploy fresh addresses (like Ink). |
| Explorer | hyperevmscan.io (Etherscan v2, chainid 999, `ETHERSCAN_API_KEY` works). Blockscout: hyperscan.com |

## Ownership (baked into the deploy, deployer never owns anything)

Governance owner = `0x2d09d0c2f82c59b19b3c65a48ce2c550bf0921f9`, verified as `UniswapWormholeMessageReceiver`
(hyperevmscan exact-match verified; wormhole chainId 47; ETHEREUM_CHAIN_ID 2; messageSender = canonical
`0xf5F4496219F31CDCBa6130B5402873624585615a`; wormhole core `0x7C0f…3aB3` answers chainId 47,
governanceChainId 1, guardian set 7).

| Contract | How the owner is set |
|---|---|
| UniswapV2Factory.feeToSetter | constructor arg |
| UniswapV3Factory.owner | `setOwner(owner)` two txs after creation in the same script run (after `enableFeeAmount(100,1)`) |
| PoolManager.owner | constructor arg |
| ProxyAdmin (v3 NFT descriptor, v4 PositionDescriptor) | TransparentUpgradeableProxy constructor arg |
| FeeCollector.owner | `0xbE84D31B2eE049DCb1d8E7c798511632b44d1b55` (ops AWS-KMS EOA, same as every other chain; sweeps need a hot key) |

`test/HyperEVMDeploy.t.sol` asserts all of the above and that the deployer owns nothing.

## What gets deployed (one task file, one broadcast, 29 txs / 27 contracts)

v2 Factory + Router02 · v3 Factory, Multicall, QuoterV2, TickLens, NFTDescriptor lib, NFT descriptor (proxy),
NPM, V3Migrator, SwapRouter · v4 PoolManager, PositionDescriptor (proxy), PositionManager, V4Quoter, StateView,
ReservesLens (canonical CREATE2), PermissionsAdapterFactory · view Quoter v3 · MixedRouteQuoterV2 · SwapRouter02 ·
UniversalRouter v2.2 (Across SpokePool wired) · SwapProxy (canonical CREATE2) · FeeOnTransferDetector · FeeCollector.

Off: Calibur/ERC7914Detector (no 7702), hooks, UR 2.0, UnsupportedProtocol (Across exists), Permit2 (pre-existing).

## Gas and funding

| | gas | at 0.15 gwei | at 1 gwei (worst case cap) |
|---|---|---|---|
| Deploy (measured on fork) | 72.2M | 0.011 HYPE | 0.072 HYPE |
| Smoke scripts v2+v3+v4 | ~20M | 0.003 HYPE | 0.02 HYPE |
| Core-account seed | | 0.1 HYPE (recoverable) | |

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

Deployer nonce is 0 today. If it stays 0 until deploy, CREATE addresses equal the fork rehearsal:
v2 Factory `0x8bcEaA40B9AcdfAedF85AdF4FF01F5Ad6517937f`, v3 Factory `0x1f7d7550B1b028f7571E69A784071F0205FD2EfA`,
PoolManager `0x12D4Fd9C5DeDd00ab8a0bCe2CF0167bbf94b6B1F`, PositionManager `0x0d7Ab5B3db668128Aff6F70C4eBC71D7d4DA9bf9`,
UniversalRouter `0xC01397e3d679Ec979F012C55B01cEcfBf6E22715`. Don't rely on these, read them from the broadcast.

### If the broadcast halts midway
Do not restart from scratch. Mark each landed contract `deploy:false` + `address` in
`script/deploy/tasks/999/task-pending.json`, set `protocols.swap-router-contracts.deploy=false` if SwapRouter02
already landed (it ignores the per-contract flag), rerun `$H deploy`. Big blocks: the mempool holds max 8 pending
nonces per address and drops txs after 24h, another reason for `--slow`.

### Testnet (998) rehearsal, optional
`script/deploy/tasks/998/task-pending.json` mirrors mainnet with testnet USDC, zero SpokePool, and ReservesLens
pre-existing. Needs testnet HYPE on 0x9701… (faucet at app.hyperliquid-testnet.xyz needs a mainnet Core account).
Then the same steps with `testnet` as the second arg. Dry-run already passes there.

## Explorer verification plan (all 27 contracts, both explorers)

Explorers: **hyperevmscan.io** (Etherscan v2, chainid 999, `ETHERSCAN_API_KEY` works) and **Sourcify** (chain 999 +
998 supported, keyless). hyperscan.com (the old Blockscout) now redirects to hl.eco, which has no verification API
and reads Sourcify, so Sourcify is the second target. Testnet 998: Sourcify only (no Etherscan instance).

**Step 0, before deploy: prove reproducibility.** `python3 script/hyperevm/check_reproducibility.py --pin`
recompiles every source with the recorded settings and compares keccak(creation code) with the briefcase initcode
that Deploy-all actually ships. Result 2026-09-15: **24/24 exact matches** (22 at the current submodule pins;
UniversalRouter and PermissionsAdapterFactory only at the briefcase-era pins `universal-router@020e1b78`,
`v4-periphery@363226d9`, which verify.sh checks out and restores automatically). SwapProxy is a frozen canonical
initcode, same bytes as every other chain.

**Step 1, after deploy:** `$H verify` (= `script/hyperevm/verify.sh 999 both`) submits every address from
`deployments/json/999.json` to both explorers with constructor args derived from the task file, then prints a
post-check table (Etherscan ContractName + Sourcify match). Filter with `verify.sh 999 etherscan PoolManager`.

| Group | Contracts | Settings | Notes |
|---|---|---|---|
| v2 | Factory, Router02 | 0.5.16 / 0.6.6, 999999 runs, istanbul | |
| v3 | Factory (800), Multicall/QuoterV2/TickLens/Migrator/SwapRouter (1000000), NPM (2000), NFTDescriptor lib + descriptor impl (1000) | 0.7.6, istanbul | descriptor impl links the lib at `0x2E9D…B3ED` via `--libraries` |
| proxies | 2× TransparentUpgradeableProxy, 2× ProxyAdmin | 0.8.26, 200, cancun | Etherscan needs "Is this a proxy?" clicked on the UI afterwards to show the impl ABI |
| v4 | PoolManager/V4Quoter/StateView/ReservesLens/PAF (44444444), PositionDescriptor (1), PositionManager (500) | 0.8.26, via-ir, cancun | PositionManager is 500 runs, not 30000 as older notes say |
| routers/quoters | SwapRouter02 (0.7.6/1000000), Quoter (0.7.6/200), MixedRouteQuoterV2 (0.8.26/200/via-ir), UR v2.2 (0.8.26/1/via-ir) | | UR constructor is one RouterParameters struct (11 fields) |
| utils | FeeOnTransferDetector, FeeCollector | 0.8.19, 200, paris | FeeCollector args = deploy-time owner (KMS EOA), UR, Permit2, USDC |
| canonical | SwapProxy, ReservesLens | frozen / via-ir | Etherscan links by bytecode match once verified on any chain |

Fallbacks: indexer lag (wait 60s, rerun with the contract name filter); `--guess-constructor-args` if an arg
is wrong; Sourcify partial match means metadata drift, re-run reproducibility check for that contract.
Not yet exercised against a live deploy (nothing is deployed); the compile side is fully proven.

## Files
- `script/deploy/tasks/999/task-pending.json`: task file
- `script/hyperevm/hyperevm.sh`: step driver · `toggle_big_blocks.py`: HyperCore flag · `build_registry.py`:
  broadcast → deployments JSON with onchain checks · `verify.sh`: both-explorer verification ·
  `check_reproducibility.py` + `BriefcaseHashes.s.sol`: pre-deploy bytecode == source proof
- `test/HyperEVMDeploy.t.sol`: fork test (ownership, wiring, fake-token pools + swaps on v2/v3/v4 via routers and UR)
- `src/briefcase/deployers/v3-periphery/NFTDescriptorDeployer.sol`: library deploy made idempotent (CREATE2
  collision on 998 where the lib already existed)

## After deploy
PR stack: base deploy (this branch) → follow-ups. Record adopted Permit2 in the registry (done by build_registry).
No ownership handover needed: governance owns everything from block one. Post a Foundation forum note that the
canonical v3 factory address is squatted on HyperEVM and integrators must use the registry address.

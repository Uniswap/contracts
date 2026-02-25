# Aggregator Hook Scripts

Aggregator hook pool discovery and creation utilities. Merged from agg-hook-tests.

## Factories

Aggregator Hook factories should be deployed before running any of these scripts, although not strictly necessary. If desired you can deploy and initialize directly from an EOA. If Factories are not deployed, you must use --self-deploy when creating pools.

## Scripts

### Historical discovery (one-time full scrape)

| Script | Description |
|--------|-------------|
| `historical/FluidDexLite.ts` | Scrape LogInitialize events from FluidDexLite |
| `historical/FluidDexT1.ts` | Scrape LogDexDeployed events from FluidDexFactory |
| `historical/StableSwapNG.ts` | Enumerate pool_count + pool_list from Curve StableSwap-NG factory |

### Polling discovery (checkpoint-based, for cron)

| Script | Description |
|--------|-------------|
| `polling/FluidDexLite.ts` | Poll LogInitialize since checkpoint |
| `polling/FluidDexT1.ts` | Poll LogDexDeployed since checkpoint |
| `polling/StableSwapNG.ts` | Poll PlainPoolDeployed/MetaPoolDeployed events since checkpoint; fetch last N pools by index |

### Pool creation

| Script | Description |
|--------|-------------|
| `src/createPools.ts` | Create Uniswap v4 hooks from discovered pool configs |

---

## Environment variables

All discovery scripts use chain-ID-suffixed env vars. Use `VAR_<chainId>` (e.g. `RPC_URL_1`, `RPC_URL_8453`) or `VAR` for single-chain usage.

### By script

| Script | Required | Optional |
|--------|----------|----------|
| **fluiddexlite** (hist) | `RPC_URL` | `DEX_LITE_RESOLVER_ADDRESS` (default mainnet resolver) |
| **fluiddexlite** (poll) | `RPC_URL`, `DEX_LITE_ADDRESS` | — |
| **fluiddext1** (poll + hist) | `RPC_URL`, `FLUID_DEX_RESOLVER` | `FLUID_DEX_FACTORY`, `FACTORY_ADDRESS`, `RPS`, `CONCURRENCY` |
| **stableswapng** (poll + hist) | `RPC_URL` | `FACTORY_ADDRESS`, `RPS`, `CONCURRENCY`, `FINALITY_BLOCKS`, `LOOKBACK_BLOCKS` (poll only) |

### Polling-only env (optional)

| Env | Default | Description |
|-----|---------|-------------|
| `FINALITY_BLOCKS` | 10 | Subtract from latest; checkpoint = last scanned block |
| `LOOKBACK_BLOCKS` | 200000 | Used when checkpoint missing and no `--start-block` |

---

## CLI arguments

All discovery scripts require `--chain-id <n>`.

### Common args

| Arg | Default (poll) | Default (hist) | Description |
|-----|----------------|----------------|-------------|
| `--chain-id` | (required) | (required) | Chain ID; selects env vars |
| `--output-dir` | `detected` | `detected` | Output base dir; files go to `output-dir/chain-id/<filename>.json` |
| `--checkpoint-dir` | `checkpoints` | — | Checkpoint dir (polling only) |
| `--chunk-blocks` | 10000 | 100000 | Block chunk size for getLogs |
| `--start-block` | — | — | Start scan from this block. Override checkpoint for polling. |

### Historical-only args

| Arg | Default | Description |
|-----|---------|-------------|
| `--end-block` | latest | End block for event scan |

### Script-specific args

| Script | Arg | Default | Description |
|--------|-----|---------|-------------|
| fluiddext1 (hist) | `--mode` | enumerate | `logs` \| `enumerate` \| `both` |
| stableswapng (poll) | `--chunk-blocks` | 10000 | Block chunk size for event scan |
| stableswapng (hist) | `--chunk` | 500 | pool_list batch size |
| stableswapng (hist) | `--start-index` | 0 | Start pool_list index |

---

## Output paths

- **Output**: `{OUTPUT_DIR}/{CHAIN_ID}/{OUTPUT_FILE}.json`
- **Checkpoint** (polling): `{CHECKPOINT_DIR}/{CHAIN_ID}/{CHECKPOINT_FILE}.json`

| Script | Output file | Checkpoint file |
|--------|-------------|-----------------|
| fluiddexlite | fluiddexlite-pools.json | dexlite_checkpoint.json |
| fluiddext1 | fluiddext1-pools.json | fluiddext1_checkpoint.json |
| stableswapng | stableswapng-pools.json | stableswapng_checkpoint.json |

---

## Example invocations

```bash
# From contracts/aggregator-hooks/ directory:
cd aggregator-hooks && npm install

# Historical fluiddexlite on mainnet
npx tsx historical/FluidDexLite.ts --chain-id 1

# Historical fluiddext1 on Base
npx tsx historical/FluidDexT1.ts --chain-id 8453 --output-dir output

# Polling fluiddexlite on mainnet
npx tsx polling/FluidDexLite.ts --chain-id 1

# Historical stableswapng with custom chunk
npx tsx historical/StableSwapNG.ts --chain-id 1 --chunk 200

# createPools with chain-id (uses RPC_URL_1 from env)
npx tsx src/createPools.ts detected/1/fluiddexlite-pools-curated.json 0xFactoryAddr --chain-id 1
```

---

## createPools

### Arguments

| Arg | Required | Default | Description |
|-----|----------|---------|-------------|
| `jsonFile` | yes | — | Path to JSON file with pool configs (each must have `poolType`) |
| `factoryAddress` | yes* | — | Factory contract address (*required when not using `--self-deploy`) |
| `--self-deploy` | no | — | Deploy hooks from wallet instead of via factory |
| `--chain-id <n>` | no | — | Chain ID; selects `RPC_URL_<n>` from env |
| `--registry-dir <path>` | no | — | Append deployed pools to `deployed-<poolType>.json` in this dir |
| `--dry-run` | no | — | Simulate forge scripts without broadcasting |
| `--verbose`, `-v` | no | — | Run forge scripts with `-vvvv` |
| `--start-at <n>` | no | 1 | Start at 1-based pool index (skip earlier pools). Use to resume. |
| `--jobs <n>`, `-j <n>` | no | 1 | Parallel salt mining workers (1–16). Speeds up mining. |

**Modes:**

- **Factory mode:** `createPools.ts pools.json 0xFactoryAddr [--chain-id 1] [--registry-dir ./deployed-pools]`
- **Self-deploy:** `createPools.ts pools.json --self-deploy [--chain-id 1] [--registry-dir ./deployed-pools]`

### Environment variables

| Env | Description |
|-----|-------------|
| `RPC_URL` or `RPC_URL_<chainId>` | RPC endpoint (use `RPC_URL_1` etc. when `--chain-id` is set) |
| `PRIVATE_KEY` | Signing key for transactions (required even with `--dry-run`) |

### Dry run and verbose

Use `--dry-run` to simulate without broadcasting:

```bash
npx tsx src/createPools.ts your-pools.json --self-deploy --chain-id 1 --dry-run
```

Use `--verbose` or `-v` to run forge scripts with maximum verbosity (`-vvvv`) and log full forge output on errors.

---

## Setup

### TypeScript scripts

```bash
cd aggregator-hooks
npm install
cp .env.example .env
# Edit .env with your values
```

### Solidity (mine_hook, createPools)

The `createPools` script and `mine_hook.sh` run from the **contracts/** directory (project root). They require:

1. **v4-hooks-public** (aggregator-hooks branch): Already added as submodule. Ensure it's on the `aggregator-hooks` branch:
   ```bash
   cd lib/v4-hooks-public && git fetch origin aggregator-hooks && git checkout aggregator-hooks
   git submodule update --init --recursive
   ```

2. **Foundry**: `forge` must be available. The scripts use `script/SelfCreateHook.s.sol` and `lib/v4-hooks-public/script/MineAggregatorHook.s.sol`.

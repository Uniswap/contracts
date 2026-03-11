# Aggregator Hook Scripts

Aggregator hook pool discovery and creation utilities. Merged from agg-hook-tests.

## Factories

Aggregator Hook factories should be deployed before running any of these scripts, although not strictly necessary. If desired you can deploy and initialize directly from an EOA. If Factories are not deployed, you must use --self-deploy when creating pools.

## Scripts

### Historical discovery (one-time full scrape)

| Script                       | Description                                                       |
| ---------------------------- | ----------------------------------------------------------------- |
| `historical/FluidDexLite.ts` | Scrape LogInitialize events from FluidDexLite                     |
| `historical/FluidDexT1.ts`   | Scrape LogDexDeployed events from FluidDexFactory                 |
| `historical/StableSwapNG.ts` | Enumerate pool_count + pool_list from Curve StableSwap-NG factory |

### Polling discovery (incremental, checkpoint-based)

Polling scripts scan only new blocks since the last run. They load and update a checkpoint file to avoid re-processing. Use these for ongoing discovery (e.g. cron) instead of historical one-time scrapes.

| Script                    | Description                                                                  |
| ------------------------- | ---------------------------------------------------------------------------- |
| `polling/FluidDexLite.ts` | Scan LogInitialize events from FluidDexLite since checkpoint                 |
| `polling/FluidDexT1.ts`   | Scan LogDexDeployed events from FluidDexFactory; fetch tokens via resolver   |
| `polling/StableSwapNG.ts` | Scan PlainPoolDeployed/MetaPoolDeployed events; fetch new pools from factory |

All polling scripts append new pools to the same output files used by historical scripts, in createPools format.

**Polling options:**

| Arg                | Default       | Description                                                     |
| ------------------ | ------------- | --------------------------------------------------------------- |
| `--checkpoint-dir` | `checkpoints` | Where to store/load checkpoint files (`{dir}/{chainId}/*.json`) |
| `--start-block`    | —             | Override checkpoint; start scan from this block                 |

**Polling env vars:**

| Env               | Default | Description                                                                 |
| ----------------- | ------- | --------------------------------------------------------------------------- |
| `FINALITY_BLOCKS` | 10      | Blocks to subtract from latest; checkpoint stops before finality for safety |
| `LOOKBACK_BLOCKS` | 200000  | Blocks to scan when checkpoint is missing and no `--start-block` given      |

### Pool creation

| Script               | Description                                          |
| -------------------- | ---------------------------------------------------- |
| `src/createPools.ts` | Create Uniswap v4 hooks from discovered pool configs |

---

## Environment variables

All discovery scripts use chain-ID-suffixed env vars. Use `VAR_<chainId>` (e.g. `RPC_URL_1`, `RPC_URL_8453`) or `VAR` for single-chain usage.

### By script

| Script           | Required                        | Optional                                                     |
| ---------------- | ------------------------------- | ------------------------------------------------------------ |
| **fluiddexlite** | `RPC_URL`                       | `DEX_LITE_RESOLVER_ADDRESS` (default mainnet resolver)       |
| **fluiddext1**   | `RPC_URL`, `FLUID_DEX_RESOLVER` | `FLUID_DEX_FACTORY`, `FACTORY_ADDRESS`, `RPS`, `CONCURRENCY` |
| **stableswapng** | `RPC_URL`                       | `FACTORY_ADDRESS`, `RPS`, `CONCURRENCY`                      |

**Polling scripts** use the same env vars as their historical counterparts (fluiddexlite, fluiddext1, stableswapng), plus `FINALITY_BLOCKS` and `LOOKBACK_BLOCKS` (see Polling env vars above). FluidDexLite polling also requires `DEX_LITE_ADDRESS`.

---

## CLI arguments

All discovery scripts require `--chain-id <n>`.

### Common args

| Arg              | Default    | Description                                                        |
| ---------------- | ---------- | ------------------------------------------------------------------ |
| `--chain-id`     | (required) | Chain ID; selects env vars                                         |
| `--output-dir`   | `detected` | Output base dir; files go to `output-dir/chain-id/<filename>.json` |
| `--chunk-blocks` | 100000     | Block chunk size for getLogs                                       |
| `--start-block`  | —          | Start scan from this block                                         |

### Discovery args

| Arg           | Default | Description              |
| ------------- | ------- | ------------------------ |
| `--end-block` | latest  | End block for event scan |

### Script-specific args

| Script       | Arg                | Default       | Description                     |
| ------------ | ------------------ | ------------- | ------------------------------- |
| fluiddext1   | `--mode`           | enumerate     | `logs` \| `enumerate` \| `both` |
| stableswapng | `--chunk`          | 500           | pool_list batch size            |
| stableswapng | `--start-index`    | 0             | Start pool_list index           |
| **polling**  | `--checkpoint-dir` | `checkpoints` | Checkpoint storage directory    |

---

## Output paths

- **Output**: `{OUTPUT_DIR}/{CHAIN_ID}/{OUTPUT_FILE}.json`

| Script       | Output file             |
| ------------ | ----------------------- |
| fluiddexlite | fluiddexlite-pools.json |
| fluiddext1   | fluiddext1-pools.json   |
| stableswapng | stableswapng-pools.json |

Polling scripts write to the same output paths and append new pools. Checkpoints go to `{checkpoint-dir}/{chainId}/{protocol}_checkpoint.json`.

---

## Example invocations

**Important:** Run all commands from the `aggregator-hooks/` directory so the scripts load `.env` from that folder.

```bash
# From contracts/aggregator-hooks/ directory:
cd aggregator-hooks && npm install
cp .env.example .env
# Edit .env with your values, then run:

# Historical fluiddexlite on mainnet
npx tsx historical/FluidDexLite.ts --chain-id 1

# Historical fluiddext1 on Base
npx tsx historical/FluidDexT1.ts --chain-id 8453 --output-dir output

# Historical stableswapng with custom chunk
npx tsx historical/StableSwapNG.ts --chain-id 1 --chunk 200

# Polling (incremental; use cron or run periodically)
npx tsx polling/FluidDexLite.ts --chain-id 1
npx tsx polling/FluidDexT1.ts --chain-id 8453 --output-dir output
npx tsx polling/StableSwapNG.ts --chain-id 1 --checkpoint-dir checkpoints

# createPools with chain-id (uses RPC_URL_1 from env)
npx tsx src/createPools.ts detected/1/fluiddexlite-pools-curated.json 0xFactoryAddr --chain-id 1

# createPools with Etherscan verification (ETHERSCAN_API_KEY must be set)
npx tsx src/createPools.ts detected/1/fluiddexlite-pools-curated.json 0xFactoryAddr --chain-id 1 --verify

# createPools self-deploy with Blockscout verification (BLOCKSCOUT_API_URL_1 must be set in .env)
npx tsx src/createPools.ts detected/1/fluiddext1-pools-curated.json --self-deploy --chain-id 1 --verify
```

---

## createPools

### Arguments

| Arg                            | Required | Default         | Description                                                                  |
| ------------------------------ | -------- | --------------- | ---------------------------------------------------------------------------- |
| `jsonFile`                     | yes      | —               | Path to JSON file with pool configs (each must have `poolType`)              |
| `factoryAddress`               | yes\*    | —               | Factory contract address (\*required when not using `--self-deploy`)         |
| `--self-deploy`                | no       | —               | Deploy hooks from wallet instead of via factory                              |
| `--chain-id <n>`               | no       | —               | Chain ID; selects `RPC_URL_<n>` from env                                     |
| `--registry-dir <path>`        | no       | `created-pools` | Append deployed pools to `deployed-<poolType>.json` in this dir              |
| `--dry-run`                    | no       | —               | Simulate forge scripts without broadcasting                                  |
| `--verbose`, `-v`              | no       | —               | Run forge scripts with `-vvvv`                                               |
| `--start-at <n>`               | no       | 1               | Start at 1-based pool index (skip earlier pools). Use to resume.             |
| `--jobs <n>`, `-j <n>`         | no       | 1               | Parallel salt mining workers (1–16). Speeds up mining.                       |
| `--priority-gas-price <price>` | no       | RPC default     | Max priority fee per gas for EIP1559 (e.g. `3gwei`). Speeds up tx inclusion. |
| `--verify`                     | no       | —               | Submit hook contract for block explorer verification after deployment        |
| `--verifier <name>`            | no       | `etherscan`     | Verifier backend: `etherscan`, `blockscout`, or `sourcify`                   |
| `--verifier-url <url>`         | no       | —               | Custom verifier API URL. Auto-selected if `BLOCKSCOUT_API_URL` env is set.   |
| `--compiler-version <ver>`     | no       | from artifact   | Solc version to pass to the verifier (e.g. `0.8.24`). See note below.        |

**Modes:**

- **Factory mode:** `createPools.ts pools.json 0xFactoryAddr [--chain-id 1] [--registry-dir ./deployed-pools]`
- **Self-deploy:** `createPools.ts pools.json --self-deploy [--chain-id 1] [--registry-dir ./deployed-pools]`

### Environment variables

| Env                                                    | Description                                                                        |
| ------------------------------------------------------ | ---------------------------------------------------------------------------------- |
| `RPC_URL` or `RPC_URL_<chainId>`                       | RPC endpoint (use `RPC_URL_1` etc. when `--chain-id` is set)                       |
| `PRIVATE_KEY`                                          | Signing key for transactions (required even with `--dry-run`)                      |
| `POOL_MANAGER` or `POOL_MANAGER_<chainId>`             | Uniswap v4 PoolManager address (required for self-deploy)                         |
| `ETHERSCAN_API_KEY` or `ETHERSCAN_API_KEY_<chainId>`   | API key for Etherscan verification (required when using `--verify` with Etherscan) |
| `BLOCKSCOUT_API_URL` or `BLOCKSCOUT_API_URL_<chainId>` | Blockscout API URL. If set, `--verify` automatically uses Blockscout.              |

**StableSwap (stableswap):** `STABLESWAP_METAREGISTRY_ADDRESS_<chainId>` — Curve MetaRegistry for meta pool rejection (required for self-deploy).

**StableSwap-NG (stableswapng):** `STABLESWAPNG_FACTORY_ADDRESS_<chainId>` or `FACTORY_ADDRESS_<chainId>` — Curve StableSwap NG factory for meta pool rejection. Defaults to mainnet `0x6A8cbed756804B16E05E741eDaBd5cB544AE21bf` if unset.

### Security

- `PRIVATE_KEY` is passed to forge via the process environment only (not the command line).

### Dry run and verbose

Use `--dry-run` to simulate without broadcasting:

```bash
npx tsx src/createPools.ts your-pools.json --self-deploy --chain-id 1 --dry-run
```

Use `--verbose` or `-v` to run forge scripts with maximum verbosity (`-vvvv`) and log full forge output on errors.

### Contract verification

Pass `--verify` to automatically submit each deployed hook for block explorer verification after deployment. Verification failures are non-fatal — the script logs a warning and continues.

**Etherscan:**

```bash
# Requires ETHERSCAN_API_KEY or ETHERSCAN_API_KEY_1 in env
npx tsx src/createPools.ts pools.json 0xFactory --chain-id 1 --verify
npx tsx src/createPools.ts pools.json --self-deploy --chain-id 1 --verify
```

**Blockscout (via `--verifier-url`):**

```bash
npx tsx src/createPools.ts pools.json 0xFactory --chain-id 1 --verify \
  --verifier blockscout \
  --verifier-url https://eth.blockscout.com/api
```

**Blockscout (via env var, no extra flags needed):**

Set `BLOCKSCOUT_API_URL` (or `BLOCKSCOUT_API_URL_<chainId>`) in `.env`. When this is set, `--verify` automatically uses Blockscout without needing `--verifier` or `--verifier-url` on the command line:

```bash
# .env
BLOCKSCOUT_API_URL_1=https://eth.blockscout.com/api
BLOCKSCOUT_API_URL_8453=https://base.blockscout.com/api

# Then just:
npx tsx src/createPools.ts pools.json 0xFactory --chain-id 1 --verify
```

**Well-known Blockscout API URLs:**

| Chain    | Chain ID | URL                                   |
| -------- | -------- | ------------------------------------- |
| Mainnet  | 1        | `https://eth.blockscout.com/api`      |
| Base     | 8453     | `https://base.blockscout.com/api`     |
| Arbitrum | 42161    | `https://arbitrum.blockscout.com/api` |
| Optimism | 10       | `https://optimism.blockscout.com/api` |

> **Note:** Blockscout's public instances do not require an API key. `ETHERSCAN_API_KEY` can be omitted when using Blockscout.

#### Compiler version and factory mode

In factory mode, the factory embeds the hook's bytecode at _its own_ compile time. Verification must use the same solc version the factory was compiled with — not necessarily the version currently installed locally.

The script auto-detects the compiler version from the build artifact in `out/` (populated by `forge build`). This is reliable **as long as** the installed forge/solc version matches what built the factory. If it doesn't, pass `--compiler-version` explicitly:

```bash
# Factory was compiled with 0.8.24; local solc is different
npx tsx src/createPools.ts pools.json 0xFactory --chain-id 1 --verify --compiler-version 0.8.24
```

To check what version the factory was originally built with, look at the git history or the `out/` artifact at the time of factory deployment. In self-deploy mode this is not an issue — forge compiles and verifies with the same local version automatically.

---

## Setup

### TypeScript scripts

```bash
cd aggregator-hooks
npm install
cp .env.example .env
# Edit .env with your values
```

**Run all discovery and createPools commands from the `aggregator-hooks/` directory** so they load the `.env` file in that folder.

### Solidity (mine_hook, createPools)

The `createPools` script and `mine_hook.sh` run from the **contracts/** directory (project root). They require:

> **Note:** When running `createPools` via `npx tsx src/createPools.ts`, run it from **aggregator-hooks/** so it loads `aggregator-hooks/.env`. The forge scripts invoked by createPools run from contracts/ but inherit env vars from the parent process.

1. **v4-hooks-public** (aggregator-hooks branch): Already added as submodule. Ensure it's on the `aggregator-hooks` branch:

   ```bash
   cd lib/v4-hooks-public && git fetch origin aggregator-hooks && git checkout aggregator-hooks
   git submodule update --init --recursive
   ```

2. **Foundry**: `forge` must be available. The scripts use `script/SelfCreateHook.s.sol` and `lib/v4-hooks-public/script/MineAggregatorHook.s.sol`.

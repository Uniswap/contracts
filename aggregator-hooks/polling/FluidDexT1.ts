/**
 * Fluid Dex T1 pool discovery (checkpoint-based polling):
 * - loads checkpoint which stores lastProcessedBlock
 * - scans blocks since checkpoint for LogDexDeployed events from FluidDexFactory
 * - for each new dex, fetches currency0/currency1 via resolver.getDexTokens
 * - appends to output in createPools format
 *
 * Usage:
 *   npx tsx polling/fluiddext1.ts --chain-id 1
 *
 * Options:
 *   --chain-id <n>          (required) Chain ID; loads RPC_URL_<n>, FLUID_DEX_RESOLVER_<n>, etc.
 *   --output-dir <path>     output directory (default: detected); writes to output-dir/chain-id/fluiddext1-pools.json
 *   --checkpoint-dir <path>  checkpoint directory (default: checkpoints)
 *   --chunk-blocks <n>      block chunk size for getLogs (default: 10000)
 *   --start-block <n>       (optional) override checkpoint; start scan from this block
 *
 * Env vars (use VAR_<chainId> or VAR for single chain):
 *   RPC_URL                 (required)
 *   FLUID_DEX_RESOLVER (required)
 *   FLUID_DEX_FACTORY       (optional, default mainnet)
 *   FINALITY_BLOCKS         (optional, default 10) subtract from latest; checkpoint = last scanned block
 *   LOOKBACK_BLOCKS         (optional, default 200000) used when checkpoint missing and no --start-block
 */

import "dotenv/config";
import fs from "node:fs";
import path from "node:path";
import { ethers } from "ethers";
import {
  parseArgs,
  getEnvForChain,
  toInt,
  resolveOutputPath,
  resolveCheckpointPath,
} from "@src/cli";

const OUTPUT_FILE = "fluiddext1-pools.json";
const CHECKPOINT_FILE = "fluiddext1_checkpoint.json";
const DEFAULT_FACTORY = "0x91716c4eDA1fB55e84Bf8b4c7085f84285c19085";

/** Fluid native token; map to address(0) for Uniswap v4 pool init */
const FLUID_NATIVE = "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE";
const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";

function toUniswapV4Currency(addr: string): string {
  return addr.toLowerCase() === FLUID_NATIVE.toLowerCase()
    ? ZERO_ADDRESS
    : ethers.getAddress(addr);
}

type Checkpoint = {
  chainId: number;
  factory: string;
  lastProcessedBlock: number;
  updatedAt: string;
};

/** Same shape as createPools.ts FluidDexT1PoolConfig */
type CreatePoolsFluidDexT1Config = {
  poolType: "fluiddext1";
  fluidPool: string;
  currency0: string;
  currency1: string;
  fee: number | null;
  tickSpacing: number | null;
  sqrtPriceX96: string | null;
};

const FACTORY_ABI = [
  "event LogDexDeployed(address indexed dex, uint256 indexed dexId)",
];

const RESOLVER_ABI = [
  "function getPoolTokens(address pool) external view returns (address token0, address token1)",
];

function ensureDirForFile(filePath: string) {
  fs.mkdirSync(path.dirname(path.resolve(filePath)), { recursive: true });
}

function safeReadJson<T>(filePath: string): T | null {
  try {
    return JSON.parse(fs.readFileSync(filePath, "utf8")) as T;
  } catch {
    return null;
  }
}

function atomicWriteFile(filePath: string, contents: string) {
  ensureDirForFile(filePath);
  const abs = path.resolve(filePath);
  fs.writeFileSync(abs + ".tmp", contents);
  fs.renameSync(abs + ".tmp", abs);
}

function loadExistingKeys(outFile: string): Set<string> {
  const keys = new Set<string>();
  if (!fs.existsSync(outFile)) return keys;
  try {
    const arr = safeReadJson<CreatePoolsFluidDexT1Config[]>(outFile);
    if (!Array.isArray(arr)) return keys;
    for (const x of arr)
      keys.add(`${x.fluidPool}:${x.currency0}:${x.currency1}`);
  } catch {
    // ignore
  }
  return keys;
}

/** Return [currency0, currency1] with currency0 < currency1 (lexicographic on mapped addrs) */
function orderCurrencies(a: string, b: string): [string, string] {
  const mapped = [toUniswapV4Currency(a), toUniswapV4Currency(b)].sort((x, y) =>
    x.toLowerCase().localeCompare(y.toLowerCase()),
  );
  return [mapped[0], mapped[1]];
}

function getEnvInt(name: string, chainId: number, def: number): number {
  const v = getEnvForChain(name, chainId);
  if (!v) return def;
  const n = Number(v);
  return Number.isFinite(n) ? Math.max(0, Math.floor(n)) : def;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));

  const chainIdRaw = args["chain-id"];
  if (chainIdRaw == null) {
    console.error("Missing required --chain-id <n>");
    process.exit(1);
  }
  const chainId = toInt(chainIdRaw, 0);
  if (chainId <= 0) {
    console.error("--chain-id must be a positive integer");
    process.exit(1);
  }

  const rpcUrl = getEnvForChain("RPC_URL", chainId);
  const resolverAddr = getEnvForChain("FLUID_DEX_RESOLVER", chainId);
  const factoryRaw =
    getEnvForChain("FLUID_DEX_FACTORY", chainId) ??
    getEnvForChain("FACTORY_ADDRESS", chainId) ??
    DEFAULT_FACTORY;

  if (!rpcUrl || !resolverAddr) {
    throw new Error("Missing required env: RPC_URL and FLUID_DEX_RESOLVER");
  }

  const factory = ethers.getAddress(factoryRaw);

  const outputDir = (args["output-dir"] as string) ?? "detected";
  const checkpointDir = (args["checkpoint-dir"] as string) ?? "checkpoints";
  const chunkBlocks = Math.max(1, toInt(args["chunk-blocks"], 10000));

  const finality = getEnvInt("FINALITY_BLOCKS", chainId, 10);
  const lookbackBlocks = getEnvInt("LOOKBACK_BLOCKS", chainId, 200000);
  const startBlockArg = args["start-block"];

  const provider = new ethers.JsonRpcProvider(rpcUrl);
  const resolver = new ethers.Contract(
    ethers.getAddress(resolverAddr),
    RESOLVER_ABI,
    provider,
  );

  const iface = new ethers.Interface(FACTORY_ABI as unknown as string[]);
  const topic0 = iface.getEvent("LogDexDeployed")!.topicHash;

  const latestBlock = await provider.getBlockNumber();
  const toBlock = Math.max(0, latestBlock - finality);

  const cpPath = resolveCheckpointPath(checkpointDir, chainId, CHECKPOINT_FILE);
  const cp = safeReadJson<Checkpoint>(cpPath);

  let fromBlock: number;
  if (startBlockArg != null) {
    fromBlock = Math.max(0, toInt(startBlockArg, 0));
  } else if (
    cp?.chainId === chainId &&
    cp?.factory?.toLowerCase() === factory.toLowerCase()
  ) {
    fromBlock = cp.lastProcessedBlock + 1;
  } else {
    fromBlock = Math.max(0, toBlock - lookbackBlocks);
  }

  if (fromBlock > toBlock) {
    const newCp: Checkpoint = {
      chainId,
      factory,
      lastProcessedBlock: toBlock,
      updatedAt: new Date().toISOString(),
    };
    ensureDirForFile(cpPath);
    fs.writeFileSync(cpPath, JSON.stringify(newCp, null, 2) + "\n");
    console.log(
      JSON.stringify(
        { ok: true, note: "No new blocks to scan", fromBlock, toBlock },
        null,
        2,
      ),
    );
    return;
  }

  const outPath = resolveOutputPath(outputDir, chainId, OUTPUT_FILE);
  const seenKeys = loadExistingKeys(outPath);
  let allRecords = safeReadJson<CreatePoolsFluidDexT1Config[]>(outPath) ?? [];
  let totalLogs = 0;
  let newPools = 0;

  for (let start = fromBlock; start <= toBlock; start += chunkBlocks) {
    const end = Math.min(toBlock, start + chunkBlocks - 1);

    const logs = await provider.getLogs({
      address: factory,
      topics: [topic0],
      fromBlock: start,
      toBlock: end,
    });

    totalLogs += logs.length;
    const newRecords: CreatePoolsFluidDexT1Config[] = [];

    for (const log of logs) {
      let parsed: ethers.LogDescription | null;
      try {
        parsed = iface.parseLog(log);
      } catch {
        continue;
      }
      if (!parsed) continue;

      const dex = ethers.getAddress(parsed.args.dex as string);

      let token0: string;
      let token1: string;
      try {
        [token0, token1] = await resolver.getPoolTokens(dex);
      } catch {
        console.error(`Failed getPoolTokens for ${dex}`);
        continue;
      }

      const [currency0, currency1] = orderCurrencies(token0, token1);
      const key = `${dex}:${currency0}:${currency1}`;
      if (seenKeys.has(key)) continue;
      seenKeys.add(key);

      newPools++;
      newRecords.push({
        poolType: "fluiddext1",
        fluidPool: dex,
        currency0,
        currency1,
        fee: null,
        tickSpacing: null,
        sqrtPriceX96: null,
      });
    }

    if (newRecords.length > 0) {
      allRecords = allRecords.concat(newRecords);
      atomicWriteFile(outPath, JSON.stringify(allRecords, null, 2) + "\n");
    }

    const interimCp: Checkpoint = {
      chainId,
      factory,
      lastProcessedBlock: end,
      updatedAt: new Date().toISOString(),
    };
    ensureDirForFile(cpPath);
    fs.writeFileSync(cpPath, JSON.stringify(interimCp, null, 2) + "\n");
    console.error(
      `[scan] ${start}..${end} logs=${logs.length} new=${newRecords.length}`,
    );
  }

  console.log(
    JSON.stringify(
      {
        ok: true,
        chainId,
        factory,
        scanned: {
          fromBlock,
          toBlock,
          latestBlock,
          finality,
          chunkBlocks,
        },
        logsFound: totalLogs,
        newPools,
        outFile: outPath,
        checkpointFile: cpPath,
      },
      null,
      2,
    ),
  );
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});

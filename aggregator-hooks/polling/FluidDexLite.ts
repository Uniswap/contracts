/**
 * Fluid Dex Lite pool discovery (checkpoint-based polling):
 * - loads checkpoint which stores lastProcessedBlock
 * - scans blocks since checkpoint for LogInitialize events from FluidDexLite
 * - decodes events and appends new pool records to output
 * - updates checkpoint to the latest safely processed block
 *
 * Usage:
 *   npx tsx polling/fluiddexlite.ts --chain-id 1
 *
 * Options:
 *   --chain-id <n>          (required) Chain ID; loads RPC_URL_<n>, DEX_LITE_ADDRESS_<n>
 *   --output-dir <path>      output directory (default: detected); writes to output-dir/chain-id/fluiddexlite-pools.json
 *   --checkpoint-dir <path>  checkpoint directory (default: checkpoints); writes to checkpoint-dir/chain-id/dexlite_checkpoint.json
 *   --chunk-blocks <n>       block chunk size for getLogs (default: 10000)
 *   --start-block <n>       (optional) override checkpoint; start scan from this block
 *
 * Env vars (use VAR_<chainId> or VAR for single chain):
 *   RPC_URL                 (required)
 *   DEX_LITE_ADDRESS        (required) FluidDexLite singleton
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

const OUTPUT_FILE = "fluiddexlite-pools.json";
const CHECKPOINT_FILE = "dexlite_checkpoint.json";

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
  dexLite: string;
  lastProcessedBlock: number;
  updatedAt: string;
};

/** Same shape as createPools.ts FluidDexLitePoolConfig */
type CreatePoolsFluidLiteConfig = {
  poolType: "fluiddexlite";
  dexSalt: string;
  currency0: string;
  currency1: string;
  fee: number | null;
  tickSpacing: number | null;
  sqrtPriceX96: string | null;
};

const LOG_INITIALIZE_ABI = [
  "event LogInitialize(uint256 dexId, tuple(address token0,address token1,bytes32 salt) dexKey, tuple(tuple(address token0,address token1,bytes32 salt) dexKey,uint256 fee,uint256 revenueCut,bool rebalancingStatus,uint256 centerPrice,uint256 centerPriceContract,uint256 upperPercent,uint256 lowerPercent,uint256 upperShiftThreshold,uint256 lowerShiftThreshold,uint256 shiftTime,uint256 minCenterPrice,uint256 maxCenterPrice,uint256 token0Amount,uint256 token1Amount) params, uint256 time)",
] as const;

function ensureDirForFile(filePath: string) {
  const dir = path.dirname(path.resolve(filePath));
  fs.mkdirSync(dir, { recursive: true });
}

function safeReadJson<T>(filePath: string): T | null {
  try {
    const raw = fs.readFileSync(filePath, "utf8");
    return JSON.parse(raw) as T;
  } catch {
    return null;
  }
}

function atomicWriteFile(filePath: string, contents: string) {
  ensureDirForFile(filePath);
  const abs = path.resolve(filePath);
  const tmp = abs + ".tmp";
  fs.writeFileSync(tmp, contents);
  fs.renameSync(tmp, abs);
}

function loadExistingKeys(outFile: string): Set<string> {
  const keys = new Set<string>();
  if (!fs.existsSync(outFile)) return keys;
  const raw = fs.readFileSync(outFile, "utf8").trim();
  if (!raw) return keys;
  try {
    const arr = JSON.parse(raw) as CreatePoolsFluidLiteConfig[];
    if (!Array.isArray(arr)) return keys;
    for (const x of arr) {
      keys.add(`${x.dexSalt}:${x.currency0}:${x.currency1}`);
    }
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
  const dexLiteRaw = getEnvForChain("DEX_LITE_ADDRESS", chainId);
  if (!rpcUrl || !dexLiteRaw) {
    throw new Error(
      "Missing required env: RPC_URL and DEX_LITE_ADDRESS (or RPC_URL_<chainId>, DEX_LITE_ADDRESS_<chainId>)",
    );
  }
  const dexLite = ethers.getAddress(dexLiteRaw);

  const outputDir = (args["output-dir"] as string) ?? "detected";
  const checkpointDir = (args["checkpoint-dir"] as string) ?? "checkpoints";
  const chunkBlocks = Math.max(1, toInt(args["chunk-blocks"], 10000));

  const finality = getEnvInt("FINALITY_BLOCKS", chainId, 10);
  const lookbackBlocks = getEnvInt("LOOKBACK_BLOCKS", chainId, 200000);
  const startBlockArg = args["start-block"];

  const provider = new ethers.JsonRpcProvider(rpcUrl);
  const iface = new ethers.Interface(LOG_INITIALIZE_ABI as unknown as string[]);
  const topic0 = iface.getEvent("LogInitialize")!.topicHash;

  const latestBlock = await provider.getBlockNumber();
  const toBlock = Math.max(0, latestBlock - finality);

  const cpPath = resolveCheckpointPath(checkpointDir, chainId, CHECKPOINT_FILE);
  const cp = safeReadJson<Checkpoint>(cpPath);

  let fromBlock: number;
  if (startBlockArg != null) {
    fromBlock = Math.max(0, toInt(startBlockArg, 0));
  } else if (
    cp &&
    cp.chainId === chainId &&
    cp.dexLite.toLowerCase() === dexLite.toLowerCase()
  ) {
    fromBlock = cp.lastProcessedBlock + 1;
  } else {
    fromBlock = Math.max(0, toBlock - lookbackBlocks);
  }

  if (fromBlock > toBlock) {
    const newCp: Checkpoint = {
      chainId,
      dexLite,
      lastProcessedBlock: toBlock,
      updatedAt: new Date().toISOString(),
    };
    atomicWriteFile(cpPath, JSON.stringify(newCp, null, 2) + "\n");
    console.log(
      JSON.stringify(
        {
          ok: true,
          note: "No new blocks to scan",
          chainId,
          dexLite,
          fromBlock,
          toBlock,
          latestBlock,
          finality,
          checkpointFile: cpPath,
        },
        null,
        2,
      ),
    );
    return;
  }

  const outPath = resolveOutputPath(outputDir, chainId, OUTPUT_FILE);
  const seenKeys = loadExistingKeys(outPath);
  ensureDirForFile(outPath);

  let totalLogs = 0;
  let newPools = 0;

  for (let start = fromBlock; start <= toBlock; start += chunkBlocks) {
    const end = Math.min(toBlock, start + chunkBlocks - 1);

    const logs = await provider.getLogs({
      address: dexLite,
      topics: [topic0],
      fromBlock: start,
      toBlock: end,
    });

    totalLogs += logs.length;
    const newRecords: CreatePoolsFluidLiteConfig[] = [];

    for (const log of logs) {
      let parsed: ethers.LogDescription | null;
      try {
        parsed = iface.parseLog(log);
      } catch {
        continue;
      }

      const dexKey = parsed?.args[1] as {
        token0: string;
        token1: string;
        salt: string;
      };

      const token0 = ethers.getAddress(dexKey.token0);
      const token1 = ethers.getAddress(dexKey.token1);
      const salt = dexKey.salt as string;

      const [currency0, currency1] = orderCurrencies(token0, token1);
      const dedupeKey = `${salt}:${currency0}:${currency1}`;
      if (seenKeys.has(dedupeKey)) continue;
      seenKeys.add(dedupeKey);

      newPools++;
      newRecords.push({
        poolType: "fluiddexlite",
        dexSalt: salt,
        currency0,
        currency1,
        fee: null,
        tickSpacing: null,
        sqrtPriceX96: null,
      });
    }

    if (newRecords.length > 0) {
      const existing =
        safeReadJson<CreatePoolsFluidLiteConfig[]>(outPath) ?? [];
      const merged = existing.concat(newRecords);
      atomicWriteFile(outPath, JSON.stringify(merged, null, 2) + "\n");
    }

    const interimCp: Checkpoint = {
      chainId,
      dexLite,
      lastProcessedBlock: end,
      updatedAt: new Date().toISOString(),
    };
    atomicWriteFile(cpPath, JSON.stringify(interimCp, null, 2) + "\n");

    console.error(
      `[scan] ${start}..${end} logs=${logs.length} new=${newRecords.length}`,
    );
  }

  console.log(
    JSON.stringify(
      {
        ok: true,
        chainId,
        dexLite,
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

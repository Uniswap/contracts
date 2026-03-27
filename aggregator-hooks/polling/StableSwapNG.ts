/**
 * StableSwap-NG pool discovery (block-based polling):
 * - loads checkpoint which stores lastProcessedBlock
 * - scans blocks since checkpoint for PlainPoolDeployed/MetaPoolDeployed events
 * - event count = number of new pools; fetches pool_list(n-i+1)..pool_list(n) where n=poolCount-1, i=eventCount
 * - appends new pool records to output in createPools format
 * - updates checkpoint to last scanned block
 *
 * Usage:
 *   npx tsx polling/stableswapng.ts --chain-id 1
 *
 * Options:
 *   --chain-id <n>          (required) Chain ID; loads RPC_URL_<n>, STABLESWAPNG_FACTORY_<n>
 *   --output-dir <path>     output directory (default: detected)
 *   --checkpoint-dir <path> checkpoint directory (default: checkpoints)
 *   --chunk-blocks <n>      block chunk size for getLogs (default: 10000)
 *   --start-block <n>       (optional) override checkpoint; start scan from this block
 *
 * Env vars (use VAR_<chainId> or VAR for single chain):
 *   RPC_URL                 (required)
 *   STABLESWAPNG_FACTORY     (optional, default mainnet Curve StableSwap-NG factory)
 *   FINALITY_BLOCKS         (optional, default 10) subtract from latest; checkpoint = last scanned block
 *   LOOKBACK_BLOCKS         (optional, default 200000) used when checkpoint missing and no --start-block
 *   RPS                     (optional, default 80) max RPC requests per second
 *   CONCURRENCY             (optional, default 8) max concurrent RPC calls
 */

import "dotenv/config";
import fs from "node:fs";
import path from "node:path";
import { ethers } from "ethers";
import { parseArgs, getEnvForChain, toInt, resolveOutputPath, resolveCheckpointPath } from "@src/cli";

const OUTPUT_FILE = "stableswapng-pools.json";
const CHECKPOINT_FILE = "stableswapng_checkpoint.json";
const DEFAULT_FACTORY = "0x6A8cbed756804B16E05E741eDaBd5cB544AE21bf";

type Checkpoint = {
  chainId: number;
  factory: string;
  lastProcessedBlock: number;
  lastKnownPoolCount: number;
  updatedAt: string;
};

/** Same shape as createPools.ts StableSwapPoolConfig for stableswapng */
type CreatePoolsStableSwapConfig = {
  poolType: "stableswapng";
  curvePool: string;
  tokens: string[];
  fee: number | null;
  tickSpacing: number | null;
  sqrtPriceX96: string | null;
};

const FACTORY_ABI = [
  "function pool_count() view returns (uint256)",
  "function pool_list(uint256) view returns (address)",
  "function get_n_coins(address) view returns (uint256)",
  "function get_coins(address) view returns (address[])",
  "function get_base_pool(address) view returns (address)",
  "event PlainPoolDeployed(address[] coins, uint256 A, uint256 fee, address deployer)",
  "event MetaPoolDeployed(address coin, address base_pool, uint256 A, uint256 fee, address deployer)",
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

function loadExistingPoolAddrs(outFile: string): Set<string> {
  const keys = new Set<string>();
  if (!fs.existsSync(outFile)) return keys;
  try {
    const arr = safeReadJson<CreatePoolsStableSwapConfig[]>(outFile);
    if (!Array.isArray(arr)) return keys;
    for (const x of arr) keys.add(x.curvePool.toLowerCase());
  } catch {
    // ignore
  }
  return keys;
}

function pRateLimit(rps: number): () => Promise<void> {
  if (rps <= 0) return async () => {};
  const minGapMs = 1000 / rps;
  let nextAllowed = 0;
  return async function acquire() {
    const now = Date.now();
    if (now < nextAllowed) await new Promise((r) => setTimeout(r, nextAllowed - now));
    nextAllowed = Math.max(now, nextAllowed) + minGapMs;
  };
}

function pLimit(concurrency: number) {
  let active = 0;
  const queue: (() => void)[] = [];
  return async function limit<T>(fn: () => Promise<T>): Promise<T> {
    if (active >= concurrency) await new Promise<void>((r) => queue.push(r));
    active++;
    try {
      return await fn();
    } finally {
      active--;
      queue.shift()?.();
    }
  };
}

function uniqAddresses(addrs: string[]): string[] {
  const s = new Set<string>();
  for (const a of addrs) {
    if (!a) continue;
    const norm = a.toLowerCase();
    if (norm === ethers.ZeroAddress.toLowerCase()) continue;
    s.add(ethers.getAddress(a));
  }
  return [...s];
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
  const factoryRaw = getEnvForChain("STABLESWAPNG_FACTORY", chainId) ?? DEFAULT_FACTORY;

  if (!rpcUrl) {
    throw new Error("Missing required env: RPC_URL (or RPC_URL_<chainId>)");
  }

  const factory = ethers.getAddress(factoryRaw);

  const outputDir = (args["output-dir"] as string) ?? "detected";
  const checkpointDir = (args["checkpoint-dir"] as string) ?? "checkpoints";
  const chunkBlocks = Math.max(1, toInt(args["chunk-blocks"], 10000));

  const finality = getEnvInt("FINALITY_BLOCKS", chainId, 10);
  const lookbackBlocks = getEnvInt("LOOKBACK_BLOCKS", chainId, 200000);
  const startBlockArg = args["start-block"];

  const concurrency = Math.max(1, toInt(getEnvForChain("CONCURRENCY", chainId), 8));
  const rps = toInt(getEnvForChain("RPS", chainId), 80);
  const rateLimit = pRateLimit(rps);
  const limit = pLimit(concurrency);

  const provider = new ethers.JsonRpcProvider(rpcUrl);
  const contract = new ethers.Contract(factory, FACTORY_ABI, provider);

  const iface = new ethers.Interface(FACTORY_ABI as unknown as string[]);
  const plainTopic = iface.getEvent("PlainPoolDeployed")!.topicHash;
  const metaTopic = iface.getEvent("MetaPoolDeployed")!.topicHash;

  const latestBlock = await provider.getBlockNumber();
  const toBlock = Math.max(0, latestBlock - finality);

  const cpPath = resolveCheckpointPath(checkpointDir, chainId, CHECKPOINT_FILE);
  const cp = safeReadJson<Checkpoint>(cpPath);

  let fromBlock: number;
  if (startBlockArg != null) {
    fromBlock = Math.max(0, toInt(startBlockArg, 0));
  } else if (cp?.chainId === chainId && cp?.factory?.toLowerCase() === factory.toLowerCase()) {
    fromBlock = cp.lastProcessedBlock + 1;
  } else {
    fromBlock = Math.max(0, toBlock - lookbackBlocks);
  }

  const poolCountBn = await contract.pool_count();
  const poolCount = Number(poolCountBn);
  if (!Number.isFinite(poolCount) || poolCount < 0) {
    throw new Error(`Unexpected pool_count: ${poolCountBn}`);
  }

  const lastKnownPoolCount =
    cp?.chainId === chainId && cp?.factory?.toLowerCase() === factory.toLowerCase() ? cp.lastKnownPoolCount ?? 0 : 0;

  if (fromBlock > toBlock && poolCount <= lastKnownPoolCount) {
    const newCp: Checkpoint = {
      chainId,
      factory,
      lastProcessedBlock: toBlock,
      lastKnownPoolCount: poolCount,
      updatedAt: new Date().toISOString(),
    };
    atomicWriteFile(cpPath, JSON.stringify(newCp, null, 2) + "\n");
    console.log(
      JSON.stringify({ ok: true, note: "No new blocks or pools to process", fromBlock, toBlock, poolCount }, null, 2),
    );
    return;
  }

  let eventCount = 0;
  if (fromBlock <= toBlock) {
    for (let start = fromBlock; start <= toBlock; start += chunkBlocks) {
      const end = Math.min(toBlock, start + chunkBlocks - 1);

      const logs = await provider.getLogs({
        address: factory,
        fromBlock: start,
        toBlock: end,
        topics: [[plainTopic, metaTopic]],
      });

      eventCount += logs.length;
      console.error(`[scan] ${start}..${end} events=${logs.length} total=${eventCount}`);
    }
  }

  const startIndex = Math.max(0, lastKnownPoolCount);
  const fetchCount = poolCount - startIndex;

  if (fetchCount <= 0) {
    const newCp: Checkpoint = {
      chainId,
      factory,
      lastProcessedBlock: Math.max(toBlock, cp?.lastProcessedBlock ?? 0),
      lastKnownPoolCount: poolCount,
      updatedAt: new Date().toISOString(),
    };
    atomicWriteFile(cpPath, JSON.stringify(newCp, null, 2) + "\n");
    console.log(
      JSON.stringify(
        {
          ok: true,
          chainId,
          factory,
          eventCount,
          newPools: 0,
          outFile: resolveOutputPath(outputDir, chainId, OUTPUT_FILE),
          checkpointFile: cpPath,
        },
        null,
        2,
      ),
    );
    return;
  }

  const outPath = resolveOutputPath(outputDir, chainId, OUTPUT_FILE);
  const seenAddrs = loadExistingPoolAddrs(outPath);
  let allRecords = safeReadJson<CreatePoolsStableSwapConfig[]>(outPath) ?? [];
  let newCount = 0;

  for (let i = startIndex; i < poolCount; i++) {
    const curvePool = await limit(async () => {
      await rateLimit();
      const addr = await contract.pool_list(i);
      return ethers.getAddress(addr);
    });

    if (seenAddrs.has(curvePool.toLowerCase())) continue;
    seenAddrs.add(curvePool.toLowerCase());

    const meta = await limit(async () => {
      await rateLimit();
      const [nCoinsBn, coinsRaw, basePoolRaw] = await Promise.all([
        contract.get_n_coins(curvePool) as Promise<bigint>,
        contract.get_coins(curvePool) as Promise<string[]>,
        contract.get_base_pool(curvePool) as Promise<string>,
      ]);
      const basePool = ethers.getAddress(basePoolRaw);
      const isPlain = basePool.toLowerCase() === ethers.ZeroAddress.toLowerCase();
      const coins = uniqAddresses(coinsRaw as string[]);
      return { nCoins: Number(nCoinsBn), coins, isPlain };
    });

    if (!meta.isPlain) continue;

    allRecords.push({
      poolType: "stableswapng",
      curvePool,
      tokens: meta.coins,
      fee: null,
      tickSpacing: null,
      sqrtPriceX96: null,
    });
    newCount++;
  }

  if (newCount > 0) {
    atomicWriteFile(outPath, JSON.stringify(allRecords, null, 2) + "\n");
  }

  const newCp: Checkpoint = {
    chainId,
    factory,
    lastProcessedBlock: Math.max(toBlock, cp?.lastProcessedBlock ?? 0),
    lastKnownPoolCount: poolCount,
    updatedAt: new Date().toISOString(),
  };
  atomicWriteFile(cpPath, JSON.stringify(newCp, null, 2) + "\n");

  console.log(
    JSON.stringify(
      {
        ok: true,
        chainId,
        factory,
        scanned: { fromBlock, toBlock, latestBlock, finality, chunkBlocks },
        eventCount,
        poolsFetched: fetchCount,
        newPools: newCount,
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

/**
 * Slipstream pool discovery (checkpoint-based polling).
 * Scans new PoolCreated events from the Slipstream (Velodrome/Aerodrome CL)
 * factory since the last checkpoint and appends new pools to the output file.
 *
 * Usage:
 *   npx tsx polling/Slipstream.ts --chain-id 10
 *
 * Options:
 *   --chain-id <n>           (required) Chain ID
 *   --output-dir <path>      output directory (default: detected)
 *   --checkpoint-dir <path>  checkpoint directory (default: checkpoints)
 *   --chunk-blocks <n>       block chunk size (default: 10000)
 *   --start-block <n>        (optional) override checkpoint start block
 *
 * Env vars (VAR_<chainId> or VAR):
 *   RPC_URL                  (required)
 *   SLIPSTREAM_FACTORY       (required — no chain-agnostic default)
 *   FINALITY_BLOCKS          (optional, default 10)
 *   LOOKBACK_BLOCKS          (optional, default 200000)
 */

import "dotenv/config";
import fs from "node:fs";
import path from "node:path";
import { ethers } from "ethers";
import { parseArgs, getEnvForChain, toInt, resolveOutputPath, resolveCheckpointPath } from "@src/cli";

const OUTPUT_FILE = "slipstream-pools.json";
const CHECKPOINT_FILE = "slipstream_checkpoint.json";
const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";

// Slipstream CLFactory: tickSpacing is the third indexed param (not fee)
const FACTORY_ABI = [
  "event PoolCreated(address indexed token0, address indexed token1, int24 indexed tickSpacing, address pool)",
];

type Checkpoint = { chainId: number; factory: string; lastProcessedBlock: number; updatedAt: string };

type SlipstreamPoolConfig = {
  poolType: "slipstream";
  slipstreamPool: string;
  currency0: string;
  currency1: string;
  tickSpacing: number;
  sqrtPriceX96: null;
};

function isNative(addr: string): boolean {
  return addr.toLowerCase() === ZERO_ADDRESS;
}

function ensureDirForFile(filePath: string) {
  fs.mkdirSync(path.dirname(path.resolve(filePath)), { recursive: true });
}

function safeReadJson<T>(filePath: string): T | null {
  try { return JSON.parse(fs.readFileSync(filePath, "utf8")) as T; } catch { return null; }
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
    const arr = safeReadJson<SlipstreamPoolConfig[]>(outFile);
    if (!Array.isArray(arr)) return keys;
    for (const x of arr) keys.add(x.slipstreamPool.toLowerCase());
  } catch { /* ignore */ }
  return keys;
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
  if (chainIdRaw == null) { console.error("Missing required --chain-id <n>"); process.exit(1); }
  const chainId = toInt(chainIdRaw, 0);
  if (chainId <= 0) { console.error("--chain-id must be a positive integer"); process.exit(1); }

  const rpcUrl = getEnvForChain("RPC_URL", chainId);
  if (!rpcUrl) throw new Error("Missing required env: RPC_URL");

  const factoryRaw = getEnvForChain("SLIPSTREAM_FACTORY", chainId);
  if (!factoryRaw) throw new Error("Missing required env: SLIPSTREAM_FACTORY (or SLIPSTREAM_FACTORY_<chainId>)");
  const factory = ethers.getAddress(factoryRaw);

  const outputDir = (args["output-dir"] as string) ?? "detected";
  const checkpointDir = (args["checkpoint-dir"] as string) ?? "checkpoints";
  const chunkBlocks = Math.max(1, toInt(args["chunk-blocks"], 10_000));
  const finality = getEnvInt("FINALITY_BLOCKS", chainId, 10);
  const lookbackBlocks = getEnvInt("LOOKBACK_BLOCKS", chainId, 200_000);
  const startBlockArg = args["start-block"];

  const provider = new ethers.JsonRpcProvider(rpcUrl);
  const iface = new ethers.Interface(FACTORY_ABI);
  const topic0 = iface.getEvent("PoolCreated")!.topicHash;

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

  if (fromBlock > toBlock) {
    const newCp: Checkpoint = { chainId, factory, lastProcessedBlock: toBlock, updatedAt: new Date().toISOString() };
    atomicWriteFile(cpPath, JSON.stringify(newCp, null, 2) + "\n");
    console.log(JSON.stringify({ ok: true, note: "No new blocks to scan", fromBlock, toBlock }, null, 2));
    return;
  }

  const outPath = resolveOutputPath(outputDir, chainId, OUTPUT_FILE);
  const seenKeys = loadExistingKeys(outPath);
  let allRecords = safeReadJson<SlipstreamPoolConfig[]>(outPath) ?? [];
  let totalLogs = 0;
  let newPools = 0;

  for (let start = fromBlock; start <= toBlock; start += chunkBlocks) {
    const end = Math.min(toBlock, start + chunkBlocks - 1);

    const logs = await provider.getLogs({ address: factory, topics: [topic0], fromBlock: start, toBlock: end });
    totalLogs += logs.length;
    const newRecords: SlipstreamPoolConfig[] = [];

    for (const log of logs) {
      let parsed: ethers.LogDescription | null;
      try { parsed = iface.parseLog(log); } catch { continue; }
      if (!parsed) continue;

      const token0 = ethers.getAddress(parsed.args.token0 as string);
      const token1 = ethers.getAddress(parsed.args.token1 as string);
      const pool = ethers.getAddress(parsed.args.pool as string);
      const tickSpacing = Number(parsed.args.tickSpacing);

      if (isNative(token0) || isNative(token1)) continue;
      if (seenKeys.has(pool.toLowerCase())) continue;
      seenKeys.add(pool.toLowerCase());

      newPools++;
      newRecords.push({ poolType: "slipstream", slipstreamPool: pool, currency0: token0, currency1: token1, tickSpacing, sqrtPriceX96: null });
    }

    if (newRecords.length > 0) {
      allRecords = allRecords.concat(newRecords);
      atomicWriteFile(outPath, JSON.stringify(allRecords, null, 2) + "\n");
    }

    const interimCp: Checkpoint = { chainId, factory, lastProcessedBlock: end, updatedAt: new Date().toISOString() };
    atomicWriteFile(cpPath, JSON.stringify(interimCp, null, 2) + "\n");
    console.error(`[scan] ${start}..${end} logs=${logs.length} new=${newRecords.length}`);
  }

  console.log(JSON.stringify({
    ok: true, chainId, factory,
    scanned: { fromBlock, toBlock, latestBlock, finality, chunkBlocks },
    logsFound: totalLogs, newPools, outFile: outPath, checkpointFile: cpPath,
  }, null, 2));
}

main().catch((err) => { console.error(err); process.exitCode = 1; });

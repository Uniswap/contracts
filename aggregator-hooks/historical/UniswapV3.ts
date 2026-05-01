/**
 * Uniswap V3 historical pool discovery.
 * Scans PoolCreated events from the Uniswap V3 factory and outputs pool
 * configs in createPools.ts UniswapV3PoolConfig format.
 *
 * Usage:
 *   npx tsx historical/UniswapV3.ts --chain-id 1
 *
 * Options:
 *   --chain-id <n>          (required) Chain ID
 *   --output-dir <path>     output directory (default: detected)
 *   --chunk-blocks <n>      block chunk size for getLogs (default: 10000; auto-halved on range errors)
 *   --start-block <n>       start block (default: 0)
 *   --end-block <n>         end block (default: latest)
 *
 * Env vars (VAR_<chainId> or VAR):
 *   RPC_URL                 (required)
 *   UNISWAP_V3_FACTORY      (optional, default mainnet factory)
 *   RPS                     (optional, default 80)
 *   CONCURRENCY             (optional, default 8)
 *
 * Output: JSON array in UniswapV3PoolConfig format (fee + tickSpacing from event).
 */

import "dotenv/config";
import fs from "node:fs";
import path from "node:path";
import { ethers } from "ethers";
import { parseArgs, getEnvForChain, toInt, resolveOutputPath } from "@src/cli";
import type { Address } from "../creation-modules/types.js";

const OUTPUT_FILE = "uniswapv3-pools.json";
const DEFAULT_FACTORY: Address = "0x1F98431c8aD98523631AE4a59f267346ea31F984";
const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";

const FACTORY_ABI = [
  "event PoolCreated(address indexed token0, address indexed token1, uint24 indexed fee, int24 tickSpacing, address pool)",
];

type UniswapV3PoolConfig = {
  poolType: "uniswapv3";
  v3Pool: Address;
  currency0: Address;
  currency1: Address;
  fee: number;
  tickSpacing: number;
  sqrtPriceX96: null;
};

function pRateLimit(rps: number): () => Promise<void> {
  if (rps <= 0) return async () => {};
  const minGapMs = 1000 / rps;
  let nextAllowed = 0;
  return async function acquire(): Promise<void> {
    const now = Date.now();
    if (now < nextAllowed) await new Promise<void>((r) => setTimeout(r, nextAllowed - now));
    nextAllowed = Math.max(now, nextAllowed) + minGapMs;
  };
}

function isRangeLimitError(err: unknown): boolean {
  const msg = String((err as { error?: { message?: string }; message?: string })?.error?.message ?? (err as { message?: string })?.message ?? "");
  return msg.toLowerCase().includes("range") || msg.toLowerCase().includes("limit") || msg.includes("-32614");
}

/** getLogs with automatic chunk-halving on range-limit errors. */
async function getLogsWithRetry(
  provider: ethers.JsonRpcProvider,
  filter: { address: string; topics: string[]; fromBlock: bigint; toBlock: bigint },
): Promise<ethers.Log[]> {
  try {
    return await provider.getLogs({
      address: filter.address,
      topics: filter.topics,
      fromBlock: filter.fromBlock,
      toBlock: filter.toBlock,
    });
  } catch (err) {
    if (!isRangeLimitError(err) || filter.toBlock <= filter.fromBlock) throw err;
    const mid = filter.fromBlock + (filter.toBlock - filter.fromBlock) / 2n;
    const [lo, hi] = await Promise.all([
      getLogsWithRetry(provider, { ...filter, toBlock: mid }),
      getLogsWithRetry(provider, { ...filter, fromBlock: mid + 1n }),
    ]);
    return lo.concat(hi);
  }
}

function isNative(addr: string): boolean {
  return addr.toLowerCase() === ZERO_ADDRESS;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));

  const chainIdRaw = args["chain-id"];
  if (chainIdRaw == null) { console.error("Missing required --chain-id <n>"); process.exit(1); }
  const chainId = toInt(chainIdRaw, 0);
  if (chainId <= 0) { console.error("--chain-id must be a positive integer"); process.exit(1); }

  const rpcUrl = getEnvForChain("RPC_URL", chainId);
  if (!rpcUrl) { console.error("Missing env: RPC_URL"); process.exit(1); }

  const factoryRaw = getEnvForChain("UNISWAP_V3_FACTORY", chainId) ?? DEFAULT_FACTORY;
  const factory = ethers.getAddress(factoryRaw) as Address;

  const outputDir = (args["output-dir"] as string) ?? "detected";
  const chunkSize = BigInt(Math.max(1, toInt(args["chunk-blocks"], 10_000)));
  const startBlock = BigInt(Math.max(0, toInt(args["start-block"], 0)));
  const rps = toInt(getEnvForChain("RPS", chainId) ?? "80", 80);
  const rateLimitAcquire = pRateLimit(rps);

  const provider = new ethers.JsonRpcProvider(rpcUrl);
  const iface = new ethers.Interface(FACTORY_ABI);
  const topic0 = iface.getEvent("PoolCreated")!.topicHash;

  const latest = BigInt(await provider.getBlockNumber());
  const endBlockRaw = args["end-block"];
  const endBlock = endBlockRaw ? BigInt(String(endBlockRaw)) : latest;

  console.error(`Factory: ${factory}`);
  console.error(`Scanning blocks ${startBlock}..${endBlock} (chunk=${chunkSize})`);

  const seen = new Set<Address>();
  const configs: UniswapV3PoolConfig[] = [];

  for (let from = startBlock; from <= endBlock; from += chunkSize) {
    const to = from + chunkSize - 1n > endBlock ? endBlock : from + chunkSize - 1n;
    await rateLimitAcquire();

    const logs = await getLogsWithRetry(provider, { address: factory, topics: [topic0], fromBlock: from, toBlock: to });

    for (const log of logs) {
      const parsed = iface.parseLog(log);
      if (!parsed) continue;

      const token0 = ethers.getAddress(parsed.args.token0 as string) as Address;
      const token1 = ethers.getAddress(parsed.args.token1 as string) as Address;
      const pool = ethers.getAddress(parsed.args.pool as string) as Address;
      const fee = Number(parsed.args.fee);
      const tickSpacing = Number(parsed.args.tickSpacing);

      // Skip native currency — UniswapV3Aggregator reverts on address(0)
      if (isNative(token0) || isNative(token1)) continue;
      if (seen.has(pool)) continue;
      seen.add(pool);

      // token0 < token1 is guaranteed by the V3 factory; currency ordering is already correct
      configs.push({
        poolType: "uniswapv3",
        v3Pool: pool,
        currency0: token0,
        currency1: token1,
        fee,
        tickSpacing,
        sqrtPriceX96: null,
      });
    }

    if (to === endBlock || (to - startBlock) % (chunkSize * 10n) === 0n) {
      console.error(`[scan] ${from}..${to} — found ${configs.length} pools so far`);
    }
    console.log(`[scan] ${from}..${to} — found ${configs.length} pools so far`);
  }

  const outPath = resolveOutputPath(outputDir, chainId, OUTPUT_FILE);
  fs.mkdirSync(path.dirname(outPath), { recursive: true });
  fs.writeFileSync(outPath, JSON.stringify(configs, null, 2) + "\n");
  console.log(JSON.stringify({ ok: true, chainId, factory, poolsFound: configs.length, outFile: outPath }, null, 2));
}

main().catch((e) => { console.error(e); process.exit(1); });

/**
 * StableSwap-NG historical pool discovery.
 * Enumerates all pools from Curve StableSwap-NG Factory via pool_count + pool_list.
 *
 * Usage:
 *   npx tsx historical/stableswapng.ts --chain-id 1
 *
 * Options:
 *   --chain-id <n>            (required) Chain ID; loads RPC_URL_<n>, FACTORY_ADDRESS_<n>
 *   --output-dir <path>       output directory (default: output); writes to output-dir/chain-id/stableswapng-pools.json
 *   --chunk <n>               chunk size for pool_list reads (default: 500)
 *   --start-index <n>         start at pool_list index n (default: 0)
 *
 * Env vars (use VAR_<chainId> or VAR for single chain):
 *   RPC_URL                   (required)
 *   FACTORY_ADDRESS           (optional, default mainnet Curve StableSwap-NG factory)
 *   RPS                       (optional, default 80) max RPC requests per second
 *   CONCURRENCY               (optional, default 8) max concurrent RPC calls
 *
 * Output: JSON array in createPools.ts StableSwapPoolConfig format.
 */

import "dotenv/config";
import fs from "node:fs";
import path from "node:path";
import { JsonRpcProvider, Contract, getAddress, ZeroAddress } from "ethers";
import { parseArgs, getEnvForChain, toInt, resolveOutputPath } from "@src/cli";
import { STABLESWAPNG_HISTORICAL_FACTORY_ABI } from "../abis/index.js";
import type { Address } from "../creation-modules/types.js";

const OUTPUT_FILE = "stableswapng-pools.json";
const DEFAULT_FACTORY: Address = "0x6A8cbed756804B16E05E741eDaBd5cB544AE21bf";

type PoolMeta = {
  pool: Address;
  kind: "plain" | "meta";
  nCoins?: number;
  coins?: Address[];
  basePool?: Address;
};

/** Same shape as createPools.ts StableSwapPoolConfig for stableswapng pool type */
type CreatePoolsStableSwapConfig = {
  poolType: "stableswapng";
  curvePool: Address;
  tokens: Address[];
  fee: number | null;
  tickSpacing: number | null;
  sqrtPriceX96: bigint | null;
};

const CREATE_POOLS_DEFAULTS = {
  fee: null as number | null,
  tickSpacing: null as number | null,
  sqrtPriceX96: null as bigint | null,
} as const;

function saveJson(filePath: string, data: unknown): void {
  fs.writeFileSync(filePath, JSON.stringify(data, null, 2));
}

function pRateLimit(rps: number): () => Promise<void> {
  if (rps <= 0) return async () => {};
  const minGapMs = 1000 / rps;
  let nextAllowed = 0;
  return async function acquire(): Promise<void> {
    const now = Date.now();
    if (now < nextAllowed) {
      await new Promise<void>((r) => setTimeout(r, nextAllowed - now));
    }
    nextAllowed = Math.max(now, nextAllowed) + minGapMs;
  };
}

function pLimit(concurrency: number) {
  let active = 0;
  const queue: Array<() => void> = [];

  const next = (): void => {
    active--;
    const fn = queue.shift();
    if (fn) fn();
  };

  return async function limit<T>(fn: () => Promise<T>): Promise<T> {
    if (active >= concurrency) {
      await new Promise<void>((resolve) => queue.push(resolve));
    }
    active++;
    try {
      return await fn();
    } finally {
      next();
    }
  };
}

function uniqAddresses(addrs: string[]): Address[] {
  const s = new Set<Address>();
  for (const a of addrs) {
    if (!a) continue;
    const norm = a.toLowerCase();
    if (norm === ZeroAddress.toLowerCase()) continue;
    s.add(getAddress(a) as Address);
  }
  return [...s];
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
  const factoryAddrRaw = getEnvForChain("FACTORY_ADDRESS", chainId) ?? DEFAULT_FACTORY;

  if (!rpcUrl) {
    console.error("Missing env: RPC_URL (or RPC_URL_<chainId>)");
    process.exit(1);
  }

  const factoryAddress = getAddress(factoryAddrRaw) as Address;
  const outputDir = (args["output-dir"] as string) ?? "detected";
  const chunkSize = toInt(args["chunk"], 500);
  const concurrency = Math.max(1, toInt(getEnvForChain("CONCURRENCY", chainId), 8));
  const rps = toInt(getEnvForChain("RPS", chainId), 80);
  const rateLimitAcquire = rps > 0 ? pRateLimit(rps) : async () => {};
  const startIndex = toInt(args["start-index"], 0);

  const provider = new JsonRpcProvider(rpcUrl);
  const factory = new Contract(factoryAddress, STABLESWAPNG_HISTORICAL_FACTORY_ABI, provider);
  const limit = pLimit(concurrency);

  const poolCountBn: bigint = await factory.pool_count();
  const poolCount = Number(poolCountBn);
  if (!Number.isFinite(poolCount) || poolCount < 0) {
    throw new Error(`Unexpected pool_count: ${poolCountBn.toString()}`);
  }

  console.log(`Factory: ${factoryAddress}`);
  console.log(`pool_count: ${poolCount}`);
  console.log(`Starting at index: ${startIndex}`);
  console.log(`chunkSize=${chunkSize} concurrency=${concurrency} rps=${rps > 0 ? rps : "unlimited"}`);

  const pools: Address[] = [];
  const metas: PoolMeta[] = [];
  const metaByPool = new Map<Address, PoolMeta>();

  for (let i = startIndex; i < poolCount; i += chunkSize) {
    const end = Math.min(poolCount, i + chunkSize);

    const addrs = await Promise.all(
      Array.from({ length: end - i }, (_, k) =>
        limit(async () => {
          await rateLimitAcquire();
          const addr: string = await factory.pool_list(i + k);
          return getAddress(addr) as Address;
        }),
      ),
    );

    pools.push(...addrs);

    const chunkMetas = await Promise.all(
      addrs.map((pool) =>
        limit(async () => {
          await rateLimitAcquire();
          const nCoinsBn = (await factory.get_n_coins(pool)) as bigint;
          await rateLimitAcquire();
          const coinsRaw = (await factory.get_coins(pool)) as string[];
          await rateLimitAcquire();
          const basePoolRaw = await factory.get_base_pool(pool);

          const basePool = getAddress(basePoolRaw) as Address;
          const coins = uniqAddresses(coinsRaw);

          return {
            pool,
            kind: basePool.toLowerCase() === ZeroAddress.toLowerCase() ? "plain" : "meta",
            nCoins: Number(nCoinsBn),
            coins,
            basePool: basePool.toLowerCase() === ZeroAddress.toLowerCase() ? undefined : basePool,
          } satisfies PoolMeta;
        }),
      ),
    );

    metas.push(...chunkMetas);
    for (let j = 0; j < addrs.length; j++) metaByPool.set(addrs[j], chunkMetas[j]);
    console.log(`Fetched [${i}, ${end}) / ${poolCount}`);
  }

  const uniquePools = uniqAddresses(pools);

  const createPoolsConfigs: CreatePoolsStableSwapConfig[] = uniquePools
    .filter((curvePool) => metaByPool.get(curvePool)?.kind === "plain")
    .map((curvePool) => {
      const meta = metaByPool.get(curvePool)!;
      const tokens = meta?.coins ?? [];
      return {
        poolType: "stableswapng" as const,
        curvePool,
        tokens,
        fee: CREATE_POOLS_DEFAULTS.fee,
        tickSpacing: CREATE_POOLS_DEFAULTS.tickSpacing,
        sqrtPriceX96: CREATE_POOLS_DEFAULTS.sqrtPriceX96,
      };
    });

  const outPath = resolveOutputPath(outputDir, chainId, OUTPUT_FILE);
  fs.mkdirSync(path.dirname(outPath), { recursive: true });
  saveJson(outPath, createPoolsConfigs);
  console.log(`Wrote ${outPath} (${createPoolsConfigs.length} pools in createPools.ts format)`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});

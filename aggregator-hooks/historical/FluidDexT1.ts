/**
 * Fluid Dex T1 historical pool discovery.
 * Scrapes LogDexDeployed events from FluidDexFactory and fetches tokens via resolver.
 *
 * Usage:
 *   npx tsx historical/fluiddext1.ts --chain-id 1
 *
 * Options:
 *   --chain-id <n>          (required) Chain ID; loads RPC_URL_<n>, FLUID_DEX_RESOLVER_<n>, etc.
 *   --output-dir <path>     output directory (default: output); writes to output-dir/chain-id/fluiddext1-pools.json
 *   --chunk-blocks <n>      block chunk size for getLogs (default: 100000)
 *   --start-block <n>       start block for log scan (default: 0)
 *   --end-block <n>         end block for log scan (default: latest)
 *   --mode <mode>           logs|enumerate|both (default: logs)
 *
 * Env vars (use VAR_<chainId> or VAR for single chain):
 *   RPC_URL                     (required)
 *   FLUID_DEX_T1_RESOLVER       (required) IFluidDexResolver for getPoolTokens; FLUID_DEX_RESOLVER fallback
 *   FLUID_DEX_FACTORY           (optional, default mainnet)
 *   RPS                     (optional, default 80) max RPC requests per second
 *   CONCURRENCY             (optional, default 8) max concurrent RPC calls
 *
 * Output: JSON array in createPools.ts FluidDexT1PoolConfig format.
 */

import "dotenv/config";
import fs from "node:fs";
import path from "node:path";
import { JsonRpcProvider, Contract, Interface, getAddress } from "ethers";
import { parseArgs, getEnvForChain, toInt, resolveOutputPath } from "@src/cli";
import { FLUIDDEXT1_HISTORICAL_FACTORY_ABI, FLUIDDEXT1_RESOLVER_ABI } from "../abis/index.js";
import type { Address } from "../creation-modules/types.js";

const OUTPUT_FILE = "fluiddext1-pools.json";
const DEFAULT_FACTORY: Address = "0x91716c4eDA1fB55e84Bf8b4c7085f84285c19085";

/** Same shape as createPools.ts FluidDexT1PoolConfig */
type CreatePoolsFluidDexT1Config = {
  poolType: "fluiddext1";
  fluidPool: Address;
  currency0: Address;
  currency1: Address;
  fee: number | null;
  tickSpacing: number | null;
  sqrtPriceX96: bigint | null;
};

/** Fluid native token; map to address(0) for Uniswap v4 pool init */
const FLUID_NATIVE: Address = "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE";
const ZERO_ADDRESS: Address = "0x0000000000000000000000000000000000000000";

function toUniswapV4Currency(addr: string): Address {
  return addr.toLowerCase() === FLUID_NATIVE.toLowerCase() ? ZERO_ADDRESS : (getAddress(addr) as Address);
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

function orderCurrencies(token0: Address, token1: Address): [Address, Address] {
  const mapped = [toUniswapV4Currency(token0), toUniswapV4Currency(token1)].sort((a, b) =>
    a.toLowerCase().localeCompare(b.toLowerCase()),
  );
  return [mapped[0]!, mapped[1]!];
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
  const resolverAddr =
    getEnvForChain("FLUID_DEX_T1_RESOLVER", chainId) ?? getEnvForChain("FLUID_DEX_RESOLVER", chainId);
  const factoryAddrRaw =
    getEnvForChain("FLUID_DEX_FACTORY", chainId) ?? getEnvForChain("FACTORY_ADDRESS", chainId) ?? DEFAULT_FACTORY;

  if (!rpcUrl || !resolverAddr) {
    console.error("Missing env: RPC_URL and (FLUID_DEX_T1_RESOLVER or FLUID_DEX_RESOLVER)");
    process.exit(1);
  }

  const factoryAddr = getAddress(factoryAddrRaw.toLowerCase()) as Address;
  const outputDir = (args["output-dir"] as string) ?? "detected";
  const chunkSize = BigInt(Math.max(1, toInt(args["chunk-blocks"], 100_000)));
  const startBlock = BigInt(Math.max(0, toInt(args["start-block"], 0)));
  const endBlockRaw = args["end-block"];
  const mode = ((args["mode"] as string | undefined) ?? "enumerate").toLowerCase();
  const rps = toInt(args["rps"] ?? getEnvForChain("RPS", chainId), 80);
  const concurrency = Math.max(1, toInt(getEnvForChain("CONCURRENCY", chainId), 8));

  const rateLimitAcquire = pRateLimit(rps);
  const limit = pLimit(concurrency);

  const provider = new JsonRpcProvider(rpcUrl);
  const factory = new Contract(factoryAddr, FLUIDDEXT1_HISTORICAL_FACTORY_ABI, provider);
  const resolver = new Contract(getAddress(resolverAddr.toLowerCase()), FLUIDDEXT1_RESOLVER_ABI, provider);

  const latest = BigInt(await provider.getBlockNumber());
  const endBlock = endBlockRaw ? BigInt(String(endBlockRaw)) : latest;

  if (startBlock < 0n) throw new Error("start-block must be >= 0");
  if (endBlock < startBlock) throw new Error("end-block must be >= start-block");

  const byDexAddr = new Map<Address, string>();

  if (mode === "logs" || mode === "both") {
    const iface = new Interface(FLUIDDEXT1_HISTORICAL_FACTORY_ABI as unknown as string[]);
    const topic0 = iface.getEvent("LogDexDeployed")!.topicHash;

    for (let from = startBlock; from <= endBlock; from += chunkSize) {
      const to = from + chunkSize - 1n > endBlock ? endBlock : from + chunkSize - 1n;

      const logs = await provider.getLogs({
        address: factoryAddr,
        fromBlock: from,
        toBlock: to,
        topics: [topic0],
      });

      for (const log of logs) {
        const parsed = iface.parseLog(log);
        const dex = getAddress(parsed!.args.dex) as Address;
        const dexId = parsed!.args.dexId.toString();
        if (!byDexAddr.has(dex)) byDexAddr.set(dex, dexId);
      }

      if ((to - startBlock) % (chunkSize * 10n) === 0n || to === endBlock) {
        console.error(`[logs] scanned ${from}..${to} (${logs.length} logs)`);
      }
    }
  }

  if (mode === "enumerate" || mode === "both") {
    const total = await factory.totalDexes();
    console.error(`[enumerate] totalDexes() = ${total}`);

    for (let i = 1n; i <= total; i++) {
      const dex = getAddress(await factory.getDexAddress(i)) as Address;
      const ok = await factory.isDex(dex);
      if (!ok) continue;

      if (!byDexAddr.has(dex)) byDexAddr.set(dex, i.toString());

      if (i % 50n === 0n || i === total) {
        console.error(`[enumerate] ${i}/${total}`);
      }
    }
  }

  const uniqueDexes = Array.from(byDexAddr.keys());
  console.log(`Found ${uniqueDexes.length} unique Fluid Dex T1 pools. Fetching tokens via resolver...`);

  const configs: CreatePoolsFluidDexT1Config[] = [];
  let skipped = 0;

  for (const fluidPool of uniqueDexes) {
    const config = await limit(async () => {
      await rateLimitAcquire();
      let token0: Address;
      let token1: Address;
      try {
        [token0, token1] = (await resolver.getPoolTokens(fluidPool)) as [Address, Address];
      } catch {
        return null;
      }
      const [currency0, currency1] = orderCurrencies(token0, token1);

      return {
        poolType: "fluiddext1" as const,
        fluidPool,
        currency0,
        currency1,
        fee: null,
        tickSpacing: null,
        sqrtPriceX96: null,
      } satisfies CreatePoolsFluidDexT1Config;
    });

    if (config) configs.push(config);
    else skipped++;
  }

  if (skipped > 0) {
    console.error(`Skipped ${skipped} pools (getPoolTokens reverted - may be VaultT1 or deprecated)`);
  }

  const outPath = resolveOutputPath(outputDir, chainId, OUTPUT_FILE);
  fs.mkdirSync(path.dirname(outPath), { recursive: true });
  fs.writeFileSync(outPath, JSON.stringify(configs, null, 2));
  console.log(`Wrote ${outPath} (${configs.length} pools in createPools.ts format)`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});

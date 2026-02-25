/**
 * Fluid Dex Lite historical pool discovery.
 * Enumerates all pools via FluidDexLiteResolver.getAllDexes().
 *
 * FluidDexLite does NOT emit LogInitialize events; pool discovery uses the
 * resolver's getAllDexes() view (see Fluid DEX Lite integration docs).
 *
 * Usage:
 *   npx tsx historical/fluiddexlite.ts --chain-id 1
 *
 * Options:
 *   --chain-id <n>          (required) Chain ID; loads RPC_URL_<n>, DEX_LITE_RESOLVER_ADDRESS_<n>
 *   --output-dir <path>     output directory (default: detected); writes to output-dir/chain-id/fluiddexlite-pools.json
 *
 * Env vars (use VAR_<chainId> or VAR for single chain):
 *   RPC_URL                 (required)
 *   DEX_LITE_RESOLVER_ADDRESS  (optional) FluidDexLiteResolver; default mainnet: 0x26b696D0dfDAB6c894Aa9a6575fCD07BB25BbD2C
 *   DEX_LITE_ADDRESS        (optional, legacy) kept for backward compat; resolver is used for discovery
 *
 * Output: JSON array in createPools.ts FluidDexLitePoolConfig format.
 * Fees are fetched via getDexState() and converted from Fluid 1e4 to Uniswap v4 1e6 format.
 */

import "dotenv/config";
import fs from "node:fs";
import path from "node:path";
import { ethers } from "ethers";
import { parseArgs, getEnvForChain, toInt, resolveOutputPath } from "@src/cli";

const OUTPUT_FILE = "fluiddexlite-pools.json";
const DEFAULT_RESOLVER = "0x26b696D0dfDAB6c894Aa9a6575fCD07BB25BbD2C";

/** Fluid native token; map to address(0) for Uniswap v4 pool init */
const FLUID_NATIVE = "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE";
const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";

function toUniswapV4Currency(addr: string): string {
  return addr.toLowerCase() === FLUID_NATIVE.toLowerCase() ? ZERO_ADDRESS : ethers.getAddress(addr);
}

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

const RESOLVER_ABI = [
  "function getAllDexes() external view returns (tuple(address token0, address token1, bytes32 salt)[] memory)",
  "function getDexState(tuple(address token0, address token1, bytes32 salt) dexKey) external view returns (tuple(tuple(uint256 fee, uint256 revenueCut, uint256 rebalancingStatus, bool isCenterPriceShiftActive, uint256 centerPrice, address centerPriceAddress, bool isRangePercentShiftActive, uint256 upperRangePercent, uint256 lowerRangePercent, bool isThresholdPercentShiftActive, uint256 upperShiftThresholdPercent, uint256 lowerShiftThresholdPercent, uint256 token0Decimals, uint256 token1Decimals, uint256 totalToken0AdjustedAmount, uint256 totalToken1AdjustedAmount) dexVariables, tuple(uint256 lastInteractionTimestamp, uint256 rebalancingShiftingTime, uint256 maxCenterPrice, uint256 minCenterPrice, uint256 shiftPercentage, uint256 centerPriceShiftingTime, uint256 startTimestamp) centerPriceShift, tuple(uint256 oldUpperRangePercent, uint256 oldLowerRangePercent, uint256 shiftingTime, uint256 startTimestamp) rangeShift, tuple(uint256 oldUpperThresholdPercent, uint256 oldLowerThresholdPercent, uint256 shiftingTime, uint256 startTimestamp) thresholdShift) dexState)",
] as const;

/** Fluid fee uses 1e4 basis (10000 = 100%). Uniswap v4 uses 1e6 (10000 = 1%). */
function fluidFeeToUniswapV4(fluidFee: bigint | number): number {
  const MAX_U24 = 16_777_215;
  const converted = Number(fluidFee) * 100; // fluidFee * 1e6 / 1e4
  return Math.min(Math.max(0, Math.floor(converted)), MAX_U24);
}

function ensureDirForFile(filePath: string) {
  const dir = path.dirname(path.resolve(filePath));
  fs.mkdirSync(dir, { recursive: true });
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
  const resolverRaw = getEnvForChain("DEX_LITE_RESOLVER_ADDRESS", chainId) ?? DEFAULT_RESOLVER;
  if (!rpcUrl) {
    console.error("Missing env: RPC_URL (or RPC_URL_<chainId>)");
    process.exit(1);
  }

  const resolver = ethers.getAddress(resolverRaw);
  const outputDir = (args["output-dir"] as string) ?? "detected";

  const provider = new ethers.JsonRpcProvider(rpcUrl);
  const resolverContract = new ethers.Contract(resolver, RESOLVER_ABI as unknown as string[], provider);

  console.error(`[enum] FluidDexLiteResolver at ${resolver}`);
  const dexKeys = (await resolverContract.getAllDexes()) as Array<{
    token0: string;
    token1: string;
    salt: string;
  }>;

  const configs: CreatePoolsFluidLiteConfig[] = [];
  for (const dk of dexKeys) {
    const mapped = [toUniswapV4Currency(dk.token0), toUniswapV4Currency(dk.token1)].sort((a, b) =>
      a.toLowerCase().localeCompare(b.toLowerCase()),
    );
    const [currency0, currency1] = [mapped[0], mapped[1]];

    let fee: number | null = null;
    try {
      const dexKey = { token0: dk.token0, token1: dk.token1, salt: dk.salt };
      const dexState = (await resolverContract.getDexState(dexKey)) as {
        dexVariables: { fee: bigint | number };
      };
      const fluidFee = dexState.dexVariables.fee;
      if (fluidFee && Number(fluidFee) > 0) {
        fee = fluidFeeToUniswapV4(fluidFee);
      }
    } catch {
      // getDexState reverted; keep fee null
    }

    configs.push({
      poolType: "fluiddexlite",
      dexSalt: dk.salt as string,
      currency0,
      currency1,
      fee,
      tickSpacing: null,
      sqrtPriceX96: null,
    });
  }

  const outPath = resolveOutputPath(outputDir, chainId, OUTPUT_FILE);
  ensureDirForFile(outPath);
  fs.writeFileSync(outPath, JSON.stringify(configs, null, 2) + "\n");

  console.log(
    JSON.stringify(
      {
        ok: true,
        chainId,
        resolver,
        poolsFound: configs.length,
        outFile: outPath,
      },
      null,
      2,
    ),
  );
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});

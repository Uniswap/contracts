#!/usr/bin/env node

import "dotenv/config";
import { ethers } from "ethers";
import { readFileSync, writeFileSync, existsSync, mkdirSync } from "fs";
import { execSync, spawn } from "child_process";
import { join, dirname } from "path";
import { fileURLToPath } from "url";

const __dirname = dirname(fileURLToPath(import.meta.url));
// projectRoot = contracts/ (where foundry.toml, script/, mine_hook.sh live)
const projectRoot = join(__dirname, "..", "..");
import { getEnvForChain, mustEnvForChain, toInt } from "@src/cli";

/** PoolKey shape for registry output (matches Uniswap v4 PoolKey) */
interface PoolKeyRecord {
  currency0: string;
  currency1: string;
  fee: number;
  tickSpacing: number;
  hooks: string;
}

/** Entry appended to pool-deployed registry */
interface PoolDeployedEntry {
  poolKeys: PoolKeyRecord[];
  metadata: {
    externalPool: string;
    hookAddress: string;
    txHash?: string;
    blockNumber?: number;
    [key: string]: unknown;
  };
}

// Foundry's default CREATE2 deployer - used when deploying via forge script with new X{salt}
const CREATE2_DEPLOYER = "0x4e59b44847b379578588920cA78FbF26c0B4956C";

// Protocol IDs from MineAggregatorHook.s.sol
const PROTOCOL_IDS = {
  STABLESWAP: 0xc1,
  STABLESWAPNG: 0xc2,
  FLUIDDEXT1: 0xf1,
  FLUIDDEXLITE: 0xf3,
} as const;

type PoolType = "stableswap" | "stableswapng" | "fluiddext1" | "fluiddexlite";

interface StableSwapPoolConfig {
  poolType: "stableswap" | "stableswapng";
  curvePool: string;
  tokens: string[];
  fee: number | null; // Uniswap v4 fee (in basis points). null uses default: 0
  tickSpacing: number | null; // Uniswap v4 tick spacing. null uses default: 60
  sqrtPriceX96: string | null; // Uniswap v4 sqrt price. null uses default: 1:1 (2^96)
}

interface FluidDexT1PoolConfig {
  poolType: "fluiddext1";
  fluidPool: string;
  currency0: string;
  currency1: string;
  fee: number | null; // Uniswap v4 fee (in basis points). null uses default: 0
  tickSpacing: number | null; // Uniswap v4 tick spacing. null uses default: 60
  sqrtPriceX96: string | null; // Uniswap v4 sqrt price. null uses default: 1:1 (2^96)
}

interface FluidDexLitePoolConfig {
  poolType: "fluiddexlite";
  dexSalt: string;
  currency0: string;
  currency1: string;
  fee: number | null; // Uniswap v4 fee (in basis points). null uses default: 0
  tickSpacing: number | null; // Uniswap v4 tick spacing. null uses default: 60
  sqrtPriceX96: string | null; // Uniswap v4 sqrt price. null uses default: 1:1 (2^96)
}

// Immutables for self-deploy (read from env) or factory (read from contract)
interface SelfDeployImmutables {
  poolManager: string;
  fluidDexReservesResolver?: string;
  fluidLiquidity?: string;
  fluidDexLite?: string;
  fluidDexLiteResolver?: string;
}

type PoolConfig = StableSwapPoolConfig | FluidDexT1PoolConfig | FluidDexLitePoolConfig;

// Factory ABIs - minimal interfaces for reading immutables and calling createPool
const STABLE_SWAP_FACTORY_ABI = [
  "function POOL_MANAGER() external view returns (address)",
  "function createPool(bytes32 salt, address curvePool, address[] calldata tokens, uint24 fee, int24 tickSpacing, uint160 sqrtPriceX96) external returns (address hook)",
];

const STABLE_SWAP_NG_FACTORY_ABI = [
  "function POOL_MANAGER() external view returns (address)",
  "function createPool(bytes32 salt, address curvePool, address[] calldata tokens, uint24 fee, int24 tickSpacing, uint160 sqrtPriceX96) external returns (address hook)",
];

const FLUID_DEX_T1_FACTORY_ABI = [
  "function POOL_MANAGER() external view returns (address)",
  "function fluidDexReservesResolver() external view returns (address)",
  "function FLUID_LIQUIDITY() external view returns (address)",
  "function createPool(bytes32 salt, address fluidPool, address currency0, address currency1, uint24 fee, int24 tickSpacing, uint160 sqrtPriceX96) external returns (address hook)",
];

const FLUID_DEX_LITE_FACTORY_ABI = [
  "function POOL_MANAGER() external view returns (address)",
  "function FLUID_DEX_LITE() external view returns (address)",
  "function FLUID_DEX_LITE_RESOLVER() external view returns (address)",
  "function createPool(bytes32 salt, bytes32 dexSalt, address currency0, address currency1, uint24 fee, int24 tickSpacing, uint160 sqrtPriceX96) external returns (address hook)",
];

interface FactoryImmutables {
  poolManager: string;
  [key: string]: string; // For additional immutables
}

interface ParsedArgs {
  jsonFile: string;
  factoryAddress: string | null;
  selfDeploy: boolean;
  rpcUrl: string;
  /** Chain ID for env vars (required for self-deploy) */
  chainId: number | null;
  /** When set, append deployed pools to registry files in this dir (e.g. --registry-dir ./deployed-pools) */
  registryDir: string | null;
  /** When set, simulate forge scripts without broadcasting transactions */
  dryRun: boolean;
  /** When set, run forge scripts verbosely (-vvvv) and log full output on errors */
  verbose: boolean;
  /** 1-based index to start at (skip earlier pools). e.g. --start-at 3 starts with 3rd pool. */
  startAt: number;
  /** Number of parallel mining workers (default 1) */
  jobs: number;
}

/**
 * Parse command line arguments
 */
function parseArgs(): ParsedArgs {
  const args = process.argv.slice(2);

  // Check for --self-deploy flag
  const selfDeployIndex = args.indexOf("--self-deploy");
  const selfDeploy = selfDeployIndex !== -1;

  // Extract positional args (exclude known flags and their values)
  const flagNames = [
    "--self-deploy",
    "--chain-id",
    "--registry-dir",
    "--dry-run",
    "--verbose",
    "-v",
    "--start-at",
    "--jobs",
    "-j",
  ];
  const positionalArgs: string[] = [];
  for (let i = 0; i < args.length; i++) {
    const a = args[i];
    if (flagNames.includes(a)) {
      if (a === "--chain-id" || a === "--registry-dir" || a === "--start-at" || a === "--jobs" || a === "-j") i++; // skip value
      continue;
    }
    positionalArgs.push(a);
  }

  const minArgs = 1;
  if (positionalArgs.length < minArgs) {
    console.error("Usage: ts-node createPools.ts <jsonFile> [factoryAddress] [--self-deploy] [--chain-id <n>]");
    console.error(
      "  jsonFile: Path to JSON file containing pool configurations (each config must have a 'poolType' field)",
    );
    console.error("  factoryAddress: Factory contract address (required unless --self-deploy)");
    console.error("  --self-deploy: Deploy hooks directly from wallet instead of via factory");
    console.error("  --chain-id <n>: Chain ID; selects RPC_URL_<n> from env (e.g. RPC_URL_1 for mainnet)");
    console.error("");
    console.error("Modes:");
    console.error(
      "  Factory mode: ts-node createPools.ts pools.json 0xFactoryAddr [--chain-id 1] [--registry-dir ./deployed-pools]",
    );
    console.error(
      "  Self-deploy:  ts-node createPools.ts pools.json --self-deploy [--chain-id 1] [--registry-dir ./deployed-pools]",
    );
    console.error("  --dry-run:    Simulate without broadcasting (forge script runs but no txs sent)");
    console.error("  --verbose, -v: Run forge scripts verbosely and log full output on errors");
    console.error(
      "  --start-at <n>: Start at 1-based pool index (skip earlier pools). e.g. --start-at 3 to resume from pool 3.",
    );
    console.error("  --jobs <n>, -j <n>: Run N parallel salt mining workers (default 1). Speeds up mining.");
    console.error("");
    console.error("Environment variables:");
    console.error("  RPC_URL_<chainId>: RPC endpoint (required when --chain-id set)");
    console.error("  PRIVATE_KEY: Private key for signing transactions (required)");
    process.exit(1);
  }

  const jsonFile = positionalArgs[0];
  const factoryAddress = selfDeploy ? null : positionalArgs[1];

  // Validate mutual exclusivity (factory address looks like 0x...)
  if (selfDeploy && positionalArgs.length >= 2 && positionalArgs[1].startsWith("0x")) {
    console.error("Error: --self-deploy and factoryAddress are mutually exclusive");
    process.exit(1);
  }

  if (!selfDeploy && (!factoryAddress || positionalArgs.length < 2)) {
    console.error("Error: In factory mode, factoryAddress is required (e.g. createPools.ts pools.json 0xFactoryAddr)");
    process.exit(1);
  }

  const chainIdIndex = args.indexOf("--chain-id");
  const chainIdRaw = chainIdIndex !== -1 && args[chainIdIndex + 1] ? args[chainIdIndex + 1] : null;
  const chainId = chainIdRaw != null ? toInt(String(chainIdRaw), 0) : null;

  const rpcUrl =
    chainId != null && chainId > 0
      ? getEnvForChain("RPC_URL", chainId)
      : (process.env.RPC_URL ?? "").trim() || undefined;
  if (!rpcUrl) {
    console.error(
      chainId != null && chainId > 0
        ? `Error: RPC_URL_${chainId} environment variable is required when using --chain-id ${chainId}`
        : "Error: RPC_URL environment variable is required",
    );
    process.exit(1);
  }

  const privateKey = process.env.PRIVATE_KEY;
  if (!privateKey) {
    console.error("Error: PRIVATE_KEY environment variable is required");
    process.exit(1);
  }

  const registryDirIndex = args.indexOf("--registry-dir");
  const registryDir = registryDirIndex !== -1 && args[registryDirIndex + 1] ? args[registryDirIndex + 1] : null;

  const dryRun = args.includes("--dry-run");
  const verbose = args.includes("--verbose") || args.includes("-v");

  const startAtIndex = args.indexOf("--start-at");
  const startAtRaw = startAtIndex !== -1 && args[startAtIndex + 1] ? args[startAtIndex + 1] : null;
  const startAt = startAtRaw != null ? toInt(String(startAtRaw), 1) : 1;
  if (startAt < 1) {
    console.error("Error: --start-at must be >= 1");
    process.exit(1);
  }

  const jobsIndex = args.indexOf("--jobs");
  const jobsIndexShort = args.indexOf("-j");
  const jobsIdx = jobsIndex !== -1 ? jobsIndex : jobsIndexShort;
  const jobsRaw = jobsIdx !== -1 && args[jobsIdx + 1] ? args[jobsIdx + 1] : null;
  const jobs = jobsRaw != null ? toInt(String(jobsRaw), 1) : 1;
  if (jobs < 1 || jobs > 16) {
    console.error("Error: --jobs must be between 1 and 16");
    process.exit(1);
  }

  return {
    jsonFile,
    factoryAddress,
    selfDeploy,
    rpcUrl,
    chainId,
    registryDir,
    dryRun,
    verbose,
    startAt,
    jobs,
  };
}

const POOL_TYPES: PoolType[] = ["stableswap", "stableswapng", "fluiddext1", "fluiddexlite"];

function isPoolType(s: unknown): s is PoolType {
  return typeof s === "string" && POOL_TYPES.includes(s as PoolType);
}

/** Default values for Uniswap v4 hook parameters when not specified */
const DEFAULT_HOOK_PARAMS = {
  fee: 0,
  tickSpacing: 60,
  sqrtPriceX96: "79228162514264337593543950336", // 1:1 (2^96)
} as const;

/**
 * Get resolved hook parameters with defaults applied
 */
function getHookParams(config: StableSwapPoolConfig | FluidDexT1PoolConfig | FluidDexLitePoolConfig) {
  return {
    fee: config.fee ?? DEFAULT_HOOK_PARAMS.fee,
    tickSpacing: config.tickSpacing ?? DEFAULT_HOOK_PARAMS.tickSpacing,
    sqrtPriceX96: config.sqrtPriceX96 ?? DEFAULT_HOOK_PARAMS.sqrtPriceX96,
  };
}

/**
 * Build PoolKey records for registry. For stableswap/stableswapng: all token pairs.
 * For fluiddext1/fluiddexlite: single pair. currency0 < currency1 for v4 ordering.
 */
function buildPoolKeys(poolConfig: PoolConfig, poolType: PoolType, hookAddress: string): PoolKeyRecord[] {
  const params = getHookParams(poolConfig);

  const orderPair = (a: string, b: string): [string, string] => (a.toLowerCase() < b.toLowerCase() ? [a, b] : [b, a]);

  switch (poolType) {
    case "stableswap":
    case "stableswapng": {
      const config = poolConfig as StableSwapPoolConfig;
      const tokens = config.tokens;
      const keys: PoolKeyRecord[] = [];
      for (let i = 0; i < tokens.length; i++) {
        for (let j = i + 1; j < tokens.length; j++) {
          const [c0, c1] = orderPair(tokens[i], tokens[j]);
          keys.push({
            currency0: c0,
            currency1: c1,
            fee: params.fee,
            tickSpacing: params.tickSpacing,
            hooks: hookAddress,
          });
        }
      }
      return keys;
    }
    case "fluiddext1":
    case "fluiddexlite": {
      const config = poolConfig as FluidDexT1PoolConfig | FluidDexLitePoolConfig;
      const [c0, c1] = orderPair(config.currency0, config.currency1);
      return [
        {
          currency0: c0,
          currency1: c1,
          fee: params.fee,
          tickSpacing: params.tickSpacing,
          hooks: hookAddress,
        },
      ];
    }
  }
}

/**
 * Get external pool address/identifier for metadata
 */
function getExternalPool(poolConfig: PoolConfig, poolType: PoolType): string {
  switch (poolType) {
    case "stableswap":
    case "stableswapng":
      return (poolConfig as StableSwapPoolConfig).curvePool;
    case "fluiddext1":
      return (poolConfig as FluidDexT1PoolConfig).fluidPool;
    case "fluiddexlite":
      return (poolConfig as FluidDexLitePoolConfig).dexSalt;
  }
}

/**
 * Append a deployed pool entry to the registry file for the given pool type.
 * File is an array of PoolDeployedEntry. Creates file if it doesn't exist.
 */
function appendToRegistryFile(registryDir: string, poolType: PoolType, entry: PoolDeployedEntry): void {
  const fileName = `deployed-${poolType}.json`;
  const filePath = join(registryDir, fileName);

  let poolsDeployed: PoolDeployedEntry[];
  if (existsSync(filePath)) {
    const content = readFileSync(filePath, "utf-8");
    poolsDeployed = JSON.parse(content) as PoolDeployedEntry[];
  } else {
    poolsDeployed = [];
  }

  poolsDeployed.push(entry);

  if (!existsSync(registryDir)) {
    mkdirSync(registryDir, { recursive: true });
  }
  writeFileSync(filePath, JSON.stringify(poolsDeployed, null, 2));
  console.log(`Appended to registry: ${filePath}`);
}

/**
 * Load and parse JSON file for factory mode.
 * Each config must have a "poolType" field; all configs must have the same poolType.
 */
function loadJsonFile(filePath: string): PoolConfig[] {
  try {
    const content = readFileSync(filePath, "utf-8");
    const pools = JSON.parse(content);

    if (!Array.isArray(pools)) {
      throw new Error("JSON file must contain an array of pool configurations");
    }

    if (pools.length === 0) {
      throw new Error("JSON file must contain at least one pool configuration");
    }

    for (let i = 0; i < pools.length; i++) {
      const p = pools[i];
      if (!isPoolType(p?.poolType)) {
        throw new Error(`Pool ${i + 1} missing or invalid 'poolType'. Must be one of: ${POOL_TYPES.join(", ")}`);
      }
    }

    const firstType = pools[0].poolType as PoolType;
    for (let i = 1; i < pools.length; i++) {
      if (pools[i].poolType !== firstType) {
        throw new Error(
          `Pool ${i + 1} has poolType "${pools[i].poolType}" but all configs must have the same poolType (first is "${firstType}")`,
        );
      }
    }

    return pools;
  } catch (error) {
    if (error instanceof Error) {
      console.error(`Error loading JSON file: ${error.message}`);
    } else {
      console.error("Unknown error loading JSON file");
    }
    process.exit(1);
  }
}

/**
 * Read immutables from env vars for self-deploy mode.
 * Uses VAR or VAR_<chainId> (e.g. POOL_MANAGER_1, DEX_LITE_ADDRESS_1).
 */
function getImmutablesFromEnv(chainId: number, poolType: PoolType): SelfDeployImmutables {
  const immutables: SelfDeployImmutables = {
    poolManager: mustEnvForChain("POOL_MANAGER", chainId),
  };

  if (poolType === "fluiddext1") {
    immutables.fluidDexReservesResolver = mustEnvForChain("FLUID_DEX_RESOLVER", chainId);
    immutables.fluidLiquidity = mustEnvForChain("FLUID_LIQUIDITY", chainId);
  } else if (poolType === "fluiddexlite") {
    const dexLite = getEnvForChain("FLUID_DEX_LITE", chainId) ?? getEnvForChain("DEX_LITE_ADDRESS", chainId);
    const dexLiteResolver =
      getEnvForChain("FLUID_DEX_LITE_RESOLVER", chainId) ?? getEnvForChain("DEX_LITE_RESOLVER_ADDRESS", chainId);
    if (!dexLite)
      throw new Error(`FLUID_DEX_LITE_${chainId} or DEX_LITE_ADDRESS_${chainId} required for fluiddexlite self-deploy`);
    if (!dexLiteResolver)
      throw new Error(
        `FLUID_DEX_LITE_RESOLVER_${chainId} or DEX_LITE_RESOLVER_ADDRESS_${chainId} required for fluiddexlite self-deploy`,
      );
    immutables.fluidDexLite = dexLite;
    immutables.fluidDexLiteResolver = dexLiteResolver;
  }

  return immutables;
}

/**
 * Convert SelfDeployImmutables to FactoryImmutables format
 */
function immutablesToFactoryFormat(immutables: SelfDeployImmutables): FactoryImmutables {
  const result: FactoryImmutables = {
    poolManager: immutables.poolManager,
  };

  if (immutables.fluidDexReservesResolver) {
    result.fluidDexReservesResolver = immutables.fluidDexReservesResolver;
  }
  if (immutables.fluidLiquidity) {
    result.fluidLiquidity = immutables.fluidLiquidity;
  }
  if (immutables.fluidDexLite) {
    result.fluidDexLite = immutables.fluidDexLite;
  }
  if (immutables.fluidDexLiteResolver) {
    result.fluidDexLiteResolver = immutables.fluidDexLiteResolver;
  }

  return result;
}

/**
 * Read factory contract immutables
 */
async function readFactoryImmutables(
  provider: ethers.Provider,
  factoryAddress: string,
  poolType: PoolType,
): Promise<FactoryImmutables> {
  let abi: string[];

  switch (poolType) {
    case "stableswap":
      abi = STABLE_SWAP_FACTORY_ABI;
      break;
    case "stableswapng":
      abi = STABLE_SWAP_NG_FACTORY_ABI;
      break;
    case "fluiddext1":
      abi = FLUID_DEX_T1_FACTORY_ABI;
      break;
    case "fluiddexlite":
      abi = FLUID_DEX_LITE_FACTORY_ABI;
      break;
  }

  const factory = new ethers.Contract(factoryAddress, abi, provider);
  const immutables: FactoryImmutables = { poolManager: "" };

  // Read POOL_MANAGER (always present)
  immutables.poolManager = await factory.POOL_MANAGER();

  // Read additional immutables based on pool type
  if (poolType === "fluiddext1") {
    immutables.fluidDexReservesResolver = await factory.FLUID_DEX_RESOLVER();
    immutables.fluidLiquidity = await factory.FLUID_LIQUIDITY();
  } else if (poolType === "fluiddexlite") {
    immutables.fluidDexLite = await factory.FLUID_DEX_LITE();
    immutables.fluidDexLiteResolver = await factory.FLUID_DEX_LITE_RESOLVER();
  }

  return immutables;
}

/**
 * Encode constructor arguments for salt mining
 */
function encodeConstructorArgs(
  poolConfig: PoolConfig,
  poolType: PoolType,
  factoryImmutables: FactoryImmutables,
): string {
  let encoded: string;

  switch (poolType) {
    case "stableswap":
    case "stableswapng": {
      const config = poolConfig as StableSwapPoolConfig;
      encoded = ethers.AbiCoder.defaultAbiCoder().encode(
        ["address", "address"],
        [factoryImmutables.poolManager, config.curvePool],
      );
      break;
    }
    case "fluiddext1": {
      const config = poolConfig as FluidDexT1PoolConfig;
      encoded = ethers.AbiCoder.defaultAbiCoder().encode(
        ["address", "address", "address", "address"],
        [
          factoryImmutables.poolManager,
          config.fluidPool,
          factoryImmutables.fluidDexReservesResolver,
          factoryImmutables.fluidLiquidity,
        ],
      );
      break;
    }
    case "fluiddexlite": {
      const config = poolConfig as FluidDexLitePoolConfig;
      encoded = ethers.AbiCoder.defaultAbiCoder().encode(
        ["address", "address", "address", "bytes32"],
        [
          factoryImmutables.poolManager,
          factoryImmutables.fluidDexLite,
          factoryImmutables.fluidDexLiteResolver,
          config.dexSalt,
        ],
      );
      break;
    }
  }

  // Ensure 0x prefix
  return encoded.startsWith("0x") ? encoded : `0x${encoded}`;
}

/**
 * Get protocol ID for pool type
 */
function getProtocolId(poolType: PoolType): number {
  switch (poolType) {
    case "stableswap":
      return PROTOCOL_IDS.STABLESWAP;
    case "stableswapng":
      return PROTOCOL_IDS.STABLESWAPNG;
    case "fluiddext1":
      return PROTOCOL_IDS.FLUIDDEXT1;
    case "fluiddexlite":
      return PROTOCOL_IDS.FLUIDDEXLITE;
  }
}

/** PoolManager Initialize event for verification */
const INITIALIZE_TOPIC = "0xdd466e674ea557f56295e2d0218a125ea4b4f0f6f3307b95f85e6110838d6438";

/**
 * When forge script fails, verify whether deployment actually succeeded (false positive).
 * Checks: 1) Hook has code at address parsed from output; 2) Initialize events for that hook.
 */
async function verifyDeploymentOnForgeFailure(
  provider: ethers.Provider,
  poolManagerAddress: string,
  poolConfig: PoolConfig,
  poolType: PoolType,
  forgeOutput: string,
): Promise<{
  hookAddress: string;
  hookDeployed: boolean;
  poolsInitialized: number;
} | null> {
  const hookMatch = forgeOutput.match(/Hook Address:\s*(0x[a-fA-F0-9]{40})/);
  if (!hookMatch) return null;

  const hookAddress = ethers.getAddress(hookMatch[1]);
  const code = await provider.getCode(hookAddress);
  const hookDeployed = !!code && code !== "0x" && code.length > 2;

  if (!hookDeployed) return { hookAddress, hookDeployed: false, poolsInitialized: 0 };

  const poolKeys = buildPoolKeys(poolConfig, poolType, hookAddress);
  let poolsInitialized = 0;

  try {
    const blockNumber = await provider.getBlockNumber();
    const fromBlock = Math.max(0, blockNumber - 500);
    const logs = await provider.getLogs({
      address: poolManagerAddress,
      topics: [INITIALIZE_TOPIC],
      fromBlock,
      toBlock: blockNumber,
    });

    for (const log of logs) {
      if (log.topics.length < 4) continue;
      const currency0 = "0x" + log.topics[2].slice(26);
      const currency1 = "0x" + log.topics[3].slice(26);
      const data = ethers.AbiCoder.defaultAbiCoder().decode(
        ["uint24", "int24", "address", "uint160", "int24"],
        log.data,
      );
      const hooks = data[2];
      if (hooks?.toLowerCase() !== hookAddress.toLowerCase()) continue;
      if (
        poolKeys.some(
          (k) =>
            k.currency0.toLowerCase() === currency0.toLowerCase() &&
            k.currency1.toLowerCase() === currency1.toLowerCase(),
        )
      ) {
        poolsInitialized++;
      }
    }
  } catch {
    // Ignore log query errors
  }

  return { hookAddress, hookDeployed, poolsInitialized };
}

/**
 * Run a single mine_hook.sh worker. Resolves with salt on success, rejects on failure.
 */
function runMineHookWorker(
  scriptPath: string,
  args: string[],
  execEnv: NodeJS.ProcessEnv,
  projectRoot: string,
  streamOutput: boolean,
): Promise<{ salt: string; output: string }> {
  return new Promise((resolve, reject) => {
    const child = spawn("bash", args, {
      cwd: projectRoot,
      env: execEnv,
      stdio: ["inherit", "pipe", streamOutput ? "inherit" : "pipe"],
    });

    let output = "";
    child.stdout!.on("data", (chunk) => {
      const str = chunk.toString();
      output += str;
      if (streamOutput) process.stdout.write(chunk);
    });

    child.on("close", (code) => {
      if (code === 0) {
        const saltMatch = output.match(/Salt \(bytes32\):\s*(0x[a-fA-F0-9]{64})/);
        if (saltMatch) resolve({ salt: saltMatch[1], output });
        else reject(new Error("Could not parse salt from mine_hook.sh output"));
      } else {
        const err = new Error(`mine_hook.sh exited with code ${code}`) as Error & { stdout?: string };
        err.stdout = output;
        reject(err);
      }
    });
    child.on("error", reject);
  });
}

/**
 * Mine salt using mine_hook.sh script
 * @param constructorArgs - Hex-encoded constructor arguments
 * @param protocolId - Protocol identifier
 * @param deployerAddress - Optional deployer address (factory address or wallet address)
 * @param verbose - When true, run forge verbosely (passed via FORGE_VERBOSE env)
 * @param jobs - Number of parallel workers (default 1). Each searches a different random region.
 */
async function mineSalt(
  constructorArgs: string,
  protocolId: number,
  deployerAddress?: string,
  verbose = false,
  jobs = 1,
): Promise<string> {
  const scriptPath = join(projectRoot, "mine_hook.sh");
  const protocolIdHex = `0x${protocolId.toString(16).toUpperCase()}`;

  console.log(`Mining salt for protocol ${protocolIdHex}...`);
  console.log(`Constructor args: ${constructorArgs.substring(0, 66)}...`);
  if (deployerAddress) {
    console.log(`Deployer address: ${deployerAddress}`);
  }
  if (jobs > 1) {
    console.log(`Running ${jobs} parallel mining workers...`);
  }

  const baseArgs = [scriptPath, constructorArgs, protocolIdHex];
  if (deployerAddress) {
    baseArgs.push("500", deployerAddress);
  }
  const execEnv = {
    ...process.env,
    ...(verbose && { FORGE_VERBOSE: "1" }),
  };

  try {
    if (jobs === 1) {
      const result = await runMineHookWorker(scriptPath, baseArgs, execEnv, projectRoot, true);
      console.log(`✓ Found salt: ${result.salt}`);
      return result.salt;
    }

    // Parallel: run N workers, first to find a valid salt wins
    const children: ReturnType<typeof spawn>[] = [];
    const workerPromises: Promise<{ salt: string } | null>[] = [];

    for (let i = 0; i < jobs; i++) {
      const child = spawn("bash", baseArgs, {
        cwd: projectRoot,
        env: execEnv,
        stdio: ["inherit", "pipe", "pipe"],
      });
      children.push(child);

      let output = "";
      child.stdout!.on("data", (chunk) => {
        output += chunk.toString();
      });

      const promise = new Promise<{ salt: string } | null>((resolve) => {
        child.on("close", (code) => {
          if (code === 0) {
            const saltMatch = output.match(/Salt \(bytes32\):\s*(0x[a-fA-F0-9]{64})/);
            if (saltMatch) resolve({ salt: saltMatch[1] });
            else resolve(null);
          } else {
            resolve(null);
          }
        });
        child.on("error", () => resolve(null));
      });
      workerPromises.push(promise);
    }

    const killAll = () => {
      children.forEach((c) => {
        try {
          c.kill("SIGTERM");
        } catch {
          /* ignore */
        }
      });
    };

    // Race: first success wins; reject only when all fail
    const salt = await new Promise<string>((resolve, reject) => {
      let failedCount = 0;
      workerPromises.forEach((p) => {
        p.then((result) => {
          if (result) {
            killAll();
            resolve(result.salt);
          } else {
            failedCount++;
            if (failedCount === jobs) {
              reject(new Error("All mining workers failed"));
            }
          }
        });
      });
    });

    console.log(`✓ Found salt: ${salt}`);
    return salt;
  } catch (error) {
    console.error("Error mining salt:");
    if (error instanceof Error) {
      console.error(error.message);
      const execErr = error as { stdout?: string; stderr?: string };
      if (execErr.stdout) {
        console.error("\n--- Forge/mine_hook stdout ---\n", execErr.stdout);
      }
      if (execErr.stderr) {
        console.error("\n--- Forge/mine_hook stderr ---\n", execErr.stderr);
      }
    }
    throw error;
  }
}

/**
 * Self-deploy a hook using SelfCreateHook.s.sol forge script
 */
function selfDeployPool(
  poolConfig: PoolConfig,
  poolType: PoolType,
  immutables: SelfDeployImmutables,
  salt: string,
  rpcUrl: string,
  dryRun: boolean,
  verbose = false,
): string {
  const protocolId = getProtocolId(poolType);

  // Build environment variables for the forge script
  // Ensure PRIVATE_KEY has 0x prefix (vm.envUint requires it)
  const rawKey = (process.env.PRIVATE_KEY ?? "").trim();
  const privateKey = rawKey.startsWith("0x") ? rawKey : `0x${rawKey}`;

  const envVars: Record<string, string> = {
    PROTOCOL_ID: protocolId.toString(),
    SALT: salt,
    POOL_MANAGER: immutables.poolManager,
    PRIVATE_KEY: privateKey,
  };

  // Add pool-specific environment variables
  switch (poolType) {
    case "stableswap":
    case "stableswapng": {
      const config = poolConfig as StableSwapPoolConfig;
      const params = getHookParams(config);
      envVars.CURVE_POOL = config.curvePool;
      // Pass all tokens; forge script will init one Uniswap pool per pair
      envVars.TOKENS = config.tokens.join(",");
      envVars.FEE = params.fee.toString();
      envVars.TICK_SPACING = params.tickSpacing.toString();
      envVars.SQRT_PRICE_X96 = params.sqrtPriceX96;
      break;
    }
    case "fluiddext1": {
      const config = poolConfig as FluidDexT1PoolConfig;
      const params = getHookParams(config);
      envVars.FLUID_POOL = config.fluidPool;
      envVars.FLUID_DEX_RESOLVER = immutables.fluidDexReservesResolver!;
      envVars.FLUID_LIQUIDITY = immutables.fluidLiquidity!;
      envVars.TOKENS = [config.currency0, config.currency1].join(",");
      envVars.FEE = params.fee.toString();
      envVars.TICK_SPACING = params.tickSpacing.toString();
      envVars.SQRT_PRICE_X96 = params.sqrtPriceX96;
      break;
    }
    case "fluiddexlite": {
      const config = poolConfig as FluidDexLitePoolConfig;
      const params = getHookParams(config);
      envVars.FLUID_DEX_LITE = immutables.fluidDexLite!;
      envVars.FLUID_DEX_LITE_RESOLVER = immutables.fluidDexLiteResolver!;
      envVars.DEX_SALT = config.dexSalt;
      envVars.TOKENS = [config.currency0, config.currency1].join(",");
      envVars.FEE = params.fee.toString();
      envVars.TICK_SPACING = params.tickSpacing.toString();
      envVars.SQRT_PRICE_X96 = params.sqrtPriceX96;
      break;
    }
  }

  // Build env string for command
  const envString = Object.entries(envVars)
    .map(([key, value]) => `${key}="${value}"`)
    .join(" ");

  console.log(`Self-deploying hook via SelfCreateHook.s.sol...`);
  if (dryRun) console.log("(dry run - no broadcast)");
  console.log(`Protocol: ${poolType}, Salt: ${salt.substring(0, 18)}...`);

  try {
    const broadcastFlag = dryRun ? "" : " --broadcast";
    const verboseFlag = verbose ? " -vvvv" : "";
    const command = `${envString} forge script script/SelfCreateHook.s.sol:SelfCreateHookScript --via-ir --rpc-url "${rpcUrl}"${broadcastFlag}${verboseFlag}`;
    const output = execSync(command, {
      encoding: "utf-8",
      cwd: projectRoot,
      env: { ...process.env, ...envVars },
    });

    if (verbose) {
      console.log("\n--- Forge script output ---\n", output);
    }

    // Parse hook address from output
    const hookMatch = output.match(/Hook Address:\s*(0x[a-fA-F0-9]{40})/);
    if (hookMatch) {
      const hookAddress = hookMatch[1];
      console.log(`✓ Hook deployed at: ${hookAddress}`);
      return hookAddress;
    }

    // If we can't parse the address, just indicate success
    console.log(`✓ Self-deploy completed`);
    return "deployed";
  } catch (error) {
    console.error("Error in self-deploy:");
    if (error instanceof Error) {
      console.error(error.message);
      const execErr = error as { stdout?: string; stderr?: string };
      if (execErr.stdout) {
        console.error("\n--- Forge stdout ---\n", execErr.stdout);
      }
      if (execErr.stderr) {
        console.error("\n--- Forge stderr ---\n", execErr.stderr);
      }
    }
    throw error;
  }
}

/**
 * Create pool via factory contract
 */
async function createPool(
  signer: ethers.Signer,
  factoryAddress: string,
  poolConfig: PoolConfig,
  poolType: PoolType,
  salt: string,
): Promise<{ hookAddress: string; blockNumber: number; txHash: string }> {
  let abi: string[];
  let args: any[];

  switch (poolType) {
    case "stableswap": {
      abi = STABLE_SWAP_FACTORY_ABI;
      const config = poolConfig as StableSwapPoolConfig;
      const params = getHookParams(config);
      // Currency is type alias for address, so pass addresses directly
      args = [
        salt,
        config.curvePool,
        config.tokens, // Currency[] is address[] in ABI
        params.fee,
        params.tickSpacing,
        BigInt(params.sqrtPriceX96),
      ];
      break;
    }
    case "stableswapng": {
      abi = STABLE_SWAP_NG_FACTORY_ABI;
      const config = poolConfig as StableSwapPoolConfig;
      const params = getHookParams(config);
      // Currency is type alias for address, so pass addresses directly
      args = [
        salt,
        config.curvePool,
        config.tokens, // Currency[] is address[] in ABI
        params.fee,
        params.tickSpacing,
        BigInt(params.sqrtPriceX96),
      ];
      break;
    }
    case "fluiddext1": {
      abi = FLUID_DEX_T1_FACTORY_ABI;
      const config = poolConfig as FluidDexT1PoolConfig;
      const params = getHookParams(config);
      // Currency is type alias for address, so pass addresses directly
      args = [
        salt,
        config.fluidPool,
        config.currency0, // Currency is address in ABI
        config.currency1, // Currency is address in ABI
        params.fee,
        params.tickSpacing,
        BigInt(params.sqrtPriceX96),
      ];
      break;
    }
    case "fluiddexlite": {
      abi = FLUID_DEX_LITE_FACTORY_ABI;
      const config = poolConfig as FluidDexLitePoolConfig;
      const params = getHookParams(config);
      // Currency is type alias for address, so pass addresses directly
      args = [
        salt,
        config.dexSalt,
        config.currency0, // Currency is address in ABI
        config.currency1, // Currency is address in ABI
        params.fee,
        params.tickSpacing,
        BigInt(params.sqrtPriceX96),
      ];
      break;
    }
  }

  const factoryWithAbi = new ethers.Contract(factoryAddress, abi, signer);

  console.log(`Calling createPool on factory ${factoryAddress}...`);
  console.log(`Args:`, args.map((a, i) => `${i}: ${a.toString().substring(0, 66)}...`).join(", "));

  try {
    const tx = await factoryWithAbi.createPool(...args);
    console.log(`✓ Transaction sent: ${tx.hash}`);

    const receipt = await tx.wait();
    console.log(`✓ Transaction confirmed in block ${receipt.blockNumber}`);

    // Extract hook address from events
    const hookDeployedEvent = receipt.logs.find((log: any) => {
      try {
        const parsed = factoryWithAbi.interface.parseLog(log);
        return parsed?.name === "HookDeployed";
      } catch {
        return false;
      }
    });

    if (hookDeployedEvent) {
      const parsed = factoryWithAbi.interface.parseLog(hookDeployedEvent);
      const hookAddress = (parsed?.args.hook || parsed?.args[0]) as string;
      console.log(`✓ Hook deployed at: ${hookAddress}`);
      return {
        hookAddress,
        blockNumber: Number(receipt!.blockNumber),
        txHash: tx.hash,
      };
    }

    return {
      hookAddress: "",
      blockNumber: Number(receipt!.blockNumber),
      txHash: tx.hash,
    };
  } catch (error) {
    console.error("Error creating pool:");
    if (error instanceof Error) {
      console.error(error.message);
      // Check for revert reason in error data
      if ("data" in error && error.data) {
        console.error("Error data:", error.data);
      }
      if ("reason" in error && error.reason) {
        console.error("Revert reason:", error.reason);
      }
    }
    throw error;
  }
}

/**
 * Main execution function
 */
async function main() {
  const {
    jsonFile,
    factoryAddress,
    selfDeploy,
    rpcUrl,
    chainId: parsedChainId,
    registryDir,
    dryRun,
    verbose,
    startAt,
    jobs,
  } = parseArgs();

  console.log("=== Pool Creation Script ===");
  console.log(`JSON File: ${jsonFile}`);
  console.log(`Mode: ${selfDeploy ? "Self-Deploy" : "Factory"}`);
  if (factoryAddress) {
    console.log(`Factory Address: ${factoryAddress}`);
  }
  console.log(`RPC URL: ${rpcUrl}`);
  if (registryDir) {
    console.log(`Registry dir: ${registryDir}`);
  }
  if (dryRun) {
    console.log("DRY RUN: forge scripts will simulate without broadcasting");
  }
  if (verbose) {
    console.log("VERBOSE: forge scripts will run with -vvvv");
  }
  if (startAt > 1) {
    console.log(`Starting at pool index: ${startAt} (skipping first ${startAt - 1} pool(s))`);
  }
  if (jobs > 1) {
    console.log(`Salt mining: ${jobs} parallel workers`);
  }
  console.log("");

  // Setup provider and signer
  const provider = new ethers.JsonRpcProvider(rpcUrl);
  const privateKey = process.env.PRIVATE_KEY!;
  const signer = new ethers.Wallet(privateKey, provider);
  console.log(`Using signer: ${signer.address}`);
  console.log("");

  if (selfDeploy) {
    // Self-deploy mode: load configs (same format as factory), immutables from env
    const allPools = loadJsonFile(jsonFile);
    const pools = startAt > 1 ? allPools.slice(startAt - 1) : allPools;
    if (startAt > 1 && pools.length === 0) {
      console.error(`Error: --start-at ${startAt} exceeds pool count (${allPools.length})`);
      process.exit(1);
    }
    console.log(
      `Loaded ${allPools.length} pool configuration(s)${startAt > 1 ? `, processing from index ${startAt} (${pools.length} remaining)` : ""}`,
    );
    console.log("");

    const chainId = parsedChainId ?? Number((await provider.getNetwork()).chainId);

    for (let j = 0; j < pools.length; j++) {
      const i = startAt - 1 + j;
      const poolConfig = pools[j];
      const poolType = poolConfig.poolType;
      const immutables = getImmutablesFromEnv(chainId, poolType);
      const protocolId = getProtocolId(poolType);
      console.log(`\n--- Processing Pool ${i + 1}/${allPools.length} (${poolType}) ---`);

      try {
        // Convert immutables to factory format for constructor encoding
        const factoryImmutables = immutablesToFactoryFormat(immutables);

        // Encode constructor arguments
        const constructorArgs = encodeConstructorArgs(poolConfig, poolType, factoryImmutables);

        // Mine salt using CREATE2 deployer (Foundry routes new X{salt} through 0x4e59...)
        const salt = await mineSalt(constructorArgs, protocolId, CREATE2_DEPLOYER, verbose, jobs);

        // Self-deploy via forge script
        const hookAddress = selfDeployPool(poolConfig, poolType, immutables, salt, rpcUrl, dryRun, verbose);

        if (registryDir && hookAddress && hookAddress !== "deployed") {
          const poolKeys = buildPoolKeys(poolConfig, poolType, hookAddress);
          if (poolKeys.length > 0) {
            const blockNumber = Number(await provider.getBlockNumber());
            appendToRegistryFile(registryDir, poolType, {
              poolKeys,
              metadata: {
                externalPool: getExternalPool(poolConfig, poolType),
                hookAddress,
                blockNumber,
              },
            });
          }
        }
        console.log(`✓ Successfully created pool ${i + 1}`);
      } catch (error) {
        console.error(`✗ Failed to create pool ${i + 1}:`);
        if (error instanceof Error) {
          console.error(error.message);
          const execErr = error as { stdout?: string; stderr?: string };
          if (execErr.stdout) {
            console.error("\n--- Forge stdout ---\n", execErr.stdout);
          }
          if (execErr.stderr) {
            console.error("\n--- Forge stderr ---\n", execErr.stderr);
          }
          const forgeOutput = [execErr.stdout, execErr.stderr].filter(Boolean).join("\n");
          if (forgeOutput) {
            const verification = await verifyDeploymentOnForgeFailure(
              provider,
              immutables.poolManager,
              poolConfig,
              poolType,
              forgeOutput,
            );
            if (verification) {
              if (verification.hookDeployed) {
                console.error("");
                console.error("Verification (possible false positive):");
                console.error(`  Hook has code at ${verification.hookAddress} → deployment likely succeeded`);
                if (verification.poolsInitialized > 0) {
                  console.error(
                    `  Found ${verification.poolsInitialized} Initialize event(s) for this hook → pool(s) initialized on-chain`,
                  );
                }
                console.error("  Check block explorer to confirm.");
              }
            }
          }
        }
        // Continue with next pool
        continue;
      }
    }
  } else {
    // Factory mode: read immutables from factory contract
    const allPools = loadJsonFile(jsonFile);
    const pools = startAt > 1 ? allPools.slice(startAt - 1) : allPools;
    if (startAt > 1 && pools.length === 0) {
      console.error(`Error: --start-at ${startAt} exceeds pool count (${allPools.length})`);
      process.exit(1);
    }
    const poolType = pools[0].poolType;
    console.log(
      `Loaded ${allPools.length} pool configuration(s) (poolType: ${poolType})${startAt > 1 ? `, processing from index ${startAt} (${pools.length} remaining)` : ""}`,
    );
    console.log("");

    // Read factory immutables once
    console.log("Reading factory immutables...");
    const factoryImmutables = await readFactoryImmutables(provider, factoryAddress!, poolType);
    console.log(`POOL_MANAGER: ${factoryImmutables.poolManager}`);
    if (factoryImmutables.fluidDexReservesResolver) {
      console.log(`FLUID_DEX_RESOLVER: ${factoryImmutables.fluidDexReservesResolver}`);
    }
    if (factoryImmutables.fluidLiquidity) {
      console.log(`FLUID_LIQUIDITY: ${factoryImmutables.fluidLiquidity}`);
    }
    if (factoryImmutables.fluidDexLite) {
      console.log(`FLUID_DEX_LITE: ${factoryImmutables.fluidDexLite}`);
    }
    if (factoryImmutables.fluidDexLiteResolver) {
      console.log(`FLUID_DEX_LITE_RESOLVER: ${factoryImmutables.fluidDexLiteResolver}`);
    }
    console.log("");

    const protocolId = getProtocolId(poolType);
    for (let j = 0; j < pools.length; j++) {
      const i = startAt - 1 + j;
      const poolConfig = pools[j];
      console.log(`\n--- Processing Pool ${i + 1}/${allPools.length} ---`);

      try {
        // Encode constructor arguments
        const constructorArgs = encodeConstructorArgs(poolConfig, poolType, factoryImmutables);

        // Mine salt using factory address as deployer
        const salt = await mineSalt(constructorArgs, protocolId, factoryAddress!, false, jobs);

        // Create pool via factory
        const result = await createPool(signer, factoryAddress!, poolConfig, poolType, salt);

        if (registryDir && result.hookAddress && result.hookAddress.length > 0) {
          const poolKeys = buildPoolKeys(poolConfig, poolType, result.hookAddress);
          if (poolKeys.length > 0) {
            appendToRegistryFile(registryDir, poolType, {
              poolKeys,
              metadata: {
                externalPool: getExternalPool(poolConfig, poolType),
                hookAddress: result.hookAddress,
                txHash: result.txHash,
                blockNumber: result.blockNumber,
              },
            });
          }
        }
        console.log(`✓ Successfully created pool ${i + 1}`);
      } catch (error) {
        console.error(`✗ Failed to create pool ${i + 1}:`);
        if (error instanceof Error) {
          console.error(error.message);
          const execErr = error as { stdout?: string; stderr?: string };
          if (execErr.stdout) {
            console.error("\n--- Forge stdout ---\n", execErr.stdout);
          }
          if (execErr.stderr) {
            console.error("\n--- Forge stderr ---\n", execErr.stderr);
          }
        }
        // Continue with next pool
        continue;
      }
    }
  }

  console.log("\n=== Done ===");
}

// Run main function
main().catch((error) => {
  console.error("Fatal error:", error);
  process.exit(1);
});

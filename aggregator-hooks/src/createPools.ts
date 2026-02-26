#!/usr/bin/env node

import "dotenv/config";
import { ethers } from "ethers";
import { readFileSync, writeFileSync, existsSync, mkdirSync } from "fs";
import { execSync, spawn } from "child_process";
import { join, dirname } from "path";
import { fileURLToPath } from "url";

import { getEnvForChain, mustEnvForChain, toInt } from "./cli.js";
import {
  CREATION_MODULES,
  POOL_TYPES,
  type Address,
  type PoolConfig,
  type PoolDeployedEntry,
  type FactoryImmutables,
} from "../creation-modules/index.js";

const __dirname = dirname(fileURLToPath(import.meta.url));
const projectRoot = join(__dirname, "..", "..");

// Foundry's default CREATE2 deployer
const CREATE2_DEPLOYER = "0x4e59b44847b379578588920cA78FbF26c0B4956C";

interface ParsedArgs {
  jsonFile: string;
  factoryAddress: Address | null;
  selfDeploy: boolean;
  rpcUrl: string;
  chainId: number | null;
  registryDir: string;
  dryRun: boolean;
  verbose: boolean;
  startAt: number;
  jobs: number;
  priorityGasPrice: string | null;
}

function isPoolType(s: unknown): s is string {
  return typeof s === "string" && POOL_TYPES.includes(s);
}

function parseArgs(): ParsedArgs {
  const args = process.argv.slice(2);
  const selfDeployIndex = args.indexOf("--self-deploy");
  const selfDeploy = selfDeployIndex !== -1;

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
    "--priority-gas-price",
  ];
  const positionalArgs: string[] = [];
  for (let i = 0; i < args.length; i++) {
    const a = args[i];
    if (flagNames.includes(a)) {
      if (
        a === "--chain-id" ||
        a === "--registry-dir" ||
        a === "--start-at" ||
        a === "--jobs" ||
        a === "-j" ||
        a === "--priority-gas-price"
      )
        i++;
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
    console.error(
      "  --priority-gas-price <price>: Max priority fee per gas for EIP1559 (e.g. 3gwei). Speeds up tx inclusion.",
    );
    console.error("");
    console.error("Environment variables:");
    console.error("  RPC_URL_<chainId>: RPC endpoint (required when --chain-id set)");
    console.error("  PRIVATE_KEY: Private key for signing transactions (required)");
    process.exit(1);
  }

  const jsonFile = positionalArgs[0];
  const factoryAddress: Address | null = selfDeploy
    ? null
    : positionalArgs[1]
    ? (ethers.getAddress(positionalArgs[1]) as Address)
    : null;

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

  if (!process.env.PRIVATE_KEY) {
    console.error("Error: PRIVATE_KEY environment variable is required");
    process.exit(1);
  }

  const registryDirIndex = args.indexOf("--registry-dir");
  const registryDir =
    registryDirIndex !== -1 && args[registryDirIndex + 1] ? args[registryDirIndex + 1] : "created-pools";

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

  const priorityGasPriceIndex = args.indexOf("--priority-gas-price");
  const priorityGasPriceRaw =
    priorityGasPriceIndex !== -1 && args[priorityGasPriceIndex + 1] ? args[priorityGasPriceIndex + 1] : null;
  const priorityGasPrice = priorityGasPriceRaw?.trim() || null;

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
    priorityGasPrice,
  };
}

function appendToRegistryFile(registryDir: string, poolType: string, entry: PoolDeployedEntry): void {
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

function parseSqrtPriceX96(v: unknown): bigint | null {
  if (v == null) return null;
  if (typeof v === "bigint") return v;
  if (typeof v === "string") return BigInt(v);
  if (typeof v === "number") return BigInt(Math.floor(v));
  return null;
}

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

    const firstType = pools[0].poolType as string;
    for (let i = 1; i < pools.length; i++) {
      if (pools[i].poolType !== firstType) {
        throw new Error(
          `Pool ${i + 1} has poolType "${
            pools[i].poolType
          }" but all configs must have the same poolType (first is "${firstType}")`,
        );
      }
    }

    return pools.map((p: Record<string, unknown>) => ({
      ...p,
      sqrtPriceX96: parseSqrtPriceX96(p.sqrtPriceX96),
    })) as PoolConfig[];
  } catch (error) {
    if (error instanceof Error) {
      console.error(`Error loading JSON file: ${error.message}`);
    } else {
      console.error("Unknown error loading JSON file");
    }
    process.exit(1);
  }
}

/** PoolManager Initialize event for verification */
const INITIALIZE_TOPIC = "0xdd466e674ea557f56295e2d0218a125ea4b4f0f6f3307b95f85e6110838d6438";

async function verifyDeploymentOnForgeFailure(
  provider: ethers.Provider,
  poolManagerAddress: Address,
  poolConfig: PoolConfig,
  poolType: string,
  forgeOutput: string,
): Promise<{ hookAddress: Address; hookDeployed: boolean; poolsInitialized: number } | null> {
  const module = CREATION_MODULES[poolType];
  if (!module) return null;

  const hookMatch = forgeOutput.match(/Hook Address:\s*(0x[a-fA-F0-9]{40})/);
  if (!hookMatch) return null;

  const hookAddress = ethers.getAddress(hookMatch[1]) as Address;
  const code = await provider.getCode(hookAddress);
  const hookDeployed = !!code && code !== "0x" && code.length > 2;

  if (!hookDeployed) return { hookAddress, hookDeployed: false, poolsInitialized: 0 };

  const poolKeys = module.buildPoolKeys(poolConfig, hookAddress);
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
    /* ignore */
  }

  return { hookAddress, hookDeployed, poolsInitialized };
}

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

async function mineSalt(
  constructorArgs: string,
  protocolId: number,
  deployerAddress?: Address,
  verbose = false,
  jobs = 1,
): Promise<string> {
  const scriptPath = join(projectRoot, "mine_hook.sh");
  const protocolIdHex = `0x${protocolId.toString(16).toUpperCase()}`;

  console.log(`Mining salt for protocol ${protocolIdHex}...`);
  console.log(`Constructor args: ${constructorArgs.substring(0, 66)}...`);
  if (deployerAddress) console.log(`Deployer address: ${deployerAddress}`);
  if (jobs > 1) console.log(`Running ${jobs} parallel mining workers...`);

  const baseArgs = [scriptPath, constructorArgs, protocolIdHex];
  if (deployerAddress) baseArgs.push("500", deployerAddress);

  const execEnv = { ...process.env, ...(verbose && { FORGE_VERBOSE: "1" }) };

  try {
    if (jobs === 1) {
      const result = await runMineHookWorker(scriptPath, baseArgs, execEnv, projectRoot, true);
      console.log(`✓ Found salt: ${result.salt}`);
      return result.salt;
    }

    const children: ReturnType<typeof spawn>[] = [];
    const workerPromises: Promise<{ salt: string } | { failed: true; output: string }>[] = [];

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
      child.stderr!.on("data", (chunk) => {
        output += chunk.toString();
      });

      const promise = new Promise<{ salt: string } | { failed: true; output: string }>((resolve) => {
        child.on("close", (code) => {
          if (code === 0) {
            const saltMatch = output.match(/Salt \(bytes32\):\s*(0x[a-fA-F0-9]{64})/);
            if (saltMatch) resolve({ salt: saltMatch[1] });
            else resolve({ failed: true, output });
          } else {
            resolve({ failed: true, output });
          }
        });
        child.on("error", (err) => resolve({ failed: true, output: err.message }));
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

    const salt = await new Promise<string>((resolve, reject) => {
      let failedCount = 0;
      let lastFailedOutput = "";
      workerPromises.forEach((p) => {
        p.then((result) => {
          if ("salt" in result) {
            killAll();
            resolve(result.salt);
          } else {
            failedCount++;
            lastFailedOutput = result.output;
            if (failedCount === jobs) {
              const err = new Error("All mining workers failed") as Error & { stdout?: string };
              err.stdout = lastFailedOutput;
              reject(err);
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
      if (execErr.stdout) console.error("\n--- Forge/mine_hook output (from failed worker) ---\n", execErr.stdout);
      if (execErr.stderr) console.error("\n--- Forge/mine_hook stderr ---\n", execErr.stderr);
    }
    throw error;
  }
}

function selfDeployPool(
  poolConfig: PoolConfig,
  poolType: string,
  immutables: FactoryImmutables,
  salt: string,
  rpcUrl: string,
  dryRun: boolean,
  verbose = false,
  priorityGasPrice: string | null = null,
): Address | "deployed" {
  const module = CREATION_MODULES[poolType];
  if (!module) throw new Error(`Unknown pool type: ${poolType}`);

  const rawKey = (process.env.PRIVATE_KEY ?? "").trim();
  const privateKey = rawKey.startsWith("0x") ? rawKey : `0x${rawKey}`;

  const envVars: Record<string, string> = {
    PROTOCOL_ID: module.protocolId.toString(),
    SALT: salt,
    POOL_MANAGER: immutables.poolManager,
    PRIVATE_KEY: privateKey,
    ...module.buildSelfDeployEnvVars(poolConfig, immutables),
  };

  const { PRIVATE_KEY: _pk, ...publicEnvVars } = envVars;
  const envString = Object.entries(publicEnvVars)
    .map(([key, value]) => `${key}="${value}"`)
    .join(" ");

  console.log(`Self-deploying hook via SelfCreateHook.s.sol...`);
  if (dryRun) console.log("(dry run - no broadcast)");
  console.log(`Protocol: ${poolType}, Salt: ${salt.substring(0, 18)}...`);

  try {
    const broadcastFlag = dryRun ? "" : " --broadcast";
    const verboseFlag = verbose ? " -vvvv" : "";
    const priorityFeeFlag = priorityGasPrice ? ` --priority-gas-price ${priorityGasPrice}` : "";
    const command = `${envString} forge script script/SelfCreateHook.s.sol:SelfCreateHookScript --rpc-url "${rpcUrl}"${broadcastFlag}${priorityFeeFlag}${verboseFlag}`;
    const output = execSync(command, {
      encoding: "utf-8",
      cwd: projectRoot,
      env: { ...process.env, ...envVars },
    });

    if (verbose) console.log("\n--- Forge script output ---\n", output);

    const hookMatch = output.match(/Hook Address:\s*(0x[a-fA-F0-9]{40})/);
    if (hookMatch) {
      const addr = ethers.getAddress(hookMatch[1]) as Address;
      console.log(`✓ Hook deployed at: ${addr}`);
      return addr;
    }

    console.log(`✓ Self-deploy completed`);
    return "deployed";
  } catch (error) {
    console.error("Error in self-deploy:");
    if (error instanceof Error) {
      console.error(error.message);
      const execErr = error as { stdout?: string; stderr?: string };
      if (execErr.stdout) console.error("\n--- Forge stdout ---\n", execErr.stdout);
      if (execErr.stderr) console.error("\n--- Forge stderr ---\n", execErr.stderr);
    }
    throw error;
  }
}

async function createPool(
  signer: ethers.Signer,
  factoryAddress: Address,
  poolConfig: PoolConfig,
  poolType: string,
  salt: string,
): Promise<{ hookAddress: Address | ""; blockNumber: number; txHash: string }> {
  const module = CREATION_MODULES[poolType];
  if (!module) throw new Error(`Unknown pool type: ${poolType}`);

  const args = module.buildCreatePoolArgs(poolConfig, salt);
  const factory = new ethers.Contract(factoryAddress, module.factoryAbi, signer);

  console.log(`Calling createPool on factory ${factoryAddress}...`);
  console.log(`Args:`, args.map((a, i) => `${i}: ${String(a).substring(0, 66)}...`).join(", "));

  try {
    const tx = await factory.createPool(...args);
    console.log(`✓ Transaction sent: ${tx.hash}`);

    const receipt = await tx.wait();
    console.log(`✓ Transaction confirmed in block ${receipt!.blockNumber}`);

    const hookDeployedEvent = receipt!.logs.find((log: ethers.Log) => {
      try {
        const parsed = factory.interface.parseLog({ topics: log.topics as string[], data: log.data });
        return parsed?.name === "HookDeployed";
      } catch {
        return false;
      }
    });

    if (hookDeployedEvent) {
      const parsed = factory.interface.parseLog({
        topics: hookDeployedEvent.topics as string[],
        data: hookDeployedEvent.data,
      });
      const hookAddress = ethers.getAddress((parsed?.args.hook || parsed?.args[0]) as string) as Address;
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
      if ("data" in error && error.data) console.error("Error data:", error.data);
      if ("reason" in error && error.reason) console.error("Revert reason:", error.reason);
    }
    throw error;
  }
}

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
    priorityGasPrice,
  } = parseArgs();

  console.log("=== Pool Creation Script ===");
  console.log(`JSON File: ${jsonFile}`);
  console.log(`Mode: ${selfDeploy ? "Self-Deploy" : "Factory"}`);
  if (factoryAddress) console.log(`Factory Address: ${factoryAddress}`);
  console.log(`RPC URL: ${rpcUrl}`);
  if (registryDir) console.log(`Registry dir: ${registryDir}`);
  if (dryRun) console.log("DRY RUN: forge scripts will simulate without broadcasting");
  if (verbose) console.log("VERBOSE: forge scripts will run with -vvvv");
  if (startAt > 1) console.log(`Starting at pool index: ${startAt} (skipping first ${startAt - 1} pool(s))`);
  if (jobs > 1) console.log(`Salt mining: ${jobs} parallel workers`);
  if (priorityGasPrice) console.log(`Priority gas price: ${priorityGasPrice}`);
  console.log("");

  const provider = new ethers.JsonRpcProvider(rpcUrl);
  const privateKey = process.env.PRIVATE_KEY!;
  const signer = new ethers.Wallet(privateKey, provider);
  console.log(`Using signer: ${signer.address}`);
  console.log("");

  if (selfDeploy) {
    const allPools = loadJsonFile(jsonFile);
    const pools = startAt > 1 ? allPools.slice(startAt - 1) : allPools;
    if (startAt > 1 && pools.length === 0) {
      console.error(`Error: --start-at ${startAt} exceeds pool count (${allPools.length})`);
      process.exit(1);
    }
    console.log(
      `Loaded ${allPools.length} pool configuration(s)${
        startAt > 1 ? `, processing from index ${startAt} (${pools.length} remaining)` : ""
      }`,
    );
    console.log("");

    const chainId = parsedChainId ?? Number((await provider.getNetwork()).chainId);

    for (let j = 0; j < pools.length; j++) {
      const i = startAt - 1 + j;
      const poolConfig = pools[j];
      const poolType = poolConfig.poolType;
      const module = CREATION_MODULES[poolType];
      const immutables = module.getImmutablesFromEnv(chainId);

      console.log(`\n--- Processing Pool ${i + 1}/${allPools.length} (${poolType}) ---`);

      try {
        const constructorArgs = module.encodeConstructorArgs(poolConfig, immutables);
        const salt = await mineSalt(constructorArgs, module.protocolId, CREATE2_DEPLOYER, verbose, jobs);
        const hookAddress = selfDeployPool(
          poolConfig,
          poolType,
          immutables,
          salt,
          rpcUrl,
          dryRun,
          verbose,
          priorityGasPrice,
        );

        if (registryDir && hookAddress && hookAddress !== "deployed") {
          const poolKeys = module.buildPoolKeys(poolConfig, hookAddress);
          if (poolKeys.length > 0) {
            const blockNumber = Number(await provider.getBlockNumber());
            appendToRegistryFile(registryDir, poolType, {
              poolKeys,
              metadata: {
                externalPool: module.getExternalPool(poolConfig),
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
          if (execErr.stdout) console.error("\n--- Forge stdout ---\n", execErr.stdout);
          if (execErr.stderr) console.error("\n--- Forge stderr ---\n", execErr.stderr);
          const forgeOutput = [execErr.stdout, execErr.stderr].filter(Boolean).join("\n");
          if (forgeOutput) {
            const verification = await verifyDeploymentOnForgeFailure(
              provider,
              immutables.poolManager,
              poolConfig,
              poolType,
              forgeOutput,
            );
            if (verification?.hookDeployed) {
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
        continue;
      }
    }
  } else {
    const allPools = loadJsonFile(jsonFile);
    const pools = startAt > 1 ? allPools.slice(startAt - 1) : allPools;
    if (startAt > 1 && pools.length === 0) {
      console.error(`Error: --start-at ${startAt} exceeds pool count (${allPools.length})`);
      process.exit(1);
    }
    const poolType = pools[0].poolType as string;
    const module = CREATION_MODULES[poolType];

    console.log(
      `Loaded ${allPools.length} pool configuration(s) (poolType: ${poolType})${
        startAt > 1 ? `, processing from index ${startAt} (${pools.length} remaining)` : ""
      }`,
    );
    console.log("");

    console.log("Reading factory immutables...");
    const factoryImmutables = await module.readFactoryImmutables(provider, factoryAddress!);
    console.log(`POOL_MANAGER: ${factoryImmutables.poolManager}`);
    for (const [key, val] of Object.entries(factoryImmutables)) {
      if (key !== "poolManager" && val) console.log(`${key}: ${val}`);
    }
    console.log("");

    for (let j = 0; j < pools.length; j++) {
      const i = startAt - 1 + j;
      const poolConfig = pools[j];

      console.log(`\n--- Processing Pool ${i + 1}/${allPools.length} ---`);

      try {
        const constructorArgs = module.encodeConstructorArgs(poolConfig, factoryImmutables);
        const salt = await mineSalt(constructorArgs, module.protocolId, factoryAddress!, false, jobs);
        const result = await createPool(signer, factoryAddress!, poolConfig, poolType, salt);

        if (registryDir && result.hookAddress) {
          const poolKeys = module.buildPoolKeys(poolConfig, result.hookAddress);
          if (poolKeys.length > 0) {
            appendToRegistryFile(registryDir, poolType, {
              poolKeys,
              metadata: {
                externalPool: module.getExternalPool(poolConfig),
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
          if (execErr.stdout) console.error("\n--- Forge stdout ---\n", execErr.stdout);
          if (execErr.stderr) console.error("\n--- Forge stderr ---\n", execErr.stderr);
        }
        continue;
      }
    }
  }

  console.log("\n=== Done ===");
}

main().catch((error) => {
  console.error("Fatal error:", error);
  process.exit(1);
});

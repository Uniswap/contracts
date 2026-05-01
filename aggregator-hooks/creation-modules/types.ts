/**
 * Shared types and CreationModule interface for pool deployment.
 * Each protocol (stableswap, stableswapng, fluiddext1, fluiddexlite) implements this interface.
 */
import type { Provider } from "ethers";

/** Ethereum address: 0x-prefixed hex string */
export type Address = `0x${string}`;

/** PoolKey shape for registry output (matches Uniswap v4 PoolKey) */
export interface PoolKeyRecord {
  currency0: Address;
  currency1: Address;
  fee: number;
  tickSpacing: number;
  hooks: Address;
}

/** A single pool: its PoolKey paired with the computed PoolId */
export interface PoolEntry {
  poolKey: PoolKeyRecord;
  poolId: string;
}

/** Entry appended to pool-deployed registry */
export interface PoolDeployedEntry {
  pools: PoolEntry[];
  metadata: {
    externalPool: string;
    hookAddress: Address;
    txHash?: string;
    blockNumber?: number;
    [key: string]: unknown;
  };
}

/** Immutables for self-deploy (from env) or factory (from contract) */
export interface FactoryImmutables {
  poolManager: Address;
  [key: string]: string | Address;
}

/** Default sqrtPriceX96 for 1:1 (2^96) */
export const DEFAULT_SQRT_PRICE_X96 = 79228162514264337593543950336n;

/** Default hook parameters when not specified in config */
export const DEFAULT_HOOK_PARAMS = {
  fee: 0,
  tickSpacing: 60,
  sqrtPriceX96: DEFAULT_SQRT_PRICE_X96,
} as const;

export interface HookParams {
  fee: number;
  tickSpacing: number;
  sqrtPriceX96: bigint;
}

/**
 * Creation module interface. Each pool type implements this to provide
 * type-specific deployment logic.
 */
export interface CreationModule<TConfig = unknown> {
  /** Pool type identifier (e.g. "stableswap", "fluiddext1") */
  poolType: string;

  /** Protocol ID for salt mining (matches MineAggregatorHook.s.sol) */
  protocolId: number;

  /** Factory contract ABI for createPool and reading immutables */
  factoryAbi: string[];

  /** Solidity contract identifier for forge verify-contract (path:ContractName) */
  contractIdentifier: string;

  /** Resolve hook params with defaults */
  getHookParams(config: TConfig): HookParams;

  /** Build PoolKey records for registry */
  buildPoolKeys(config: TConfig, hookAddress: Address): PoolKeyRecord[];

  /** Get external pool address/identifier for metadata */
  getExternalPool(config: TConfig): string;

  /** Read immutables from env for self-deploy */
  getImmutablesFromEnv(chainId: number): FactoryImmutables;

  /** Read immutables from factory contract */
  readFactoryImmutables(provider: Provider, factoryAddress: Address): Promise<FactoryImmutables>;

  /** Encode constructor args for salt mining */
  encodeConstructorArgs(config: TConfig, immutables: FactoryImmutables): string;

  /** Build env vars for SelfCreateHook.s.sol self-deploy */
  buildSelfDeployEnvVars(config: TConfig, immutables: FactoryImmutables): Record<string, string>;

  /** Build createPool call args for factory contract */
  buildCreatePoolArgs(config: TConfig, salt: string): unknown[];
}

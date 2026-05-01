/**
 * Creation modules registry. Import this to get all supported pool types.
 */
import { stableswapModule } from "./StableSwap.js";
import { stableswapngModule } from "./StableSwapNG.js";
import { fluiddext1Module } from "./FluidDexT1.js";
import { fluiddexliteModule } from "./FluidDexLite.js";
import type { CreationModule } from "./types.js";

export type {
  Address,
  CreationModule,
  PoolKeyRecord,
  PoolEntry,
  PoolDeployedEntry,
  FactoryImmutables,
  HookParams,
} from "./types.js";
export type { StableSwapPoolConfig } from "./StableSwap.js";
export type { StableSwapNGPoolConfig } from "./StableSwapNG.js";
export type { FluidDexT1PoolConfig } from "./FluidDexT1.js";
export type { FluidDexLitePoolConfig } from "./FluidDexLite.js";

export { stableswapModule, stableswapngModule, fluiddext1Module, fluiddexliteModule };

export type PoolConfig =
  | import("./StableSwap.js").StableSwapPoolConfig
  | import("./StableSwapNG.js").StableSwapNGPoolConfig
  | import("./FluidDexT1.js").FluidDexT1PoolConfig
  | import("./FluidDexLite.js").FluidDexLitePoolConfig;

/** Registry of all creation modules by pool type */
export const CREATION_MODULES: Record<string, CreationModule> = {
  stableswap: stableswapModule,
  stableswapng: stableswapngModule,
  fluiddext1: fluiddext1Module,
  fluiddexlite: fluiddexliteModule,
};

export const POOL_TYPES = Object.keys(CREATION_MODULES) as string[];

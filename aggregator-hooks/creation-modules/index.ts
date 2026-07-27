/**
 * Creation modules registry. Import this to get all supported pool types.
 */
import { stableswapModule } from './StableSwap.js';
import { stableswapngModule } from './StableSwapNG.js';
import { fluiddext1Module } from './FluidDexT1.js';
import { fluiddexliteModule } from './FluidDexLite.js';
import { litepsmModule } from './LitePSM.js';
import { uniswapv3Module } from './UniswapV3.js';
import { uniswapv2Module } from './UniswapV2.js';
import { slipstreamModule } from './Slipstream.js';
import { pancakeswapv3Module } from './PancakeSwapV3.js';
import { sushiswapv2Module } from './SushiswapV2.js';
import { sushiswapv3Module } from './SushiswapV3.js';
import type { CreationModule } from './types.js';

export type {
  Address,
  CreationModule,
  PoolKeyRecord,
  PoolEntry,
  PoolDeployedEntry,
  FactoryImmutables,
  HookParams,
} from './types.js';
export type { StableSwapPoolConfig } from './StableSwap.js';
export type { StableSwapNGPoolConfig } from './StableSwapNG.js';
export type { FluidDexT1PoolConfig } from './FluidDexT1.js';
export type { FluidDexLitePoolConfig } from './FluidDexLite.js';
export type { LitePSMPoolConfig } from './LitePSM.js';
export type { UniswapV3PoolConfig } from './UniswapV3.js';
export type { UniswapV2PoolConfig } from './UniswapV2.js';
export type { SlipstreamPoolConfig } from './Slipstream.js';
export type { PancakeSwapV3PoolConfig } from './PancakeSwapV3.js';
export type { SushiswapV2PoolConfig } from './SushiswapV2.js';
export type { SushiswapV3PoolConfig } from './SushiswapV3.js';

export {
  stableswapModule,
  stableswapngModule,
  fluiddext1Module,
  fluiddexliteModule,
  litepsmModule,
};
export {
  uniswapv3Module,
  uniswapv2Module,
  slipstreamModule,
  pancakeswapv3Module,
  sushiswapv2Module,
  sushiswapv3Module,
};

export type PoolConfig =
  | import('./StableSwap.js').StableSwapPoolConfig
  | import('./StableSwapNG.js').StableSwapNGPoolConfig
  | import('./FluidDexT1.js').FluidDexT1PoolConfig
  | import('./FluidDexLite.js').FluidDexLitePoolConfig
  | import('./LitePSM.js').LitePSMPoolConfig
  | import('./UniswapV3.js').UniswapV3PoolConfig
  | import('./UniswapV2.js').UniswapV2PoolConfig
  | import('./Slipstream.js').SlipstreamPoolConfig
  | import('./PancakeSwapV3.js').PancakeSwapV3PoolConfig
  | import('./SushiswapV2.js').SushiswapV2PoolConfig
  | import('./SushiswapV3.js').SushiswapV3PoolConfig;

/** Registry of all creation modules by pool type */
export const CREATION_MODULES: Record<string, CreationModule> = {
  stableswap: stableswapModule,
  stableswapng: stableswapngModule,
  fluiddext1: fluiddext1Module,
  fluiddexlite: fluiddexliteModule,
  litepsm: litepsmModule,
  uniswapv3: uniswapv3Module,
  uniswapv2: uniswapv2Module,
  slipstream: slipstreamModule,
  pancakeswapv3: pancakeswapv3Module,
  sushiswapv2: sushiswapv2Module,
  sushiswapv3: sushiswapv3Module,
};

export const POOL_TYPES = Object.keys(CREATION_MODULES) as string[];

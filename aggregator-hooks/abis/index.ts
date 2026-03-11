/**
 * Load ABIs via createRequire (avoids import attributes for Prettier compatibility).
 */
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);

export const STABLESWAP_FACTORY_ABI: string[] = [...require("./StableswapFactory.json")];
export const STABLESWAPNG_FACTORY_ABI: string[] = [...require("./StableSwapNGFactory.json")];
export const FLUIDDEXT1_FACTORY_ABI: string[] = [...require("./FluidDexT1Factory.json")];
export const FLUIDDEXLITE_FACTORY_ABI: string[] = [...require("./FluidDexLiteFactory.json")];
export const FLUIDDEXT1_HISTORICAL_FACTORY_ABI = require("./FluidDexT1HistoricalFactory.json") as readonly string[];
export const FLUIDDEXT1_RESOLVER_ABI = require("./FluidDexT1Resolver.json") as readonly string[];
export const STABLESWAPNG_HISTORICAL_FACTORY_ABI = require("./StableSwapNGHistoricalFactory.json") as readonly string[];
export const FLUIDDEXLITE_RESOLVER_ABI = require("./FluidDexLiteResolver.json") as readonly string[];

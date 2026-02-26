/**
 * FluidDex Lite aggregator hook deployment module.
 */
import { ethers } from "ethers";
import { getEnvForChain, mustEnvForChain } from "../src/cli.js";
import { DEFAULT_SQRT_PRICE_X96, type Address, type CreationModule, type FactoryImmutables } from "./types.js";

export interface FluidDexLitePoolConfig {
  poolType: "fluiddexlite";
  dexSalt: string;
  currency0: Address;
  currency1: Address;
  fee: number | null;
  tickSpacing: number | null;
  sqrtPriceX96: bigint | null;
}

const FACTORY_ABI = [
  "function POOL_MANAGER() external view returns (address)",
  "function FLUID_DEX_LITE() external view returns (address)",
  "function FLUID_DEX_LITE_RESOLVER() external view returns (address)",
  "function createPool(bytes32 salt, bytes32 dexSalt, address currency0, address currency1, uint24 fee, int24 tickSpacing, uint160 sqrtPriceX96) external returns (address hook)",
];

const PROTOCOL_ID = 0xf3;

const orderPair = (a: Address, b: Address): [Address, Address] => (a.toLowerCase() < b.toLowerCase() ? [a, b] : [b, a]);

export const fluiddexliteModule: CreationModule<FluidDexLitePoolConfig> = {
  poolType: "fluiddexlite",
  protocolId: PROTOCOL_ID,
  factoryAbi: FACTORY_ABI,

  getHookParams(config) {
    return {
      fee: config.fee ?? 0,
      tickSpacing: config.tickSpacing ?? 60,
      sqrtPriceX96: config.sqrtPriceX96 ?? DEFAULT_SQRT_PRICE_X96,
    };
  },

  buildPoolKeys(config, hookAddress) {
    const params = this.getHookParams(config);
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
  },

  getExternalPool(config) {
    return config.dexSalt;
  },

  getImmutablesFromEnv(chainId: number): FactoryImmutables {
    const dexLite = getEnvForChain("FLUID_DEX_LITE", chainId) ?? getEnvForChain("DEX_LITE_ADDRESS", chainId);
    const dexLiteResolver =
      getEnvForChain("FLUID_DEX_LITE_RESOLVER", chainId) ?? getEnvForChain("DEX_LITE_RESOLVER_ADDRESS", chainId);
    if (!dexLite)
      throw new Error(`FLUID_DEX_LITE_${chainId} or DEX_LITE_ADDRESS_${chainId} required for fluiddexlite self-deploy`);
    if (!dexLiteResolver)
      throw new Error(
        `FLUID_DEX_LITE_RESOLVER_${chainId} or DEX_LITE_RESOLVER_ADDRESS_${chainId} required for fluiddexlite self-deploy`,
      );
    return {
      poolManager: mustEnvForChain("POOL_MANAGER", chainId) as Address,
      fluidDexLite: dexLite as Address,
      fluidDexLiteResolver: dexLiteResolver as Address,
    };
  },

  async readFactoryImmutables(provider, factoryAddress) {
    const factory = new ethers.Contract(factoryAddress, FACTORY_ABI, provider);
    const [poolManager, fluidDexLite, fluidDexLiteResolver] = await Promise.all([
      factory.POOL_MANAGER(),
      factory.FLUID_DEX_LITE(),
      factory.FLUID_DEX_LITE_RESOLVER(),
    ]);
    return {
      poolManager: poolManager as Address,
      fluidDexLite: fluidDexLite as Address,
      fluidDexLiteResolver: fluidDexLiteResolver as Address,
    };
  },

  encodeConstructorArgs(config, immutables) {
    const encoded = ethers.AbiCoder.defaultAbiCoder().encode(
      ["address", "address", "address", "bytes32"],
      [immutables.poolManager, immutables.fluidDexLite, immutables.fluidDexLiteResolver, config.dexSalt],
    );
    return encoded.startsWith("0x") ? encoded : `0x${encoded}`;
  },

  buildSelfDeployEnvVars(config, immutables) {
    const params = this.getHookParams(config);
    return {
      FLUID_DEX_LITE: immutables.fluidDexLite!,
      FLUID_DEX_LITE_RESOLVER: immutables.fluidDexLiteResolver!,
      DEX_SALT: config.dexSalt,
      TOKENS: [config.currency0, config.currency1].join(","),
      FEE: params.fee.toString(),
      TICK_SPACING: params.tickSpacing.toString(),
      SQRT_PRICE_X96: params.sqrtPriceX96.toString(),
    };
  },

  buildCreatePoolArgs(config, salt) {
    const params = this.getHookParams(config);
    return [
      salt,
      config.dexSalt,
      config.currency0,
      config.currency1,
      params.fee,
      params.tickSpacing,
      params.sqrtPriceX96,
    ];
  },
};

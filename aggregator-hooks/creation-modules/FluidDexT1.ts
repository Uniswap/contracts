/**
 * FluidDex T1 aggregator hook deployment module.
 */
import { ethers } from "ethers";
import { getEnvForChain, mustEnvForChain } from "../src/cli.js";
import { FLUIDDEXT1_FACTORY_ABI } from "../abis/index.js";
import { DEFAULT_SQRT_PRICE_X96, type Address, type CreationModule, type FactoryImmutables } from "./types.js";

export interface FluidDexT1PoolConfig {
  poolType: "fluiddext1";
  fluidPool: Address;
  currency0: Address;
  currency1: Address;
  fee: number | null;
  tickSpacing: number | null;
  sqrtPriceX96: bigint | null;
}

const PROTOCOL_ID = 0xf1;

const orderPair = (a: Address, b: Address): [Address, Address] => (a.toLowerCase() < b.toLowerCase() ? [a, b] : [b, a]);

export const fluiddext1Module: CreationModule<FluidDexT1PoolConfig> = {
  poolType: "fluiddext1",
  protocolId: PROTOCOL_ID,
  factoryAbi: FLUIDDEXT1_FACTORY_ABI,
  contractIdentifier:
    "lib/v4-hooks-public/src/aggregator-hooks/implementations/FluidDexT1/FluidDexT1Aggregator.sol:FluidDexT1Aggregator",

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
    return config.fluidPool;
  },

  getImmutablesFromEnv(chainId: number): FactoryImmutables {
    const reservesResolver =
      getEnvForChain("FLUID_DEX_T1_RESERVES_RESOLVER", chainId) ??
      getEnvForChain("FLUID_DEX_RESERVES_RESOLVER", chainId);
    const resolver = getEnvForChain("FLUID_DEX_T1_RESOLVER", chainId) ?? getEnvForChain("FLUID_DEX_RESOLVER", chainId);
    if (!reservesResolver)
      throw new Error(
        `Missing env: FLUID_DEX_T1_RESERVES_RESOLVER_${chainId} or FLUID_DEX_RESERVES_RESOLVER_${chainId}`,
      );
    if (!resolver) throw new Error(`Missing env: FLUID_DEX_T1_RESOLVER_${chainId} or FLUID_DEX_RESOLVER_${chainId}`);
    return {
      poolManager: mustEnvForChain("POOL_MANAGER", chainId) as Address,
      fluidDexReservesResolver: reservesResolver as Address,
      fluidDexResolver: resolver as Address,
      fluidLiquidity: mustEnvForChain("FLUID_LIQUIDITY", chainId) as Address,
    };
  },

  async readFactoryImmutables(provider, factoryAddress) {
    const factory = new ethers.Contract(factoryAddress, FLUIDDEXT1_FACTORY_ABI, provider);
    const [poolManager, fluidDexReservesResolver, fluidDexResolver, fluidLiquidity] = await Promise.all([
      factory.POOL_MANAGER(),
      factory.fluidDexReservesResolver(),
      factory.fluidDexResolver(),
      factory.FLUID_LIQUIDITY(),
    ]);
    return {
      poolManager: poolManager as Address,
      fluidDexReservesResolver: fluidDexReservesResolver as Address,
      fluidDexResolver: fluidDexResolver as Address,
      fluidLiquidity: fluidLiquidity as Address,
    };
  },

  encodeConstructorArgs(config, immutables) {
    const encoded = ethers.AbiCoder.defaultAbiCoder().encode(
      ["address", "address", "address", "address", "address"],
      [
        immutables.poolManager,
        config.fluidPool,
        immutables.fluidDexReservesResolver,
        immutables.fluidDexResolver,
        immutables.fluidLiquidity,
      ],
    );
    return encoded.startsWith("0x") ? encoded : `0x${encoded}`;
  },

  buildSelfDeployEnvVars(config, immutables) {
    const params = this.getHookParams(config);
    return {
      FLUID_POOL: config.fluidPool,
      FLUID_DEX_T1_RESERVES_RESOLVER: immutables.fluidDexReservesResolver!,
      FLUID_DEX_T1_RESOLVER: immutables.fluidDexResolver!,
      FLUID_LIQUIDITY: immutables.fluidLiquidity!,
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
      config.fluidPool,
      config.currency0,
      config.currency1,
      params.fee,
      params.tickSpacing,
      params.sqrtPriceX96,
    ];
  },
};

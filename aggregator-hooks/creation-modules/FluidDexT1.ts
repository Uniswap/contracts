/**
 * FluidDex T1 aggregator hook deployment module.
 */
import { ethers } from "ethers";
import { mustEnvForChain } from "../src/cli.js";
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

const FACTORY_ABI = [
  "function POOL_MANAGER() external view returns (address)",
  "function fluidDexReservesResolver() external view returns (address)",
  "function FLUID_LIQUIDITY() external view returns (address)",
  "function createPool(bytes32 salt, address fluidPool, address currency0, address currency1, uint24 fee, int24 tickSpacing, uint160 sqrtPriceX96) external returns (address hook)",
];

const PROTOCOL_ID = 0xf1;

const orderPair = (a: Address, b: Address): [Address, Address] => (a.toLowerCase() < b.toLowerCase() ? [a, b] : [b, a]);

export const fluiddext1Module: CreationModule<FluidDexT1PoolConfig> = {
  poolType: "fluiddext1",
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
    return config.fluidPool;
  },

  getImmutablesFromEnv(chainId: number): FactoryImmutables {
    return {
      poolManager: mustEnvForChain("POOL_MANAGER", chainId) as Address,
      fluidDexReservesResolver: mustEnvForChain("FLUID_DEX_RESOLVER", chainId) as Address,
      fluidLiquidity: mustEnvForChain("FLUID_LIQUIDITY", chainId) as Address,
    };
  },

  async readFactoryImmutables(provider, factoryAddress) {
    const factory = new ethers.Contract(factoryAddress, FACTORY_ABI, provider);
    const [poolManager, fluidDexReservesResolver, fluidLiquidity] = await Promise.all([
      factory.POOL_MANAGER(),
      factory.fluidDexReservesResolver(),
      factory.FLUID_LIQUIDITY(),
    ]);
    return {
      poolManager: poolManager as Address,
      fluidDexReservesResolver: fluidDexReservesResolver as Address,
      fluidLiquidity: fluidLiquidity as Address,
    };
  },

  encodeConstructorArgs(config, immutables) {
    const encoded = ethers.AbiCoder.defaultAbiCoder().encode(
      ["address", "address", "address", "address"],
      [immutables.poolManager, config.fluidPool, immutables.fluidDexReservesResolver, immutables.fluidLiquidity],
    );
    return encoded.startsWith("0x") ? encoded : `0x${encoded}`;
  },

  buildSelfDeployEnvVars(config, immutables) {
    const params = this.getHookParams(config);
    return {
      FLUID_POOL: config.fluidPool,
      FLUID_DEX_RESOLVER: immutables.fluidDexReservesResolver!,
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

/**
 * PancakeSwap V3 singleton aggregator hook deployment module.
 *
 * One PancakeSwapV3Aggregator is deployed per chain. Identical to
 * UniswapV3Aggregator in routing logic (fee-tier factory lookup) but
 * implements the PancakeSwap V3 swap callback ABI instead of Uniswap V3.
 */
import { ethers } from "ethers";
import { mustEnvForChain } from "../src/cli.js";
import { DEFAULT_SQRT_PRICE_X96, type Address, type CreationModule, type FactoryImmutables, type PoolKeyRecord } from "./types.js";

export interface PancakeSwapV3PoolConfig {
  poolType: "pancakeswapv3";
  /** The existing PancakeSwap V3 pool address being wrapped */
  v3Pool: Address;
  currency0: Address;
  currency1: Address;
  /** PancakeSwap V3 fee tier (e.g. 100, 500, 2500, 10000) */
  fee: number;
  tickSpacing?: number | null;
  sqrtPriceX96?: bigint | null;
}

const PROTOCOL_ID = 0x93;

const AGGREGATOR_ABI = [
  "function poolManager() view returns (address)",
  "function factory() view returns (address)",
];

const orderPair = (a: Address, b: Address): [Address, Address] => (a.toLowerCase() < b.toLowerCase() ? [a, b] : [b, a]);

export const pancakeswapv3Module: CreationModule<PancakeSwapV3PoolConfig> = {
  poolType: "pancakeswapv3",
  protocolId: PROTOCOL_ID,
  factoryAbi: [],
  contractIdentifier:
    "lib/v4-hooks-public/src/aggregator-hooks/PancakeSwapV3/PancakeSwapV3Aggregator.sol:PancakeSwapV3Aggregator",
  isSingleton: true,
  aggregatorEnvKey: "PANCAKESWAP_V3_AGGREGATOR",

  getHookParams(config) {
    return {
      fee: config.fee,
      tickSpacing: config.tickSpacing ?? 60,
      sqrtPriceX96: config.sqrtPriceX96 ?? DEFAULT_SQRT_PRICE_X96,
    };
  },

  buildPoolKeys(config, hookAddress) {
    const params = this.getHookParams(config);
    const [c0, c1] = orderPair(config.currency0, config.currency1);
    return [{ currency0: c0, currency1: c1, fee: params.fee, tickSpacing: params.tickSpacing, hooks: hookAddress }];
  },

  getExternalPool(config) {
    return config.v3Pool;
  },

  getImmutablesFromEnv(chainId) {
    return {
      poolManager: mustEnvForChain("POOL_MANAGER", chainId) as Address,
      externalFactory: mustEnvForChain("PANCAKESWAP_V3_FACTORY", chainId) as Address,
    };
  },

  async readFactoryImmutables(provider, aggregatorAddress) {
    const aggregator = new ethers.Contract(aggregatorAddress, AGGREGATOR_ABI, provider);
    const [poolManager, externalFactory] = await Promise.all([aggregator.poolManager(), aggregator.factory()]);
    return { poolManager: poolManager as Address, externalFactory: externalFactory as Address };
  },

  encodeConstructorArgs(_config, immutables) {
    const encoded = ethers.AbiCoder.defaultAbiCoder().encode(
      ["address", "address", "string"],
      [immutables.poolManager, immutables.externalFactory, "PancakeSwapV3Aggregator v1.0"],
    );
    return encoded.startsWith("0x") ? encoded : `0x${encoded}`;
  },

  buildSelfDeployEnvVars(_config, immutables) {
    return {
      EXTERNAL_FACTORY: immutables.externalFactory!,
      HOOK_VERSION: "PancakeSwapV3Aggregator v1.0",
    };
  },

  buildCreatePoolArgs(_config, _salt) {
    throw new Error("PancakeSwapV3 uses singleton self-deploy mode; factory mode (createPool) is not supported.");
  },

  buildInitializeArgs(config, hookAddress): [PoolKeyRecord, bigint] {
    const [poolKey] = this.buildPoolKeys(config, hookAddress);
    const sqrtPriceX96 = config.sqrtPriceX96 ?? DEFAULT_SQRT_PRICE_X96;
    return [poolKey, sqrtPriceX96];
  },
};

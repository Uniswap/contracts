/**
 * UniswapV3 singleton aggregator hook deployment module.
 *
 * One UniswapV3Aggregator is deployed per chain. Each pool config entry
 * registers a new V4 pool backed by an existing Uniswap V3 pool (resolved
 * by fee tier via the V3 factory).
 */
import { ethers } from "ethers";
import { mustEnvForChain } from "../src/cli.js";
import { DEFAULT_SQRT_PRICE_X96, type Address, type CreationModule, type FactoryImmutables, type PoolKeyRecord } from "./types.js";

export interface UniswapV3PoolConfig {
  poolType: "uniswapv3";
  /** The existing Uniswap V3 pool address being wrapped */
  v3Pool: Address;
  currency0: Address;
  currency1: Address;
  /** V3 fee tier (e.g. 500, 3000, 10000) — used for both V3 pool lookup and V4 PoolKey */
  fee: number;
  tickSpacing?: number | null;
  sqrtPriceX96?: bigint | null;
}

const PROTOCOL_ID = 0x03;

const AGGREGATOR_ABI = [
  "function poolManager() view returns (address)",
  "function factory() view returns (address)",
];

const orderPair = (a: Address, b: Address): [Address, Address] => (a.toLowerCase() < b.toLowerCase() ? [a, b] : [b, a]);

export const uniswapv3Module: CreationModule<UniswapV3PoolConfig> = {
  poolType: "uniswapv3",
  protocolId: PROTOCOL_ID,
  factoryAbi: [],
  contractIdentifier:
    "lib/v4-hooks-public/src/aggregator-hooks/implementations/UniswapV3/UniswapV3Aggregator.sol:UniswapV3Aggregator",
  isSingleton: true,
  aggregatorEnvKey: "UNISWAP_V3_AGGREGATOR",

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
      externalFactory: mustEnvForChain("UNISWAP_V3_FACTORY", chainId) as Address,
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
      [immutables.poolManager, immutables.externalFactory, "UniswapV3Aggregator v1.0"],
    );
    return encoded.startsWith("0x") ? encoded : `0x${encoded}`;
  },

  buildSelfDeployEnvVars(_config, immutables) {
    return {
      EXTERNAL_FACTORY: immutables.externalFactory!,
      HOOK_VERSION: "UniswapV3Aggregator v1.0",
    };
  },

  buildCreatePoolArgs(_config, _salt) {
    throw new Error("UniswapV3 uses singleton self-deploy mode; factory mode (createPool) is not supported.");
  },

  buildInitializeArgs(config, hookAddress): [PoolKeyRecord, bigint] {
    const [poolKey] = this.buildPoolKeys(config, hookAddress);
    const sqrtPriceX96 = config.sqrtPriceX96 ?? DEFAULT_SQRT_PRICE_X96;
    return [poolKey, sqrtPriceX96];
  },
};

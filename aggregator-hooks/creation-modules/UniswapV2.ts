/**
 * UniswapV2 singleton aggregator hook deployment module.
 *
 * One UniswapV2Aggregator is deployed per chain. Each pool config entry
 * registers a new V4 pool backed by an existing Uniswap V2 pair (resolved
 * by currency pair via the V2 factory).  Fee and tickSpacing on the V4
 * PoolKey do not affect routing — the pair is keyed by currency pair only.
 */
import { ethers } from "ethers";
import { mustEnvForChain } from "../src/cli.js";
import { DEFAULT_SQRT_PRICE_X96, type Address, type CreationModule, type FactoryImmutables, type PoolKeyRecord } from "./types.js";

export interface UniswapV2PoolConfig {
  poolType: "uniswapv2";
  /** The existing Uniswap V2 pair address being wrapped */
  v2Pair: Address;
  currency0: Address;
  currency1: Address;
  /** V4 PoolKey tickSpacing (fee is always 0 for V2 pools) */
  tickSpacing?: number | null;
  sqrtPriceX96?: bigint | null;
}

const PROTOCOL_ID = 0x02;

const AGGREGATOR_ABI = [
  "function poolManager() view returns (address)",
  "function factory() view returns (address)",
];

const orderPair = (a: Address, b: Address): [Address, Address] => (a.toLowerCase() < b.toLowerCase() ? [a, b] : [b, a]);

export const uniswapv2Module: CreationModule<UniswapV2PoolConfig> = {
  poolType: "uniswapv2",
  protocolId: PROTOCOL_ID,
  factoryAbi: [],
  contractIdentifier:
    "lib/v4-hooks-public/src/aggregator-hooks/implementations/UniswapV2/UniswapV2Aggregator.sol:UniswapV2Aggregator",
  isSingleton: true,
  aggregatorEnvKey: "UNISWAP_V2_AGGREGATOR",

  getHookParams(config) {
    return {
      fee: 0,
      tickSpacing: config.tickSpacing ?? 1,
      sqrtPriceX96: config.sqrtPriceX96 ?? DEFAULT_SQRT_PRICE_X96,
    };
  },

  buildPoolKeys(config, hookAddress) {
    const params = this.getHookParams(config);
    const [c0, c1] = orderPair(config.currency0, config.currency1);
    return [{ currency0: c0, currency1: c1, fee: params.fee, tickSpacing: params.tickSpacing, hooks: hookAddress }];
  },

  getExternalPool(config) {
    return config.v2Pair;
  },

  getImmutablesFromEnv(chainId) {
    return {
      poolManager: mustEnvForChain("POOL_MANAGER", chainId) as Address,
      externalFactory: mustEnvForChain("UNISWAP_V2_FACTORY", chainId) as Address,
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
      [immutables.poolManager, immutables.externalFactory, "UniswapV2Aggregator v1.0"],
    );
    return encoded.startsWith("0x") ? encoded : `0x${encoded}`;
  },

  buildSelfDeployEnvVars(_config, immutables) {
    return {
      EXTERNAL_FACTORY: immutables.externalFactory!,
      HOOK_VERSION: "UniswapV2Aggregator v1.0",
    };
  },

  buildCreatePoolArgs(_config, _salt) {
    throw new Error("UniswapV2 uses singleton self-deploy mode; factory mode (createPool) is not supported.");
  },

  buildInitializeArgs(config, hookAddress): [PoolKeyRecord, bigint] {
    const [poolKey] = this.buildPoolKeys(config, hookAddress);
    const sqrtPriceX96 = config.sqrtPriceX96 ?? DEFAULT_SQRT_PRICE_X96;
    return [poolKey, sqrtPriceX96];
  },
};

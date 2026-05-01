/**
 * Slipstream singleton aggregator hook deployment module.
 *
 * One SlipstreamAggregator is deployed per chain. Each pool config entry
 * registers a new V4 pool backed by an existing Slipstream CL pool (resolved
 * by tickSpacing via the Slipstream factory, rather than fee tier as in V3).
 */
import { ethers } from "ethers";
import { mustEnvForChain } from "../src/cli.js";
import { DEFAULT_SQRT_PRICE_X96, type Address, type CreationModule, type FactoryImmutables, type PoolKeyRecord } from "./types.js";

export interface SlipstreamPoolConfig {
  poolType: "slipstream";
  /** The existing Slipstream pool address being wrapped */
  slipstreamPool: Address;
  currency0: Address;
  currency1: Address;
  /** Slipstream tickSpacing — used for both pool lookup and V4 PoolKey (fee is always 0) */
  tickSpacing: number;
  sqrtPriceX96?: bigint | null;
}

const PROTOCOL_ID = 0xA1;

const AGGREGATOR_ABI = [
  "function poolManager() view returns (address)",
  "function factory() view returns (address)",
];

const orderPair = (a: Address, b: Address): [Address, Address] => (a.toLowerCase() < b.toLowerCase() ? [a, b] : [b, a]);

export const slipstreamModule: CreationModule<SlipstreamPoolConfig> = {
  poolType: "slipstream",
  protocolId: PROTOCOL_ID,
  factoryAbi: [],
  contractIdentifier:
    "lib/v4-hooks-public/src/aggregator-hooks/implementations/Slipstream/SlipstreamAggregator.sol:SlipstreamAggregator",
  isSingleton: true,
  aggregatorEnvKey: "SLIPSTREAM_AGGREGATOR",

  getHookParams(config) {
    return {
      fee: 0,
      tickSpacing: config.tickSpacing,
      sqrtPriceX96: config.sqrtPriceX96 ?? DEFAULT_SQRT_PRICE_X96,
    };
  },

  buildPoolKeys(config, hookAddress) {
    const params = this.getHookParams(config);
    const [c0, c1] = orderPair(config.currency0, config.currency1);
    return [{ currency0: c0, currency1: c1, fee: params.fee, tickSpacing: params.tickSpacing, hooks: hookAddress }];
  },

  getExternalPool(config) {
    return config.slipstreamPool;
  },

  getImmutablesFromEnv(chainId) {
    return {
      poolManager: mustEnvForChain("POOL_MANAGER", chainId) as Address,
      externalFactory: mustEnvForChain("SLIPSTREAM_FACTORY", chainId) as Address,
    };
  },

  async readFactoryImmutables(provider, aggregatorAddress) {
    const aggregator = new ethers.Contract(aggregatorAddress, AGGREGATOR_ABI, provider);
    const [poolManager, externalFactory] = await Promise.all([aggregator.poolManager(), aggregator.factory()]);
    return { poolManager: poolManager as Address, externalFactory: externalFactory as Address };
  },

  encodeConstructorArgs(_config, immutables) {
    // SlipstreamAggregator constructor: (IPoolManager manager, address slipstreamFactory)
    // hookVersion is hardcoded in the contract; not a constructor arg.
    const encoded = ethers.AbiCoder.defaultAbiCoder().encode(
      ["address", "address"],
      [immutables.poolManager, immutables.externalFactory],
    );
    return encoded.startsWith("0x") ? encoded : `0x${encoded}`;
  },

  buildSelfDeployEnvVars(_config, immutables) {
    return {
      EXTERNAL_FACTORY: immutables.externalFactory!,
    };
  },

  buildCreatePoolArgs(_config, _salt) {
    throw new Error("Slipstream uses singleton self-deploy mode; factory mode (createPool) is not supported.");
  },

  buildInitializeArgs(config, hookAddress): [PoolKeyRecord, bigint] {
    const [poolKey] = this.buildPoolKeys(config, hookAddress);
    const sqrtPriceX96 = config.sqrtPriceX96 ?? DEFAULT_SQRT_PRICE_X96;
    return [poolKey, sqrtPriceX96];
  },
};

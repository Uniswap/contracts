/**
 * StableSwap (Curve) aggregator hook deployment module.
 */
import { ethers } from "ethers";
import { mustEnvForChain } from "../src/cli.js";
import {
  DEFAULT_SQRT_PRICE_X96,
  type Address,
  type CreationModule,
  type FactoryImmutables,
  type PoolKeyRecord,
} from "./types.js";

export interface StableSwapPoolConfig {
  poolType: "stableswap";
  curvePool: Address;
  tokens: Address[];
  fee: number | null;
  tickSpacing: number | null;
  sqrtPriceX96: bigint | null;
}

const FACTORY_ABI = [
  "function POOL_MANAGER() external view returns (address)",
  "function createPool(bytes32 salt, address curvePool, address[] calldata tokens, uint24 fee, int24 tickSpacing, uint160 sqrtPriceX96) external returns (address hook)",
];

const PROTOCOL_ID = 0xc1;

const orderPair = (a: Address, b: Address): [Address, Address] => (a.toLowerCase() < b.toLowerCase() ? [a, b] : [b, a]);

export const stableswapModule: CreationModule<StableSwapPoolConfig> = {
  poolType: "stableswap",
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
    const tokens = config.tokens;
    const keys: PoolKeyRecord[] = [];
    for (let i = 0; i < tokens.length; i++) {
      for (let j = i + 1; j < tokens.length; j++) {
        const [c0, c1] = orderPair(tokens[i], tokens[j]);
        keys.push({
          currency0: c0,
          currency1: c1,
          fee: params.fee,
          tickSpacing: params.tickSpacing,
          hooks: hookAddress,
        });
      }
    }
    return keys;
  },

  getExternalPool(config) {
    return config.curvePool;
  },

  getImmutablesFromEnv(chainId: number): FactoryImmutables {
    return {
      poolManager: mustEnvForChain("POOL_MANAGER", chainId) as Address,
    };
  },

  async readFactoryImmutables(provider, factoryAddress) {
    const factory = new ethers.Contract(factoryAddress, FACTORY_ABI, provider);
    const poolManager = await factory.POOL_MANAGER();
    return { poolManager: poolManager as Address };
  },

  encodeConstructorArgs(config, immutables) {
    const encoded = ethers.AbiCoder.defaultAbiCoder().encode(
      ["address", "address"],
      [immutables.poolManager, config.curvePool],
    );
    return encoded.startsWith("0x") ? encoded : `0x${encoded}`;
  },

  buildSelfDeployEnvVars(config, immutables) {
    const params = this.getHookParams(config);
    return {
      CURVE_POOL: config.curvePool,
      TOKENS: config.tokens.join(","),
      FEE: params.fee.toString(),
      TICK_SPACING: params.tickSpacing.toString(),
      SQRT_PRICE_X96: params.sqrtPriceX96.toString(),
    };
  },

  buildCreatePoolArgs(config, salt) {
    const params = this.getHookParams(config);
    return [salt, config.curvePool, config.tokens, params.fee, params.tickSpacing, BigInt(params.sqrtPriceX96)];
  },
};

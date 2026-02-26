// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IHooks} from '@uniswap/v4-core/src/interfaces/IHooks.sol';
import {IPoolManager} from '@uniswap/v4-core/src/interfaces/IPoolManager.sol';
import {Currency} from '@uniswap/v4-core/src/types/Currency.sol';
import {PoolKey} from '@uniswap/v4-core/src/types/PoolKey.sol';
import 'forge-std/Script.sol';

import {FluidDexLiteAggregator} from '@aggregator-hooks/implementations/FluidDexLite/FluidDexLiteAggregator.sol';
import {FluidDexT1Aggregator} from '@aggregator-hooks/implementations/FluidDexT1/FluidDexT1Aggregator.sol';
import {StableSwapAggregator} from '@aggregator-hooks/implementations/StableSwap/StableSwapAggregator.sol';
import {StableSwapNGAggregator} from '@aggregator-hooks/implementations/StableSwapNG/StableSwapNGAggregator.sol';

import {IFluidDexLite} from '@aggregator-hooks/implementations/FluidDexLite/interfaces/IFluidDexLite.sol';
import {
    IFluidDexLiteResolver
} from '@aggregator-hooks/implementations/FluidDexLite/interfaces/IFluidDexLiteResolver.sol';
import {
    IFluidDexReservesResolver
} from '@aggregator-hooks/implementations/FluidDexT1/interfaces/IFluidDexReservesResolver.sol';
import {IFluidDexT1} from '@aggregator-hooks/implementations/FluidDexT1/interfaces/IFluidDexT1.sol';
import {ICurveStableSwap} from '@aggregator-hooks/implementations/StableSwap/interfaces/IStableSwap.sol';
import {ICurveStableSwapNG} from '@aggregator-hooks/implementations/StableSwapNG/interfaces/IStableSwapNG.sol';

/// @notice Self-deploys an aggregator hook and initializes the pool without using a factory
/// @dev Broadcasts from PRIVATE_KEY and deploys using CREATE2 with the provided salt
contract SelfCreateHookScript is Script {
    uint8 constant ID_STABLESWAP = 0xC1;
    uint8 constant ID_STABLESWAPNG = 0xC2;
    uint8 constant ID_FLUIDDEXT1 = 0xF1;
    uint8 constant ID_FLUIDDEXLITE = 0xF3;

    function run() public {
        // Load private key for broadcasting
        uint256 deployerPrivateKey = vm.envUint('PRIVATE_KEY');

        // Common parameters
        uint8 protocolId = uint8(vm.envUint('PROTOCOL_ID'));
        bytes32 salt = vm.envBytes32('SALT');
        address poolManager = vm.envAddress('POOL_MANAGER');

        uint24 fee = uint24(vm.envUint('FEE'));
        int24 tickSpacing = int24(int256(vm.envUint('TICK_SPACING')));
        uint160 sqrtPriceX96 = uint160(vm.envUint('SQRT_PRICE_X96'));

        address hookAddress;

        vm.startBroadcast(deployerPrivateKey);

        if (protocolId == ID_STABLESWAP) {
            hookAddress = _deployStableSwap(salt, poolManager);
        } else if (protocolId == ID_STABLESWAPNG) {
            hookAddress = _deployStableSwapNG(salt, poolManager);
        } else if (protocolId == ID_FLUIDDEXT1) {
            hookAddress = _deployFluidDexT1(salt, poolManager);
        } else if (protocolId == ID_FLUIDDEXLITE) {
            hookAddress = _deployFluidDexLite(salt, poolManager);
        } else {
            revert('Invalid protocol ID');
        }

        // Initialize one Uniswap pool per token pair. TOKENS is comma-separated (2+ for fluid, 2+ for stableswap).
        address[] memory tokens = vm.envAddress('TOKENS', ',');
        require(tokens.length >= 2, 'TOKENS must have at least 2 addresses');
        for (uint256 i = 0; i < tokens.length; i++) {
            for (uint256 j = i + 1; j < tokens.length; j++) {
                (address c0, address c1) = tokens[i] < tokens[j] ? (tokens[i], tokens[j]) : (tokens[j], tokens[i]);
                PoolKey memory poolKey = PoolKey({
                    currency0: Currency.wrap(c0),
                    currency1: Currency.wrap(c1),
                    fee: fee,
                    tickSpacing: tickSpacing,
                    hooks: IHooks(hookAddress)
                });
                IPoolManager(poolManager).initialize(poolKey, sqrtPriceX96);
                console.log('Initialized pool:', c0, c1);
            }
        }

        vm.stopBroadcast();

        // Output results
        console.log('=== Self-Deploy Hook Results ===');
        console.log('Hook Address:', hookAddress);
        console.log('Salt:', vm.toString(salt));
        console.log('Protocol ID:', protocolId);
        console.log('Pool Manager:', poolManager);
        console.log('Tokens:');
        console.log('Tokens length:', tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            console.log('Token:', tokens[i]);
        }
        console.log('Fee:', fee);
        console.log('Tick Spacing:', uint24(tickSpacing));
        console.log('Sqrt Price X96:', sqrtPriceX96);
        console.log('================================');
    }

    function _deployStableSwap(bytes32 salt, address poolManager) internal returns (address) {
        address curvePool = vm.envAddress('CURVE_POOL');

        StableSwapAggregator hook =
            new StableSwapAggregator{salt: salt}(IPoolManager(poolManager), ICurveStableSwap(curvePool));

        return address(hook);
    }

    function _deployStableSwapNG(bytes32 salt, address poolManager) internal returns (address) {
        address curvePool = vm.envAddress('CURVE_POOL');

        StableSwapNGAggregator hook =
            new StableSwapNGAggregator{salt: salt}(IPoolManager(poolManager), ICurveStableSwapNG(curvePool));

        return address(hook);
    }

    function _deployFluidDexT1(bytes32 salt, address poolManager) internal returns (address) {
        address fluidPool = vm.envAddress('FLUID_POOL');
        address fluidDexReservesResolver = vm.envAddress('FLUID_DEX_RESOLVER');
        address fluidLiquidity = vm.envAddress('FLUID_LIQUIDITY');

        FluidDexT1Aggregator hook = new FluidDexT1Aggregator{salt: salt}(
            IPoolManager(poolManager),
            IFluidDexT1(fluidPool),
            IFluidDexReservesResolver(fluidDexReservesResolver),
            fluidLiquidity
        );

        return address(hook);
    }

    function _deployFluidDexLite(bytes32 salt, address poolManager) internal returns (address) {
        address fluidDexLite = vm.envAddress('FLUID_DEX_LITE');
        address fluidDexLiteResolver = vm.envAddress('FLUID_DEX_LITE_RESOLVER');
        bytes32 dexSalt = vm.envBytes32('DEX_SALT');

        FluidDexLiteAggregator hook = new FluidDexLiteAggregator{salt: salt}(
            IPoolManager(poolManager), IFluidDexLite(fluidDexLite), IFluidDexLiteResolver(fluidDexLiteResolver), dexSalt
        );

        return address(hook);
    }
}

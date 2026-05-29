// SPDX-License-Identifier: MIT
// ^0.8.20 to match the sibling smoke scripts in this directory (these are not deployed).
pragma solidity ^0.8.20;

import {Script, console2 as console} from 'forge-std/Script.sol';

// Real v4 math libraries (briefcase copies are self-contained, pragma ^0.8.0).
import {TickMath} from '../../src/briefcase/protocols/v4-core/libraries/TickMath.sol';
import {FullMath} from '../../src/briefcase/protocols/v4-core/libraries/FullMath.sol';
import {LiquidityAmounts} from '../../src/briefcase/protocols/v4-periphery/libraries/LiquidityAmounts.sol';

interface IERC20Min {
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address) external view returns (uint256);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
}

interface IPermit2 {
    function approve(address token, address spender, uint160 amount, uint48 expiration) external;
}

// Mirrors PoolKey from v4-core
struct PoolKey {
    address currency0;
    address currency1;
    uint24 fee;
    int24 tickSpacing;
    address hooks;
}

interface IPositionManager {
    function initializePool(PoolKey calldata key, uint160 sqrtPriceX96) external returns (int24);
    function modifyLiquidities(bytes calldata unlockData, uint256 deadline) external payable;
    function nextTokenId() external view returns (uint256);
}

interface IStateView {
    function getSlot0(bytes32 poolId)
        external
        view
        returns (uint160 sqrtPriceX96, int24 tick, uint24 protocolFee, uint24 lpFee);
    function getLiquidity(bytes32 poolId) external view returns (uint128 liquidity);
}

/// @notice Creates AND funds a Uniswap v4 pool for an equal-decimals stable pair (e.g. USDC/EURC).
///
/// @dev USD-NATIVE INTERFACE. The operator only ever supplies plain USD figures. They never compute a
///      tick or a sqrtPriceX96 — this script derives both from the USD prices.
///
///      Env vars (all USD figures are scaled by 1e8, "Chainlink style": $1.00 = 100000000):
///        TOKEN_A, TOKEN_B            token addresses (order does not matter; sorted internally)
///        PRICE_A_USD_8DP            USD price of 1 whole TOKEN_A, x1e8   (e.g. USDC $1.00 -> 100000000)
///        PRICE_B_USD_8DP            USD price of 1 whole TOKEN_B, x1e8   (e.g. EURC $1.08 -> 108000000)
///        USD_PER_SIDE_8DP           target USD value to deposit on EACH side, x1e8 ($1000 -> 100000000000)
///
///      STAGED FUNDING (run this script more than once):
///        - 1st run sets the pool's STARTING price from the USD prices. Initialization happens once per
///          pool (you cannot re-initialize), but the price floats with swaps afterward like any AMM.
///          Use a real FX quote and start with a SMALL USD_PER_SIDE: if the starting price is off, the
///          pool gets arbitraged and the loss scales with the liquidity posted, so keep the first run tiny.
///        - After confirming a test swap routes, run again with the full USD_PER_SIDE. The pool is already
///          initialized, so this run skips init and adds liquidity at the pool's CURRENT live price
///          (read from StateView) — whatever swaps have left it at.
contract SeedStablePoolV4 is Script {
    // v4 Action codes
    uint8 constant MINT_POSITION = 0x02;
    uint8 constant SETTLE_PAIR = 0x0d;

    // Sensible stable-pair params. In v4 ANY fee/tickSpacing combo is allowed (no externally-enabled tiers).
    uint24 constant FEE = 500; // 0.05%
    int24 constant TICK_SPACING = 10;

    uint256 constant USD_SCALE = 1e8; // all *_8DP env inputs use this scale

    struct Env {
        address permit2;
        address poolManager;
        address positionManager;
        address stateView;
    }

    function run() public {
        Env memory e = _loadEnv();

        // --- Inputs (never hardcoded) ---
        address tokenA = vm.envAddress('TOKEN_A');
        address tokenB = vm.envAddress('TOKEN_B');
        uint256 priceA8 = vm.envUint('PRICE_A_USD_8DP');
        uint256 priceB8 = vm.envUint('PRICE_B_USD_8DP');
        uint256 usdPerSide8 = vm.envUint('USD_PER_SIDE_8DP');

        require(tokenA != address(0) && tokenB != address(0), 'token addr zero');
        require(tokenA != tokenB, 'tokens identical');
        require(priceA8 > 0 && priceB8 > 0, 'price zero');
        require(usdPerSide8 > 0, 'budget zero');

        // Order by address: currency0 < currency1. Reorder prices to match.
        (address c0, address c1, uint256 price0_8, uint256 price1_8) =
            tokenA < tokenB ? (tokenA, tokenB, priceA8, priceB8) : (tokenB, tokenA, priceB8, priceA8);

        // The 1:1-cancellation in the price/amount math below is only valid when both tokens share decimals.
        uint8 dec0 = IERC20Min(c0).decimals();
        uint8 dec1 = IERC20Min(c1).decimals();
        require(dec0 == dec1, 'unequal decimals: this script supports equal-decimal stable pairs only');

        // Convert the USD budget into raw token amounts: amount_raw = usdPerSide / price * 10^decimals.
        uint256 unit = 10 ** uint256(dec0);
        uint256 amount0 = FullMath.mulDiv(usdPerSide8, unit, price0_8);
        uint256 amount1 = FullMath.mulDiv(usdPerSide8, unit, price1_8);
        require(amount0 > 0 && amount1 > 0, 'computed amount is zero (budget too small)');

        PoolKey memory key =
            PoolKey({currency0: c0, currency1: c1, fee: FEE, tickSpacing: TICK_SPACING, hooks: address(0)});
        bytes32 poolId = keccak256(abi.encode(key));

        // If the pool is already initialized, fund at its LIVE price (top-up run); otherwise compute the
        // initialization price from the USD prices (first run).
        (uint160 livePrice,,,) = IStateView(e.stateView).getSlot0(poolId);
        bool alreadyInitialized = livePrice != 0;
        uint160 sqrtPriceX96 = alreadyInitialized ? livePrice : _sqrtPriceFromUsd(price0_8, price1_8);

        // Full-range ticks aligned to tickSpacing.
        int24 tickLower = TickMath.minUsableTick(TICK_SPACING);
        int24 tickUpper = TickMath.maxUsableTick(TICK_SPACING);
        uint160 sqrtLower = TickMath.getSqrtPriceAtTick(tickLower);
        uint160 sqrtUpper = TickMath.getSqrtPriceAtTick(tickUpper);

        // Derive the liquidity that the desired amounts buy at the (live or target) price. For a full-range
        // position straddling the price, this is the binding minimum of the liquidity implied by each side,
        // so the deposit consumes the requested amount of the binding side and <= requested of the other.
        uint128 liquidity =
            LiquidityAmounts.getLiquidityForAmounts(sqrtPriceX96, sqrtLower, sqrtUpper, amount0, amount1);
        require(liquidity > 0, 'computed liquidity is zero');

        vm.startBroadcast();
        address me = msg.sender;

        _logSetup(e, key, c0, c1, amount0, amount1, liquidity, sqrtPriceX96, alreadyInitialized, me);

        require(IERC20Min(c0).balanceOf(me) >= amount0, 'insufficient currency0 balance');
        require(IERC20Min(c1).balanceOf(me) >= amount1, 'insufficient currency1 balance');

        if (!alreadyInitialized) {
            IPositionManager(e.positionManager).initializePool(key, sqrtPriceX96);
            console.log('Pool initialized at the USD-derived starting price (init happens once per pool).');
        } else {
            console.log('Pool already initialized; topping up at the live price (price unchanged).');
        }

        _approvePermit2(c0, c1, e);

        uint128 liqBefore = IStateView(e.stateView).getLiquidity(poolId);
        uint256 tokenId = IPositionManager(e.positionManager).nextTokenId();

        // amount0Max/amount1Max = type(uint128).max: the explicitly-computed `liquidity` is the real cap,
        // and the balanceOf checks above bound the spend. This avoids the getLiquidityForAmounts (round-down)
        // vs pool (round-up) off-by-one that can revert with MaximumAmountExceeded.
        bytes memory actions = abi.encodePacked(MINT_POSITION, SETTLE_PAIR);
        bytes[] memory params = new bytes[](2);
        params[0] = abi.encode(
            key, tickLower, tickUpper, uint256(liquidity), type(uint128).max, type(uint128).max, me, bytes('')
        );
        params[1] = abi.encode(key.currency0, key.currency1);

        IPositionManager(e.positionManager).modifyLiquidities(abi.encode(actions, params), block.timestamp + 3600);
        console.log('Minted v4 position tokenId:', tokenId);

        _verifyPool(e.stateView, poolId, tokenId, liqBefore);

        console.log('');
        console.log('SUCCESS: v4 stable pool created/topped up with full-range liquidity');
        vm.stopBroadcast();
    }

    /// @notice sqrtPriceX96 for an equal-decimals pair from USD prices. price(token1/token0) = price0/price1.
    function _sqrtPriceFromUsd(uint256 price0_8, uint256 price1_8) internal pure returns (uint160) {
        // inner = (price0/price1) * 2^192  ->  sqrt(inner) = sqrt(price) * 2^96 = sqrtPriceX96
        uint256 inner = FullMath.mulDiv(price0_8, uint256(1) << 192, price1_8);
        uint256 sp = _sqrt(inner);
        require(sp > TickMath.MIN_SQRT_PRICE && sp < TickMath.MAX_SQRT_PRICE, 'price out of range');
        return uint160(sp);
    }

    /// @notice Floor integer square root (Babylonian method).
    function _sqrt(uint256 x) internal pure returns (uint256) {
        if (x == 0) return 0;
        uint256 z = (x + 1) / 2;
        uint256 y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
        return y;
    }

    function _loadEnv() internal view returns (Env memory e) {
        string memory path = string.concat('./deployments/json/', vm.toString(block.chainid), '.json');
        string memory json = vm.readFile(path);

        e.permit2 = vm.parseJsonAddress(json, '.latest.Permit2.address');
        e.poolManager = vm.parseJsonAddress(json, '.latest.PoolManager.address');
        e.positionManager = vm.parseJsonAddress(json, '.latest.PositionManager.address');
        e.stateView = vm.parseJsonAddress(json, '.latest.StateView.address');

        require(e.permit2 != address(0), 'Permit2 not in deployments JSON');
        require(e.poolManager != address(0), 'PoolManager not in deployments JSON');
        require(e.positionManager != address(0), 'PositionManager not in deployments JSON');
        require(e.stateView != address(0), 'StateView not in deployments JSON');
    }

    function _approvePermit2(address c0, address c1, Env memory e) internal {
        // Step 1: let Permit2 pull tokens from msg.sender.
        IERC20Min(c0).approve(e.permit2, type(uint256).max);
        IERC20Min(c1).approve(e.permit2, type(uint256).max);
        // Step 2: give PositionManager spender allowance via Permit2.
        IPermit2(e.permit2).approve(c0, e.positionManager, type(uint160).max, type(uint48).max);
        IPermit2(e.permit2).approve(c1, e.positionManager, type(uint160).max, type(uint48).max);
        console.log('Permit2 allowances granted to PositionManager for both tokens');
    }

    function _logSetup(
        Env memory e,
        PoolKey memory key,
        address c0,
        address c1,
        uint256 amount0,
        uint256 amount1,
        uint128 liquidity,
        uint160 sqrtPriceX96,
        bool alreadyInitialized,
        address me
    ) internal view {
        console.log('Chain:', block.chainid);
        console.log('Sender:', me);
        console.log('PoolManager:', e.poolManager);
        console.log('PositionManager:', e.positionManager);
        console.log('StateView:', e.stateView);
        console.log('Permit2:', e.permit2);
        console.log('pool already initialized:', alreadyInitialized);
        console.log('currency0:', c0);
        console.log('  symbol:', IERC20Min(c0).symbol());
        console.log('  amount0 to deposit (raw):', amount0);
        console.log('currency1:', c1);
        console.log('  symbol:', IERC20Min(c1).symbol());
        console.log('  amount1 to deposit (raw):', amount1);
        console.log('fee:', key.fee);
        console.log('sqrtPriceX96 (computed, no operator input):', sqrtPriceX96);
        console.log('computed liquidity:', liquidity);
    }

    function _verifyPool(address stateView, bytes32 poolId, uint256 tokenId, uint128 liqBefore) internal view {
        (uint160 sqrtPriceX96, int24 tick,,) = IStateView(stateView).getSlot0(poolId);
        uint128 liqAfter = IStateView(stateView).getLiquidity(poolId);
        console.log('Pool id:');
        console.logBytes32(poolId);
        console.log('Pool slot0 sqrtPriceX96:', sqrtPriceX96);
        console.log('Pool tick:', tick);
        console.log('pool liquidity before:', liqBefore);
        console.log('pool liquidity after:', liqAfter);
        require(liqAfter > liqBefore, 'liquidity did not increase');
        require(tokenId > 0, 'no position minted');
    }
}

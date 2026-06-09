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

/// @notice Creates AND funds a Uniswap v4 pool from two raw token amounts, as a concentrated position.
///
/// @dev AMOUNT-NATIVE INTERFACE. You give two token addresses and two raw amounts (in each token's
///      smallest units). The script sorts the tokens, sets the starting price to the ratio implied by
///      the amounts, and mints a concentrated position around it. It does NOT know or care about:
///        - USD prices, NAV, yield, or rebasing. You encode whatever ratio you want into the amounts.
///        - token decimals. The price is the raw amount ratio, which is exactly the v4 raw price, so any
///          decimal combination works.
///        - token order / direction. Pass the tokens in any order; the script sorts internally.
///
///      The pool price is whatever AMOUNT_B/AMOUNT_A (after sorting) works out to. To price a
///      yield-bearing token correctly, deposit the two sides in the ratio of their current values
///      (e.g. for 1 syrupUSDG = 1.05 USDG, deposit 1.05 USDG for every 1 syrupUSDG). That ratio is the
///      operator's responsibility; the script just deposits what you give it.
///
///      The position is concentrated: it spans RANGE_TICKS ticks on EACH side of the current price
///      (not full range). With tickSpacing 10, 1 tick ~= 0.01%, so the default 100 ticks ~= +/- 1%,
///      a sensible band for a stablecoin / correlated pair. Widen for more drift runway, tighten for
///      more fee density. The bounds are aligned to tickSpacing and clamped to the usable range.
///
///      Env vars:
///        TOKEN_A, TOKEN_B   token addresses (order does not matter; sorted internally)
///        AMOUNT_A, AMOUNT_B raw amount of each token to deposit, in that token's smallest units
///                           (e.g. 1000 USDG with 6 decimals = 1000000000)
///        RANGE_TICKS        (optional) ticks on each side of the current price. Default 100 (~ +/- 1%).
///
///      STAGED FUNDING (run more than once):
///        - 1st run sets the pool's STARTING price from AMOUNT_B/AMOUNT_A and mints. Initialization
///          happens once per pool (you cannot re-initialize). Start small so a wrong ratio is cheap.
///        - Later runs skip init and add liquidity at the pool's CURRENT live price (read from
///          StateView). At the live price the deposit consumes the requested amount of the binding side
///          and <= the requested amount of the other side.
contract SeedPoolV4 is Script {
    // v4 Action codes
    uint8 constant MINT_POSITION = 0x02;
    uint8 constant SETTLE_PAIR = 0x0d;

    // Pool params. In v4 ANY fee/tickSpacing combo is allowed; edit these if you want a different tier.
    uint24 constant FEE = 500; // 0.05%
    int24 constant TICK_SPACING = 10;

    // Default position half-width, in ticks, used when RANGE_TICKS is not set. With tickSpacing 10,
    // 1 tick ~= 0.01%, so 100 ticks ~= +/- 1% around the current price: a sensible stablecoin default.
    uint256 constant DEFAULT_RANGE_TICKS = 100;

    struct Env {
        address permit2;
        address poolManager;
        address positionManager;
        address stateView;
    }

    function run() public {
        Env memory e = _loadEnv();

        // --- Inputs (raw token amounts; no prices) ---
        address tokenA = vm.envAddress('TOKEN_A');
        address tokenB = vm.envAddress('TOKEN_B');
        uint256 amtA = vm.envUint('AMOUNT_A');
        uint256 amtB = vm.envUint('AMOUNT_B');

        require(tokenA != address(0) && tokenB != address(0), 'token addr zero');
        require(tokenA != tokenB, 'tokens identical');
        require(amtA > 0 && amtB > 0, 'amount zero');

        // Order by address: currency0 < currency1. Keep amounts aligned with the sorted tokens.
        (address c0, address c1, uint256 amount0, uint256 amount1) =
            tokenA < tokenB ? (tokenA, tokenB, amtA, amtB) : (tokenB, tokenA, amtB, amtA);

        PoolKey memory key =
            PoolKey({currency0: c0, currency1: c1, fee: FEE, tickSpacing: TICK_SPACING, hooks: address(0)});
        bytes32 poolId = keccak256(abi.encode(key));

        // If already initialized, fund at the LIVE price (top-up); otherwise set the starting price from
        // the raw amount ratio: price(token1/token0) = amount1 / amount0.
        (uint160 livePrice, int24 liveTick,,) = IStateView(e.stateView).getSlot0(poolId);
        bool alreadyInitialized = livePrice != 0;
        uint160 sqrtPriceX96 = alreadyInitialized ? livePrice : _sqrtPriceFromAmounts(amount0, amount1);
        int24 currentTick = alreadyInitialized ? liveTick : TickMath.getTickAtSqrtPrice(sqrtPriceX96);

        // Concentrated range: RANGE_TICKS ticks on each side of the current price, aligned to tickSpacing
        // and clamped to the usable range.
        uint256 rangeRaw = vm.envOr('RANGE_TICKS', DEFAULT_RANGE_TICKS);
        require(rangeRaw > 0 && rangeRaw <= uint256(uint24(TickMath.MAX_TICK)), 'RANGE_TICKS out of range');
        int24 rangeTicks = int24(int256(rangeRaw));

        int24 tickLower = _floorToSpacing(currentTick - rangeTicks, TICK_SPACING);
        int24 tickUpper = _ceilToSpacing(currentTick + rangeTicks, TICK_SPACING);
        int24 minTick = TickMath.minUsableTick(TICK_SPACING);
        int24 maxTick = TickMath.maxUsableTick(TICK_SPACING);
        if (tickLower < minTick) tickLower = minTick;
        if (tickUpper > maxTick) tickUpper = maxTick;
        require(tickUpper > tickLower, 'empty tick range');

        uint160 sqrtLower = TickMath.getSqrtPriceAtTick(tickLower);
        uint160 sqrtUpper = TickMath.getSqrtPriceAtTick(tickUpper);

        // Liquidity the amounts buy at the (live or implied) price within [tickLower, tickUpper]. This is
        // the binding minimum of the two sides; with amount maxes = uint128.max the deposit consumes the
        // binding side fully and <= the requested amount of the other.
        uint128 liquidity =
            LiquidityAmounts.getLiquidityForAmounts(sqrtPriceX96, sqrtLower, sqrtUpper, amount0, amount1);
        require(liquidity > 0, 'computed liquidity is zero');

        console.log('current tick:');
        console.logInt(currentTick);
        console.log('range ticks each side:');
        console.logInt(rangeTicks);
        console.log('tickLower:');
        console.logInt(tickLower);
        console.log('tickUpper:');
        console.logInt(tickUpper);

        vm.startBroadcast();
        address me = msg.sender;

        _logSetup(e, key, c0, c1, amount0, amount1, liquidity, sqrtPriceX96, alreadyInitialized, me);

        require(
            IERC20Min(c0).balanceOf(me) >= amount0,
            string.concat('insufficient ', IERC20Min(c0).symbol(), ' (currency0) balance')
        );
        require(
            IERC20Min(c1).balanceOf(me) >= amount1,
            string.concat('insufficient ', IERC20Min(c1).symbol(), ' (currency1) balance')
        );

        if (!alreadyInitialized) {
            IPositionManager(e.positionManager).initializePool(key, sqrtPriceX96);
            console.log('Pool initialized at the amount-implied starting price (init happens once per pool).');
        } else {
            console.log('Pool already initialized; topping up at the live price (price unchanged).');
        }

        _approvePermit2(c0, c1, e);

        uint128 liqBefore = IStateView(e.stateView).getLiquidity(poolId);
        uint256 tokenId = IPositionManager(e.positionManager).nextTokenId();

        // amount0Max/amount1Max = type(uint128).max: the explicitly-computed `liquidity` is the real cap,
        // and the balanceOf checks above bound the spend. Avoids the getLiquidityForAmounts (round-down)
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
        console.log('SUCCESS: v4 pool created/topped up with concentrated liquidity');
        vm.stopBroadcast();
    }

    /// @notice sqrtPriceX96 from the raw amount ratio. price(token1/token0) = amount1 / amount0.
    function _sqrtPriceFromAmounts(uint256 amount0, uint256 amount1) internal pure returns (uint160) {
        // inner = (amount1/amount0) * 2^192  ->  sqrt(inner) = sqrt(price) * 2^96 = sqrtPriceX96
        uint256 inner = FullMath.mulDiv(amount1, uint256(1) << 192, amount0);
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

    /// @notice Round a tick down to the nearest multiple of `spacing` (toward negative infinity).
    function _floorToSpacing(int24 tick, int24 spacing) internal pure returns (int24) {
        int24 q = tick / spacing;
        if (tick % spacing != 0 && tick < 0) q -= 1;
        return q * spacing;
    }

    /// @notice Round a tick up to the nearest multiple of `spacing` (toward positive infinity).
    function _ceilToSpacing(int24 tick, int24 spacing) internal pure returns (int24) {
        int24 q = tick / spacing;
        if (tick % spacing != 0 && tick > 0) q += 1;
        return q * spacing;
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
        console.log('sqrtPriceX96 (from amount ratio):', sqrtPriceX96);
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

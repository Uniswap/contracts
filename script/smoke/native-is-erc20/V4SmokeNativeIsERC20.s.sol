// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2 as console} from 'forge-std/Script.sol';

// Variant of V4SmokeTest for native-is-ERC20 chains. Uses two fresh
// TestTokens to bypass the WETH wrap. Exercises PoolManager init,
// Permit2 dual-approval (PositionManager + UR), modifyLiquidities mint,
// StateView reads, and UR V4_SWAP — the same end-to-end surface as the
// standard variant minus the WETH wrap.

interface IERC20Min {
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address) external view returns (uint256);
}

interface IPermit2 {
    function approve(address token, address spender, uint160 amount, uint48 expiration) external;
}

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

interface IUniversalRouter {
    function execute(bytes calldata commands, bytes[] calldata inputs, uint256 deadline) external payable;
}

// IV4Router.ExactInputSingleParams (UR v2.1.1 layout with minHopPriceX36)
struct ExactInputSingleParams {
    PoolKey poolKey;
    bool zeroForOne;
    uint128 amountIn;
    uint128 amountOutMinimum;
    uint256 minHopPriceX36;
    bytes hookData;
}

contract TestToken {
    string public name;
    string public symbol;
    uint8 public decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(string memory n, string memory s, uint256 supply) {
        name = n;
        symbol = s;
        totalSupply = supply;
        balanceOf[msg.sender] = supply;
    }

    function approve(address sp, uint256 a) external returns (bool) {
        allowance[msg.sender][sp] = a;
        return true;
    }

    function transfer(address to, uint256 a) external returns (bool) {
        balanceOf[msg.sender] -= a;
        balanceOf[to] += a;
        return true;
    }

    function transferFrom(address f, address t, uint256 a) external returns (bool) {
        if (allowance[f][msg.sender] != type(uint256).max) allowance[f][msg.sender] -= a;
        balanceOf[f] -= a;
        balanceOf[t] += a;
        return true;
    }
}

contract V4SmokeNativeIsERC20 is Script {
    // v4 action codes
    uint8 constant MINT_POSITION = 0x02;
    uint8 constant SWAP_EXACT_IN_SINGLE = 0x06;
    uint8 constant SETTLE_ALL = 0x0c;
    uint8 constant SETTLE_PAIR = 0x0d;
    uint8 constant TAKE_ALL = 0x0f;
    uint8 constant UR_V4_SWAP = 0x10;

    uint24 constant FEE = 3000;
    int24 constant TICK_SPACING = 60;
    int24 constant TICK_LOWER = -887_220;
    int24 constant TICK_UPPER = 887_220;
    uint160 constant SQRT_PRICE_1_1 = 79_228_162_514_264_337_593_543_950_336;

    address permit2;
    address positionManager;
    address stateView;
    address universalRouter;

    function run() public {
        // Resolve addresses from deployments JSON (chain-agnostic)
        string memory chainIdStr = vm.toString(block.chainid);
        string memory path = string.concat('./deployments/json/', chainIdStr, '.json');
        string memory json = vm.readFile(path);
        permit2 = vm.parseJsonAddress(json, '.latest.Permit2.address');
        positionManager = vm.parseJsonAddress(json, '.latest.PositionManager.address');
        stateView = vm.parseJsonAddress(json, '.latest.StateView.address');
        universalRouter = vm.parseJsonAddress(json, '.latest.UniversalRouter.address');

        require(permit2 != address(0), 'Permit2 not in deployments JSON');
        require(positionManager != address(0), 'PositionManager not in deployments JSON');
        require(stateView != address(0), 'StateView not in deployments JSON');
        require(universalRouter != address(0), 'UniversalRouter not in deployments JSON');

        vm.startBroadcast();
        address me = msg.sender;
        console.log('Chain:', block.chainid);
        console.log('Deployer:', me);
        console.log('PoolManager (via PM):', positionManager);
        console.log('StateView:', stateView);
        console.log('UniversalRouter:', universalRouter);
        console.log('Permit2:', permit2);

        TestToken a = new TestToken('SmokeV4A', 'SMK4A', 1_000_000 ether);
        TestToken b = new TestToken('SmokeV4B', 'SMK4B', 1_000_000 ether);
        console.log('Token A:', address(a));
        console.log('Token B:', address(b));

        (address c0, address c1) = address(a) < address(b) ? (address(a), address(b)) : (address(b), address(a));
        PoolKey memory key =
            PoolKey({currency0: c0, currency1: c1, fee: FEE, tickSpacing: TICK_SPACING, hooks: address(0)});

        _approve(a, b);
        IPositionManager(positionManager).initializePool(key, SQRT_PRICE_1_1);
        console.log('Pool initialized at sqrtPriceX96 = SQRT_PRICE_1_1');

        _mintPosition(key, c0, c1, me);
        _verifyPool(key);
        _swap(key, a, b, c0, me);

        console.log('');
        console.log('SUCCESS: v4 (native-is-erc20 variant) pool init + position mint + UR swap completed');
        vm.stopBroadcast();
    }

    function _approve(TestToken a, TestToken b) internal {
        a.approve(permit2, type(uint256).max);
        b.approve(permit2, type(uint256).max);
        IPermit2(permit2).approve(address(a), positionManager, type(uint160).max, type(uint48).max);
        IPermit2(permit2).approve(address(b), positionManager, type(uint160).max, type(uint48).max);
        IPermit2(permit2).approve(address(a), universalRouter, type(uint160).max, type(uint48).max);
        IPermit2(permit2).approve(address(b), universalRouter, type(uint160).max, type(uint48).max);
        console.log('Permit2 allowances granted (PositionManager + UR)');
    }

    function _mintPosition(PoolKey memory key, address c0, address c1, address me) internal {
        uint256 tokenId = IPositionManager(positionManager).nextTokenId();
        bytes memory mintActions = abi.encodePacked(MINT_POSITION, SETTLE_PAIR);
        bytes[] memory mintParams = new bytes[](2);
        uint256 liquidity = 5e13;
        mintParams[0] =
            abi.encode(key, TICK_LOWER, TICK_UPPER, liquidity, type(uint128).max, type(uint128).max, me, bytes(''));
        mintParams[1] = abi.encode(c0, c1);
        IPositionManager(positionManager).modifyLiquidities(abi.encode(mintActions, mintParams), block.timestamp + 3600);
        console.log('Minted v4 position tokenId:', tokenId);
    }

    function _verifyPool(PoolKey memory key) internal view {
        bytes32 poolId = keccak256(abi.encode(key));
        (uint160 sqrtPriceX96, int24 tick,,) = IStateView(stateView).getSlot0(poolId);
        uint128 poolLiq = IStateView(stateView).getLiquidity(poolId);
        console.log('Pool slot0:');
        console.log('  sqrtPriceX96:', sqrtPriceX96);
        console.log('  tick:', tick);
        console.log('  pool liquidity:', poolLiq);
        require(sqrtPriceX96 == SQRT_PRICE_1_1, 'pool sqrtPrice mismatch');
        require(poolLiq > 0, 'no liquidity in pool');
    }

    function _swap(PoolKey memory key, TestToken a, TestToken b, address c0, address me) internal {
        ExactInputSingleParams memory swapParams = ExactInputSingleParams({
            poolKey: key,
            zeroForOne: address(a) == c0,
            amountIn: 1e18,
            amountOutMinimum: 0,
            minHopPriceX36: 0,
            hookData: bytes('')
        });

        bytes memory swapActions = abi.encodePacked(SWAP_EXACT_IN_SINGLE, SETTLE_ALL, TAKE_ALL);
        bytes[] memory swapInnerParams = new bytes[](3);
        swapInnerParams[0] = abi.encode(swapParams);
        swapInnerParams[1] = abi.encode(address(a), type(uint256).max);
        swapInnerParams[2] = abi.encode(address(b), uint256(0));

        bytes memory commands = abi.encodePacked(UR_V4_SWAP);
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(swapActions, swapInnerParams);

        uint256 bBefore = b.balanceOf(me);
        IUniversalRouter(universalRouter).execute(commands, inputs, block.timestamp + 3600);
        uint256 bAfter = b.balanceOf(me);

        console.log('Swap: 1 A -> B via UR.V4_SWAP');
        console.log('  B delta:', bAfter - bBefore);
        require(bAfter > bBefore, "B balance didn't increase after swap");
    }
}

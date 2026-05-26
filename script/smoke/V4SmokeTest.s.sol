// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2 as console} from 'forge-std/Script.sol';

interface IERC20Min {
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address) external view returns (uint256);
}

interface IWETH9 is IERC20Min {
    function deposit() external payable;
}

interface IPermit2 {
    function approve(address token, address spender, uint160 amount, uint48 expiration) external;
}

interface INonfungiblePositionManagerV3 {
    function WETH9() external view returns (address);
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

interface IUniversalRouter {
    function execute(bytes calldata commands, bytes[] calldata inputs, uint256 deadline) external payable;
}

// Matches IV4Router.ExactInputSingleParams — must encode this whole struct as a single value.
// minHopPriceX36 was added in UR v2.1.1 (slot between amountOutMinimum and hookData).
// Set to 0 to disable the per-hop price check.
struct ExactInputSingleParams {
    PoolKey poolKey;
    bool zeroForOne;
    uint128 amountIn;
    uint128 amountOutMinimum;
    uint256 minHopPriceX36;
    bytes hookData;
}

contract TestToken {
    string public name = 'SmokeV4 Token';
    string public symbol = 'SMK4';
    uint8 public decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(uint256 _s) {
        totalSupply = _s;
        balanceOf[msg.sender] = _s;
    }

    function approve(address s, uint256 a) external returns (bool) {
        allowance[msg.sender][s] = a;
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

contract V4SmokeTest is Script {
    // v4 Action codes
    uint8 constant MINT_POSITION = 0x02;
    uint8 constant SWAP_EXACT_IN_SINGLE = 0x06;
    uint8 constant SETTLE_ALL = 0x0c;
    uint8 constant SETTLE_PAIR = 0x0d;
    uint8 constant TAKE_ALL = 0x0f;

    // UR command code for V4 swap
    uint8 constant UR_V4_SWAP = 0x10;

    uint24 constant FEE = 3000;
    int24 constant TICK_SPACING = 60;
    int24 constant TICK_LOWER = -887_220;
    int24 constant TICK_UPPER = 887_220;
    uint160 constant SQRT_PRICE_1_1 = 79_228_162_514_264_337_593_543_950_336;

    struct Env {
        address weth;
        address permit2;
        address poolManager;
        address positionManager;
        address stateView;
        address universalRouter;
    }

    function run() public {
        Env memory e = _loadEnv();

        vm.startBroadcast();
        address me = msg.sender;
        console.log('Chain:', block.chainid);
        console.log('Deployer:', me);
        _logEnv(e);

        IWETH9(e.weth).deposit{value: 0.0001 ether}();
        TestToken test = new TestToken(1_000_000 ether);
        console.log('Test token:', address(test));

        PoolKey memory key = _buildKey(address(test), e.weth);
        _approvePermit2(address(test), e);
        _initPool(key, e.positionManager);
        uint256 tokenId = _mintPosition(key, address(test), e.weth, e.positionManager, me);
        _verifyPool(key, e.stateView, tokenId);
        _doSwap(key, address(test), e, me);

        console.log('');
        console.log('SUCCESS: v4 pool initialized, position minted, swap completed via UR');
        vm.stopBroadcast();
    }

    function _loadEnv() internal view returns (Env memory e) {
        string memory chainIdStr = vm.toString(block.chainid);
        string memory path = string.concat('./deployments/json/', chainIdStr, '.json');
        string memory json = vm.readFile(path);

        e.permit2 = vm.parseJsonAddress(json, '.latest.Permit2.address');
        e.poolManager = vm.parseJsonAddress(json, '.latest.PoolManager.address');
        e.positionManager = vm.parseJsonAddress(json, '.latest.PositionManager.address');
        e.stateView = vm.parseJsonAddress(json, '.latest.StateView.address');
        e.universalRouter = vm.parseJsonAddress(json, '.latest.UniversalRouter.address');

        address v3npm = vm.parseJsonAddress(json, '.latest.NonfungiblePositionManager.address');
        e.weth = INonfungiblePositionManagerV3(v3npm).WETH9();

        require(e.permit2 != address(0), 'Permit2 not in deployments JSON');
        require(e.poolManager != address(0), 'PoolManager not in deployments JSON');
        require(e.positionManager != address(0), 'PositionManager not in deployments JSON');
        require(e.stateView != address(0), 'StateView not in deployments JSON');
        require(e.universalRouter != address(0), 'UniversalRouter not in deployments JSON');
        require(e.weth != address(0), 'WETH not derivable from v3 NPM');
    }

    function _logEnv(Env memory e) internal pure {
        console.log('PoolManager:', e.poolManager);
        console.log('PositionManager:', e.positionManager);
        console.log('StateView:', e.stateView);
        console.log('UniversalRouter:', e.universalRouter);
        console.log('Permit2:', e.permit2);
        console.log('WETH:', e.weth);
    }

    function _buildKey(address test, address weth) internal pure returns (PoolKey memory) {
        (address c0, address c1) = weth < test ? (weth, test) : (test, weth);
        return PoolKey({currency0: c0, currency1: c1, fee: FEE, tickSpacing: TICK_SPACING, hooks: address(0)});
    }

    function _approvePermit2(address test, Env memory e) internal {
        IWETH9(e.weth).approve(e.permit2, type(uint256).max);
        TestToken(test).approve(e.permit2, type(uint256).max);
        // Allowance to PositionManager (for mint)
        IPermit2(e.permit2).approve(e.weth, e.positionManager, type(uint160).max, type(uint48).max);
        IPermit2(e.permit2).approve(test, e.positionManager, type(uint160).max, type(uint48).max);
        // Allowance to UniversalRouter (for swap)
        IPermit2(e.permit2).approve(e.weth, e.universalRouter, type(uint160).max, type(uint48).max);
        IPermit2(e.permit2).approve(test, e.universalRouter, type(uint160).max, type(uint48).max);
        console.log('Permit2 allowances granted to PositionManager + UR');
    }

    function _initPool(PoolKey memory key, address positionManager) internal {
        IPositionManager(positionManager).initializePool(key, SQRT_PRICE_1_1);
        console.log('Pool initialized at sqrtPriceX96 = SQRT_PRICE_1_1');
    }

    function _mintPosition(PoolKey memory key, address test, address weth, address positionManager, address me)
        internal
        returns (uint256 tokenId)
    {
        tokenId = IPositionManager(positionManager).nextTokenId();

        bytes memory actions = abi.encodePacked(MINT_POSITION, SETTLE_PAIR);
        bytes[] memory params = new bytes[](2);
        uint256 liquidity = 5e13;
        params[0] =
            abi.encode(key, TICK_LOWER, TICK_UPPER, liquidity, type(uint128).max, type(uint128).max, me, bytes(''));
        params[1] = abi.encode(key.currency0, key.currency1);

        IPositionManager(positionManager).modifyLiquidities(abi.encode(actions, params), block.timestamp + 3600);
        console.log('Minted v4 position tokenId:', tokenId);

        // silence unused warnings
        test;
        weth;
    }

    function _verifyPool(PoolKey memory key, address stateView, uint256 tokenId) internal view {
        bytes32 poolId = keccak256(abi.encode(key));
        (uint160 sqrtPriceX96, int24 tick,,) = IStateView(stateView).getSlot0(poolId);
        uint128 liq = IStateView(stateView).getLiquidity(poolId);
        console.log('Pool slot0 (via StateView):');
        console.log('  sqrtPriceX96:', sqrtPriceX96);
        console.log('  tick:', tick);
        console.log('  pool liquidity:', liq);
        require(sqrtPriceX96 == SQRT_PRICE_1_1, 'pool sqrtPrice mismatch');
        require(liq > 0, 'no liquidity in pool');
        require(tokenId > 0, 'no position minted');
    }

    function _doSwap(PoolKey memory key, address test, Env memory e, address me) internal {
        // We swap TEST -> WETH.
        // zeroForOne = true means selling currency0 for currency1
        // If test is currency0 → zeroForOne = true (selling TEST → WETH)
        // If WETH is currency0 → zeroForOne = false (TEST is currency1, selling currency1 → currency0)
        bool zeroForOne = test == key.currency0;
        address tokenIn = test;
        address tokenOut = e.weth;

        // SWAP_EXACT_IN_SINGLE expects abi.encode(struct), where the V4Router decoder
        // reads the first word as a pointer to the struct data. Encoding the fields
        // inline (abi.encode(key, zfo, amountIn, ...)) is NOT compatible with
        // decodeSwapExactInSingleParams in CalldataDecoder.
        ExactInputSingleParams memory swapParams = ExactInputSingleParams({
            poolKey: key,
            zeroForOne: zeroForOne,
            amountIn: 1e18,
            amountOutMinimum: 0,
            minHopPriceX36: 0, // disable per-hop price check
            hookData: bytes('')
        });

        bytes memory actions = abi.encodePacked(SWAP_EXACT_IN_SINGLE, SETTLE_ALL, TAKE_ALL);
        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(swapParams);
        params[1] = abi.encode(tokenIn, type(uint256).max); // SETTLE_ALL: (currency, maxAmount)
        params[2] = abi.encode(tokenOut, uint256(0)); // TAKE_ALL:   (currency, minAmount)

        bytes memory commands = abi.encodePacked(UR_V4_SWAP);
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(actions, params);

        uint256 wethBefore = IERC20Min(e.weth).balanceOf(me);
        IUniversalRouter(e.universalRouter).execute(commands, inputs, block.timestamp + 3600);
        uint256 wethAfter = IERC20Min(e.weth).balanceOf(me);

        console.log('Swap via UR: 1 TEST -> WETH');
        console.log('  WETH delta:', wethAfter - wethBefore);
        require(wethAfter > wethBefore, "WETH balance didn't increase after swap");
    }
}

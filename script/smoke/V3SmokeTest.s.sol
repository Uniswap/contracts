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

interface IV3Factory {
    function createPool(address tokenA, address tokenB, uint24 fee) external returns (address);
    function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address);
}

interface IUniswapV3Pool {
    function initialize(uint160 sqrtPriceX96) external;
    function slot0() external view returns (uint160, int24, uint16, uint16, uint16, uint8, bool);
}

interface INonfungiblePositionManager {
    function WETH9() external view returns (address);

    struct MintParams {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
    }
    function mint(MintParams calldata) external payable returns (uint256, uint128, uint256, uint256);
}

interface ISwapRouter02 {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }
    function exactInputSingle(ExactInputSingleParams calldata) external payable returns (uint256);
}

contract TestToken {
    string public name = 'SmokeV3 Token';
    string public symbol = 'SMK3';
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

contract V3SmokeTest is Script {
    uint24 constant FEE = 3000;
    int24 constant TICK_LOWER = -887_220;
    int24 constant TICK_UPPER = 887_220;
    uint160 constant SQRT_PRICE_1_1 = 79_228_162_514_264_337_593_543_950_336;

    function run() public {
        string memory chainIdStr = vm.toString(block.chainid);
        string memory path = string.concat('./deployments/json/', chainIdStr, '.json');
        string memory json = vm.readFile(path);

        address v3Factory = vm.parseJsonAddress(json, '.latest.UniswapV3Factory.address');
        address npm = vm.parseJsonAddress(json, '.latest.NonfungiblePositionManager.address');
        address swapRouter = vm.parseJsonAddress(json, '.latest.SwapRouter02.address');
        address weth = INonfungiblePositionManager(npm).WETH9();

        require(v3Factory != address(0), 'UniswapV3Factory not in deployments JSON');
        require(npm != address(0), 'NonfungiblePositionManager not in deployments JSON');
        require(swapRouter != address(0), 'SwapRouter02 not in deployments JSON');

        vm.startBroadcast();
        address me = msg.sender;
        console.log('Chain:', block.chainid);
        console.log('Deployer:', me);
        console.log('V3 Factory:', v3Factory);
        console.log('NPM:', npm);
        console.log('SwapRouter02:', swapRouter);
        console.log('WETH:', weth);

        IWETH9(weth).deposit{value: 0.0001 ether}();
        TestToken test = new TestToken(1_000_000 ether);
        console.log('Test token:', address(test));

        address pool = _createPool(v3Factory, address(test), weth);
        _mintPosition(npm, address(test), weth, me);
        _doSwap(swapRouter, address(test), weth, me);
        pool; // silence unused warning

        console.log('');
        console.log('SUCCESS: v3 pool created, position minted, swap completed');
        vm.stopBroadcast();
    }

    function _createPool(address v3Factory, address test, address weth) internal returns (address pool) {
        (address t0, address t1) = weth < test ? (weth, test) : (test, weth);
        pool = IV3Factory(v3Factory).createPool(t0, t1, FEE);
        IUniswapV3Pool(pool).initialize(SQRT_PRICE_1_1);
        (uint160 sqrtPx,,,,,,) = IUniswapV3Pool(pool).slot0();
        console.log('Pool:', pool);
        console.log('Pool sqrtPriceX96:', sqrtPx);
    }

    function _mintPosition(address npm, address test, address weth, address me) internal {
        IWETH9(weth).approve(npm, type(uint256).max);
        TestToken(test).approve(npm, type(uint256).max);

        (address t0, address t1) = weth < test ? (weth, test) : (test, weth);
        uint256 amt0 = t0 == weth ? uint256(0.000_05 ether) : uint256(1000 ether);
        uint256 amt1 = t1 == weth ? uint256(0.000_05 ether) : uint256(1000 ether);

        INonfungiblePositionManager.MintParams memory mp = INonfungiblePositionManager.MintParams({
            token0: t0,
            token1: t1,
            fee: FEE,
            tickLower: TICK_LOWER,
            tickUpper: TICK_UPPER,
            amount0Desired: amt0,
            amount1Desired: amt1,
            amount0Min: 0,
            amount1Min: 0,
            recipient: me,
            deadline: block.timestamp + 3600
        });

        (uint256 tokenId, uint128 liq, uint256 a0, uint256 a1) = INonfungiblePositionManager(npm).mint(mp);
        console.log('Minted v3 position:');
        console.log('  tokenId:', tokenId);
        console.log('  liquidity:', liq);
        console.log('  amount0:', a0);
        console.log('  amount1:', a1);
        require(liq > 0, 'no liquidity minted');
    }

    function _doSwap(address swapRouter, address test, address weth, address me) internal {
        TestToken(test).approve(swapRouter, type(uint256).max);
        uint256 wethBefore = IERC20Min(weth).balanceOf(me);

        ISwapRouter02.ExactInputSingleParams memory sp = ISwapRouter02.ExactInputSingleParams({
            tokenIn: test,
            tokenOut: weth,
            fee: FEE,
            recipient: me,
            amountIn: 1 ether,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        uint256 out = ISwapRouter02(swapRouter).exactInputSingle(sp);
        uint256 wethAfter = IERC20Min(weth).balanceOf(me);

        console.log('Swap: 1 TEST -> WETH');
        console.log('  amount out:', out);
        console.log('  WETH delta:', wethAfter - wethBefore);
        require(out > 0, 'swap returned zero');
        require(wethAfter > wethBefore, "WETH balance didn't increase");
    }
}

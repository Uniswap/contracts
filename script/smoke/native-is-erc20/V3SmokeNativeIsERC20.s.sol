// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2 as console} from 'forge-std/Script.sol';

// Variant of V3SmokeTest for native-is-ERC20 chains. Uses two fresh
// TestTokens to bypass the WETH wrap that reverts on these chains.
// Validates v3 Factory createPool, pool initialize, NPM mint, and
// SwapRouter02 exactInputSingle — the full v3 LP+swap surface minus WETH.

interface IERC20Min {
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address) external view returns (uint256);
}

interface IV3Factory {
    function createPool(address tokenA, address tokenB, uint24 fee) external returns (address pool);
}

interface IUniswapV3Pool {
    function initialize(uint160 sqrtPriceX96) external;
}

interface INonfungiblePositionManager {
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

contract V3SmokeNativeIsERC20 is Script {
    uint24 constant FEE = 3000;
    int24 constant TICK_LOWER = -887_220;
    int24 constant TICK_UPPER = 887_220;
    uint160 constant SQRT_PRICE_1_1 = 79_228_162_514_264_337_593_543_950_336;

    address v3Factory;
    address npm;
    address swapRouter02;

    function run() public {
        // Resolve addresses from deployments JSON (chain-agnostic)
        string memory chainIdStr = vm.toString(block.chainid);
        string memory path = string.concat('./deployments/json/', chainIdStr, '.json');
        string memory json = vm.readFile(path);
        v3Factory = vm.parseJsonAddress(json, '.latest.UniswapV3Factory.address');
        npm = vm.parseJsonAddress(json, '.latest.NonfungiblePositionManager.address');
        swapRouter02 = vm.parseJsonAddress(json, '.latest.SwapRouter02.address');

        require(v3Factory != address(0), 'UniswapV3Factory not in deployments JSON');
        require(npm != address(0), 'NonfungiblePositionManager not in deployments JSON');
        require(swapRouter02 != address(0), 'SwapRouter02 not in deployments JSON');

        vm.startBroadcast();
        address me = msg.sender;
        console.log('Chain:', block.chainid);
        console.log('Deployer:', me);
        console.log('V3 Factory:', v3Factory);
        console.log('NPM:', npm);
        console.log('SwapRouter02:', swapRouter02);

        TestToken a = new TestToken('SmokeV3A', 'SMK3A', 1_000_000 ether);
        TestToken b = new TestToken('SmokeV3B', 'SMK3B', 1_000_000 ether);
        console.log('Token A:', address(a));
        console.log('Token B:', address(b));

        (address t0, address t1) =
            address(a) < address(b) ? (address(a), address(b)) : (address(b), address(a));

        address pool = IV3Factory(v3Factory).createPool(t0, t1, FEE);
        IUniswapV3Pool(pool).initialize(SQRT_PRICE_1_1);
        console.log('Pool:', pool);

        a.approve(npm, type(uint256).max);
        b.approve(npm, type(uint256).max);
        _mint(t0, t1, me);
        _swap(a, b, me);

        console.log('');
        console.log('SUCCESS: v3 (native-is-erc20 variant) pool created, position minted, swap completed');
        vm.stopBroadcast();
    }

    function _mint(address t0, address t1, address me) internal {
        INonfungiblePositionManager.MintParams memory mp = INonfungiblePositionManager.MintParams({
            token0: t0,
            token1: t1,
            fee: FEE,
            tickLower: TICK_LOWER,
            tickUpper: TICK_UPPER,
            amount0Desired: 1000 ether,
            amount1Desired: 1000 ether,
            amount0Min: 0,
            amount1Min: 0,
            recipient: me,
            deadline: block.timestamp + 3600
        });
        (uint256 tokenId, uint128 liq,,) = INonfungiblePositionManager(npm).mint(mp);
        console.log('Position tokenId:', tokenId);
        console.log('  liquidity:', liq);
        require(liq > 0, 'no v3 liquidity minted');
    }

    function _swap(TestToken a, TestToken b, address me) internal {
        a.approve(swapRouter02, type(uint256).max);
        uint256 bBefore = b.balanceOf(me);
        ISwapRouter02.ExactInputSingleParams memory sp = ISwapRouter02.ExactInputSingleParams({
            tokenIn: address(a),
            tokenOut: address(b),
            fee: FEE,
            recipient: me,
            amountIn: 1 ether,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });
        uint256 out = ISwapRouter02(swapRouter02).exactInputSingle(sp);
        uint256 bAfter = b.balanceOf(me);

        console.log('Swap: 1 A -> B');
        console.log('  amount out:', out);
        console.log('  B delta:', bAfter - bBefore);
        require(out > 0, 'swap returned zero');
        require(bAfter > bBefore, "B balance didn't increase");
    }
}

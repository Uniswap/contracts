// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2 as console} from 'forge-std/Script.sol';

interface IERC20Min {
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IWETH9 is IERC20Min {
    function deposit() external payable;
}

interface IV2Factory {
    function getPair(address tokenA, address tokenB) external view returns (address);
}

interface IV2Router02 {
    function WETH() external view returns (address);

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity);

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}

contract TestToken {
    string public name = 'SmokeV2 Token';
    string public symbol = 'SMK2';
    uint8 public decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(uint256 _supply) {
        totalSupply = _supply;
        balanceOf[msg.sender] = _supply;
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

    function transferFrom(address from, address to, uint256 a) external returns (bool) {
        if (allowance[from][msg.sender] != type(uint256).max) allowance[from][msg.sender] -= a;
        balanceOf[from] -= a;
        balanceOf[to] += a;
        return true;
    }
}

contract V2SmokeTest is Script {
    function run() public {
        // Chain-agnostic address resolution
        string memory chainIdStr = vm.toString(block.chainid);
        string memory path = string.concat('./deployments/json/', chainIdStr, '.json');
        string memory json = vm.readFile(path);

        address v2Factory = vm.parseJsonAddress(json, '.latest.UniswapV2Factory.address');
        address v2Router = vm.parseJsonAddress(json, '.latest.UniswapV2Router02.address');
        // Derive WETH from the deployed Router02 — works on any chain
        address weth = IV2Router02(v2Router).WETH();

        require(v2Factory != address(0), 'UniswapV2Factory not in deployments JSON');
        require(v2Router != address(0), 'UniswapV2Router02 not in deployments JSON');
        require(weth != address(0), 'WETH not derivable from Router');

        vm.startBroadcast();
        address me = msg.sender;
        console.log('Chain:', block.chainid);
        console.log('Deployer:', me);
        console.log('V2 Factory:', v2Factory);
        console.log('V2 Router02:', v2Router);
        console.log('WETH:', weth);

        IWETH9(weth).deposit{value: 0.0001 ether}();
        console.log('Wrapped 0.0001 ETH; WETH balance:', IERC20Min(weth).balanceOf(me));

        TestToken test = new TestToken(1_000_000 ether);
        console.log('Test token:', address(test));

        IWETH9(weth).approve(v2Router, type(uint256).max);
        test.approve(v2Router, type(uint256).max);

        (uint256 amtA, uint256 amtB, uint256 liq) = IV2Router02(v2Router)
            .addLiquidity(weth, address(test), 0.000_05 ether, 1000 ether, 0, 0, me, block.timestamp + 3600);
        console.log('Added v2 liquidity:');
        console.log('  amountA (WETH):', amtA);
        console.log('  amountB (TEST):', amtB);
        console.log('  LP tokens:', liq);
        require(liq > 0, 'no LP minted');

        address pair = IV2Factory(v2Factory).getPair(weth, address(test));
        console.log('Pair address:', pair);
        require(pair != address(0), 'pair address should be non-zero');

        uint256 wethBefore = IERC20Min(weth).balanceOf(me);
        address[] memory swapPath = new address[](2);
        swapPath[0] = address(test);
        swapPath[1] = weth;

        uint256[] memory amounts =
            IV2Router02(v2Router).swapExactTokensForTokens(1 ether, 0, swapPath, me, block.timestamp + 3600);
        uint256 wethAfter = IERC20Min(weth).balanceOf(me);

        console.log('Swap: 1 TEST -> WETH');
        console.log('  amount in:', amounts[0]);
        console.log('  amount out:', amounts[1]);
        console.log('  WETH delta:', wethAfter - wethBefore);
        require(amounts[1] > 0, 'swap returned zero');
        require(wethAfter > wethBefore, "WETH balance didn't increase");

        console.log('');
        console.log('SUCCESS: v2 pair created, liquidity added, swap completed');
        vm.stopBroadcast();
    }
}

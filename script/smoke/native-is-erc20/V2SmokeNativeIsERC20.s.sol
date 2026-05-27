// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2 as console} from 'forge-std/Script.sol';

// Variant of V2SmokeTest for chains where the native gas token is itself
// an ERC-20 (CELO, Arc, ...). On these chains, the WETH9 dependency is wired
// to a placeholder (e.g., UnsupportedProtocol) that reverts on deposit/withdraw,
// so the standard V2SmokeTest halts at the WETH wrap step.
//
// This variant skips the WETH leg entirely and exercises pair creation,
// liquidity add, and a swap using two freshly-deployed TestTokens. The v2
// pool mechanics are token-agnostic, so the same code paths get covered.

interface IERC20Min {
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IV2Factory {
    function getPair(address tokenA, address tokenB) external view returns (address);
}

interface IV2Router02 {
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

contract V2SmokeNativeIsERC20 is Script {
    function run() public {
        // Resolve addresses from deployments JSON (chain-agnostic)
        string memory chainIdStr = vm.toString(block.chainid);
        string memory path = string.concat('./deployments/json/', chainIdStr, '.json');
        string memory json = vm.readFile(path);
        address v2Factory = vm.parseJsonAddress(json, '.latest.UniswapV2Factory.address');
        address v2Router = vm.parseJsonAddress(json, '.latest.UniswapV2Router02.address');

        require(v2Factory != address(0), 'UniswapV2Factory not in deployments JSON');
        require(v2Router != address(0), 'UniswapV2Router02 not in deployments JSON');

        vm.startBroadcast();
        address me = msg.sender;
        console.log('Chain:', block.chainid);
        console.log('Deployer:', me);
        console.log('V2 Factory:', v2Factory);
        console.log('V2 Router02:', v2Router);

        // Two fresh TestTokens stand in for the WETH/test pair in the standard variant
        TestToken a = new TestToken('SmokeV2A', 'SMK2A', 1_000_000 ether);
        TestToken b = new TestToken('SmokeV2B', 'SMK2B', 1_000_000 ether);
        console.log('TestTokenA:', address(a));
        console.log('TestTokenB:', address(b));

        a.approve(v2Router, type(uint256).max);
        b.approve(v2Router, type(uint256).max);

        (uint256 amtA, uint256 amtB, uint256 liq) = IV2Router02(v2Router).addLiquidity(
            address(a), address(b), 1000 ether, 1000 ether, 0, 0, me, block.timestamp + 3600
        );
        console.log('Added v2 liquidity:');
        console.log('  amountA:', amtA);
        console.log('  amountB:', amtB);
        console.log('  LP tokens:', liq);
        require(liq > 0, 'no LP minted');

        address pair = IV2Factory(v2Factory).getPair(address(a), address(b));
        console.log('Pair address:', pair);
        require(pair != address(0), 'pair should exist');

        uint256 bBefore = b.balanceOf(me);
        address[] memory swapPath = new address[](2);
        swapPath[0] = address(a);
        swapPath[1] = address(b);
        uint256[] memory amounts = IV2Router02(v2Router).swapExactTokensForTokens(
            1 ether, 0, swapPath, me, block.timestamp + 3600
        );
        uint256 bAfter = b.balanceOf(me);

        console.log('Swap: 1 A -> B');
        console.log('  amount in:', amounts[0]);
        console.log('  amount out:', amounts[1]);
        console.log('  B delta:', bAfter - bBefore);
        require(amounts[1] > 0, 'swap returned zero');
        require(bAfter > bBefore, "B balance didn't increase");

        console.log('');
        console.log('SUCCESS: v2 (native-is-erc20 variant) pair created, liquidity added, swap completed');
        vm.stopBroadcast();
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2 as console} from 'forge-std/Test.sol';

/// @title HyperEVM deployment fork test
/// @notice Runs against a fork of HyperEVM (chain 999) AFTER Deploy-all.s.sol has been broadcast and
///         deployments/json/999.json has been written (script/hyperevm/build_registry.py).
///         Rehearsal:   anvil --fork-url <hyperevm-rpc> --port 8999 --chain-id 999 ... ; deploy ; then
///                      forge test --match-contract HyperEVMDeployTest --fork-url http://127.0.0.1:8999
///         Post-deploy: forge test --match-contract HyperEVMDeployTest --fork-url <hyperevm-rpc>
///         Covers: ownership handed to the Wormhole receiver atomically, deployer owns nothing, and a fake
///         token pool on v2 / v3 / v4 with liquidity + swaps (direct routers and via UniversalRouter).
interface IERC20Min {
    function approve(address, uint256) external returns (bool);
    function balanceOf(address) external view returns (uint256);
    function transfer(address, uint256) external returns (bool);
}

interface IWETH9 is IERC20Min {
    function deposit() external payable;
}

interface IPermit2 {
    function approve(address token, address spender, uint160 amount, uint48 expiration) external;
}

interface IOwned {
    function owner() external view returns (address);
}

interface IV2Factory {
    function feeToSetter() external view returns (address);
    function getPair(address, address) external view returns (address);
}

interface IV2Router02 {
    function WETH() external view returns (address);
    function addLiquidity(address, address, uint256, uint256, uint256, uint256, address, uint256)
        external
        returns (uint256, uint256, uint256);
    function swapExactTokensForTokens(uint256, uint256, address[] calldata, address, uint256)
        external
        returns (uint256[] memory);
}

interface IV3Factory {
    function owner() external view returns (address);
    function feeAmountTickSpacing(uint24) external view returns (int24);
}

interface INPM {
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
    function WETH9() external view returns (address);
    function createAndInitializePoolIfNecessary(address, address, uint24, uint160) external payable returns (address);
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
    function getSlot0(bytes32) external view returns (uint160, int24, uint24, uint24);
    function getLiquidity(bytes32) external view returns (uint128);
}

interface IUniversalRouter {
    function execute(bytes calldata commands, bytes[] calldata inputs, uint256 deadline) external payable;
}

interface IFeeCollector {
    function owner() external view returns (address);
    function feeToken() external view returns (address);
}

interface IWormholeReceiver {
    function chainId() external view returns (uint16);
    function ETHEREUM_CHAIN_ID() external view returns (uint16);
    function messageSender() external view returns (bytes32);
}

// UR v2.1.1+ struct: minHopPriceX36 sits between amountOutMinimum and hookData.
struct V4ExactInputSingleParams {
    PoolKey poolKey;
    bool zeroForOne;
    uint128 amountIn;
    uint128 amountOutMinimum;
    uint256 minHopPriceX36;
    bytes hookData;
}

contract FakeToken {
    string public name = 'HyperEVM Smoke Token';
    string public symbol = 'HSMK';
    uint8 public decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(uint256 s) {
        totalSupply = s;
        balanceOf[msg.sender] = s;
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

contract HyperEVMDeployTest is Test {
    uint256 constant CHAIN_ID = 999;
    // Uniswap governance's Wormhole message receiver on HyperEVM (verified: UniswapWormholeMessageReceiver,
    // wormhole chain id 47, sender = canonical Ethereum UniswapWormholeMessageSender)
    address constant OWNER = 0x2D09D0C2F82c59B19B3C65a48CE2c550Bf0921f9;
    address constant DEPLOYER = 0x9701fb0aDe1E269c8f64Ec0C7b3cfADB31A13A52; // swap-test
    address constant FEE_COLLECTOR_OWNER = 0xbE84D31B2eE049DCb1d8E7c798511632b44d1b55; // AWS KMS ops EOA
    address constant WHYPE = 0x5555555555555555555555555555555555555555;
    address constant USDC = 0xb88339CB7199b77E23DB6E890353E22632Ba630f;
    address constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    // UR commands
    uint8 constant CMD_V3_SWAP_EXACT_IN = 0x00;
    uint8 constant CMD_V2_SWAP_EXACT_IN = 0x08;
    uint8 constant CMD_V4_SWAP = 0x10;
    // v4 actions
    uint8 constant MINT_POSITION = 0x02;
    uint8 constant SWAP_EXACT_IN_SINGLE = 0x06;
    uint8 constant SETTLE_ALL = 0x0c;
    uint8 constant SETTLE_PAIR = 0x0d;
    uint8 constant TAKE_ALL = 0x0f;
    uint160 constant SQRT_PRICE_1_1 = 79_228_162_514_264_337_593_543_950_336;

    struct D {
        address v2Factory;
        address v2Router;
        address v3Factory;
        address npm;
        address swapRouter02;
        address poolManager;
        address posm;
        address stateView;
        address ur;
        address feeCollector;
        address nftDescriptorAdmin;
        address posDescriptorAdmin;
        address permissionsAdapterFactory;
    }

    D d;
    address alice = makeAddr('alice');
    FakeToken tok;

    function setUp() public {
        require(block.chainid == CHAIN_ID, 'run with --fork-url pointing at HyperEVM (chain 999)');
        string memory json = vm.readFile('./deployments/json/999.json');
        d.v2Factory = vm.parseJsonAddress(json, '.latest.UniswapV2Factory.address');
        d.v2Router = vm.parseJsonAddress(json, '.latest.UniswapV2Router02.address');
        d.v3Factory = vm.parseJsonAddress(json, '.latest.UniswapV3Factory.address');
        d.npm = vm.parseJsonAddress(json, '.latest.NonfungiblePositionManager.address');
        d.swapRouter02 = vm.parseJsonAddress(json, '.latest.SwapRouter02.address');
        d.poolManager = vm.parseJsonAddress(json, '.latest.PoolManager.address');
        d.posm = vm.parseJsonAddress(json, '.latest.PositionManager.address');
        d.stateView = vm.parseJsonAddress(json, '.latest.StateView.address');
        d.ur = vm.parseJsonAddress(json, '.latest.UniversalRouter.address');
        d.feeCollector = vm.parseJsonAddress(json, '.latest.FeeCollector.address');
        d.nftDescriptorAdmin = vm.parseJsonAddress(json, '.latest.NonfungibleTokenPositionDescriptor.proxyAdmin');
        d.posDescriptorAdmin = vm.parseJsonAddress(json, '.latest.PositionDescriptor.proxyAdmin');
        d.permissionsAdapterFactory = vm.parseJsonAddress(json, '.latest.PermissionsAdapterFactory.address');

        vm.deal(alice, 100 ether);
        vm.startPrank(alice);
        tok = new FakeToken(1_000_000 ether);
        IWETH9(WHYPE).deposit{value: 10 ether}();
        vm.stopPrank();
    }

    // ---------------------------------------------------------------- ownership

    function test_owner_isWormholeReceiver() public view {
        IWormholeReceiver r = IWormholeReceiver(OWNER);
        assertGt(OWNER.code.length, 0, 'owner has no code');
        assertEq(r.chainId(), 47, 'wormhole chain id');
        assertEq(r.ETHEREUM_CHAIN_ID(), 2, 'eth wormhole chain id');
        assertEq(
            r.messageSender(),
            bytes32(uint256(uint160(0xf5F4496219F31CDCBa6130B5402873624585615a))),
            'canonical UniswapWormholeMessageSender'
        );
    }

    function test_ownership_allGovernanceRolesAreReceiver() public view {
        assertEq(IV2Factory(d.v2Factory).feeToSetter(), OWNER, 'v2 feeToSetter');
        assertEq(IV3Factory(d.v3Factory).owner(), OWNER, 'v3 owner');
        assertEq(IOwned(d.poolManager).owner(), OWNER, 'v4 PoolManager owner');
        assertEq(IOwned(d.nftDescriptorAdmin).owner(), OWNER, 'v3 descriptor ProxyAdmin owner');
        assertEq(IOwned(d.posDescriptorAdmin).owner(), OWNER, 'v4 descriptor ProxyAdmin owner');
        assertEq(IFeeCollector(d.feeCollector).owner(), FEE_COLLECTOR_OWNER, 'FeeCollector owner (ops EOA)');
        assertEq(IFeeCollector(d.feeCollector).feeToken(), USDC, 'FeeCollector feeToken');
    }

    function test_ownership_deployerOwnsNothing() public view {
        assertTrue(IV2Factory(d.v2Factory).feeToSetter() != DEPLOYER);
        assertTrue(IV3Factory(d.v3Factory).owner() != DEPLOYER);
        assertTrue(IOwned(d.poolManager).owner() != DEPLOYER);
        assertTrue(IOwned(d.nftDescriptorAdmin).owner() != DEPLOYER);
        assertTrue(IOwned(d.posDescriptorAdmin).owner() != DEPLOYER);
        assertTrue(IFeeCollector(d.feeCollector).owner() != DEPLOYER);
    }

    function test_wiring() public view {
        assertEq(IV2Router02(d.v2Router).WETH(), WHYPE, 'v2 router WETH = WHYPE');
        assertEq(INPM(d.npm).WETH9(), WHYPE, 'npm WETH9 = WHYPE');
        assertEq(IV3Factory(d.v3Factory).feeAmountTickSpacing(100), 1, '1bp fee tier enabled');
        assertGt(PERMIT2.code.length, 0, 'permit2 present');
        assertGt(d.permissionsAdapterFactory.code.length, 0, 'PAF present');
    }

    // ---------------------------------------------------------------- v2

    function test_v2_fakePool_addLiquidity_and_swap() public {
        vm.startPrank(alice);
        IWETH9(WHYPE).approve(d.v2Router, type(uint256).max);
        tok.approve(d.v2Router, type(uint256).max);
        (,, uint256 liq) = IV2Router02(d.v2Router)
            .addLiquidity(WHYPE, address(tok), 1 ether, 1000 ether, 0, 0, alice, block.timestamp + 1);
        assertGt(liq, 0);
        assertTrue(IV2Factory(d.v2Factory).getPair(WHYPE, address(tok)) != address(0));

        address[] memory path = new address[](2);
        path[0] = address(tok);
        path[1] = WHYPE;
        uint256 before = IERC20Min(WHYPE).balanceOf(alice);
        IV2Router02(d.v2Router).swapExactTokensForTokens(1 ether, 0, path, alice, block.timestamp + 1);
        assertGt(IERC20Min(WHYPE).balanceOf(alice), before, 'v2 direct swap');

        // via UniversalRouter (Permit2 pull)
        _permit2(address(tok), d.ur);
        bytes memory commands = abi.encodePacked(CMD_V2_SWAP_EXACT_IN);
        bytes[] memory inputs = new bytes[](1);
        uint256[] memory minHop = new uint256[](1); // UR v2.1.1+: per-hop min price, 0 = disabled
        inputs[0] = abi.encode(alice, uint256(1 ether), uint256(0), path, true, minHop);
        before = IERC20Min(WHYPE).balanceOf(alice);
        IUniversalRouter(d.ur).execute(commands, inputs, block.timestamp + 1);
        assertGt(IERC20Min(WHYPE).balanceOf(alice), before, 'v2 swap via UR');
        vm.stopPrank();
    }

    // ---------------------------------------------------------------- v3

    function test_v3_fakePool_mint_and_swap() public {
        vm.startPrank(alice);
        (address t0, address t1) = WHYPE < address(tok) ? (WHYPE, address(tok)) : (address(tok), WHYPE);
        INPM(d.npm).createAndInitializePoolIfNecessary(t0, t1, 3000, SQRT_PRICE_1_1);
        IWETH9(WHYPE).approve(d.npm, type(uint256).max);
        tok.approve(d.npm, type(uint256).max);
        (, uint128 liq,,) = INPM(d.npm)
            .mint(
                INPM.MintParams({
                    token0: t0,
                    token1: t1,
                    fee: 3000,
                    tickLower: -887_220,
                    tickUpper: 887_220,
                    amount0Desired: 1 ether,
                    amount1Desired: 1 ether,
                    amount0Min: 0,
                    amount1Min: 0,
                    recipient: alice,
                    deadline: block.timestamp + 1
                })
            );
        assertGt(liq, 0);

        // direct SwapRouter02
        tok.approve(d.swapRouter02, type(uint256).max);
        uint256 before = IERC20Min(WHYPE).balanceOf(alice);
        ISwapRouter02(d.swapRouter02)
            .exactInputSingle(ISwapRouter02.ExactInputSingleParams(address(tok), WHYPE, 3000, alice, 0.01 ether, 0, 0));
        assertGt(IERC20Min(WHYPE).balanceOf(alice), before, 'v3 direct swap');

        // via UR (path = tokenIn | fee | tokenOut). UR v2.1.1+ takes an extra minHopPriceX36[] arg.
        _permit2(address(tok), d.ur);
        bytes memory path = abi.encodePacked(address(tok), uint24(3000), WHYPE);
        uint256[] memory minHop = new uint256[](1);
        bytes memory commands = abi.encodePacked(CMD_V3_SWAP_EXACT_IN);
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(alice, uint256(0.01 ether), uint256(0), path, true, minHop);
        before = IERC20Min(WHYPE).balanceOf(alice);
        IUniversalRouter(d.ur).execute(commands, inputs, block.timestamp + 1);
        assertGt(IERC20Min(WHYPE).balanceOf(alice), before, 'v3 swap via UR');
        vm.stopPrank();
    }

    // ---------------------------------------------------------------- v4

    function test_v4_fakePool_mint_and_swap_viaUR() public {
        vm.startPrank(alice);
        (address c0, address c1) = WHYPE < address(tok) ? (WHYPE, address(tok)) : (address(tok), WHYPE);
        PoolKey memory key = PoolKey({currency0: c0, currency1: c1, fee: 3000, tickSpacing: 60, hooks: address(0)});
        _permit2(WHYPE, d.posm);
        _permit2(address(tok), d.posm);
        _permit2(address(tok), d.ur);

        IPositionManager(d.posm).initializePool(key, SQRT_PRICE_1_1);
        uint256 tokenId = IPositionManager(d.posm).nextTokenId();
        bytes memory actions = abi.encodePacked(MINT_POSITION, SETTLE_PAIR);
        bytes[] memory params = new bytes[](2);
        params[0] = abi.encode(
            key, int24(-887_220), int24(887_220), uint256(1e18), type(uint128).max, type(uint128).max, alice, bytes('')
        );
        params[1] = abi.encode(key.currency0, key.currency1);
        IPositionManager(d.posm).modifyLiquidities(abi.encode(actions, params), block.timestamp + 1);

        bytes32 poolId = keccak256(abi.encode(key));
        (uint160 sqrtP,,,) = IStateView(d.stateView).getSlot0(poolId);
        assertEq(sqrtP, SQRT_PRICE_1_1);
        assertGt(IStateView(d.stateView).getLiquidity(poolId), 0);
        assertGt(tokenId, 0);

        V4ExactInputSingleParams memory sp = V4ExactInputSingleParams({
            poolKey: key,
            zeroForOne: address(tok) == c0,
            amountIn: 0.1 ether,
            amountOutMinimum: 0,
            minHopPriceX36: 0,
            hookData: bytes('')
        });
        bytes memory swapActions = abi.encodePacked(SWAP_EXACT_IN_SINGLE, SETTLE_ALL, TAKE_ALL);
        bytes[] memory sparams = new bytes[](3);
        sparams[0] = abi.encode(sp);
        sparams[1] = abi.encode(address(tok), type(uint256).max);
        sparams[2] = abi.encode(WHYPE, uint256(0));
        bytes memory commands = abi.encodePacked(CMD_V4_SWAP);
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(swapActions, sparams);

        uint256 before = IERC20Min(WHYPE).balanceOf(alice);
        IUniversalRouter(d.ur).execute(commands, inputs, block.timestamp + 1);
        assertGt(IERC20Min(WHYPE).balanceOf(alice), before, 'v4 swap via UR');
        // and back the other way, several swaps in a row
        for (uint256 i; i < 3; ++i) {
            IUniversalRouter(d.ur).execute(commands, inputs, block.timestamp + 1);
        }
        vm.stopPrank();
    }

    // ---------------------------------------------------------------- helpers

    function _permit2(address token, address spender) internal {
        IERC20Min(token).approve(PERMIT2, type(uint256).max);
        IPermit2(PERMIT2).approve(token, spender, type(uint160).max, type(uint48).max);
    }
}

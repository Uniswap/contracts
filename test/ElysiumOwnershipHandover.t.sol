// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ElysiumOwnershipHandover} from '../script/elysium/OwnershipHandover.s.sol';
import {Test} from 'forge-std/Test.sol';

/// @title Elysium ownership handover fork test
/// @notice Runs script/elysium/OwnershipHandover.s.sol against a fork of Elysium (chain 99901) while the deployer
///         still holds the five admin roles, with a stand-in receiver that exposes the same getters and immutables
///         as UniswapWormholeMessageReceiver.
///         The fork is pinned to a block before the handover so the test keeps reproducing after it. foundry.toml
///         skips *.t.sol, so override the skip list to compile it:
///           ELYSIUM_RPC_URL=<elysium-rpc> FOUNDRY_SKIP='["src/pkgs/**"]' forge test \
///             --match-path test/ElysiumOwnershipHandover.t.sol
interface IHolders {
    function feeToSetter() external view returns (address);
    function owner() external view returns (address);
    function setFeeToSetter(address) external;
    function setOwner(address) external;
    function transferOwnership(address) external;
}

/// @notice Mirrors the public surface and immutable layout of UniswapWormholeMessageReceiver
contract MockWormholeReceiver {
    uint16 public constant ETHEREUM_CHAIN_ID = 2;
    bytes32 public immutable messageSender;
    uint16 public immutable chainId;
    address private immutable wormhole;

    constructor(address wormholeAddress, bytes32 _messageSender, uint16 _chainId) {
        wormhole = wormholeAddress;
        messageSender = _messageSender;
        chainId = _chainId;
    }

    /// @dev reads the immutable so it lands in the runtime code, as receiveMessage does in the real receiver
    function wormholeIsSet() external view returns (bool) {
        return wormhole != address(0);
    }
}

contract ElysiumOwnershipHandoverTest is Test {
    uint256 constant CHAIN_ID = 99_901;
    uint256 constant PRE_HANDOVER_BLOCK = 1_099_800;
    address constant DEPLOYER = 0x2179a60856E37dfeAacA0ab043B931fE224b27B6;
    address constant WORMHOLE_CORE = 0xC8aD24fC6063c41cB5C12a8e3851AafC3b3CF027;
    bytes32 constant MESSAGE_SENDER = bytes32(uint256(uint160(0xf5F4496219F31CDCBa6130B5402873624585615a)));

    address constant V2_FACTORY = 0xBbBcC62853a5fA27b93d6Bab3E6F7ce841E25Df2;
    address constant V3_FACTORY = 0x1707327F626496A7b5b3872e7E4d2879Df7d7a9f;
    address constant POOL_MANAGER = 0xE2e105d3F7209A9DA11f83cCf3E7398a753823F1;
    address constant V3_NFT_DESCRIPTOR_PROXY = 0x661E93cca42AfacB172121EF892830cA3b70F08d;
    bytes32 constant ERC1967_ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;
    address constant V3_NFT_DESCRIPTOR_PROXY_ADMIN = 0x740eE255852f114b18B9B94aE754Ae6f8413897d;
    address constant V4_POSITION_DESCRIPTOR_PROXY_ADMIN = 0x031B9Eb5d9E5610f57b095C1003346b9928e1566;

    ElysiumOwnershipHandover handoverScript;
    address receiver;

    function setUp() public {
        vm.createSelectFork(vm.envString('ELYSIUM_RPC_URL'), PRE_HANDOVER_BLOCK);
        require(block.chainid == CHAIN_ID, 'ELYSIUM_RPC_URL is not Elysium (chain 99901)');
        require(IHolders(V2_FACTORY).feeToSetter() == DEPLOYER, 'fork must predate the handover');
        handoverScript = new ElysiumOwnershipHandover();
        receiver = address(new MockWormholeReceiver(WORMHOLE_CORE, MESSAGE_SENDER, 74));
    }

    function test_handover_handsAllFiveRolesToReceiver() public {
        handoverScript.handover(receiver);
        _assertHolders(receiver);
    }

    function test_handover_secondRunIsNoOp() public {
        handoverScript.handover(receiver);
        vm.recordLogs();
        handoverScript.handover(receiver);
        // the second run broadcasts nothing, so no OwnershipTransferred-style events are emitted
        assertEq(vm.getRecordedLogs().length, 0, 'second run emitted events');
        _assertHolders(receiver);
    }

    function test_handover_skipsRolesAlreadyHeldByReceiver() public {
        vm.prank(DEPLOYER);
        IHolders(V3_FACTORY).setOwner(receiver);
        handoverScript.handover(receiver);
        _assertHolders(receiver);
    }

    function test_handover_revertsOnUnexpectedHolderBeforeAnyTransfer() public {
        // the stranger holds the last role, so a send-then-check bug would have four transfers to leak
        address stranger = makeAddr('stranger');
        vm.prank(DEPLOYER);
        IHolders(V4_POSITION_DESCRIPTOR_PROXY_ADMIN).transferOwnership(stranger);

        vm.expectCall(V2_FACTORY, abi.encodeCall(IHolders.setFeeToSetter, (receiver)), 0);
        vm.expectCall(V3_FACTORY, abi.encodeCall(IHolders.setOwner, (receiver)), 0);
        vm.expectCall(POOL_MANAGER, abi.encodeCall(IHolders.transferOwnership, (receiver)), 0);
        vm.expectCall(V3_NFT_DESCRIPTOR_PROXY_ADMIN, abi.encodeCall(IHolders.transferOwnership, (receiver)), 0);
        vm.expectRevert(
            bytes(string.concat('Unexpected holder of v4 PositionDescriptor ProxyAdmin owner: ', vm.toString(stranger)))
        );
        handoverScript.handover(receiver);
    }

    function test_handover_revertsOnReceiverWithWrongChainId() public {
        address bad = address(new MockWormholeReceiver(WORMHOLE_CORE, MESSAGE_SENDER, 47));
        vm.expectRevert(bytes('Receiver chainId is not 74'));
        handoverScript.handover(bad);
    }

    function test_handover_revertsOnReceiverWithWrongSender() public {
        address bad = address(new MockWormholeReceiver(WORMHOLE_CORE, bytes32(uint256(1)), 74));
        vm.expectRevert(bytes('Receiver messageSender is not the Ethereum sender'));
        handoverScript.handover(bad);
    }

    function test_handover_revertsOnReceiverWithWrongWormholeCore() public {
        address bad = address(new MockWormholeReceiver(makeAddr('otherCore'), MESSAGE_SENDER, 74));
        vm.expectRevert(bytes('Receiver is not bound to the Elysium Wormhole core'));
        handoverScript.handover(bad);
    }

    function test_handover_revertsOnReceiverWithoutCode() public {
        address bad = makeAddr('eoa');
        vm.expectRevert(bytes('Receiver has no code'));
        handoverScript.handover(bad);
    }

    function test_handover_revertsOnZeroOrDeployerReceiver() public {
        vm.expectRevert(bytes('Receiver is zero or the deployer'));
        handoverScript.handover(address(0));

        vm.expectRevert(bytes('Receiver is zero or the deployer'));
        handoverScript.handover(DEPLOYER);
    }

    function test_handover_revertsOnProxyAdminMismatch() public {
        vm.store(V3_NFT_DESCRIPTOR_PROXY, ERC1967_ADMIN_SLOT, bytes32(uint256(uint160(makeAddr('otherAdmin')))));
        vm.expectRevert(bytes(string.concat('ProxyAdmin mismatch for proxy ', vm.toString(V3_NFT_DESCRIPTOR_PROXY))));
        handoverScript.handover(receiver);
    }

    function test_handover_revertsOnWormholeCoreWithWrongChainId() public {
        vm.mockCall(WORMHOLE_CORE, abi.encodeWithSignature('chainId()'), abi.encode(uint16(47)));
        vm.expectRevert(bytes('Wormhole core chainId is not 74'));
        handoverScript.handover(receiver);
    }

    function test_handover_revertsOnUnreadableHolder() public {
        vm.mockCallRevert(POOL_MANAGER, abi.encodeWithSignature('owner()'), '');
        vm.expectRevert(bytes('Cannot read holder of v4 PoolManager owner'));
        handoverScript.handover(receiver);
    }

    function test_printCalldataFor_passesPreChecks() public view {
        handoverScript.printCalldataFor(receiver);
    }

    function _assertHolders(address expected) internal view {
        assertEq(IHolders(V2_FACTORY).feeToSetter(), expected, 'v2 feeToSetter');
        assertEq(IHolders(V3_FACTORY).owner(), expected, 'v3 owner');
        assertEq(IHolders(POOL_MANAGER).owner(), expected, 'v4 PoolManager owner');
        assertEq(IHolders(V3_NFT_DESCRIPTOR_PROXY_ADMIN).owner(), expected, 'v3 descriptor ProxyAdmin owner');
        assertEq(IHolders(V4_POSITION_DESCRIPTOR_PROXY_ADMIN).owner(), expected, 'v4 descriptor ProxyAdmin owner');
    }
}

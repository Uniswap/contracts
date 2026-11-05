// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2 as console} from 'forge-std/Script.sol';

interface IV2Factory {
    function feeToSetter() external view returns (address);
    function setFeeToSetter(address) external;
}

interface IV3Factory {
    function owner() external view returns (address);
    function setOwner(address) external;
}

interface IOwnable {
    function owner() external view returns (address);
    function transferOwnership(address) external;
}

interface IUniswapWormholeMessageReceiver {
    function messageSender() external view returns (bytes32);
    function chainId() external view returns (uint16);
    function ETHEREUM_CHAIN_ID() external view returns (uint16);
}

interface IWormholeCore {
    function chainId() external view returns (uint16);
}

/// @title Elysium ownership handover
/// @notice Moves the five admin roles of the Elysium (chain 99901) deployment from the deployer to the Uniswap
///         governance UniswapWormholeMessageReceiver. Every transfer is single step and irreversible, so the script
///         checks everything before sending anything:
///           - the receiver has code, trusts the canonical Ethereum UniswapWormholeMessageSender, accepts Wormhole
///             chain id 74 (Elysium) and is bound to the Elysium Wormhole core
///           - each descriptor ProxyAdmin still matches the ERC1967 admin slot of its proxy
///           - each role is held by the deployer (pending) or already by the receiver (skipped); any other holder
///             aborts the run before the first transaction
///         and after broadcasting asserts that the receiver holds all five roles. A second run is a no-op.
///
///         Roles:
///           v2 Factory                  setFeeToSetter(receiver)
///           v3 Factory                  setOwner(receiver)
///           v4 PoolManager              transferOwnership(receiver)
///           v3 NFT descriptor ProxyAdmin transferOwnership(receiver)
///           v4 PositionDescriptor ProxyAdmin transferOwnership(receiver)
///
///         Usage (GOVERNANCE_RECEIVER is the deployed UniswapWormholeMessageReceiver on Elysium):
///           Simulate:  GOVERNANCE_RECEIVER=<receiver> forge script script/elysium/OwnershipHandover.s.sol \
///                        --rpc-url <elysium-rpc> --sender 0x2179a60856E37dfeAacA0ab043B931fE224b27B6
///           Broadcast: add --broadcast --legacy and the deployer signer (e.g. --account <keystore>)
///           Manual:    GOVERNANCE_RECEIVER=<receiver> forge script script/elysium/OwnershipHandover.s.sol \
///                        --rpc-url <elysium-rpc> --sig 'printCalldata()'
contract ElysiumOwnershipHandover is Script {
    struct Role {
        string name;
        address target;
        /// @dev view getter returning the current holder of the role
        bytes4 getter;
        /// @dev call that hands the role to the receiver
        bytes data;
    }

    uint256 internal constant ELYSIUM_CHAIN_ID = 99_901;

    /// @dev deployer of the Elysium Deploy-all broadcast and current holder of every role
    address internal constant EXPECTED_DEPLOYER = 0x2179a60856E37dfeAacA0ab043B931fE224b27B6;

    // Deploy-all broadcast on Elysium, verified on the Elysium Blockscout explorer
    address internal constant V2_FACTORY = 0xBbBcC62853a5fA27b93d6Bab3E6F7ce841E25Df2;
    address internal constant V3_FACTORY = 0x1707327F626496A7b5b3872e7E4d2879Df7d7a9f;
    address internal constant POOL_MANAGER = 0xE2e105d3F7209A9DA11f83cCf3E7398a753823F1;
    address internal constant V3_NFT_DESCRIPTOR_PROXY = 0x661E93cca42AfacB172121EF892830cA3b70F08d;
    address internal constant V4_POSITION_DESCRIPTOR_PROXY = 0x9f92C5297EB3b39E6804b5e03899bC66B6b77348;

    // OpenZeppelin 5.0.0 ProxyAdmins created by the descriptor proxies, read from their ERC1967 admin slots
    address internal constant V3_NFT_DESCRIPTOR_PROXY_ADMIN = 0x740eE255852f114b18B9B94aE754Ae6f8413897d;
    address internal constant V4_POSITION_DESCRIPTOR_PROXY_ADMIN = 0x031B9Eb5d9E5610f57b095C1003346b9928e1566;

    /// @dev bytes32(uint256(keccak256('eip1967.proxy.admin')) - 1)
    bytes32 internal constant ERC1967_ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    /// @dev Wormhole core bridge on Elysium
    address internal constant WORMHOLE_CORE = 0xC8aD24fC6063c41cB5C12a8e3851AafC3b3CF027;
    uint16 internal constant WORMHOLE_ELYSIUM_CHAIN_ID = 74;
    uint16 internal constant WORMHOLE_ETHEREUM_CHAIN_ID = 2;

    /// @dev UniswapWormholeMessageSender on Ethereum (called by the Uniswap Timelock), in Wormhole format
    bytes32 internal constant MESSAGE_SENDER = bytes32(uint256(uint160(0xf5F4496219F31CDCBa6130B5402873624585615a)));

    function run() public {
        address receiver = vm.envAddress('GOVERNANCE_RECEIVER');
        _preflight(receiver);

        Role[] memory roles = _roles(receiver);
        bool[] memory pending = _pendingRoles(roles, receiver);

        uint256 count;
        for (uint256 i; i < roles.length; i++) {
            if (pending[i]) count++;
        }

        if (count == 0) {
            console.log('Nothing to do: the receiver already holds every role');
        } else {
            vm.startBroadcast(EXPECTED_DEPLOYER);
            for (uint256 i; i < roles.length; i++) {
                if (!pending[i]) continue;
                (bool ok,) = roles[i].target.call(roles[i].data);
                require(ok, string.concat('Transfer failed: ', roles[i].name));
                console.log('Transferred:', roles[i].name);
            }
            vm.stopBroadcast();
        }

        _assertHandedOver(roles, receiver);
        console.log('All five roles are held by the receiver:', receiver);
    }

    /// @notice Prints target and calldata for every role still held by the deployer, for sending by hand
    ///         (e.g. `cast send <target> <calldata>` from the deployer). Runs the same checks as `run()`.
    function printCalldata() public view {
        address receiver = vm.envAddress('GOVERNANCE_RECEIVER');
        _preflight(receiver);

        Role[] memory roles = _roles(receiver);
        bool[] memory pending = _pendingRoles(roles, receiver);

        console.log('From:', EXPECTED_DEPLOYER);
        for (uint256 i; i < roles.length; i++) {
            if (!pending[i]) continue;
            console.log('');
            console.log(roles[i].name);
            console.log('  to:  ', roles[i].target);
            console.log('  data:', vm.toString(roles[i].data));
        }
    }

    /// @notice Chain, receiver and ProxyAdmin checks shared by `run()` and `printCalldata()`
    function _preflight(address receiver) internal view {
        require(block.chainid == ELYSIUM_CHAIN_ID, 'Not Elysium');
        _checkReceiver(receiver);
        _checkProxyAdmin(V3_NFT_DESCRIPTOR_PROXY, V3_NFT_DESCRIPTOR_PROXY_ADMIN);
        _checkProxyAdmin(V4_POSITION_DESCRIPTOR_PROXY, V4_POSITION_DESCRIPTOR_PROXY_ADMIN);
        console.log('Chain:', block.chainid);
        console.log('Receiver:', receiver);
    }

    /// @notice Rejects any receiver that could not execute governance proposals on Elysium
    function _checkReceiver(address receiver) internal view {
        require(receiver != address(0) && receiver != EXPECTED_DEPLOYER, 'Receiver is zero or the deployer');
        require(receiver.code.length > 0, 'Receiver has no code');

        IUniswapWormholeMessageReceiver r = IUniswapWormholeMessageReceiver(receiver);
        require(r.messageSender() == MESSAGE_SENDER, 'Receiver messageSender is not the Ethereum sender');
        require(r.chainId() == WORMHOLE_ELYSIUM_CHAIN_ID, 'Receiver chainId is not 74');
        require(r.ETHEREUM_CHAIN_ID() == WORMHOLE_ETHEREUM_CHAIN_ID, 'Receiver ETHEREUM_CHAIN_ID is not 2');

        // the receiver keeps its Wormhole core in a private immutable, so look for it in the runtime code
        require(IWormholeCore(WORMHOLE_CORE).chainId() == WORMHOLE_ELYSIUM_CHAIN_ID, 'Wormhole core chainId is not 74');
        require(
            _codeContainsWord(receiver.code, bytes32(uint256(uint160(WORMHOLE_CORE)))),
            'Receiver is not bound to the Elysium Wormhole core'
        );
    }

    function _checkProxyAdmin(address proxy, address expectedAdmin) internal view {
        address admin = address(uint160(uint256(vm.load(proxy, ERC1967_ADMIN_SLOT))));
        require(admin == expectedAdmin, string.concat('ProxyAdmin mismatch for proxy ', vm.toString(proxy)));
    }

    /// @notice Marks each role held by the deployer as pending, skips roles the receiver holds, and aborts on
    ///         any other holder before a single transaction is sent
    function _pendingRoles(Role[] memory roles, address receiver) internal view returns (bool[] memory pending) {
        pending = new bool[](roles.length);
        for (uint256 i; i < roles.length; i++) {
            address holder = _holder(roles[i]);
            if (holder == receiver) {
                console.log('Already held by the receiver, skipping:', roles[i].name);
            } else if (holder == EXPECTED_DEPLOYER) {
                pending[i] = true;
                console.log('Pending:', roles[i].name);
            } else {
                revert(string.concat('Unexpected holder of ', roles[i].name, ': ', vm.toString(holder)));
            }
        }
    }

    function _assertHandedOver(Role[] memory roles, address receiver) internal view {
        for (uint256 i; i < roles.length; i++) {
            require(_holder(roles[i]) == receiver, string.concat('Not held by the receiver: ', roles[i].name));
        }
    }

    function _roles(address receiver) internal pure returns (Role[] memory roles) {
        roles = new Role[](5);
        roles[0] = Role({
            name: 'v2 Factory feeToSetter',
            target: V2_FACTORY,
            getter: IV2Factory.feeToSetter.selector,
            data: abi.encodeCall(IV2Factory.setFeeToSetter, (receiver))
        });
        roles[1] = Role({
            name: 'v3 Factory owner',
            target: V3_FACTORY,
            getter: IV3Factory.owner.selector,
            data: abi.encodeCall(IV3Factory.setOwner, (receiver))
        });
        roles[2] = Role({
            name: 'v4 PoolManager owner',
            target: POOL_MANAGER,
            getter: IOwnable.owner.selector,
            data: abi.encodeCall(IOwnable.transferOwnership, (receiver))
        });
        roles[3] = Role({
            name: 'v3 NFT descriptor ProxyAdmin owner',
            target: V3_NFT_DESCRIPTOR_PROXY_ADMIN,
            getter: IOwnable.owner.selector,
            data: abi.encodeCall(IOwnable.transferOwnership, (receiver))
        });
        roles[4] = Role({
            name: 'v4 PositionDescriptor ProxyAdmin owner',
            target: V4_POSITION_DESCRIPTOR_PROXY_ADMIN,
            getter: IOwnable.owner.selector,
            data: abi.encodeCall(IOwnable.transferOwnership, (receiver))
        });
    }

    function _holder(Role memory role) internal view returns (address) {
        (bool ok, bytes memory ret) = role.target.staticcall(abi.encodeWithSelector(role.getter));
        require(ok && ret.length == 32, string.concat('Cannot read holder of ', role.name));
        return abi.decode(ret, (address));
    }

    function _codeContainsWord(bytes memory code, bytes32 word) internal pure returns (bool) {
        if (code.length < 32) return false;
        for (uint256 i; i <= code.length - 32; i++) {
            bytes32 chunk;
            // reads 32 bytes starting at offset i; i + 32 <= code.length keeps the read inside the array
            assembly ('memory-safe') {
                chunk := mload(add(add(code, 32), i))
            }
            if (chunk == word) return true;
        }
        return false;
    }
}

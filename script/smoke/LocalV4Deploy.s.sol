// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2 as console} from 'forge-std/Script.sol';

/// @notice Minimal mintable ERC-20 for local testing (configurable decimals).
contract FakeToken {
    string public name;
    string public symbol;
    uint8 public decimals;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(string memory n, string memory s, uint8 d) {
        name = n;
        symbol = s;
        decimals = d;
    }

    function mint(address to, uint256 a) external {
        balanceOf[to] += a;
        totalSupply += a;
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

/// @notice Stands up a full local v4 stack + two fake stablecoins, then writes a deployments JSON
///         (chain 31337) in the exact shape SeedStablePoolV4 reads.
/// @dev The v4 contracts pin solc 0.8.26/cancun and Permit2 pins 0.8.17, which conflict with each other
///      and with this script. We sidestep all of it by deploying every protocol contract from its
///      PRECOMPILED bytecode (out/*.json) via vm.getCode, so no protocol source enters this compile unit.
contract LocalV4Deploy is Script {
    uint256 constant UNSUBSCRIBE_GAS_LIMIT = 100_000;

    function run() public {
        vm.startBroadcast();
        address me = msg.sender;

        // Reference artifacts by their out/ path so vm.getCode reads them from disk directly. This works
        // even when these packages are excluded from the script build via --skip (needed to dodge the
        // permit2/v4 solc-version conflict in a full-project compile).
        address permit2 = _deploy(vm.getCode('out/Permit2.sol/Permit2.json'));
        address poolManager =
            _deploy(bytes.concat(vm.getCode('out/PoolManager.sol/PoolManager.json'), abi.encode(me)));
        address positionManager = _deploy(
            bytes.concat(
                vm.getCode('out/PositionManager.sol/PositionManager.json'),
                abi.encode(poolManager, permit2, UNSUBSCRIBE_GAS_LIMIT, address(0), address(0))
            )
        );
        address stateView =
            _deploy(bytes.concat(vm.getCode('out/StateView.sol/StateView.json'), abi.encode(poolManager)));

        // Fake stablecoins (6 decimals, like USDC/EURC). "Worth" is set later via the seed script's prices.
        FakeToken abc = new FakeToken('ABC Dollar', 'ABC', 6);
        FakeToken bbc = new FakeToken('BBC Krona', 'BBC', 6);
        abc.mint(me, 1_000_000e6);
        bbc.mint(me, 1_000_000e6);

        vm.stopBroadcast();

        console.log('Permit2:', permit2);
        console.log('PoolManager:', poolManager);
        console.log('PositionManager:', positionManager);
        console.log('StateView:', stateView);
        console.log('ABC ($1.00):', address(abc));
        console.log('BBC ($0.95):', address(bbc));
    }

    function _deploy(bytes memory initcode) internal returns (address addr) {
        assembly {
            addr := create(0, add(initcode, 0x20), mload(initcode))
        }
        require(addr != address(0), 'deploy failed');
    }
}

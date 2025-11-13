// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {WETHHookDeployer} from '../src/briefcase/deployers/v4-periphery/WETHHookDeployer.sol';
import {Hooks} from '../src/briefcase/protocols/v4-core/libraries/Hooks.sol';
import {HookMiner} from '../src/briefcase/protocols/v4-periphery/utils/HookMiner.sol';
import {Script} from 'forge-std/Script.sol';
import {stdJson} from 'forge-std/StdJson.sol';
import {console} from 'forge-std/console.sol';

/// @title Mine WETH Hook Salt
/// @notice Script to mine a valid salt for WETHHook deployment
contract MineWETHHookSalt is Script {
    using stdJson for string;

    // CREATE2 Deployer Proxy address
    address constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    function run() public view {
        // Get chainId from environment
        uint256 chainId = vm.envUint('HOOKMINER_CHAINID');
        console.log('Mining salt for chain:', chainId);

        // Read task-pending.json for the chainId
        string memory taskPath = string.concat('./script/deploy/tasks/', vm.toString(chainId), '/task-pending.json');
        string memory json = vm.readFile(taskPath);

        // Parse parameters from JSON
        address poolManager = json.readAddress('.protocols.v4.contracts.PoolManager.address');
        address weth = json.readAddress('.dependencies.weth.value');

        console.log('Using PoolManager:', poolManager);
        console.log('Using WETH:', weth);

        // Required permissions for WETHHook:
        // - beforeInitialize: true (bit 0)
        // - beforeAddLiquidity: true (bit 2)
        // - beforeSwap: true (bit 6)
        // - beforeSwapReturnDelta: true (bit 7)
        uint160 flags = uint160(
            Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_SWAP_FLAG
                | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
        );

        console.log('Mining salt for flags:', flags);
        console.log('Flags in hex:', vm.toString(abi.encodePacked(flags)));

        // Get creation code from WETHHookDeployer
        bytes memory creationCode = WETHHookDeployer.initcode();

        // Constructor args: (IPoolManager _manager, address payable _weth)
        bytes memory constructorArgs = abi.encode(poolManager, weth);

        (address hookAddress, bytes32 salt) = HookMiner.find(CREATE2_DEPLOYER, flags, creationCode, constructorArgs);

        console.log('');
        console.log('========================================');
        console.log('Success!');
        console.log('========================================');
        console.log('Hook address:', hookAddress);
        console.log('Salt (decimal):', vm.toString(uint256(salt)));
        console.log('Salt (hex):', vm.toString(abi.encodePacked(salt)));
        console.log('');
        console.log('Update task-pending.json with:');
        console.log('  "value": "%s"', vm.toString(abi.encodePacked(salt)));
    }
}

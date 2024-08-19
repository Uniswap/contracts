// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IPoolManager, V4Deployer} from '../../../src/main/deployers/V4Deployer.sol';
import {Script, console2 as console, stdJson} from 'forge-std/Script.sol';

contract Test {}

contract Deploy is Script {
    using stdJson for string;

    function run() public returns (IPoolManager poolManager) {
        uint256 deployerPrivateKey = vm.envUint('PRIVATE_KEY');
        string memory input = vm.readFile('./script/deploy/v4-core/input.json');
        string memory chainIdInput = string(abi.encodePacked('["', vm.toString(block.chainid), '"]'));

        uint256 controllerGasLimit = input.readUint(string.concat(chainIdInput, '.controllerGasLimit'));

        vm.startBroadcast(deployerPrivateKey);

        poolManager = V4Deployer.deployPoolManager(controllerGasLimit);

        vm.stopBroadcast();
    }
}

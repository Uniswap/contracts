// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console2 as console, stdJson} from 'forge-std/Script.sol';

contract Test {}

contract Deploy is Script {
    using stdJson for string;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint('PRIVATE_KEY');
        string memory input = vm.readFile('./script/deploy/v4-core/input.json');
        string memory chainIdInput = string(abi.encodePacked('["', vm.toString(block.chainid), '"]'));

        uint256 controllerGasLimit = input.readUint(string.concat(chainIdInput, '.controllerGasLimit'));

        vm.startBroadcast(deployerPrivateKey);

        address poolManager = deployV4PoolManager(controllerGasLimit);

        vm.stopBroadcast();
    }

    function deployV4PoolManager(uint256 _controllerGasLimit) internal returns (address poolManager) {
        bytes memory args = abi.encode(_controllerGasLimit);
        bytes memory bytecode = abi.encodePacked(vm.getCode('out/PoolManager.sol/PoolManager.json'), args);
        assembly {
            poolManager := create(0, add(bytecode, 32), mload(bytecode))
        }
    }
}

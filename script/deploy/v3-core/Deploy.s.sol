// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console2 as console, stdJson} from 'forge-std/Script.sol';

contract Test {}

contract Deploy is Script {
    using stdJson for string;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint('PRIVATE_KEY');
        string memory input = vm.readFile('./script/deploy/v3-core/input.json');
        string memory chainIdInput = string(abi.encodePacked('["', vm.toString(block.chainid), '"]'));

        vm.startBroadcast(deployerPrivateKey);

        address factory = deployV3Factory();

        vm.stopBroadcast();
    }

    function deployV3Factory() internal returns (address factory) {
        bytes memory bytecode = abi.encodePacked(vm.getCode('out/UniswapV3Factory.sol/UniswapV3Factory.json'));
        assembly {
            factory := create(0, add(bytecode, 32), mload(bytecode))
        }
    }
}

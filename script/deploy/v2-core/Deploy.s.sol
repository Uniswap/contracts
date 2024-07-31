// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console2 as console, stdJson} from 'forge-std/Script.sol';

contract Test {}

contract Deploy is Script {
    using stdJson for string;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint('PRIVATE_KEY');
        string memory input = vm.readFile('script/deploy/v2-core/input.json');
        string memory chainIdInput = string(abi.encodePacked('["', vm.toString(block.chainid), '"]'));

        address feeToSetter = input.readAddress(string.concat(chainIdInput, '.feeToSetter'));

        vm.startBroadcast(deployerPrivateKey);

        address factory = deployV2Factory(feeToSetter);

        vm.stopBroadcast();
    }

    function deployV2Factory(address _feeToSetter) internal returns (address factory) {
        bytes memory args = abi.encode(_feeToSetter);
        bytes memory bytecode = abi.encodePacked(vm.getCode('out/UniswapV2Factory.sol/UniswapV2Factory.json'), args);
        assembly {
            factory := create(0, add(bytecode, 32), mload(bytecode))
        }
    }
}

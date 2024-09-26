// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IUniswapV2Factory, V2Deployer} from '../../../src/deployers/V2Deployer.sol';
import {Script, console2 as console, stdJson} from 'forge-std/Script.sol';

contract Deploy is Script {
    using stdJson for string;

    function run() public returns (IUniswapV2Factory factory) {
        uint256 deployerPrivateKey = vm.envUint('PRIVATE_KEY');
        string memory input = vm.readFile('./script/deploy/v2-core/input.json');
        string memory chainIdInput = string(abi.encodePacked('["', vm.toString(block.chainid), '"]'));

        address feeToSetter = input.readAddress(string.concat(chainIdInput, '.feeToSetter'));

        vm.startBroadcast(deployerPrivateKey);

        factory = V2Deployer.deployUniswapV2Factory(feeToSetter);

        vm.stopBroadcast();
    }
}

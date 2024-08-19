// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import {IUniswapV3Factory, V3Deployer} from '../../../src/main/deployers/V3Deployer.sol';
import {Script, console2 as console, stdJson} from 'forge-std/Script.sol';

contract Test {}

contract Deploy is Script {
    using stdJson for string;

    function run() public returns (IUniswapV3Factory factory) {
        uint256 deployerPrivateKey = vm.envUint('PRIVATE_KEY');
        string memory input = vm.readFile('./script/deploy/v3-core/input.json');
        uint256 id;
        assembly {
            id := chainid()
        }
        string memory chainIdInput = string(abi.encodePacked('["', vm.toString(id), '"]'));

        vm.startBroadcast(deployerPrivateKey);

        factory = V3Deployer.deployUniswapV3Factory();

        vm.stopBroadcast();
    }
}

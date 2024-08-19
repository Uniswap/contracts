// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IUniswapV2Router01, IUniswapV2Router02, V2Deployer} from '../../../src/main/deployers/V2Deployer.sol';
import {Script, console2 as console, stdJson} from 'forge-std/Script.sol';

contract Test {}

contract Deploy is Script {
    using stdJson for string;

    function run() public returns (IUniswapV2Router01 router01, IUniswapV2Router02 router02) {
        uint256 deployerPrivateKey = vm.envUint('PRIVATE_KEY');
        string memory input = vm.readFile('./script/deploy/v2-periphery/input.json');
        string memory chainIdInput = string(abi.encodePacked('["', vm.toString(block.chainid), '"]'));

        address v2Factory = input.readAddress(string.concat(chainIdInput, '.V2Factory'));
        address weth = input.readAddress(string.concat(chainIdInput, '.WETH'));

        vm.startBroadcast(deployerPrivateKey);

        router01 = V2Deployer.deployUniswapV2Router01(v2Factory, weth);
        router02 = V2Deployer.deployUniswapV2Router02(v2Factory, weth);

        vm.stopBroadcast();
    }
}

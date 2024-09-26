// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import {INonfungiblePositionManager, ISwapRouter, V3Deployer} from '../../../src/deployers/V3Deployer.sol';
import {Script, console2 as console, stdJson} from 'forge-std/Script.sol';

contract Test {}

contract Deploy is Script {
    using stdJson for string;

    function run() public returns (ISwapRouter swapRouter, INonfungiblePositionManager positionManager) {
        uint256 deployerPrivateKey = vm.envUint('PRIVATE_KEY');
        string memory input = vm.readFile('./script/deploy/v3-periphery/input.json');
        uint256 id;
        assembly {
            id := chainid()
        }
        string memory chainIdInput = string(abi.encodePacked('["', vm.toString(id), '"]'));

        address v3Factory = input.readAddress(string(abi.encodePacked(chainIdInput, '.V3Factory')));
        address weth9 = input.readAddress(string(abi.encodePacked(chainIdInput, '.WETH9')));
        address tokenDescriptor = input.readAddress(string(abi.encodePacked(chainIdInput, '.TokenDescriptor')));

        vm.startBroadcast(deployerPrivateKey);

        swapRouter = V3Deployer.deploySwapRouter(v3Factory, weth9);
        positionManager = V3Deployer.deployNonfungiblePositionManager(v3Factory, weth9, tokenDescriptor);

        vm.stopBroadcast();
    }
}

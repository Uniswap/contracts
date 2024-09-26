// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IPositionManager, IQuoter, V4Deployer} from '../../../src/deployers/V4Deployer.sol';
import {Script, console2 as console, stdJson} from 'forge-std/Script.sol';

contract Test {}

contract Deploy is Script {
    using stdJson for string;

    function run() public returns (IPositionManager positionManager, IQuoter quoter) {
        uint256 deployerPrivateKey = vm.envUint('PRIVATE_KEY');
        string memory input = vm.readFile('./script/deploy/v4-periphery/input.json');
        string memory chainIdInput = string(abi.encodePacked('["', vm.toString(block.chainid), '"]'));

        address poolManager = input.readAddress(string.concat(chainIdInput, '.PoolManager'));
        address permit2 = input.readAddress(string.concat(chainIdInput, '.Permit2'));

        vm.startBroadcast(deployerPrivateKey);

        positionManager = V4Deployer.deployPositionManager(poolManager, permit2);
        quoter = V4Deployer.deployQuoter(poolManager);

        vm.stopBroadcast();
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console2 as console, stdJson} from 'forge-std/Script.sol';

contract Test {}

contract Deploy is Script {
    using stdJson for string;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint('PRIVATE_KEY');
        string memory input = vm.readFile('./script/deploy/v3-periphery/input.json');
        string memory chainIdInput = string(abi.encodePacked('["', vm.toString(block.chainid), '"]'));

        address v3Factory = input.readAddress(string.concat(chainIdInput, '.V3Factory'));
        address weth9 = input.readAddress(string.concat(chainIdInput, '.WETH9'));
        address tokenDescriptor = input.readAddress(string.concat(chainIdInput, '.TokenDescriptor'));

        vm.startBroadcast(deployerPrivateKey);

        address swapRouter = deployV3SwapRouter(v3Factory, weth9);
        address positionMaager = deployV3PositionManager(v3Factory, weth9, tokenDescriptor);

        vm.stopBroadcast();
    }

    function deployV3PositionManager(address _v3Factory, address _weth9, address _tokenDescriptor)
        internal
        returns (address positionManager)
    {
        bytes memory args = abi.encode(_v3Factory, _weth9, _tokenDescriptor);
        bytes memory bytecode =
            abi.encodePacked(vm.getCode('out/NonfungiblePositionManager.sol/NonfungiblePositionManager.json'), args);
        assembly {
            positionManager := create(0, add(bytecode, 32), mload(bytecode))
        }
    }

    function deployV3SwapRouter(address _v3Factory, address _weth9) internal returns (address swapRouter) {
        bytes memory args = abi.encode(_v3Factory, _weth9);
        bytes memory bytecode = abi.encodePacked(vm.getCode('out/SwapRouter.sol/SwapRouter.json'), args);
        assembly {
            swapRouter := create(0, add(bytecode, 32), mload(bytecode))
        }
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console2 as console, stdJson} from 'forge-std/Script.sol';

contract Test {}

contract Deploy is Script {
    using stdJson for string;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint('PRIVATE_KEY');
        string memory input = vm.readFile('./script/deploy/v2-periphery/input.json');
        string memory chainIdInput = string(abi.encodePacked('["', vm.toString(block.chainid), '"]'));

        address v2Factory = input.readAddress(string.concat(chainIdInput, '.V2Factory'));
        address weth = input.readAddress(string.concat(chainIdInput, '.WETH'));

        vm.startBroadcast(deployerPrivateKey);

        address router01 = deployV2Router01(v2Factory, weth);
        address router02 = deployV2Router02(v2Factory, weth);

        vm.stopBroadcast();
    }

    function deployV2Router01(address _factory, address _WETH) internal returns (address router) {
        bytes memory args = abi.encode(_factory, _WETH);
        bytes memory bytecode = abi.encodePacked(vm.getCode('out/UniswapV2Router01.sol/UniswapV2Router01.json'), args);
        assembly {
            router := create(0, add(bytecode, 32), mload(bytecode))
        }
    }

    function deployV2Router02(address _factory, address _WETH) internal returns (address router) {
        bytes memory args = abi.encode(_factory, _WETH);
        bytes memory bytecode = abi.encodePacked(vm.getCode('out/UniswapV2Router02.sol/UniswapV2Router02.json'), args);
        assembly {
            router := create(0, add(bytecode, 32), mload(bytecode))
        }
    }
}

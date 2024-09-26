// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {IUniswapV2Factory} from '../pkgs/v2-core/contracts/interfaces/IUniswapV2Factory.sol';
import {IUniswapV2Router01} from '../pkgs/v2-periphery/contracts/interfaces/IUniswapV2Router01.sol';
import {IUniswapV2Router02} from '../pkgs/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol';
import {Vm} from 'forge-std/Vm.sol';

library V2Deployer {
    address constant VM_ADDRESS = address(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    function deployUniswapV2Factory(address _feeToSetter) internal returns (IUniswapV2Factory factory) {
        Vm vm = Vm(VM_ADDRESS);
        bytes memory args = abi.encode(_feeToSetter);
        bytes memory bytecode = abi.encodePacked(vm.getCode('out/UniswapV2Factory.sol/UniswapV2Factory.json'), args);
        assembly {
            factory := create(0, add(bytecode, 32), mload(bytecode))
        }
    }

    function deployUniswapV2Router01(address _factory, address _WETH) internal returns (IUniswapV2Router01 router) {
        Vm vm = Vm(VM_ADDRESS);
        bytes memory args = abi.encode(_factory, _WETH);
        bytes memory bytecode = abi.encodePacked(vm.getCode('out/UniswapV2Router01.sol/UniswapV2Router01.json'), args);
        assembly {
            router := create(0, add(bytecode, 32), mload(bytecode))
        }
    }

    function deployUniswapV2Router02(address _factory, address _WETH) internal returns (IUniswapV2Router02 router) {
        Vm vm = Vm(VM_ADDRESS);
        bytes memory args = abi.encode(_factory, _WETH);
        bytes memory bytecode = abi.encodePacked(vm.getCode('out/UniswapV2Router02.sol/UniswapV2Router02.json'), args);
        assembly {
            router := create(0, add(bytecode, 32), mload(bytecode))
        }
    }
}

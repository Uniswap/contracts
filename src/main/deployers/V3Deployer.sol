// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;

import {IUniswapV3Factory} from '../../pkgs/v3-core/contracts/interfaces/IUniswapV3Factory.sol';
import {INonfungiblePositionManager} from '../../pkgs/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol';
import {ISwapRouter} from '../../pkgs/v3-periphery/contracts/interfaces/ISwapRouter.sol';
import {Vm} from 'forge-std/Vm.sol';

library V3Deployer {
    address constant VM_ADDRESS = address(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    function deployUniswapV3Factory() internal returns (IUniswapV3Factory factory) {
        Vm vm = Vm(VM_ADDRESS);
        bytes memory bytecode = abi.encodePacked(vm.getCode('out/UniswapV3Factory.sol/UniswapV3Factory.json'));
        assembly {
            factory := create(0, add(bytecode, 32), mload(bytecode))
        }
    }

    function deployNonfungiblePositionManager(address _v3Factory, address _weth9, address _tokenDescriptor)
        internal
        returns (INonfungiblePositionManager positionManager)
    {
        Vm vm = Vm(VM_ADDRESS);
        bytes memory args = abi.encode(_v3Factory, _weth9, _tokenDescriptor);
        bytes memory bytecode =
            abi.encodePacked(vm.getCode('out/NonfungiblePositionManager.sol/NonfungiblePositionManager.json'), args);
        assembly {
            positionManager := create(0, add(bytecode, 32), mload(bytecode))
        }
    }

    function deploySwapRouter(address _v3Factory, address _weth9) internal returns (ISwapRouter swapRouter) {
        Vm vm = Vm(VM_ADDRESS);
        bytes memory args = abi.encode(_v3Factory, _weth9);
        bytes memory bytecode = abi.encodePacked(vm.getCode('out/SwapRouter.sol/SwapRouter.json'), args);
        assembly {
            swapRouter := create(0, add(bytecode, 32), mload(bytecode))
        }
    }
}

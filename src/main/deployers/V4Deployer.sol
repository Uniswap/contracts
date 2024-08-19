// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {IPermit2} from '../../pkgs/permit2/src/interfaces/IPermit2.sol';
import {IPoolManager} from '../../pkgs/v4-core/src/interfaces/IPoolManager.sol';
import {IPositionManager} from '../../pkgs/v4-periphery/src/interfaces/IPositionManager.sol';
import {IQuoter} from '../../pkgs/v4-periphery/src/interfaces/IQuoter.sol';
import {Vm} from 'forge-std/Vm.sol';

library V4Deployer {
    address constant VM_ADDRESS = address(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    function deployPoolManager(uint256 _controllerGasLimit) internal returns (IPoolManager poolManager) {
        Vm vm = Vm(VM_ADDRESS);
        bytes memory args = abi.encode(_controllerGasLimit);
        bytes memory bytecode = abi.encodePacked(vm.getCode('out/PoolManager.sol/PoolManager.json'), args);
        assembly {
            poolManager := create(0, add(bytecode, 32), mload(bytecode))
        }
    }

    function deployPositionManager(address poolManagerAddress, address permit2Address)
        internal
        returns (IPositionManager positionManager)
    {
        Vm vm = Vm(VM_ADDRESS);

        IPoolManager poolManager = IPoolManager(poolManagerAddress);
        IPermit2 permit2 = IPermit2(permit2Address);
        bytes memory args = abi.encode(poolManager, permit2);
        bytes memory bytecode = abi.encodePacked(vm.getCode('out/PositionManager.sol/PositionManager.json'), args);
        assembly {
            positionManager := create(0, add(bytecode, 32), mload(bytecode))
        }
    }

    function deployQuoter(address poolManagerAddress) internal returns (IQuoter quoter) {
        Vm vm = Vm(VM_ADDRESS);

        IPoolManager poolManager = IPoolManager(poolManagerAddress);
        bytes memory args = abi.encode(poolManager);
        bytes memory bytecode = abi.encodePacked(vm.getCode('out/Quoter.sol/Quoter.json'), args);
        assembly {
            quoter := create(0, add(bytecode, 32), mload(bytecode))
        }
    }
}

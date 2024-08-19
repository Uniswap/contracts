// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {IPermit2} from '../../pkgs/permit2/src/interfaces/IPermit2.sol';
import {IUniversalRouter} from '../../pkgs/universal-router/contracts/interfaces/IUniversalRouter.sol';
import {Vm} from 'forge-std/Vm.sol';

library V4Deployer {
    address constant VM_ADDRESS = address(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    function deployPermit2() internal returns (IPermit2 permit2) {
        Vm vm = Vm(VM_ADDRESS);
        bytes memory bytecode = abi.encodePacked(vm.getCode('out/PoolManager.sol/PoolManager.json'));
        assembly {
            permit2 := create(0, add(bytecode, 32), mload(bytecode))
        }
    }

    function deployUniversalRouter() internal returns (IUniversalRouter universalRouter) {
        Vm vm = Vm(VM_ADDRESS);
        bytes memory args = abi.encode();
        bytes memory bytecode = abi.encodePacked(vm.getCode('out/UniversalRouter.sol/UniversalRouter.json'), args);
        assembly {
            universalRouter := create(0, add(bytecode, 32), mload(bytecode))
        }
    }
}

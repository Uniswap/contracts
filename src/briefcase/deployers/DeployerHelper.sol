// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0;

library DeployerHelper {
    function create(bytes memory initcode) internal returns (address contractAddress) {
        assembly {
            contractAddress := create(0, add(initcode, 32), mload(initcode))
            if iszero(contractAddress) {
                let ptr := mload(0x40)
                let errorSize := returndatasize()
                returndatacopy(ptr, 0, errorSize)
                revert(ptr, errorSize)
            }
        }
    }

    function create2(bytes memory initcode, bytes32 salt) internal returns (address contractAddress) {
        assembly {
            contractAddress := create2(0, add(initcode, 32), mload(initcode), salt)
            if iszero(contractAddress) {
                let ptr := mload(0x40)
                let errorSize := returndatasize()
                returndatacopy(ptr, 0, errorSize)
                revert(ptr, errorSize)
            }
        }
    }

    function create2(bytes memory initcode) internal returns (address contractAddress) {
        return create2(initcode, hex'00');
    }
}

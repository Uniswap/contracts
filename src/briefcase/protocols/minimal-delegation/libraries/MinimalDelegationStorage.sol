// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {EnumerableSetLib} from '../../lib-external/solady/src/utils/EnumerableSetLib.sol';

/// @custom:storage-location erc7201:Uniswap.MinimalDelegation.1.0.0
struct MinimalDelegationStorage {
    EnumerableSetLib.Bytes32Set keyHashes;
    mapping(bytes32 keyHash => bytes encodedKey) keyStorage;
    address entryPoint;
}

library MinimalDelegationStorageLib {
    /// @dev keccak256(abi.encode(uint256(keccak256("Uniswap.MinimalDelegation.1.0.0")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant MINIMAL_DELEGATION_STORAGE_LOCATION =
        0xc807f46cbe2302f9a007e47db23c8af6a94680c1d26280fb9582873dbe5c9200;

    function namespaceAndVersion() external pure returns (string memory) {
        return 'Uniswap.MinimalDelegation.1.0.0';
    }

    function get() internal pure returns (MinimalDelegationStorage storage $) {
        assembly {
            $.slot := MINIMAL_DELEGATION_STORAGE_LOCATION
        }
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/// @title PrefixedSaltLib
/// @notice A library for packing and updating the salt with a prefix for EIP-712 domain separators
library PrefixedSaltLib {
    /// @notice Pack the prefix and implementation address into a bytes32
    function pack(uint96 prefix, address implementation) internal pure returns (bytes32) {
        return bytes32((uint256(prefix) << 160) | uint160(implementation));
    }
}

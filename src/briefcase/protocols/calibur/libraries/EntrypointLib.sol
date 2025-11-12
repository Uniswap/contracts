// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/// @title EntrypointLib
/// @dev This library is used to dirty the most significant bit of the cached entrypoint
/// to indicate that the entrypoint has been overriden by the account
library EntrypointLib {
    uint256 internal constant ENTRY_POINT_OVERRIDDEN = 1 << 255;

    /// @notice Packs the entry point into a uint256.
    function pack(address entrypoint) internal pure returns (uint256) {
        return uint256(uint160(entrypoint)) | ENTRY_POINT_OVERRIDDEN;
    }

    /// @notice Unpacks the entry point address from a uint256.
    function unpack(uint256 packedEntrypoint) internal pure returns (address) {
        return address(uint160(packedEntrypoint & ~ENTRY_POINT_OVERRIDDEN));
    }

    /// @notice Checks if the entry point has been overriden by the user.
    function isOverriden(uint256 packedEntrypoint) internal pure returns (bool) {
        return packedEntrypoint & ENTRY_POINT_OVERRIDDEN != 0;
    }
}

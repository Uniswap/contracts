// SPDX-License-Identifier: MIT
pragma solidity >=0.6.2;

/// @title IERC1271
interface IERC1271 {
    /// @notice Validates the `signature` against the given `hash`.
    /// @dev Supports the following signature workflows:
    /// - 64 or 65-byte ECDSA signatures from address(this)
    /// - Nested typed data signatures as defined by ERC-7739
    /// - Nested personal signatures as defined by ERC-7739
    /// @return result `0x1626ba7e` if validation succeeded, else `0xffffffff`.
    function isValidSignature(bytes32 hash, bytes calldata signature) external view returns (bytes4);
}

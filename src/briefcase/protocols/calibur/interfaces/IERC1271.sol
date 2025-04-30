// SPDX-License-Identifier: MIT
pragma solidity >=0.6.2;

/// @title IERC1271
interface IERC1271 {
    /// @notice Returns whether the caller is considered safe to skip the nested EIP-712 workflow
    function erc1271CallerIsSafe(address caller) external view returns (bool);

    /// @notice Sets whether the caller is considered safe to skip the nested EIP-712 workflow
    function setERC1271CallerIsSafe(address caller, bool isSafe) external;

    /// @notice Validates the `signature` against the given `hash`.
    /// @dev Wraps the given `hash` in a EIP-712 compliant struct along with the domain separator to be replay safe. Then validates the signature against it.
    /// @return result `0x1626ba7e` if validation succeeded, else `0xffffffff`.
    function isValidSignature(bytes32 hash, bytes calldata signature) external view returns (bytes4);
}

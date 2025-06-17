// SPDX-License-Identifier: MIT
pragma solidity >=0.6.2;

/// @title IEIP712
interface IEIP712 {
    /// @notice Encode the EIP-5267 domain into bytes
    /// @dev for use in ERC-7739
    function domainBytes() external view returns (bytes memory);

    /// @notice Returns the `domainSeparator` used to create EIP-712 compliant hashes.
    /// @return The 32 bytes domain separator result.
    function domainSeparator() external view returns (bytes32);

    /// @notice Public getter for `_hashTypedData()` to produce a EIP-712 hash using this account's domain separator
    /// @param hash The nested typed data. Assumes the hash is the result of applying EIP-712 `hashStruct`.
    function hashTypedData(bytes32 hash) external view returns (bytes32);

    /// @notice Update the EIP-712 domain salt by setting the upper 96 bits to `prefix`
    ///   12 bytes | 20 bytes
    ///   prefix   | Implementation address (immutable, set on deployment)
    /// @dev Use this to invalidate existing signatures signed under the old domain separator
    /// @param prefix The prefix to set
    function updateSalt(uint96 prefix) external;
}

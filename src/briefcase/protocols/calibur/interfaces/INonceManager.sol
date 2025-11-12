// SPDX-License-Identifier: MIT
pragma solidity >=0.6.2;

/// @title INonceManager
/// @notice Interface for managing nonces used to prevent replay attacks
/// @dev Each nonce consists of a 192-bit key and 64-bit sequence number
///      The key allows multiple independent nonce sequences
///      The sequence must be used in order (0, 1, 2, etc) for each key
interface INonceManager {
    /// @notice The event emitted when a nonce is invalidated
    event NonceInvalidated(uint256 nonce);

    /// @notice The error emitted when a nonce is invalid
    error InvalidNonce();

    /// @notice The error emitted when too many nonces are invalidated in one transaction
    error ExcessiveInvalidation();

    /// @notice Returns the next valid sequence number for a given key
    /// @param key The sequence key, passed as uint256 but only 192 bits are used.
    /// @return seq The sequence number padded to 256 bits but only the lower 64 bits should be used.
    function getSeq(uint256 key) external view returns (uint256 seq);

    /// @notice Invalidates all sequence numbers for a given key up to but not including the provided sequence number in the nonce
    /// @param newNonce The new nonce to set. Invalidates all sequence numbers for the key less than it.
    function invalidateNonce(uint256 newNonce) external;
}

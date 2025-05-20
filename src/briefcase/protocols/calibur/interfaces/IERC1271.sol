// SPDX-License-Identifier: MIT
pragma solidity >=0.6.2;

/// @title IERC1271
interface IERC1271 {
    /// @notice Validates the `signature` against the given `hash`.
    /// @dev Supports the following signature workflows:
    /// - 64 or 65-byte ECDSA signatures from address(this)
    /// - Nested typed data signatures as defined by ERC-7739
    /// - Nested personal signatures as defined by ERC-7739
    /// @dev A wrappedSignature contains a keyHash, signature, and any optional hook data
    ///      `signature` can contain extra fields used for webauthn verification or ERC7739 nested typed data verification
    /// @dev An unwrapped signature is only valid for the root key. However, the root key can also sign a 7739 rehashed signature.
    /// It is possible for an unwrapped signature from the root key to be replayed IF the root key is registered on another wallet, not this one, and that wallet
    /// does not enforce defensive rehashing for its keys. If this is a concern, use a 7739 wrapped signature for the root key.
    /// @return result `0x1626ba7e` if validation succeeded, else `0xffffffff`.
    function isValidSignature(bytes32 hash, bytes calldata signature) external view returns (bytes4);
}

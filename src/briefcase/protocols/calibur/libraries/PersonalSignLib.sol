// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/// @title PersonalSignLib
/// @notice Library for hashing nested personal sign messages per ERC-7739
library PersonalSignLib {
    bytes private constant PERSONAL_SIGN_TYPE = 'PersonalSign(bytes prefixed)';
    bytes32 private constant PERSONAL_SIGN_TYPEHASH = keccak256(PERSONAL_SIGN_TYPE);

    /// @notice Calculate the hash of the PersonalSign type according to EIP-712
    /// @dev This function is used within the context of ERC-1271 where we only have access to a bytes32 hash.
    ///      We assume that `message` is the hash of `prefixed`,
    /// keccak256("\x19Ethereum Signed Message:\n" || len(someMessage) || someMessage)
    ///      such that it is compatible with how EIP-712 handles dynamic types
    /// i.e. keccak256(abi.encode(PERSONAL_SIGN_TYPEHASH, keccak256(prefixed)))
    function hash(bytes32 message) internal pure returns (bytes32) {
        return keccak256(abi.encode(PERSONAL_SIGN_TYPEHASH, message));
    }
}

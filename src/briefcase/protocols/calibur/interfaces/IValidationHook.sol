// SPDX-License-Identifier: MIT
pragma solidity >=0.6.2;

import {PackedUserOperation} from '../lib/account-abstraction/interfaces/PackedUserOperation.sol';

/// @title IValidationHook
/// @notice Hook interface for optional signature validation logic
/// @dev The keyHash is validated against the signature before each hook is called, but
///      the hookData is NOT signed over or validated within the account. It MUST be treated as unsafe and can be set by anybody.
interface IValidationHook {
    /// @notice Hook called after `validateUserOp` is called on the account by the entrypoint
    /// @param keyHash the key which signed over userOpHash
    /// @param userOp UserOperation
    /// @param userOpHash hash of the UserOperation
    /// @param hookData any data to be passed to the hook. This has NOT been validated by the user signature
    /// @return selector Must be afterValidateUserOp.selector
    /// @dev The hook can revert to prevent the UserOperation from being validated.
    function afterValidateUserOp(
        bytes32 keyHash,
        PackedUserOperation calldata userOp,
        bytes32 userOpHash,
        bytes calldata hookData
    ) external view returns (bytes4 selector);

    /// @notice Hook called after verifying a signature over a digest in an EIP-1271 callback.
    /// @dev MUST revert to signal that validation should fail
    /// @param keyHash the key which signed over digest
    /// @param digest the digest to verify
    /// @param hookData any data to be passed to the hook.This has NOT been validated by the user signature
    /// @return selector Must be afterIsValidSignature.selector
    function afterIsValidSignature(bytes32 keyHash, bytes32 digest, bytes calldata hookData)
        external
        view
        returns (bytes4 selector);

    /// @notice Hook called after verifying a signature over `SignedBatchedCall`.
    /// @dev MUST revert to signal that validation should fail
    /// @param keyHash the key which signed over digest
    /// @param digest the digest to verify
    /// @param hookData any data to be passed to the hook. This has NOT been validated by the user signature
    /// @return selector Must be afterVerifySignature.selector
    function afterVerifySignature(bytes32 keyHash, bytes32 digest, bytes calldata hookData)
        external
        view
        returns (bytes4 selector);
}

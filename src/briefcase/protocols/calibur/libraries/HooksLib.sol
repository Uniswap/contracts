// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IExecutionHook} from '../interfaces/IExecutionHook.sol';
import {IHook} from '../interfaces/IHook.sol';
import {IValidationHook} from '../interfaces/IValidationHook.sol';
import {PackedUserOperation} from '../lib/account-abstraction/interfaces/PackedUserOperation.sol';

/// @title HooksLib
/// @notice Hooks are invoked by inspecting the least significant bits of the address it is deployed to
/// For example, a hook deployed to address: 0x000000000000000000000000000000000000000a
/// has the lowest bits '1010' which would cause the `afterValidateUserOp`, and `beforeExecute` hooks to be used.
/// @author Inspired by https://github.com/Uniswap/v4-core/blob/main/src/libraries/Hooks.sol
library HooksLib {
    using HooksLib for IHook;

    /// @notice Internal constant hook flags
    uint160 internal constant AFTER_VERIFY_SIGNATURE_FLAG = 1 << 0;
    uint160 internal constant AFTER_VALIDATE_USER_OP_FLAG = 1 << 1;
    uint160 internal constant AFTER_IS_VALID_SIGNATURE_FLAG = 1 << 2;
    uint160 internal constant BEFORE_EXECUTE_FLAG = 1 << 3;
    uint160 internal constant AFTER_EXECUTE_FLAG = 1 << 4;

    /// @notice Hook did not return its selector
    error InvalidHookResponse();

    /// @notice Returns whether the flag is configured for the hook
    function hasPermission(IHook self, uint160 flag) internal pure returns (bool) {
        return uint160(address(self)) & flag != 0;
    }

    /// @notice Handles the afterValidateUserOp hook
    /// @notice MAY revert if desired according to ERC-4337 spec
    /// @dev Expected to validate the userOp and return a validationData which will override the internally computed validationData
    function handleAfterValidateUserOp(
        IHook self,
        bytes32 keyHash,
        PackedUserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 validationData,
        bytes memory hookData
    ) internal view {
        if (self.hasPermission(HooksLib.AFTER_VALIDATE_USER_OP_FLAG)) {
            (bytes4 hookSelector) = self.afterValidateUserOp(keyHash, userOp, userOpHash, validationData, hookData);
            if (hookSelector != IValidationHook.afterValidateUserOp.selector) revert InvalidHookResponse();
        }
    }

    /// @notice Handles the afterIsValidSignature hook
    /// @notice MUST revert if validation fails
    /// @dev Expected to validate the signature and return a value which will override the internally computed ERC-1271 magic value
    function handleAfterIsValidSignature(IHook self, bytes32 keyHash, bytes32 digest, bytes memory hookData)
        internal
        view
    {
        if (self.hasPermission(HooksLib.AFTER_IS_VALID_SIGNATURE_FLAG)) {
            bytes4 hookSelector = self.afterIsValidSignature(keyHash, digest, hookData);
            if (hookSelector != IValidationHook.afterIsValidSignature.selector) revert InvalidHookResponse();
        }
    }

    /// @notice Handles the afterVerifySignature hook
    /// @notice MUST revert if validation fails
    function handleAfterVerifySignature(IHook self, bytes32 keyHash, bytes32 digest, bytes memory hookData)
        internal
        view
    {
        if (self.hasPermission(HooksLib.AFTER_VERIFY_SIGNATURE_FLAG)) {
            bytes4 hookSelector = self.afterVerifySignature(keyHash, digest, hookData);
            if (hookSelector != IValidationHook.afterVerifySignature.selector) revert InvalidHookResponse();
        }
    }

    /// @notice Handles the beforeExecute hook
    /// @dev Expected to revert if the execution should be reverted
    /// @return beforeExecuteData any data which the hook wishes to be passed into the afterExecute hook
    function handleBeforeExecute(IHook self, bytes32 keyHash, address to, uint256 value, bytes memory data)
        internal
        returns (bytes memory beforeExecuteData)
    {
        if (self.hasPermission(HooksLib.BEFORE_EXECUTE_FLAG)) {
            bytes4 hookSelector;
            (hookSelector, beforeExecuteData) = self.beforeExecute(keyHash, to, value, data);
            if (hookSelector != IExecutionHook.beforeExecute.selector) revert InvalidHookResponse();
        }
    }

    /// @notice Handles the afterExecute hook
    /// @param beforeExecuteData data returned from the beforeExecute hook
    /// @dev Expected to revert if the execution should be reverted
    function handleAfterExecute(
        IHook self,
        bytes32 keyHash,
        bool success,
        bytes memory output,
        bytes memory beforeExecuteData
    ) internal {
        if (self.hasPermission(HooksLib.AFTER_EXECUTE_FLAG)) {
            bytes4 hookSelector = self.afterExecute(keyHash, success, output, beforeExecuteData);
            if (hookSelector != IExecutionHook.afterExecute.selector) revert InvalidHookResponse();
        }
    }
}

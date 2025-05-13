// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

using ModeDecoder for bytes32;

/// @title ModeDecoder
/// @notice Decodes a bytes32 mode as specified in ERC-7821 and ERC-7579.
/// @dev This library only supports two modes: BATCHED_CALL and BATCHED_CAN_REVERT_CALL.
library ModeDecoder {
    // Mode layout adhering to ERC-7579
    // 1 byte           | 1 byte    | 4 bytes       | 4 bytes       | 22 bytes
    // CALL_TYPE        | EXEC_TYPE | UNUSED        | MODE_SELECTOR | MODE_PAYLOAD
    bytes32 constant BATCHED_CALL = 0x0100000000000000000000000000000000000000000000000000000000000000;
    bytes32 constant BATCHED_CAN_REVERT_CALL = 0x0101000000000000000000000000000000000000000000000000000000000000;

    // Mode Masks
    bytes32 constant EXTRACT_EXEC_TYPE = 0x00ff000000000000000000000000000000000000000000000000000000000000;

    // Supported modes:
    // 0x01           | 0x00      | unused        | 0x00000000   | unused
    // 0x01           | 0x01      | unused        | 0x00000000   | unused
    // - A batched call that reverts on failure, specifying mode selector 0x00000000 means no other data is present
    // - A batched call that does not revert on failure, specifying mode selector 0x00000000 means no other data is present
    function isBatchedCall(bytes32 mode) internal pure returns (bool) {
        return mode == BATCHED_CALL || mode == BATCHED_CAN_REVERT_CALL;
    }

    // Revert if the EXEC_TYPE is 0.
    // The EXEC_TYPE is guaranteed to be ONLY 1 or 0 since the mode is checked with strict equality in isBatchedCall().
    function revertOnFailure(bytes32 mode) internal pure returns (bool) {
        return mode & EXTRACT_EXEC_TYPE == 0;
    }
}

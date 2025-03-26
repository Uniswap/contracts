// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

using ModeDecoder for bytes32;

library ModeDecoder {
    // Mode layout adhering to ERC-7579
    // 1 byte           | 1 byte    | 4 bytes       | 4 bytes       | 22 bytes
    // CALL_TYPE        | EXEC_TYPE | UNUSED        | MODE_SELECTOR | MODE_PAYLOAD
    bytes32 constant BATCHED_CALL = 0x0100000000000000000000000000000000000000000000000000000000000000;
    bytes32 constant BATCHED_CAN_REVERT_CALL = 0x0101000000000000000000000000000000000000000000000000000000000000;
    bytes32 constant BATCHED_CALL_SUPPORTS_OPDATA = 0x0100000000007821000100000000000000000000000000000000000000000000;
    bytes32 constant BATCHED_CALL_SUPPORTS_OPDATA_AND_CAN_REVERT =
        0x0101000000007821000100000000000000000000000000000000000000000000;

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

    // Supported modes:
    // 0x01           | 0x00      | unused        | 0x78210001   | unused
    // 0x01           | 0x01      | unused        | 0x78210001   | unused
    // - A batched call that requires opData
    // - A batched call that does not revert on failure, and requires opData
    function supportsOpData(bytes32 mode) internal pure returns (bool) {
        return mode == BATCHED_CALL_SUPPORTS_OPDATA || mode == BATCHED_CALL_SUPPORTS_OPDATA_AND_CAN_REVERT;
    }

    // Revert if the EXEC_TYPE is 0.
    // The EXEC_TYPE is guaranteed to be ONLY 1 or 0 since the mode is checked with strict equality in isBatchedCall().
    function shouldRevert(bytes32 mode) internal pure returns (bool) {
        return mode & EXTRACT_EXEC_TYPE == 0;
    }
}

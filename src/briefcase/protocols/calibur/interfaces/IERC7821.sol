// SPDX-License-Identifier: MIT
pragma solidity >=0.6.2;

interface IERC7821 {
    /// @dev Thrown when an unsupported execution mode is provided.
    error UnsupportedExecutionMode();

    /// @dev Executes a batched call.
    /// @dev The mode is checked with strict equality in the implementation and only supports two mode types.
    /// @param mode The mode to execute the batched call in.
    /// @param executionData The data to execute the batched call with.
    function execute(bytes32 mode, bytes calldata executionData) external payable;

    /// @dev Provided for execution mode support detection.
    /// @dev This returns true for the BATCHED_CALL "0x010...00" and BATCHED_CALL_CAN_REVERT "0x01010...00" modes.
    function supportsExecutionMode(bytes32 mode) external view returns (bool result);
}

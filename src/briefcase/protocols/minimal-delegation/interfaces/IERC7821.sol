// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.6.2;

interface IERC7821 {
    error UnsupportedExecutionMode();
    error Unauthorized();
    error CallFailed(bytes reason);
    error InvalidSignature();

    function execute(bytes32 mode, bytes calldata executionData) external payable;

    /// @dev Provided for execution mode support detection.
    function supportsExecutionMode(bytes32 mode) external view returns (bool result);
}

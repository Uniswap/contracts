// SPDX-License-Identifier: MIT
pragma solidity >=0.6.2;

/// @title IDexCallback
/// @notice Callback interface required by Fluid DEX v1 "withCallback" swaps
interface IDexCallback {
    /// @notice   dex liquidity callback
    /// @param    token_ The token being transferred
    /// @param    amount_ The amount being transferred
    function dexCallback(address token_, uint256 amount_) external;
}

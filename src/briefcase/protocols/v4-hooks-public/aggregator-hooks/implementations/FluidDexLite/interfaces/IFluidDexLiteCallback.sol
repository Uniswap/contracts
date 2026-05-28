// SPDX-License-Identifier: MIT
pragma solidity >=0.6.2;

/// @title IFluidDexLiteCallback
/// @notice Callback interface required by Fluid DEX Lite swaps when isCallback is true
interface IFluidDexLiteCallback {
    /// @notice Called by Fluid DEX Lite to request token transfer from the caller
    /// @dev Must transfer exactly `amount_` of `token_` to msg.sender (the DEX)
    /// @param token_ The token address that must be transferred
    /// @param amount_ The amount of tokens that must be transferred
    /// @param data_ Arbitrary callback data passed through from the swap call
    function dexCallback(address token_, uint256 amount_, bytes calldata data_) external;
}

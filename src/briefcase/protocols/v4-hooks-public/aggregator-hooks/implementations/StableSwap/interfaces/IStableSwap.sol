// SPDX-License-Identifier: MIT
pragma solidity >=0.6.2;

/// @title ICurveStableSwap
/// @notice Interface for Curve StableSwap pools
/// @dev We have to write our own interface file since the source code is in vyper
interface ICurveStableSwap {
    /// @notice Calculates the expected output amount for a swap
    /// @param i Index of the input token in the pool
    /// @param j Index of the output token in the pool
    /// @param dx Amount of input tokens to swap
    /// @return The expected amount of output tokens
    function get_dy(int128 i, int128 j, uint256 dx) external view returns (uint256);

    /// @notice Executes a token swap
    /// @param i Index of the input token in the pool
    /// @param j Index of the output token in the pool
    /// @param dx Amount of input tokens to swap
    /// @param min_dy Minimum amount of output tokens to receive (slippage protection)
    /// @return The actual amount of output tokens received
    function exchange(int128 i, int128 j, uint256 dx, uint256 min_dy) external payable returns (uint256);

    /// @notice Returns the token address at a given index
    /// @param i Index of the token in the pool
    /// @return The token address at that index
    function coins(uint256 i) external view returns (address);

    /// @notice Returns the balance of a token at a given index
    /// @param i Index of the token in the pool
    /// @return The balance of the token at that index
    function balances(uint256 i) external view returns (uint256);
}

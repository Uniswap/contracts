// SPDX-License-Identifier: MIT
pragma solidity >=0.6.2;

/// @title ICurveStableSwapNG
/// @notice Interface for Curve StableSwap NG pools
/// @dev Based on the Vyper implementation at https://github.com/curvefi/stableswap-ng
/// @dev We have to write our own interface file since the source code is in vyper
interface ICurveStableSwapNG {
    /// @notice Calculates the required input amount for a desired output (inverse quote)
    /// @param i Index of the input token in the pool
    /// @param j Index of the output token in the pool
    /// @param dy Desired amount of output tokens
    /// @return The required amount of input tokens
    function get_dx(int128 i, int128 j, uint256 dy) external view returns (uint256);

    /// @notice Calculates the expected output amount for a swap
    /// @param i Index of the input token in the pool
    /// @param j Index of the output token in the pool
    /// @param dx Amount of input tokens to swap
    /// @return The expected amount of output tokens
    function get_dy(int128 i, int128 j, uint256 dx) external view returns (uint256);

    /// @notice Executes a token swap with custom receiver
    /// @param i Index of the input token in the pool
    /// @param j Index of the output token in the pool
    /// @param dx Amount of input tokens to swap
    /// @param min_dy Minimum amount of output tokens to receive (slippage protection)
    /// @param receiver Address to receive the output tokens
    /// @return The actual amount of output tokens received
    function exchange(int128 i, int128 j, uint256 dx, uint256 min_dy, address receiver) external returns (uint256);

    /// @notice Returns the number of coins in the pool
    /// @return The number of tokens in this pool
    function N_COINS() external view returns (uint256);

    /// @notice Returns the token address at a given index
    /// @param i Index of the token in the pool
    /// @return The token address at that index
    function coins(uint256 i) external view returns (address);

    /// @notice Returns the balance of a token at a given index
    /// @param i Index of the token in the pool
    /// @return The balance of the token at that index
    function balances(uint256 i) external view returns (uint256);
}

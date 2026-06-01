// SPDX-License-Identifier: MIT
pragma solidity >=0.6.2;

/// @title ITempoExchange
/// @notice Interface for Tempo's enshrined stablecoin DEX
/// @dev Tempo uses uint128 for amounts, not uint256. All stablecoins use 6 decimals.
/// @dev The exchange is a precompiled contract at a fixed address on Tempo chain.
interface ITempoExchange {
    /// @notice Executes a swap with an exact input amount
    /// @param tokenIn The address of the input token
    /// @param tokenOut The address of the output token
    /// @param amountIn The exact amount of input tokens to swap
    /// @param minAmountOut The minimum amount of output tokens to receive (slippage protection)
    /// @return amountOut The amount of output tokens received
    function swapExactAmountIn(address tokenIn, address tokenOut, uint128 amountIn, uint128 minAmountOut)
        external
        returns (uint128 amountOut);

    /// @notice Executes a swap with an exact output amount
    /// @param tokenIn The address of the input token
    /// @param tokenOut The address of the output token
    /// @param amountOut The exact amount of output tokens to receive
    /// @param maxAmountIn The maximum amount of input tokens to spend (slippage protection)
    /// @return amountIn The amount of input tokens spent
    function swapExactAmountOut(address tokenIn, address tokenOut, uint128 amountOut, uint128 maxAmountIn)
        external
        returns (uint128 amountIn);

    /// @notice Calculates the expected output amount for an exact input swap
    /// @param tokenIn The address of the input token
    /// @param tokenOut The address of the output token
    /// @param amountIn The amount of input tokens
    /// @return amountOut The expected amount of output tokens
    function quoteSwapExactAmountIn(address tokenIn, address tokenOut, uint128 amountIn)
        external
        view
        returns (uint128 amountOut);

    /// @notice Calculates the required input amount for an exact output swap
    /// @param tokenIn The address of the input token
    /// @param tokenOut The address of the output token
    /// @param amountOut The desired amount of output tokens
    /// @return amountIn The required amount of input tokens
    function quoteSwapExactAmountOut(address tokenIn, address tokenOut, uint128 amountOut)
        external
        view
        returns (uint128 amountIn);
}

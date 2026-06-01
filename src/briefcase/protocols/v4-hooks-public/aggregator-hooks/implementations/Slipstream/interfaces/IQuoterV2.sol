// SPDX-License-Identifier: MIT
pragma solidity >=0.6.2;

/// @title IQuoterV2
/// @notice Aerodrome Slipstream Base quoter ABI (`int24 tickSpacing` — Uni QuoterV2 uses `uint24 fee`).
interface IQuoterV2 {
    struct QuoteExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        int24 tickSpacing;
        uint160 sqrtPriceLimitX96;
    }

    struct QuoteExactOutputSingleParams {
        address tokenIn;
        address tokenOut;
        uint256 amountOut;
        int24 tickSpacing;
        uint160 sqrtPriceLimitX96;
    }

    /// @notice Simulates a single-hop exact-input swap and returns the output amount without state changes
    /// @param params Single-hop exact-input quote parameters
    /// @return amountOut Amount of `tokenOut` that would be received for `params.amountIn`
    function quoteExactInputSingle(QuoteExactInputSingleParams memory params) external returns (uint256 amountOut);

    /// @notice Simulates a single-hop exact-output swap and returns the required input without state changes
    /// @param params Single-hop exact-output quote parameters
    /// @return amountIn Amount of `tokenIn` required to receive `params.amountOut`
    function quoteExactOutputSingle(QuoteExactOutputSingleParams memory params) external returns (uint256 amountIn);
}

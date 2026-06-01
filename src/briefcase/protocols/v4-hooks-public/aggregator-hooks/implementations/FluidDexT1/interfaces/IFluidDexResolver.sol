// SPDX-License-Identifier: MIT
pragma solidity >=0.6.2;

/// @title IFluidDexResolver
/// @notice Interface for the Fluid DEX T1 resolver
interface IFluidDexResolver {
    /// @notice Get the addresses of the tokens in a DEX
    /// @param dex_ The address of the DEX
    /// @return token0_ The address of token0 in the DEX
    /// @return token1_ The address of token1 in the DEX
    function getDexTokens(address dex_) external view returns (address token0_, address token1_);

    /// @notice estimates swap IN tokens execution
    /// @param dex_ Dex pool
    /// @param swap0to1_ Direction of swap. If true, swaps token0 for token1; if false, swaps token1 for token0
    /// @param amountIn_ The exact amount of input tokens to swap
    /// @param amountOutMin_ The minimum amount of output tokens the user is willing to accept
    /// @return amountOut_ The amount of output tokens received from the swap
    function estimateSwapIn(address dex_, bool swap0to1_, uint256 amountIn_, uint256 amountOutMin_)
        external
        payable
        returns (uint256 amountOut_);

    /// @notice estimates swap OUT tokens execution
    /// @param dex_ Dex pool
    /// @param swap0to1_ Direction of swap. If true, swaps token0 for token1; if false, swaps token1 for token0
    /// @param amountOut_ The exact amount of tokens to receive after swap
    /// @param amountInMax_ Maximum amount of tokens to swap in
    /// @return amountIn_ The amount of input tokens used for the swap
    function estimateSwapOut(address dex_, bool swap0to1_, uint256 amountOut_, uint256 amountInMax_)
        external
        payable
        returns (uint256 amountIn_);
}

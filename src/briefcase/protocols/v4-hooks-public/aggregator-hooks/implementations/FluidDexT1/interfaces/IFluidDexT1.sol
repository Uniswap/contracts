// SPDX-License-Identifier: MIT
pragma solidity >=0.6.2;

/// @title IFluidDexT1
/// @notice Interface for the Fluid DEX T1 pool (colloquially Fluid DEX v1)
interface IFluidDexT1 {
    struct CollateralReserves {
        uint256 token0RealReserves;
        uint256 token1RealReserves;
        uint256 token0ImaginaryReserves;
        uint256 token1ImaginaryReserves;
    }

    struct DebtReserves {
        uint256 token0Debt;
        uint256 token1Debt;
        uint256 token0RealReserves;
        uint256 token1RealReserves;
        uint256 token0ImaginaryReserves;
        uint256 token1ImaginaryReserves;
    }

    /// @notice Executes a swap with an exact input amount
    /// @param swap0to1_ Direction of swap. If true, swaps token0 for token1; if false, swaps token1 for token0
    /// @param amountIn_ The exact amount of input tokens to swap
    /// @param amountOutMin_ The minimum amount of output tokens the user is willing to accept
    /// @param to_ The recipient address for the output tokens
    /// @return amountOut_ The amount of output tokens received from the swap
    function swapIn(bool swap0to1_, uint256 amountIn_, uint256 amountOutMin_, address to_)
        external
        payable
        returns (uint256 amountOut_);

    /// @notice Executes a swap with an exact output amount
    /// @param swap0to1_ Direction of swap. If true, swaps token0 for token1; if false, swaps token1 for token0
    /// @param amountOut_ The exact amount of output tokens to receive
    /// @param amountInMax_ The maximum amount of input tokens the user is willing to spend
    /// @param to_ The recipient address for the output tokens
    /// @return amountIn_ The amount of input tokens used for the swap
    function swapOut(bool swap0to1_, uint256 amountOut_, uint256 amountInMax_, address to_)
        external
        payable
        returns (uint256 amountIn_);

    /// @notice Executes a swap with an exact input amount using a callback for token transfer
    /// @dev The caller must implement IFluidDexCallback to provide the input tokens
    /// @param swap0to1_ Direction of swap. If true, swaps token0 for token1; if false, swaps token1 for token0
    /// @param amountIn_ The exact amount of input tokens to swap
    /// @param amountOutMin_ The minimum amount of output tokens the user is willing to accept
    /// @param to_ The recipient address for the output tokens
    /// @return amountOut_ The amount of output tokens received from the swap
    function swapInWithCallback(bool swap0to1_, uint256 amountIn_, uint256 amountOutMin_, address to_)
        external
        payable
        returns (uint256 amountOut_);

    /// @notice Executes a swap with an exact output amount using a callback for token transfer
    /// @dev The caller must implement IFluidDexCallback to provide the input tokens
    /// @param swap0to1_ Direction of swap. If true, swaps token0 for token1; if false, swaps token1 for token0
    /// @param amountOut_ The exact amount of output tokens to receive
    /// @param amountInMax_ The maximum amount of input tokens the user is willing to spend
    /// @param to_ The recipient address for the output tokens
    /// @return amountIn_ The amount of input tokens used for the swap
    function swapOutWithCallback(bool swap0to1_, uint256 amountOut_, uint256 amountInMax_, address to_)
        external
        payable
        returns (uint256 amountIn_);
}

// SPDX-License-Identifier: MIT
pragma solidity >=0.6.2;

/// @title IUniswapV3Pool
/// @notice Minimal Uniswap V3 compatible pool interface
interface IUniswapV3Pool {
    /// @notice First token of the pool by address sort order
    /// @return Token address of token0
    function token0() external view returns (address);

    /// @notice Second token of the pool by address sort order
    /// @return Token address of token1
    function token1() external view returns (address);

    /// @notice Swap fee of the pool, in hundredths of a bip (i.e. 1e6 = 100%)
    /// @return Fee tier identifier
    function fee() external view returns (uint24);

    /// @notice Minimum number of ticks between initialized ticks
    /// @return Spacing between usable ticks
    function tickSpacing() external view returns (int24);

    /// @notice Execute a swap against the pool
    /// @param recipient Address that receives the output of the swap
    /// @param zeroForOne When true, swap token0 for token1; when false, token1 for token0
    /// @param amountSpecified Amount of swap: exact input is positive, exact output is negative (periphery-style)
    /// @param sqrtPriceLimitX96 Price limit for the swap (Q64.96); pool price will not cross this bound
    /// @param data Opaque bytes passed through to `IUniswapV3SwapCallback.uniswapV3SwapCallback`
    /// @return amount0 Delta of the pool's token0 balance (negative if pool received token0)
    /// @return amount1 Delta of the pool's token1 balance (negative if pool received token1)
    function swap(
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bytes calldata data
    ) external returns (int256 amount0, int256 amount1);
}

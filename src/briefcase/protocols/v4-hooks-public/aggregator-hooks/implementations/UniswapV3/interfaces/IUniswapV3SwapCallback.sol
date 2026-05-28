// SPDX-License-Identifier: MIT
pragma solidity >=0.6.2;

/// @title IUniswapV3SwapCallback
/// @notice Callback from Uniswap V3 compatible pools during swap
interface IUniswapV3SwapCallback {
    /// @notice Called to `msg.sender` after executing a swap on the pool
    /// @param amount0Delta Owed amount of token0: pay pool if positive, receive from pool if negative
    /// @param amount1Delta Owed amount of token1: pay pool if positive, receive from pool if negative
    /// @param data Arbitrary data forwarded from the `swap` call, e.g. payer routing
    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external;
}

// SPDX-License-Identifier: MIT
pragma solidity >=0.6.2;

/// @title IPancakeSwapV3Callback
/// @notice Callback from PancakeSwap V3 compatible pools during swap (matches `IPancakeV3SwapCallback` on-chain name)
interface IPancakeSwapV3Callback {
    /// @notice Called to `msg.sender` after executing a swap on the pool
    /// @param amount0Delta Owed amount of token0: pay pool if positive, receive from pool if negative
    /// @param amount1Delta Owed amount of token1: pay pool if positive, receive from pool if negative
    /// @param data Arbitrary data forwarded from the `swap` call, e.g. payer routing
    function pancakeV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external;
}

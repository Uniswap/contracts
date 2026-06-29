// SPDX-License-Identifier: MIT
pragma solidity >=0.6.2;

import {PoolId} from '../../../v4-core/types/PoolId.sol';

/// @title IAggregatorHook
/// @notice Interface for the AggregatorHook contract. An implemented aggregator hook should be able to use liquidity from external sources
interface IAggregatorHook {
    error UnspecifiedAmountExceeded();
    error PoolDoesNotExist();
    error LiquidityNotAllowed();

    event AggregatorPoolRegistered(PoolId indexed poolId);
    event TokenJarUpdated(address indexed tokenJar);
    event HookSwap(PoolId indexed poolId, address indexed sender, int256 amount0, int256 amount1, uint24 swapFee);

    /// @notice Quotes amount of unspecified side for a given amount of specified side
    /// @param zeroToOne Whether the swap is from token0 to token1 or from token1 to token0
    /// @param amountSpecified The amount of tokens in or out (negative for exact-in, positive for exact-out)
    /// @return amountUnspecified amount of unspecified side (always positive to adhere to practices by other quote functions)
    /// @dev This function is meant to be called as a view function even though it is not one. This is because the swap
    /// might be simulated but not finalized. Applies protocol fee on top of the raw quote from the underlying liquidity source
    function quote(bool zeroToOne, int256 amountSpecified, PoolId poolId) external returns (uint256 amountUnspecified);

    /// @notice Returns the pseudo TVL: the amount of the UniswapV4 pool's tokens locked in the aggregated pool
    /// @param poolId The pool ID of the UniswapV4 pool
    /// @return amount0 The amount of token0 in the aggregated pool
    /// @return amount1 The amount of token1 in the aggregated pool
    function pseudoTotalValueLocked(PoolId poolId) external returns (uint256 amount0, uint256 amount1);
}

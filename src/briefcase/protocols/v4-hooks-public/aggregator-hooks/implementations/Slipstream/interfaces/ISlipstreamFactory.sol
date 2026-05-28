// SPDX-License-Identifier: MIT
pragma solidity >=0.6.2;

/// @title ISlipstreamFactory
/// @notice Slipstream-style concentrated liquidity pools keyed by tickSpacing (e.g. Aerodrome Slipstream)
interface ISlipstreamFactory {
    /// @notice Returns the pool address for a pair and tick spacing, or `address(0)` if it does not exist
    /// @param tokenA One token of the pair
    /// @param tokenB The other token of the pair
    /// @param tickSpacing Tick spacing of the pool
    /// @return pool The pool contract, or zero address if none deployed
    function getPool(address tokenA, address tokenB, int24 tickSpacing) external view returns (address pool);
}

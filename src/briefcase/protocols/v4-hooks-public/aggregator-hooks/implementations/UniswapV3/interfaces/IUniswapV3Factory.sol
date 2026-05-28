// SPDX-License-Identifier: MIT
pragma solidity >=0.6.2;

/// @title IUniswapV3Factory
/// @notice Minimal Uniswap V3 factory (fee-tier pool lookup)
interface IUniswapV3Factory {
    /// @notice Returns the pool address for a pair and fee tier, or `address(0)` if it does not exist
    /// @param tokenA One token of the pair
    /// @param tokenB The other token of the pair
    /// @param fee Fee tier of the pool
    /// @return pool The pool contract, or zero address if none deployed
    function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address pool);
}

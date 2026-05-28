// SPDX-License-Identifier: MIT
pragma solidity >=0.6.2;

import {IFluidDexLite} from './IFluidDexLite.sol';

/// @title IFluidDexLiteResolver
/// @notice Interface for the Fluid DEX Lite resolver
interface IFluidDexLiteResolver {
    /// @notice Returns all registered DEX pools
    /// @return An array of DexKey structs identifying each pool
    function getAllDexes() external view returns (IFluidDexLite.DexKey[] memory);

    /// @notice Retrieves the current state configuration of a DEX pool
    /// @param dexKey The unique key identifying the DEX pool
    /// @return The current DexState including variables, shifts, and thresholds
    function getDexState(IFluidDexLite.DexKey memory dexKey) external view returns (IFluidDexLite.DexState memory);

    /// @notice Retrieves complete data for a DEX pool including state, prices, and reserves
    /// @param dexKey The unique key identifying the DEX pool
    /// @return Complete DexEntireData struct with all pool information
    function getDexEntireData(IFluidDexLite.DexKey memory dexKey) external returns (IFluidDexLite.DexEntireData memory);

    /// @notice Retrieves current prices and reserves for a DEX pool
    /// @param dexKey The unique key identifying the DEX pool
    /// @return Prices struct with pool, center, range, and threshold prices
    /// @return Reserves struct with real and imaginary reserves for both tokens
    function getPricesAndReserves(IFluidDexLite.DexKey memory dexKey)
        external
        returns (IFluidDexLite.Prices memory, IFluidDexLite.Reserves memory);

    /// @notice Estimates the result of a single-hop swap without executing it
    /// @param dexKey The unique key identifying the DEX pool
    /// @param swap0To1 Direction of swap. If true, swaps token0 for token1; if false, swaps token1 for token0
    /// @param amountSpecified The amount to swap. Positive for exact input, negative for exact output
    /// @return The estimated unspecified amount (output for exact-in, input for exact-out)
    function estimateSwapSingle(IFluidDexLite.DexKey calldata dexKey, bool swap0To1, int256 amountSpecified)
        external
        returns (uint256);

    /// @notice Estimates the result of a multi-hop swap without executing it
    /// @param path Array of token addresses representing the swap route
    /// @param dexKeys Array of DexKey structs for each hop in the route
    /// @param amountSpecified The amount to swap. Positive for exact input, negative for exact output
    /// @return The estimated final output amount
    function estimateSwapHop(address[] calldata path, IFluidDexLite.DexKey[] calldata dexKeys, int256 amountSpecified)
        external
        view
        returns (uint256);
}

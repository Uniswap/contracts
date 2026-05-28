// SPDX-License-Identifier: MIT
pragma solidity >=0.6.2;

import {IFluidDexT1} from './IFluidDexT1.sol';

/// @title IFluidDexReservesResolver
/// @notice Interface for the Fluid DEX T1 reserves resolver
interface IFluidDexReservesResolver {
    struct DexLimits {
        TokenLimit withdrawableToken0;
        TokenLimit withdrawableToken1;
        TokenLimit borrowableToken0;
        TokenLimit borrowableToken1;
    }

    struct TokenLimit {
        uint256 available;
        uint256 expandsTo;
        uint256 expandDuration;
    }

    struct PoolWithReserves {
        address pool;
        address token0;
        address token1;
        uint256 fee;
        uint256 centerPrice;
        IFluidDexT1.CollateralReserves collateralReserves;
        IFluidDexT1.DebtReserves debtReserves;
        DexLimits limits;
    }

    /// @notice Get pool data with reserves for a specific DEX
    /// @param pool_ The address of the pool
    /// @return poolReserves_ The pool data including reserves
    /// @dev Matches Fluid's FluidDexReservesResolver.getPoolReserves
    function getPoolReserves(address pool_) external view returns (PoolWithReserves memory poolReserves_);
}

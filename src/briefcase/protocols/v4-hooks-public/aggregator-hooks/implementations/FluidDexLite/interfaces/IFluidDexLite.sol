// SPDX-License-Identifier: MIT
pragma solidity >=0.6.2;

/// @title IFluidDexLite
/// @notice Interface for the Fluid DEX Lite pool
interface IFluidDexLite {
    struct DexKey {
        address token0;
        address token1;
        bytes32 salt;
    }

    struct DexState {
        DexVariables dexVariables;
        CenterPriceShift centerPriceShift;
        RangeShift rangeShift;
        ThresholdShift thresholdShift;
    }

    struct DexVariables {
        uint256 fee;
        uint256 revenueCut;
        uint256 rebalancingStatus;
        bool isCenterPriceShiftActive;
        uint256 centerPrice;
        address centerPriceAddress;
        bool isRangePercentShiftActive;
        uint256 upperRangePercent;
        uint256 lowerRangePercent;
        bool isThresholdPercentShiftActive;
        uint256 upperShiftThresholdPercent;
        uint256 lowerShiftThresholdPercent;
        uint256 token0Decimals;
        uint256 token1Decimals;
        uint256 totalToken0AdjustedAmount;
        uint256 totalToken1AdjustedAmount;
    }

    struct CenterPriceShift {
        uint256 lastInteractionTimestamp;
        uint256 rebalancingShiftingTime;
        uint256 maxCenterPrice;
        uint256 minCenterPrice;
        uint256 shiftPercentage;
        uint256 centerPriceShiftingTime;
        uint256 startTimestamp;
    }

    struct RangeShift {
        uint256 oldUpperRangePercent;
        uint256 oldLowerRangePercent;
        uint256 shiftingTime;
        uint256 startTimestamp;
    }

    struct ThresholdShift {
        uint256 oldUpperThresholdPercent;
        uint256 oldLowerThresholdPercent;
        uint256 shiftingTime;
        uint256 startTimestamp;
    }

    struct Prices {
        uint256 poolPrice;
        uint256 centerPrice;
        uint256 upperRangePrice;
        uint256 lowerRangePrice;
        uint256 upperThresholdPrice;
        uint256 lowerThresholdPrice;
    }

    struct Reserves {
        uint256 token0RealReserves;
        uint256 token1RealReserves;
        uint256 token0ImaginaryReserves;
        uint256 token1ImaginaryReserves;
    }

    struct ConstantViews {
        address liquidity;
        address deployer;
    }

    struct DexEntireData {
        bytes8 dexId;
        DexKey dexKey;
        ConstantViews constantViews;
        Prices prices;
        Reserves reserves;
        DexState dexState;
    }

    /// @notice Executes a single-hop swap on the Fluid DEX Lite pool
    /// @param dexKey_ The unique key identifying the DEX pool (token0, token1, salt)
    /// @param swap0To1_ Direction of swap. If true, swaps token0 for token1; if false, swaps token1 for token0
    /// @param amountSpecified_ The amount to swap. Positive for exact input, negative for exact output
    /// @param amountLimit_ Slippage protection. Min output for exact-in, max input for exact-out
    /// @param to_ The recipient address for the output tokens
    /// @param isCallback_ If true, uses callback mechanism for token transfer instead of direct transfer
    /// @param callbackData_ Arbitrary data passed to the callback function if isCallback_ is true
    /// @param extraData_ Additional data for specialized swap logic
    /// @return amountUnspecified_ The unspecified amount (output for exact-in, input for exact-out)
    function swapSingle(
        DexKey calldata dexKey_,
        bool swap0To1_,
        int256 amountSpecified_,
        uint256 amountLimit_,
        address to_,
        bool isCallback_,
        bytes calldata callbackData_,
        bytes calldata extraData_
    ) external payable returns (uint256 amountUnspecified_);
}

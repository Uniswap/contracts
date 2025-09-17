// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {FixedPointMathLib} from '../../lib-external/solady/src/utils/FixedPointMathLib.sol';
import {AuctionStepLib} from './AuctionStepLib.sol';
import {FixedPoint96} from './FixedPoint96.sol';

struct Checkpoint {
    uint256 clearingPrice;
    uint128 blockCleared;
    uint128 totalCleared;
    uint24 cumulativeMps;
    uint24 mps;
    uint64 prev;
    uint64 next;
    uint128 resolvedDemandAboveClearingPrice;
    uint256 cumulativeMpsPerPrice;
    uint256 cumulativeSupplySoldToClearingPrice;
}

/// @title CheckpointLib
library CheckpointLib {
    using FixedPointMathLib for uint128;
    using AuctionStepLib for uint128;
    using CheckpointLib for Checkpoint;

    /// @notice Return a new checkpoint after advancing the current checkpoint by a number of blocks
    /// @dev The checkpoint must have a non zero clearing price
    /// @param checkpoint The checkpoint to transform
    /// @param totalSupply The total supply of the auction
    /// @param floorPrice The floor price of the auction
    /// @param blockDelta The number of blocks to advance
    /// @param mps The number of mps to add
    /// @return The transformed checkpoint
    function transform(
        Checkpoint memory checkpoint,
        uint128 totalSupply,
        uint256 floorPrice,
        uint64 blockDelta,
        uint24 mps
    ) internal pure returns (Checkpoint memory) {
        // This is an unsafe cast, but we ensure in the construtor that the max blockDelta (end - start) * mps is always less than 1e7 (100%)
        uint24 deltaMps = uint24(mps * blockDelta);
        checkpoint.blockCleared = checkpoint.getBlockCleared(checkpoint.getSupply(totalSupply, mps), floorPrice);

        uint128 supplyDelta = checkpoint.blockCleared * blockDelta;
        checkpoint.totalCleared += supplyDelta;
        checkpoint.cumulativeMps += deltaMps;
        checkpoint.cumulativeSupplySoldToClearingPrice +=
            getSupplySoldToClearingPrice(supplyDelta, checkpoint.resolvedDemandAboveClearingPrice, deltaMps);
        checkpoint.cumulativeMpsPerPrice +=
            checkpoint.clearingPrice == 0 ? 0 : getMpsPerPrice(deltaMps, checkpoint.clearingPrice);
        return checkpoint;
    }

    /// @notice Calculate the supply sold to the clearing price
    /// @param supplyMps The supply of the auction
    /// @param resolvedDemandAboveClearingPrice The demand above the clearing price
    /// @param mpsDelta The number of mps to add
    /// @return an X96 fixed point number representing the partial fill rate
    function getSupplySoldToClearingPrice(uint128 supplyMps, uint128 resolvedDemandAboveClearingPrice, uint24 mpsDelta)
        internal
        pure
        returns (uint128)
    {
        if (supplyMps == 0) return 0;
        return (supplyMps - resolvedDemandAboveClearingPrice.applyMps(mpsDelta));
    }

    /// @notice Calculate the actualy supply to sell given the total cleared in the auction so far
    /// @param checkpoint The last checkpointed state of the auction
    /// @param totalSupply immutable total supply of the auction
    /// @param mps the number of mps, following the auction sale schedule
    function getSupply(Checkpoint memory checkpoint, uint128 totalSupply, uint24 mps) internal pure returns (uint128) {
        return uint128(
            (totalSupply - checkpoint.totalCleared).fullMulDiv(mps, AuctionStepLib.MPS - checkpoint.cumulativeMps)
        );
    }

    /// @notice Get the amount of tokens sold in a block at a checkpoint based on its clearing price and the floorPrice
    /// @param checkpoint The last checkpointed state of the auction
    /// @param supply The supply being sold
    /// @param floorPrice immutable floor price of the auction
    function getBlockCleared(Checkpoint memory checkpoint, uint128 supply, uint256 floorPrice)
        internal
        pure
        returns (uint128)
    {
        return checkpoint.clearingPrice > floorPrice
            ? supply
            : checkpoint.resolvedDemandAboveClearingPrice.applyMps(checkpoint.mps);
    }

    /// @notice Calculate the supply to price ratio
    /// @dev This function returns a value in Q96 form
    /// @param mps The number of supply mps sold
    /// @param price The price they were sold at
    /// @return the ratio
    function getMpsPerPrice(uint24 mps, uint256 price) internal pure returns (uint256) {
        // The bitshift cannot overflow because a uint24 shifted left 96 * 2 will always be less than 2^256
        return (uint256(mps) << (FixedPoint96.RESOLUTION * 2)) / price;
    }

    /// @notice Calculate the total currency raised
    /// @param checkpoint The checkpoint to calculate the currency raised from
    /// @return The total currency raised
    function getCurrencyRaised(Checkpoint memory checkpoint) internal pure returns (uint128) {
        return uint128(
            checkpoint.totalCleared.fullMulDiv(
                checkpoint.cumulativeMps * FixedPoint96.Q96, checkpoint.cumulativeMpsPerPrice
            )
        );
    }
}

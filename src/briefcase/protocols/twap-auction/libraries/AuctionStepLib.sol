// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

struct AuctionStep {
    uint24 mps; // Mps to sell per block in the step
    uint64 startBlock; // Start block of the step (inclusive)
    uint64 endBlock; // Ending block of the step (exclusive)
}

library AuctionStepLib {
    /// @notice we use milli-bips, or one thousandth of a basis point

    uint24 public constant MPS = 1e7;

    /// @notice Unpack the mps and block delta from the auction steps data
    function parse(bytes8 data) internal pure returns (uint24 mps, uint40 blockDelta) {
        mps = uint24(bytes3(data));
        blockDelta = uint40(uint64(data));
    }

    /// @notice Load a word at `offset` from data and parse it into mps and blockDelta
    function get(bytes memory data, uint256 offset) internal pure returns (uint24 mps, uint40 blockDelta) {
        assembly {
            let packedValue := mload(add(add(data, 0x20), offset))
            packedValue := shr(192, packedValue)
            mps := shr(40, packedValue)
            blockDelta := and(packedValue, 0xFFFFFFFFFF)
        }
    }

    /// @notice Apply mps to a value
    /// @dev Requires that value is > MPS to avoid loss of precision
    function applyMps(uint128 value, uint24 mps) internal pure returns (uint128) {
        return mps * value / MPS;
    }
}

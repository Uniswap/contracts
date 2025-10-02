// SPDX-License-Identifier: MIT
pragma solidity >=0.6.2;

/// @title ITickStorage
/// @notice Interface for the TickStorage contract
interface ITickStorage {
    /// @notice Error thrown when the tick price is not increasing
    error TickPriceNotIncreasing();
    /// @notice Error thrown when the price is not at a boundary designated by the tick spacing
    error TickPriceNotAtBoundary();
    /// @notice Emitted when a tick is initialized
    /// @param price The price of the tick

    event TickInitialized(uint256 price);

    /// @notice Emitted when the nextActiveTick is updated
    /// @param price The price of the tick
    event NextActiveTickUpdated(uint256 price);

    /// @notice The price of the next initialized tick above the clearing price
    /// @dev This will be equal to the clearingPrice if no ticks have been initialized yet
    function nextActiveTickPrice() external view returns (uint256);

    /// @notice Get the floor price of the auction
    function floorPrice() external view returns (uint256);

    /// @notice Get the tick spacing enforced for bid prices
    function tickSpacing() external view returns (uint256);
}

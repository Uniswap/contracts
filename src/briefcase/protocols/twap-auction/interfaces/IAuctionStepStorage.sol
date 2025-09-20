// SPDX-License-Identifier: MIT
pragma solidity >=0.6.2;

interface IAuctionStepStorage {
    /// @notice Error thrown when the SSTORE2 pointer is the zero address
    error InvalidPointer();
    /// @notice Error thrown when the auction is over
    error AuctionIsOver();
    /// @notice Error thrown when the auction data length is invalid
    error InvalidAuctionDataLength();
    /// @notice Error thrown when the mps is invalid
    error InvalidMps();
    /// @notice Error thrown when the end block is invalid
    error InvalidEndBlock();

    /// @notice The block at which the auction starts
    function startBlock() external view returns (uint64);
    /// @notice The block at which the auction ends
    function endBlock() external view returns (uint64);

    /// @notice Emitted when an auction step is recorded
    /// @param startBlock The start block of the auction step
    /// @param endBlock The end block of the auction step
    /// @param mps The percentage of total tokens to sell per block during this auction step, represented in ten-millionths of the total supply (1e7 = 100%)
    event AuctionStepRecorded(uint256 indexed startBlock, uint256 indexed endBlock, uint24 mps);
}

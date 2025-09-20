// SPDX-License-Identifier: MIT
pragma solidity >=0.6.2;

import {IDistributionStrategy} from './external/IDistributionStrategy.sol';

/// @title IAuctionFactory
interface IAuctionFactory is IDistributionStrategy {
    /// @notice Emitted when an auction is created
    /// @param auction The address of the auction contract
    /// @param token The address of the token
    /// @param amount The amount of tokens to sell
    /// @param configData The configuration data for the auction
    event AuctionCreated(address indexed auction, address token, uint256 amount, bytes configData);
}

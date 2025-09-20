// SPDX-License-Identifier: MIT
pragma solidity >=0.6.2;

import {IDistributionContract} from './IDistributionContract.sol';

/// @title IDistributionStrategy
/// @notice Interface for token distribution strategies.
interface IDistributionStrategy {
    /// @notice Initialize a distribution of tokens under this strategy.
    /// @dev Contracts can choose to deploy an instance with a factory-model or handle all distributions within the
    /// implementing contract. For some strategies this function will handle the entire distribution, for others it
    /// could merely set up initial state and provide additional entrypoints to handle the distribution logic.
    /// @param token The address of the token to be distributed.
    /// @param amount The amount of tokens intended for distribution.
    /// @param configData Arbitrary, strategy-specific parameters.
    /// @param salt The salt to use for the deterministic deployment.
    /// @return distributionContract The contract that will handle or manage the distribution.
    ///         (Could be `address(this)` if the strategy is handled in-place, or a newly deployed instance).
    function initializeDistribution(address token, uint128 amount, bytes calldata configData, bytes32 salt)
        external
        returns (IDistributionContract distributionContract);
}

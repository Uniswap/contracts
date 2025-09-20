// SPDX-License-Identifier: MIT
pragma solidity >=0.6.2;

/// @title IDistributionContract
/// @notice Interface for token distribution contracts.
interface IDistributionContract {
    /// @notice Notify a distribution contract that it has received the tokens to distribute
    function onTokensReceived() external;
}

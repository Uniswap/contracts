// SPDX-License-Identifier: MIT
pragma solidity >=0.6.2;

interface IValidationHook {
    /// @notice Validate a bid
    /// @dev MUST revert if the bid is invalid
    /// @param maxPrice The maximum price the bidder is willing to pay
    /// @param exactIn Whether the bid is exact in
    /// @param amount The amount of the bid
    /// @param owner The owner of the bid
    /// @param sender The sender of the bid
    /// @param hookData Additional data to pass to the hook required for validation
    function validate(
        uint256 maxPrice,
        bool exactIn,
        uint128 amount,
        address owner,
        address sender,
        bytes calldata hookData
    ) external view;
}

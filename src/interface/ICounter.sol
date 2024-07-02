// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

interface ICounter {
    /// @return The current number
    function number() external view returns (uint256);

    /// @notice Sets the number
    /// @param newNumber The new number
    function setNumber(uint256 newNumber) external;

    /// @notice Increments the number by 1
    function increment() external;
}

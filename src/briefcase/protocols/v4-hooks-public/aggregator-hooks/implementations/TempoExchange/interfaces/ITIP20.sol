// SPDX-License-Identifier: MIT
pragma solidity >=0.6.2;

/// @title ITIP20
/// @notice Interface for Tempo TIP-20 tokens (precompile stablecoins)
/// @dev Each TIP-20 token defines a quoteToken() forming a DEX tree. PathUSD is the root (quoteToken = address(0)).
interface ITIP20 {
    /// @notice Returns the token name
    function name() external view returns (string memory);

    /// @notice Returns the token symbol
    function symbol() external view returns (string memory);

    /// @notice Returns the parent token in the DEX tree
    /// @dev PathUSD (the root token) returns address(0)
    function quoteToken() external view returns (address);

    /// @notice Returns the total supply of the token
    function totalSupply() external view returns (uint256);
}

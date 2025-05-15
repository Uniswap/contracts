// SPDX-License-Identifier: MIT
pragma solidity >=0.6.2;

/**
 * @title ITokenFactory
 * @dev Generic interface for a token factory.
 */
interface ITokenFactory {
    /// @notice Emitted when a new token is created
    event TokenCreated(address tokenAddress);

    /**
     * @notice Creates a new token contract
     * @param name          The ERC20-style name of the token.
     * @param symbol        The ERC20-style symbol of the token.
     * @param decimals      The number of decimal places for the token.
     * @param initialSupply The initial supply to mint upon creation.
     * @param recipient     The recipient of the initial supply.
     * @param data          Additional factory-specific data required for token creation.
     * @return tokenAddress The address of the newly created token.
     */
    function createToken(
        string calldata name,
        string calldata symbol,
        uint8 decimals,
        uint256 initialSupply,
        address recipient,
        bytes calldata data
    ) external returns (address tokenAddress);
}

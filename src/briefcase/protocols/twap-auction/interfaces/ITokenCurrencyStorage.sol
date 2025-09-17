// SPDX-License-Identifier: MIT
pragma solidity >=0.6.2;

interface ITokenCurrencyStorage {
    /// @notice Error thrown when the total supply is zero
    error TotalSupplyIsZero();
    /// @notice Error thrown when the funds recipient is the zero address
    error FundsRecipientIsZero();
    /// @notice Error thrown when the function is called by an address other than the funds recipient
    error OnlyFundsRecipient();
    /// @notice Error thrown when the currency cannot be swept
    error CannotSweepCurrency();
    /// @notice Error thrown when the tokens cannot be swept
    error CannotSweepTokens();
    /// @notice Error thrown when the graduation threshold is invalid
    error InvalidGraduationThresholdMps();
    /// @notice Error thrown when the auction has not graduated
    error NotGraduated();
    /// @notice Error thrown when the funds recipient data cannot be decoded
    error FundsRecipientCallFailed();

    /// @notice Emitted when the tokens are swept
    /// @param tokensRecipient The address of the tokens recipient
    /// @param tokensAmount The amount of tokens swept
    event TokensSwept(address indexed tokensRecipient, uint256 tokensAmount);

    /// @notice Emitted when the currency is swept
    /// @param fundsRecipient The address of the funds recipient
    /// @param currencyAmount The amount of currency swept
    event CurrencySwept(address indexed fundsRecipient, uint256 currencyAmount);
}

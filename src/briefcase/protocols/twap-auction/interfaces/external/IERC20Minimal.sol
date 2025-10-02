// SPDX-License-Identifier: MIT
pragma solidity >=0.6.2;

/// @notice Minimal ERC20 interface
interface IERC20Minimal {
    /// @notice Returns an account's balance in the token
    /// @param account The account for which to look up the number of tokens it has, i.e. its balance
    /// @return The number of tokens held by the account
    function balanceOf(address account) external view returns (uint256);

    /// @notice Transfers the amount of token from the `msg.sender` to the recipient
    /// @param recipient The account that will receive the amount transferred
    /// @param amount The number of tokens to send from the sender to the recipient
    /// @return Returns true for a successful transfer, false for an unsuccessful transfer
    function transfer(address recipient, uint256 amount) external returns (bool);

    /// @notice Approves the spender to spend the amount of tokens from the `msg.sender`
    /// @param spender The account that will be allowed to spend the amount
    /// @param amount The number of tokens to allow the spender to spend
    /// @return Returns true for a successful approval, false for an unsuccessful approval
    function approve(address spender, uint256 amount) external returns (bool);
}

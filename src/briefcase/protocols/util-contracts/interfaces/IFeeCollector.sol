// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.6.2;

import {ERC20} from "../../lib-external/solmate/src/tokens/ERC20.sol";
import {IPermit2} from "../external/IPermit2.sol";

/// @notice The collector of protocol fees that will be used to swap and send to a fee recipient address.
interface IFeeCollector {
    /// @notice Error thrown when the call to UniversalRouter fails.
    error UniversalRouterCallFailed();

    /// @notice Emitted when the UniversalRouter address is changed.
    /// @param oldUniversalRouter The old router address.
    /// @param newUniversalRouter The new router address.
    event UniversalRouterChanged(address oldUniversalRouter, address newUniversalRouter);

    /// @notice Swaps the contract balance.
    /// @param swapData The bytes call data to be forwarded to UniversalRouter.
    /// @param nativeValue The amount of native currency to send to UniversalRouter.
    function swapBalance(bytes calldata swapData, uint256 nativeValue) external;

    /// @notice Approves tokens for swapping and then swaps the contract balance.
    /// @param swapData The bytes call data to be forwarded to UniversalRouter.
    /// @param nativeValue The amount of native currency to send to UniversalRouter.
    /// @param tokensToApprove An array of ERC20 tokens to approve for spending.
    function swapBalance(bytes calldata swapData, uint256 nativeValue, ERC20[] calldata tokensToApprove) external;

    /// @notice Revokes approvals on tokens by setting their allowance to 0.
    /// @param tokensToRevoke The token to revoke the approval for.
    function revokeTokenApprovals(ERC20[] calldata tokensToRevoke) external;

    /// @notice Revokes the permit2 allowance of a spender by setting token allowances to 0.
    /// @param approvals The approvals to revoke.
    function revokePermit2Approvals(IPermit2.TokenSpenderPair[] calldata approvals) external;

    /// @notice Transfers the fee token balance from this contract to the fee recipient.
    /// @param feeRecipient The address to send the fee token balance to.
    /// @param amount The amount to withdraw.
    function withdrawFeeToken(address feeRecipient, uint256 amount) external;

    /// @notice Sets the address of the UniversalRouter contract.
    /// @param _universalRouter The address of the UniversalRouter contract.
    function setUniversalRouter(address _universalRouter) external;
}
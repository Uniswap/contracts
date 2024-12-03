// SPDX-License-Identifier: MIT
pragma solidity >=0.6.2;

import {BalanceDelta} from '../../v4-core/types/BalanceDelta.sol';
import {PositionInfo} from '../libraries/PositionInfoLibrary.sol';

/// @notice Interface that a Subscriber contract should implement to receive updates from the v4 position manager
interface ISubscriber {
    /// @param tokenId the token ID of the position
    /// @param data additional data passed in by the caller
    function notifySubscribe(uint256 tokenId, bytes memory data) external;
    /// @notice Called when a position unsubscribes from the subscriber
    /// @dev This call's gas is capped at `unsubscribeGasLimit` (set at deployment)
    /// @dev Because of EIP-150, solidity may only allocate 63/64 of gasleft()
    /// @param tokenId the token ID of the position
    function notifyUnsubscribe(uint256 tokenId) external;
    /// @notice Called when a position is burned
    /// @param tokenId the token ID of the position
    /// @param owner the current owner of the tokenId
    /// @param info information about the position
    /// @param liquidity the amount of liquidity decreased in the position, may be 0
    /// @param feesAccrued the fees accrued by the position if liquidity was decreased
    function notifyBurn(uint256 tokenId, address owner, PositionInfo info, uint256 liquidity, BalanceDelta feesAccrued)
        external;
    /// @param tokenId the token ID of the position
    /// @param liquidityChange the change in liquidity on the underlying position
    /// @param feesAccrued the fees to be collected from the position as a result of the modifyLiquidity call
    function notifyModifyLiquidity(uint256 tokenId, int256 liquidityChange, BalanceDelta feesAccrued) external;
}
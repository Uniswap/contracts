// SPDX-License-Identifier: UNLICENSED

import {IPoolManager} from '../../v4-core/interfaces/IPoolManager.sol';
import {TickMath} from '../../v4-core/libraries/TickMath.sol';
import {BalanceDelta} from '../../v4-core/types/BalanceDelta.sol';
import {PoolId, PoolIdLibrary} from '../../v4-core/types/PoolId.sol';
import {PoolKey} from '../../v4-core/types/PoolKey.sol';
import {QuoterRevert} from '../libraries/QuoterRevert.sol';
import {SafeCallback} from './SafeCallback.sol';

abstract contract BaseV4Quoter is SafeCallback {
    using QuoterRevert for *;
    using PoolIdLibrary for PoolId;

    error NotEnoughLiquidity(PoolId poolId);
    error NotSelf();
    error UnexpectedCallSuccess();

    constructor(IPoolManager _poolManager) SafeCallback(_poolManager) {}

    /// @dev Only this address may call this function. Used to mimic internal functions, using an
    /// external call to catch and parse revert reasons
    modifier selfOnly() {
        if (msg.sender != address(this)) revert NotSelf();
        _;
    }

    function _unlockCallback(bytes calldata data) internal override returns (bytes memory) {
        (bool success, bytes memory returnData) = address(this).call(data);
        // Every quote path gathers a quote, and then reverts either with QuoteSwap(quoteAmount) or alternative error
        if (success) revert UnexpectedCallSuccess();
        // Bubble the revert string, whether a valid quote or an alternative error
        returnData.bubbleReason();
    }

    /// @dev Execute a swap and return the balance delta
    /// @notice if amountSpecified < 0, the swap is exactInput, otherwise exactOutput
    function _swap(PoolKey memory poolKey, bool zeroForOne, int256 amountSpecified, bytes calldata hookData)
        internal
        returns (BalanceDelta swapDelta)
    {
        swapDelta = poolManager.swap(
            poolKey,
            IPoolManager.SwapParams({
                zeroForOne: zeroForOne,
                amountSpecified: amountSpecified,
                sqrtPriceLimitX96: zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
            }),
            hookData
        );

        // Check that the pool was not illiquid.
        int128 amountSpecifiedActual = (zeroForOne == (amountSpecified < 0)) ? swapDelta.amount0() : swapDelta.amount1();
        if (amountSpecifiedActual != amountSpecified) {
            revert NotEnoughLiquidity(poolKey.toId());
        }
    }
}

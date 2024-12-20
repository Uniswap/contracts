// SPDX-License-Identifier: MIT
pragma solidity >=0.6.2;

import {Currency} from '../../v4-core/types/Currency.sol';
import {PoolKey} from '../../v4-core/types/PoolKey.sol';

import {PathKey} from '../libraries/PathKey.sol';
import {IImmutableState} from './IImmutableState.sol';

/// @title IV4Router
/// @notice Interface for the V4Router contract
interface IV4Router is IImmutableState {
    /// @notice Emitted when an exactInput swap does not receive its minAmountOut
    error V4TooLittleReceived(uint256 minAmountOutReceived, uint256 amountReceived);
    /// @notice Emitted when an exactOutput is asked for more than its maxAmountIn
    error V4TooMuchRequested(uint256 maxAmountInRequested, uint256 amountRequested);

    /// @notice Parameters for a single-hop exact-input swap
    struct ExactInputSingleParams {
        PoolKey poolKey;
        bool zeroForOne;
        uint128 amountIn;
        uint128 amountOutMinimum;
        bytes hookData;
    }

    /// @notice Parameters for a multi-hop exact-input swap
    struct ExactInputParams {
        Currency currencyIn;
        PathKey[] path;
        uint128 amountIn;
        uint128 amountOutMinimum;
    }

    /// @notice Parameters for a single-hop exact-output swap
    struct ExactOutputSingleParams {
        PoolKey poolKey;
        bool zeroForOne;
        uint128 amountOut;
        uint128 amountInMaximum;
        bytes hookData;
    }

    /// @notice Parameters for a multi-hop exact-output swap
    struct ExactOutputParams {
        Currency currencyOut;
        PathKey[] path;
        uint128 amountOut;
        uint128 amountInMaximum;
    }
}

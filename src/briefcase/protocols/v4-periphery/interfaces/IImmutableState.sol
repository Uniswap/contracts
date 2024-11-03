// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.6.2;

import {IPoolManager} from '../../v4-core/interfaces/IPoolManager.sol';

/// @title Interface for ImmutableState
interface IImmutableState {
    /// @notice The Uniswap v4 PoolManager contract
    function poolManager() external view returns (IPoolManager);
}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import {INonfungiblePositionManager} from '../../v3-periphery/interfaces/INonfungiblePositionManager.sol';
import {IPositionManager} from '../../v4-periphery/interfaces/IPositionManager.sol';

struct MigratorParameters {
    address v3PositionManager;
    address v4PositionManager;
}

/// @title Migrator Immutables
/// @notice Immutable state for liquidity-migration contracts
contract MigratorImmutables {
    /// @notice v3 PositionManager address
    INonfungiblePositionManager public immutable V3_POSITION_MANAGER;
    /// @notice v4 PositionManager address
    IPositionManager public immutable V4_POSITION_MANAGER;

    constructor(MigratorParameters memory params) {
        V3_POSITION_MANAGER = INonfungiblePositionManager(params.v3PositionManager);
        V4_POSITION_MANAGER = IPositionManager(params.v4PositionManager);
    }
}

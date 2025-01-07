// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @dev there is a solidity compiler error making it impossible to compile the PoolManager from the src/pkgs/ submodule right now.
/// https://github.com/ethereum/solidity/issues/15582
/// so adding it as a library and importing it here so it's compiled and shows up in the out/ directory to be processed for deployers & briefcase
import {PoolManager} from 'lib/v4-core/src/PoolManager.sol';

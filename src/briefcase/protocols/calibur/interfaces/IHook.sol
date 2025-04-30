// SPDX-License-Identifier: MIT
pragma solidity >=0.6.2;

import {IExecutionHook} from './IExecutionHook.sol';
import {IValidationHook} from './IValidationHook.sol';

/// @title IHook
/// @notice Unified interface for validation and execution hooks
/// @dev Hooks may implement both interfaces
interface IHook is IValidationHook, IExecutionHook {}

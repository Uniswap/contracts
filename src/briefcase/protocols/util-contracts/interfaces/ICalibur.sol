// SPDX-License-Identifier: MIT
pragma solidity >=0.6.2;

import {IERC7914} from './IERC7914.sol';

/// A non-upgradeable contract that can be delegated to with a 7702 delegation transaction.
/// This implementation supports:
/// ERC-7914 transfer from native
interface ICalibur is IERC7914 {}

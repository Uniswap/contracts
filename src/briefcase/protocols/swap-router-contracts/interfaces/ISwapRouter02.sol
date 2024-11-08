// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.6.2;
pragma abicoder v2;

import {ISelfPermit} from '../../v3-periphery/interfaces/ISelfPermit.sol';
import {IApproveAndCall} from './IApproveAndCall.sol';
import {IMulticallExtended} from './IMulticallExtended.sol';
import {IV2SwapRouter} from './IV2SwapRouter.sol';
import {IV3SwapRouter} from './IV3SwapRouter.sol';

/// @title Router token swapping functionality
interface ISwapRouter02 is IV2SwapRouter, IV3SwapRouter, IApproveAndCall, IMulticallExtended, ISelfPermit {}

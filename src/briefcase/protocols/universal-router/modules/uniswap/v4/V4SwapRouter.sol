// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import {IPoolManager} from '../../../../v4-core/interfaces/IPoolManager.sol';
import {Currency} from '../../../../v4-core/types/Currency.sol';

import {V4Router} from '../../../../v4-periphery/V4Router.sol';
import {Permit2Payments} from '../../Permit2Payments.sol';

/// @title Router for Uniswap v4 Trades
abstract contract V4SwapRouter is V4Router, Permit2Payments {
    constructor(address _poolManager) V4Router(IPoolManager(_poolManager)) {}

    function _pay(Currency token, address payer, uint256 amount) internal override {
        payOrPermit2Transfer(Currency.unwrap(token), payer, address(poolManager), amount);
    }
}

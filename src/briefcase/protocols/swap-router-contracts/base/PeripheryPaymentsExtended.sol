// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.7.5;

import {PeripheryPayments} from '../../v3-periphery/base/PeripheryPayments.sol';
import {IWETH9} from '../../v3-periphery/interfaces/external/IWETH9.sol';
import {TransferHelper} from '../../v3-periphery/libraries/TransferHelper.sol';
import {IPeripheryPaymentsExtended} from '../interfaces/IPeripheryPaymentsExtended.sol';

abstract contract PeripheryPaymentsExtended is IPeripheryPaymentsExtended, PeripheryPayments {
    /// @inheritdoc IPeripheryPaymentsExtended
    function unwrapWETH9(uint256 amountMinimum) external payable override {
        unwrapWETH9(amountMinimum, msg.sender);
    }

    /// @inheritdoc IPeripheryPaymentsExtended
    function wrapETH(uint256 value) external payable override {
        IWETH9(WETH9).deposit{value: value}();
    }

    /// @inheritdoc IPeripheryPaymentsExtended
    function sweepToken(address token, uint256 amountMinimum) external payable override {
        sweepToken(token, amountMinimum, msg.sender);
    }

    /// @inheritdoc IPeripheryPaymentsExtended
    function pull(address token, uint256 value) external payable override {
        TransferHelper.safeTransferFrom(token, msg.sender, address(this), value);
    }
}

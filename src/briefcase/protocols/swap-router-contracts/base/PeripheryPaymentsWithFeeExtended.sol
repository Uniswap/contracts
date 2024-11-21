// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.7.5;

import {PeripheryPaymentsWithFee} from '../../v3-periphery/base/PeripheryPaymentsWithFee.sol';
import {IPeripheryPaymentsWithFeeExtended} from '../interfaces/IPeripheryPaymentsWithFeeExtended.sol';
import {PeripheryPaymentsExtended} from './PeripheryPaymentsExtended.sol';

abstract contract PeripheryPaymentsWithFeeExtended is
    IPeripheryPaymentsWithFeeExtended,
    PeripheryPaymentsExtended,
    PeripheryPaymentsWithFee
{
    /// @inheritdoc IPeripheryPaymentsWithFeeExtended
    function unwrapWETH9WithFee(uint256 amountMinimum, uint256 feeBips, address feeRecipient)
        external
        payable
        override
    {
        unwrapWETH9WithFee(amountMinimum, msg.sender, feeBips, feeRecipient);
    }

    /// @inheritdoc IPeripheryPaymentsWithFeeExtended
    function sweepTokenWithFee(address token, uint256 amountMinimum, uint256 feeBips, address feeRecipient)
        external
        payable
        override
    {
        sweepTokenWithFee(token, amountMinimum, msg.sender, feeBips, feeRecipient);
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {ICounter} from './interface/ICounter.sol';

contract Counter is ICounter {
    uint256 public number;

    constructor(uint256 initialNumber) {
        number = initialNumber;
    }

    /// @inheritdoc ICounter
    function setNumber(uint256 newNumber) public {
        number = newNumber;
    }

    /// @inheritdoc ICounter
    function increment() public {
        number++;
    }
}

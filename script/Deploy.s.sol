// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import 'forge-std/Script.sol';

import {Counter} from 'src/Counter.sol';

contract Deploy is Script {
    using stdJson for string;

    function run() public returns (Counter) {
        uint256 initialNumber = 5;
        return new Counter(initialNumber);
    }
}

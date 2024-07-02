// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from 'forge-std/Test.sol';

contract DummyTest is Test {
    /// @dev tests throw an error in CI if there is no test to run
    function test() external pure {
        assertTrue(true);
    }
}

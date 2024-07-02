// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {GasSnapshot} from 'forge-gas-snapshot/GasSnapshot.sol';
import 'forge-std/Test.sol';

import {Deploy} from 'script/Deploy.s.sol';
import {Counter} from 'src/Counter.sol';

abstract contract Deployed is Test {
    Counter counter;

    function setUp() public virtual {
        uint256 initialNumber = 10;
        counter = new Counter(initialNumber);
    }
}

contract CounterTest_Deployed is Deployed, GasSnapshot {
    function test_IsInitialized() public view {
        assertEq(counter.number(), 10);
    }

    function test_IncrementsNumber() public {
        counter.increment();
        snapLastCall('Increment counter number');
        assertEq(counter.number(), 11);
    }

    function test_fuzz_SetsNumber(uint256 x) public {
        counter.setNumber(x);
        assertEq(counter.number(), x);
    }

    function test_SetNumber_gas() public {
        uint256 x = 100;
        counter.setNumber(x);
        snapLastCall('Set counter number');
    }
}

contract DeploymentTest is Test {
    Counter counter;

    function setUp() public virtual {
        counter = new Deploy().run();
    }

    function test_IsDeployedCorrectly() public view {
        assertEq(counter.number(), 5);
    }
}

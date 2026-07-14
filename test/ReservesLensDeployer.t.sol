// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ReservesLensDeployer} from '../src/briefcase/deployers/v4-periphery/ReservesLensDeployer.sol';
import {Test} from 'forge-std/Test.sol';

/// @notice Guards the canonical ReservesLens deployment. ReservesLens is constructor-free, so its initcode
///         is byte-identical on every chain and a single salt yields one cross-chain address via the
///         deterministic CREATE2 factory. If either assertion fails, the initcode drifted (regenerate and
///         re-pin deliberately) or the canonical address moved. The salt mirrors the default in
///         script/deploy/tasks/task_template.json (protocols.v4.contracts.ReservesLens).
contract ReservesLensDeployerTest is Test {
    address internal constant CREATE2_FACTORY = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
    bytes32 internal constant SALT = 0xbe3a44816031cf9fa9b3de006cfe808c702e82029e5fa5325d99a4b177f1414f;
    bytes32 internal constant INITCODE_HASH = 0x6c7ca10687a2f929c8c16fa6323306255526ef96fb820be2822bb7631af873f8;
    address internal constant CANONICAL_ADDRESS = 0x0000001b173C3bbF3984D417d8614E3eed34865B;

    function test_initcodeHash_isPinned() external pure {
        assertEq(keccak256(ReservesLensDeployer.initcode()), INITCODE_HASH, 'ReservesLens initcode drifted');
    }

    function test_canonicalAddress_matchesCreate2() external pure {
        address predicted =
            address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), CREATE2_FACTORY, SALT, INITCODE_HASH)))));
        assertEq(predicted, CANONICAL_ADDRESS, 'canonical ReservesLens address moved');
    }
}

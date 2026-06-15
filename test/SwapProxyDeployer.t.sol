// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {SwapProxyDeployer} from '../src/briefcase/deployers/universal-router/SwapProxyDeployer.sol';
import {Test} from 'forge-std/Test.sol';

/// @notice Guards the canonical SwapProxy deployment. Its initcode is frozen (see SwapProxyDeployer)
///         because the canonical address depends on an IPFS-metadata build that cannot be regenerated
///         in this repo. If either assertion fails, the canonical cross-chain address has moved and the
///         change must be rejected (or the constants deliberately re-pinned). The salt mirrors the
///         default in script/deploy/tasks/task_template.json (protocols.swap-proxy).
contract SwapProxyDeployerTest is Test {
    address internal constant CREATE2_FACTORY = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
    bytes32 internal constant SALT = 0xd00319ff7795e528cc1ccd28bd6e08e46a42130d69ab4992d656773ba5fb323c;
    bytes32 internal constant INITCODE_HASH = 0x342d83f4d7400dd603e2a6829db9cb032e7f62a2dda94746f2acd4e7e881bb2f;
    address internal constant CANONICAL_ADDRESS = 0x0000000085E102724e78eCd2F45DC9cA239Affad;

    function test_initcodeHash_isFrozen() external pure {
        assertEq(keccak256(SwapProxyDeployer.initcode()), INITCODE_HASH, 'SwapProxy initcode drifted');
    }

    function test_canonicalAddress_matchesCreate2() external pure {
        address predicted =
            address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), CREATE2_FACTORY, SALT, INITCODE_HASH)))));
        assertEq(predicted, CANONICAL_ADDRESS, 'canonical SwapProxy address moved');
    }
}

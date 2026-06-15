// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {SwapProxyDeployer} from '../src/briefcase/deployers/universal-router/SwapProxyDeployer.sol';
import {Test} from 'forge-std/Test.sol';

/// @notice Guards the canonical SwapProxy deployment: the frozen initcode and the resulting CREATE2
///         address must never change. If this test fails, the canonical cross-chain address has moved
///         and the change must be rejected (or the constants deliberately re-pinned).
contract SwapProxyDeployerTest is Test {
    address internal constant CREATE2_FACTORY = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    function test_initcodeHash_isFrozen() external pure {
        assertEq(keccak256(SwapProxyDeployer.initcode()), SwapProxyDeployer.INITCODE_HASH, 'initcode drifted');
    }

    function test_canonicalAddress_matchesCreate2() external pure {
        address predicted = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff), CREATE2_FACTORY, SwapProxyDeployer.SALT, SwapProxyDeployer.INITCODE_HASH
                        )
                    )
                )
            )
        );
        assertEq(predicted, SwapProxyDeployer.CANONICAL_ADDRESS, 'canonical address moved');
    }

    function test_deploy_landsAtCanonicalAddress_andIsIdempotent() external {
        // Foundry pre-deploys the deterministic CREATE2 factory at 0x4e59...4956C in the test EVM.
        assertGt(CREATE2_FACTORY.code.length, 0, 'CREATE2 factory missing in test EVM');

        address deployed = SwapProxyDeployer.deploy();
        assertEq(deployed, SwapProxyDeployer.CANONICAL_ADDRESS, 'deployed to wrong address');
        assertGt(deployed.code.length, 0, 'no code at canonical address');

        // Second call must be a no-op returning the same address (no revert).
        assertEq(SwapProxyDeployer.deploy(), SwapProxyDeployer.CANONICAL_ADDRESS, 'not idempotent');
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console} from 'forge-std/Script.sol';
import {ReservesLensDeployer} from '../../src/briefcase/deployers/v4-periphery/ReservesLensDeployer.sol';

/// @notice Deploys ReservesLens deterministically via the canonical CREATE2 factory.
/// @dev ReservesLens is constructor-free, so the mined salt yields the same address on every chain.
///      Run per chain: forge script script/deploy/DeployReservesLens.s.sol --rpc-url <url> --account <keystore> --broadcast
contract DeployReservesLens is Script {
    /// @dev mined for 3 leading zero bytes against init-code-hash 0x6c7ca10687a2f929c8c16fa6323306255526ef96fb820be2822bb7631af873f8
    bytes32 internal constant SALT = 0xbe3a44816031cf9fa9b3de006cfe808c702e82029e5fa5325d99a4b177f1414f;
    address internal constant EXPECTED = 0x0000001b173C3bbF3984D417d8614E3eed34865B;

    function run() external {
        if (EXPECTED.code.length > 0) {
            console.log('ReservesLens already deployed at', EXPECTED);
            return;
        }

        vm.startBroadcast();
        address deployed = ReservesLensDeployer.deploy(SALT);
        vm.stopBroadcast();

        console.log('ReservesLens deployed at', deployed);
        require(deployed == EXPECTED, 'address mismatch: initcode or salt changed');
    }
}

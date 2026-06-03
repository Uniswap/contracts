// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console2} from 'forge-std/Script.sol';

/// @title DeploySwapProxyCreate2
/// @notice Deploys SwapProxy to a single deterministic address on every chain via the canonical
///         CREATE2 factory, using a FROZEN initcode artifact rather than a fresh local compile.
/// @dev Source-of-truth model (see .swapproxy-deploy/README.md):
///      - The address is determined ONLY by {factory, salt, initcode}, never by the deployer key.
///      - The initcode is the frozen canonical SwapProxy build (matches the mainnet-verified 1005-byte
///        runtime). We deploy these exact bytes so every chain converges on identical bytecode.
///      - We intentionally do NOT recompile SwapProxy from the universal-router submodule here: the
///        repo's `universal-router` profile (optimizer_runs=1, bytecode_hash=none) yields a different
///        964-byte build, and the UR router implementation is irrelevant to SwapProxy's bytecode
///        anyway (SwapProxy only references the IUniversalRouter interface).
contract DeploySwapProxyCreate2 is Script {
    // NOTE: CREATE2_FACTORY (0x4e59...4956C, the Arachnid deterministic deployment proxy) is
    // inherited from forge-std's CommonBase and is the same address on every supported chain.

    /// @notice Salt for the canonical SwapProxy deployment.
    bytes32 internal constant SALT = bytes32(0);

    /// @notice keccak256 of the frozen initcode. Guards against artifact corruption.
    bytes32 internal constant INITCODE_HASH = 0x342d83f4d7400dd603e2a6829db9cb032e7f62a2dda94746f2acd4e7e881bb2f;

    /// @notice Deterministic SwapProxy address for {CREATE2_FACTORY, SALT, INITCODE_HASH}.
    address internal constant EXPECTED_ADDRESS = 0x18F2e4BE6c4E266a8150605867D81a484E77708a;

    /// @notice Path to the frozen canonical initcode (hex, 0x-prefixed, no trailing whitespace).
    string internal constant INITCODE_PATH = '.swapproxy-deploy/canonical-initcode.hex';

    error InitcodeHashMismatch(bytes32 expected, bytes32 actual);
    error AddressMismatch(address expected, address actual);
    error FactoryMissing(address factory);
    error DeployFailed();

    function run() external {
        bytes memory initcode = vm.parseBytes(vm.readFile(INITCODE_PATH));

        // The frozen artifact must be byte-identical to what the constants describe.
        bytes32 initcodeHash = keccak256(initcode);
        if (initcodeHash != INITCODE_HASH) revert InitcodeHashMismatch(INITCODE_HASH, initcodeHash);

        address predicted = _create2Address(SALT, initcodeHash);
        if (predicted != EXPECTED_ADDRESS) revert AddressMismatch(EXPECTED_ADDRESS, predicted);

        // Idempotent: if SwapProxy already lives at the canonical address on this chain, do nothing.
        if (EXPECTED_ADDRESS.code.length != 0) {
            console2.log('SwapProxy already deployed at', EXPECTED_ADDRESS);
            return;
        }

        if (CREATE2_FACTORY.code.length == 0) revert FactoryMissing(CREATE2_FACTORY);

        vm.startBroadcast();
        // Arachnid factory calldata is `salt (32 bytes) ++ initcode`.
        (bool ok,) = CREATE2_FACTORY.call(abi.encodePacked(SALT, initcode));
        vm.stopBroadcast();

        if (!ok || EXPECTED_ADDRESS.code.length == 0) revert DeployFailed();
        console2.log('SwapProxy deployed at', EXPECTED_ADDRESS);
    }

    /// @notice Computes the CREATE2 address: keccak256(0xff ++ factory ++ salt ++ initcodeHash)[12:].
    function _create2Address(bytes32 salt, bytes32 initcodeHash) internal pure returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), CREATE2_FACTORY, salt, initcodeHash)))));
    }
}

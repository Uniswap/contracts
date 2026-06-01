// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Hooks} from '../../../v4-core/libraries/Hooks.sol';

/// @title AggregatorHookMiner
/// @notice a minimal library for mining aggregator hook addresses
/// @dev This library is a version of HookMiner that incorporates the aggregator hook identification system.
library AggregatorHookMiner {
    // mask to slice out the bottom 14 bit of the address
    uint160 constant FLAG_MASK = Hooks.ALL_HOOK_MASK; // 0000 ... 0000 0011 1111 1111 1111

    // Maximum number of iterations to find a salt, avoid infinite loops or MemoryOOG
    // (arbitrarily set)
    uint256 constant MAX_LOOP = 160_444;

    /// @notice Find a salt that produces a hook address with the desired `flags` and first byte ID
    /// @param deployer The address that will deploy the hook. In `forge test`, this will be the test contract `address(this)` or the pranking address
    /// In `forge script`, this should be `0x4e59b44847b379578588920cA78FbF26c0B4956C` (CREATE2 Deployer Proxy)
    /// @param flags The desired flags for the hook address. Example `uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG | ...)`
    /// @param firstByte The desired first byte of the hook address (e.g., 0xC1 for StableSwap, 0xC2 for StableSwap-NG, 0xF1 for FluidDexT1, 0x71 for TempoExchange, etc.)
    /// @param creationCode The creation code of a hook contract. Example: `type(Counter).creationCode`
    /// @param constructorArgs The encoded constructor arguments of a hook contract. Example: `abi.encode(address(manager))`
    /// @param saltOffset The starting salt value for the search. Increment by MAX_LOOP for subsequent attempts.
    /// @return hookAddress The computed hook address
    /// @return salt The salt that produces the hook address
    function find(
        address deployer,
        uint160 flags,
        uint8 firstByte,
        bytes memory creationCode,
        bytes memory constructorArgs,
        uint256 saltOffset
    ) internal view returns (address, bytes32) {
        flags = flags & FLAG_MASK; // mask for only the bottom 14 bits
        // Shift first byte to the most significant byte position (bits 152-159)
        uint160 firstByteMask = uint160(0xFF) << 152; // 0xFF00000000000000000000000000000000000000
        uint160 desiredFirstByte = uint160(firstByte) << 152;
        bytes memory creationCodeWithArgs = abi.encodePacked(creationCode, constructorArgs);

        address hookAddress;
        for (uint256 salt = saltOffset; salt < saltOffset + MAX_LOOP; salt++) {
            hookAddress = computeAddress(deployer, salt, creationCodeWithArgs);

            // if the hook's bottom 14 bits match the desired flags, first byte matches the desired ID, AND the address does not have bytecode, we found a match
            if (
                uint160(hookAddress) & FLAG_MASK == flags && (uint160(hookAddress) & firstByteMask) == desiredFirstByte
                    && hookAddress.code.length == 0
            ) {
                return (hookAddress, bytes32(salt));
            }
        }
        revert('HookMiner: could not find salt');
    }

    /// @notice Precompute a contract address deployed via CREATE2
    /// @param deployer The address that will deploy the hook. In `forge test`, this will be the test contract `address(this)` or the pranking address
    /// In `forge script`, this should be `0x4e59b44847b379578588920cA78FbF26c0B4956C` (CREATE2 Deployer Proxy)
    /// @param salt The salt used to deploy the hook
    /// @param creationCodeWithArgs The creation code of a hook contract, with encoded constructor arguments appended. Example: `abi.encodePacked(type(Counter).creationCode, abi.encode(constructorArg1, constructorArg2))`
    /// @return hookAddress The address of the hook
    function computeAddress(address deployer, uint256 salt, bytes memory creationCodeWithArgs)
        internal
        pure
        returns (address hookAddress)
    {
        return address(
            uint160(uint256(keccak256(abi.encodePacked(bytes1(0xFF), deployer, salt, keccak256(creationCodeWithArgs)))))
        );
    }
}

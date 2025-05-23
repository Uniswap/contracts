// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

struct Call {
    address to;
    uint256 value;
    bytes data;
}

/// @title CallLib
/// @notice A library for hashing and encoding calls
library CallLib {
    /// @dev The type string for the Call struct
    bytes internal constant CALL_TYPE = 'Call(address to,uint256 value,bytes data)';

    /// @dev The typehash for the Call struct
    bytes32 internal constant CALL_TYPEHASH = keccak256(CALL_TYPE);

    /// @notice Hash a single struct according to EIP-712.
    function hash(Call memory call) internal pure returns (bytes32) {
        return keccak256(abi.encode(CALL_TYPEHASH, call.to, call.value, keccak256(call.data)));
    }

    /// @notice Hash an array of structs according to EIP-712.
    function hash(Call[] memory calls) internal pure returns (bytes32) {
        bytes32[] memory hashes = new bytes32[](calls.length);
        unchecked {
            for (uint256 i = 0; i < calls.length; i++) {
                hashes[i] = hash(calls[i]);
            }
        }
        return keccak256(abi.encodePacked(hashes));
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

struct Call {
    address to;
    uint256 value;
    bytes data;
}

library CallLib {
    /// @dev The type string for the Call struct
    bytes internal constant CALL_TYPE = 'Call(address to,uint256 value,bytes data)';

    /// @dev The typehash for the Call struct
    bytes32 internal constant CALL_TYPEHASH = keccak256(CALL_TYPE);

    /// @notice Hash a single call
    function hash(Call memory call) internal pure returns (bytes32) {
        return keccak256(abi.encode(CALL_TYPEHASH, call.to, call.value, call.data));
    }

    /// @notice Hash a series of calls
    function hash(Call[] memory calls) internal pure returns (bytes32) {
        unchecked {
            bytes memory packedHashes = new bytes(32 * calls.length);

            for (uint256 i = 0; i < calls.length; i++) {
                bytes32 callHash = hash(calls[i]);
                assembly {
                    mstore(add(add(packedHashes, 0x20), mul(i, 0x20)), callHash)
                }
            }

            return keccak256(packedHashes);
        }
    }
}

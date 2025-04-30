// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {BatchedCall, BatchedCallLib} from './BatchedCallLib.sol';

struct SignedBatchedCall {
    BatchedCall batchedCall;
    uint256 nonce;
    bytes32 keyHash;
    address executor; // address(0) allows anyone to execute the batched call
}

/// @title SignedBatchedCallLib
/// @notice Library for EIP-712 hashing of SignedBatchedCall
library SignedBatchedCallLib {
    using BatchedCallLib for BatchedCall;

    /// @dev The type string for the SignedBatchedCall struct
    bytes internal constant SIGNED_BATCHED_CALL_TYPE =
        'SignedBatchedCall(BatchedCall batchedCall,uint256 nonce,bytes32 keyHash,address executor)BatchedCall(Call[] calls,bool revertOnFailure)Call(address to,uint256 value,bytes data)';
    /// @dev The typehash for the SignedBatchedCall struct
    bytes32 internal constant SIGNED_BATCHED_CALL_TYPEHASH = keccak256(SIGNED_BATCHED_CALL_TYPE);

    /// @notice Hashes a SignedBatchedCall struct.
    function hash(SignedBatchedCall memory signedBatchedCall) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                SIGNED_BATCHED_CALL_TYPEHASH,
                signedBatchedCall.batchedCall.hash(),
                signedBatchedCall.nonce,
                signedBatchedCall.keyHash,
                signedBatchedCall.executor
            )
        );
    }
}

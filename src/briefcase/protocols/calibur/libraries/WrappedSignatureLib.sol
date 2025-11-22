// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {CalldataDecoder} from './CalldataDecoder.sol';

/// @title WrappedSignatureLib
/// @notice A library for handling signatures with different wrapping schemes
library WrappedSignatureLib {
    using CalldataDecoder for bytes;

    /// error InvalidSignatureLength();
    uint256 constant INVALID_SIGNATURE_LENGTH_SELECTOR = 0x4be6321b;

    /// @notice Returns true if the signature is empty
    /// @dev For use in the ERC-7739 sentinel value check
    function isEmpty(bytes calldata data) internal pure returns (bool) {
        return data.length == 0;
    }

    /// @notice Returns true for standard or compact length ECDSA signatures
    /// @dev will also return true for standard p256 signatures however those MUST be wrapped with extra information in the verify sig flow
    function isRawSignature(bytes calldata data) internal pure returns (bool) {
        return data.length == 65 || data.length == 64;
    }

    /// @notice Decode the signature and hook data from the calldata
    /// @dev The calldata is expected to be encoded as `abi.encode(bytes signature, bytes hookData)`
    /// If the length of the data does not match the encoded length the function will revert with `SliceOutOfBounds()`
    /// Also, if the signature is less than 64 bytes, it will revert with `InvalidSignatureLength()`
    function decodeWithHookData(bytes calldata data)
        internal
        pure
        returns (bytes calldata signature, bytes calldata hookData)
    {
        signature = data.safeToBytes(0);
        hookData = data.safeToBytes(1);
        assembly ("memory-safe") {
            if lt(signature.length, 64) {
                mstore(0, INVALID_SIGNATURE_LENGTH_SELECTOR)
                revert(0x1c, 4)
            }
        }
    }

    /// @notice Decode the keyHash, signature, and hook data from the calldata
    /// @dev The calldata is expected to be encoded as `abi.encode(bytes32 keyHash, bytes signature, bytes hookData)`
    /// If the length of the data does not match the encoded length the function will revert with `SliceOutOfBounds()`
    /// Also, if the signature is less than 64 bytes, it will revert with `InvalidSignatureLength()`
    function decodeWithKeyHashAndHookData(bytes calldata data)
        internal
        pure
        returns (bytes32 keyHash, bytes calldata signature, bytes calldata hookData)
    {
        assembly {
            keyHash := calldataload(data.offset)
        }
        signature = data.safeToBytes(1);
        hookData = data.safeToBytes(2);
        assembly ("memory-safe") {
            if lt(signature.length, 64) {
                mstore(0, INVALID_SIGNATURE_LENGTH_SELECTOR)
                revert(0x1c, 4)
            }
        }
    }

    /// @notice Decode the signature, appSeparator, contentsHash, and contentsDescr from the calldata
    ///         the return values MUST be checked for length before use
    /// @dev The calldata is expected to be encoded as `abi.encode(bytes signature, bytes32 appSeparator, bytes32 contentsHash, string contentsDescr)`
    ///      there may be an uint16 contentsLength at the end of the calldata, but this is not used
    /// This function should NOT revert, and just returns empty values if the bytes length are incorrect.
    function decodeAsTypedDataSig(bytes calldata data)
        internal
        pure
        returns (bytes calldata signature, bytes32 appSeparator, bytes32 contentsHash, string calldata contentsDescr)
    {
        signature = data.toBytes(0);
        assembly {
            appSeparator := calldataload(add(data.offset, 0x20))
            contentsHash := calldataload(add(data.offset, 0x40))
        }
        contentsDescr = string(data.toBytes(3));
    }
}

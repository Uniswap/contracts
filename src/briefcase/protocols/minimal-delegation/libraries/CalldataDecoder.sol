// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Call} from './CallLib.sol';

library CalldataDecoder {
    using CalldataDecoder for bytes;
    /// @notice equivalent to SliceOutOfBounds.selector, stored in least-significant bits

    /// @notice mask used for offsets and lengths to ensure no overflow
    /// @dev no sane abi encoding will pass in an offset or length greater than type(uint32).max
    ///      (note that this does deviate from standard solidity behavior and offsets/lengths will
    ///      be interpreted as mod type(uint32).max which will only impact malicious/buggy callers)
    uint256 constant OFFSET_OR_LENGTH_MASK = 0xffffffff;
    uint256 constant OFFSET_OR_LENGTH_MASK_AND_WORD_ALIGN = 0xffffffe0;

    /// error SliceOutOfBounds();
    uint256 constant SLICE_ERROR_SELECTOR = 0x3b99b53d;

    /// @notice equivalent to abi.decode(data, (uint256, bytes)) in calldata
    /// @return _value A uint256 value
    /// @return _data Bytes data following the uint256 value.
    function decodeUint256Bytes(bytes calldata data) internal pure returns (uint256 _value, bytes calldata _data) {
        assembly {
            _value := calldataload(data.offset)
        }
        _data = data.toBytes(1);
    }

    // TODO length check
    function decodeCalls(bytes calldata data) internal pure returns (Call[] calldata calls) {
        assembly {
            let lengthPtr := add(data.offset, calldataload(data.offset))
            calls.offset := add(lengthPtr, 0x20)
            calls.length := calldataload(lengthPtr)
        }
    }

    // TODO: Length check
    function decodeCallsBytes(bytes calldata data)
        internal
        pure
        returns (Call[] calldata calls, bytes calldata opData)
    {
        assembly {
            let lengthPtr := add(data.offset, calldataload(data.offset))
            calls.offset := add(lengthPtr, 0x20)
            calls.length := calldataload(lengthPtr)

            let opLengthPtr := add(data.offset, calldataload(add(data.offset, 0x20)))
            opData.offset := add(opLengthPtr, 0x20)
            opData.length := calldataload(opLengthPtr)
        }
    }

    /// TODO: Import CalldataDecoder.sol, has been previously audited.
    /// @notice Decode the `_arg`-th element in `_bytes` as `bytes`
    // @param _bytes The input bytes string to extract a bytes string from
    // @param _arg The index of the argument to extract
    function toBytes(bytes calldata _bytes, uint256 _arg) internal pure returns (bytes calldata res) {
        uint256 length;
        assembly ("memory-safe") {
            // The offset of the `_arg`-th element is `32 * arg`, which stores the offset of the length pointer.
            // shl(5, x) is equivalent to mul(32, x)
            let lengthPtr :=
                add(_bytes.offset, and(calldataload(add(_bytes.offset, shl(5, _arg))), OFFSET_OR_LENGTH_MASK))
            // the number of bytes in the bytes string
            length := and(calldataload(lengthPtr), OFFSET_OR_LENGTH_MASK)
            // the offset where the bytes string begins
            let offset := add(lengthPtr, 0x20)
            // assign the return parameters
            res.length := length
            res.offset := offset

            // if the provided bytes string isnt as long as the encoding says, revert
            if lt(add(_bytes.length, _bytes.offset), add(length, offset)) {
                mstore(0, SLICE_ERROR_SELECTOR)
                revert(0x1c, 4)
            }
        }
    }
}

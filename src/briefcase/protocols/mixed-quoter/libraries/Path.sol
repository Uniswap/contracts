// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.6.0;

import {BytesLib} from '../../universal-router/modules/uniswap/v3/BytesLib.sol';
import {V3Path} from '../../universal-router/modules/uniswap/v3/V3Path.sol';
import {IHooks} from '../../v4-core/interfaces/IHooks.sol';
import {Currency} from '../../v4-core/types/Currency.sol';
import {PoolKey} from '../../v4-core/types/PoolKey.sol';
import {Constants} from './Constants.sol';

/// @title Functions for manipulating path data for multihop swaps
library Path {
    using Path for bytes;
    using V3Path for bytes;
    using BytesLib for bytes;

    /// @notice Decodes the first pool in path
    /// @param path The bytes encoded swap path
    function decodeProtocolVersion(bytes calldata path) internal pure returns (uint8 protocolVersion) {
        if (path.length < Constants.ADDR_SIZE) revert BytesLib.SliceOutOfBounds();
        protocolVersion = (path.toUint8(Constants.ADDR_SIZE) & Constants.PROTOCOL_VERSION_BITMASK)
            >> Constants.PROTOCOL_VERSION_BITMASK_SHIFT;
    }

    /// @notice Decodes the first pool in path
    /// @param path The bytes encoded swap path
    /// @return tokenA The first token of the given pool
    /// @return tokenB The second token of the given pool
    function decodeFirstV2Pool(bytes calldata path) internal pure returns (address tokenA, address tokenB) {
        if (path.length < Constants.V2_POP_OFFSET) revert BytesLib.SliceOutOfBounds();
        tokenA = path.toAddress(0);
        tokenB = path.toAddress(Constants.NEXT_V2_POOL_OFFSET);
    }

    /// @notice Decodes the first pool in path
    /// @param path The bytes encoded swap path
    /// @return tokenA The first token of the given pool
    /// @return fee The fee level of the pool
    /// @return tokenB The second token of the given pool
    function decodeFirstV3Pool(bytes calldata path) internal pure returns (address tokenA, uint24 fee, address tokenB) {
        // calls the function in V3Path library
        (tokenA, fee, tokenB) = path.decodeFirstPool();
        fee = (fee << Constants.FEE_SHIFT) >> Constants.FEE_SHIFT;
    }

    /// @notice Decodes the first pool in path
    /// @param path The bytes encoded swap path
    /// @return tokenIn The address at byte 0
    /// @return fee The uint24 starting at byte 20
    /// @return tickSpacing The uint24 starting at byte 23
    /// @return hooks The address at byte 26
    /// @return tokenOut The address at byte 47
    function decodeFirstV4Pool(bytes calldata path)
        internal
        pure
        returns (address tokenIn, uint24 fee, uint24 tickSpacing, address hooks, address tokenOut)
    {
        if (path.length < Constants.V4_POP_OFFSET) revert BytesLib.SliceOutOfBounds();
        tokenIn = path.toAddress(0);
        fee = path.toUint24(Constants.ADDR_SIZE) & Constants.V4_FEE_BITMASK;
        tickSpacing = path.toUint24(Constants.ADDR_SIZE + Constants.V4_FEE_SIZE);
        hooks = path.toAddress(Constants.ADDR_SIZE + Constants.V4_FEE_SIZE + Constants.TICK_SPACING_SIZE);
        tokenOut = path.toAddress(Constants.NEXT_V4_POOL_OFFSET);
    }

    /// @notice v4 pool convert to pool key
    /// @dev length and overflow checks must be carried out before calling
    /// @param token0 The address at byte 0
    /// @param fee The uint24 starting at byte 20
    /// @param tickSpacing The uint24 starting at byte 23
    /// @param hooks The address at byte 26
    /// @param token1 The address at byte 46
    /// @return PoolKey
    function v4PoolToPoolKey(address token0, uint24 fee, uint24 tickSpacing, address hooks, address token1)
        internal
        pure
        returns (PoolKey memory)
    {
        (token0, token1) = token0 < token1 ? (token0, token1) : (token1, token0);
        Currency currency0 = Currency.wrap(token0);
        Currency currency1 = Currency.wrap(token1);
        return PoolKey({
            currency0: currency0, currency1: currency1, fee: fee, tickSpacing: int24(tickSpacing), hooks: IHooks(hooks)
        });
    }

    /// @notice Skips a token + fee element
    /// @param path The swap path
    function skipToken(bytes calldata path, uint8 protocolVersion) internal pure returns (bytes calldata) {
        if (protocolVersion == uint8(2) || protocolVersion == uint8(0)) {
            // treat wrap, unwrap command like protocol v2
            return path[Constants.NEXT_V2_POOL_OFFSET:];
        } else if (protocolVersion == uint8(3)) {
            return path[Constants.NEXT_V3_POOL_OFFSET:];
        } else if (protocolVersion == uint8(4)) {
            return path[Constants.NEXT_V4_POOL_OFFSET:];
        } else {
            revert('invalid_PROTOCOL_VERSION');
        }
    }

    function skipHookData(bytes calldata allHookData, uint256 hookDataLength) internal pure returns (bytes calldata) {
        return allHookData[hookDataLength:];
    }

    function toAddress(bytes calldata _bytes, uint256 _start) internal pure returns (address result) {
        require(_bytes.length >= _start + 20, 'toAddress_outOfBounds');

        assembly {
            result := shr(96, calldataload(add(_bytes.offset, _start)))
        }
    }

    function toUint24(bytes calldata _bytes, uint256 _start) internal pure returns (uint24 result) {
        require(_bytes.length >= _start + 3, 'toUint24_outOfBounds');

        assembly {
            result := shr(232, calldataload(add(_bytes.offset, _start)))
        }
    }

    function toUint8(bytes calldata _bytes, uint256 _start) internal pure returns (uint8 result) {
        require(_bytes.length >= _start + 1, 'toUint8_outOfBounds');

        assembly {
            result := shr(248, calldataload(add(_bytes.offset, _start)))
        }
    }
}

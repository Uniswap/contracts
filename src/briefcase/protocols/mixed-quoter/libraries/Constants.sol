// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

/// @title Constant state
/// @notice Constant state used by the Mixed Quoter
library Constants {
    /// @dev The bitmask for the protocol version, used to determine the protocol version
    /// 01110000 is the bit mask.
    /// We only need one byte, 8 bit, because the fee is largest 100%, 1000000 hundreds of bps, or 000011110100001001000000
    /// So the first four bit can be reserved for protocol versions.
    /// If protocol version is 0, 0000xxxxxxxxxxxxxxxxxxxx & 01110000 = 00000000
    /// If protocol version is 2, 0010xxxxxxxxxxxxxxxxxxxx & 01110000 = 00100000
    /// If protocol version is 3, 0011xxxxxxxxxxxxxxxxxxxx & 01110000 = 00110000
    /// If protocol version is 4, 0100xxxxxxxxxxxxxxxxxxxx & 01110000 = 01000000
    uint8 internal constant PROTOCOL_VERSION_BITMASK = 0x70; // 0111 0000

    /// @dev protocol version bit shift to recover the protocol version
    /// 20 is the number of bits in the bitmask
    /// If protocol version is 2, 00100000 >> 4 = 0010
    /// If protocol version is 3, 00110000 >> 4 = 0011
    /// If protocol version is 4, 01000000 >> 4 = 0100
    uint8 internal constant PROTOCOL_VERSION_BITMASK_SHIFT = 4;

    /// @dev fee bit shift to recover the fee, applicable to v3 v4 LP fees
    /// left shift 4 bits, and then right shift 4 bits
    /// for example, a v3 fee 0.3% is 3000, or 101110111000
    /// (101110111000 << 4) >> 4 = 000000000000101110111000
    uint8 internal constant FEE_SHIFT = 4;

    /// @dev fee bitmask to recover the fee, applicable to v4 LP fees
    /// for example, a v4 fee 100% is 1000000, or 000011110100001001000000
    /// 000011110100001001000000 & 100011111111111111111111 = 000011110100001001000000
    /// if v4 fee is dynamic, then it's 100000000000000000000000
    /// 100000000000000000000000 & 100011111111111111111111 = 100000000000000000000000
    uint24 internal constant V4_FEE_BITMASK = 0x8FFFFF; // 100011111111111111111111

    /// @dev The length of the bytes encoded address
    uint8 internal constant ADDR_SIZE = 20;

    /// @dev The length of the bytes encoded fee
    /// V2 we only have 1 byte fee, because v2 fee is only 0.3%, so we only need to encode the protocol version size, which is the same as v2 fee size.
    uint8 internal constant V2_FEE_SIZE = 1;

    /// @dev The length of the bytes encoded fee
    uint8 internal constant V3_FEE_SIZE = 3;

    /// @dev The length of the bytes encoded fee
    uint8 internal constant V4_FEE_SIZE = 3;

    /// @dev The length of the bytes encoded tick spacing
    uint8 internal constant TICK_SPACING_SIZE = 3;

    /// @dev The offset of a single token address (20)
    uint8 internal constant NEXT_V2_POOL_OFFSET = ADDR_SIZE + V2_FEE_SIZE;

    /// @dev The offset of an encoded pool key
    /// Token (20) + Token (20) = 40
    uint8 internal constant V2_POP_OFFSET = NEXT_V2_POOL_OFFSET + ADDR_SIZE;

    /// @dev The offset of a single token address (20) and pool fee (3)
    uint8 internal constant NEXT_V3_POOL_OFFSET = ADDR_SIZE + V3_FEE_SIZE;

    /// @dev The offset of an encoded pool key
    /// Token (20) + Fee (3) + Token (20) = 43
    uint8 internal constant V3_POP_OFFSET = NEXT_V3_POOL_OFFSET + ADDR_SIZE;

    /// @dev The offset of a single token address (20) and pool fee (3) + tick spacing (3) + hooks address (20) = 46
    uint8 internal constant NEXT_V4_POOL_OFFSET = ADDR_SIZE + V4_FEE_SIZE + TICK_SPACING_SIZE + ADDR_SIZE;

    /// @dev The offset of a single token address (20) and pool fee (3) + tick spacing (3) + hooks address (20) + token address (20) = 66
    uint8 internal constant V4_POP_OFFSET = NEXT_V4_POOL_OFFSET + ADDR_SIZE;

    /// @dev The minimum length of an encoding that contains 2 or more pools
    uint8 internal constant MULTIPLE_POOLS_MIN_LENGTH = 2;

    bytes32 internal constant UNISWAP_V2_POOL_INIT_CODE_HASH =
        hex'96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f';

    bytes32 internal constant UNISWAP_V3_POOL_INIT_CODE_HASH =
        0xe34f199b19b2b4f47f68442619d555527d244f78a3297ea89325f843f87b8b54;

    uint8 internal constant MINIMUM_VALID_RESPONSE_LENGTH = 92;
}

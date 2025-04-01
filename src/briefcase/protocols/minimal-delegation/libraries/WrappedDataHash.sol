// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

/// @title WrappedDataHash
/// @notice A library to produce EIP-712 compliant typed data hash over arbitrary data. This is meant to be used in the ERC-1271 callback to wrap arbitrary data with a wallet specific typehash.
/// The typehash should then be hashed with the wallet specific domain separator to prevent replay attacks that can occur with ERC-1271 compliant wallets.
/// Note that verifying the hash with only the typed wrapper will not prevent replay attacks. The data must be signed over with the domain separator to prevent replay attacks.
/// @dev See https://mirror.xyz/curiousapple.eth/pFqAdW2LiJ-6S4sg_u1z08k4vK6BCJ33LcyXpnNb8yU
/// @author Modified from Coinbase (https://github.com/coinbase/smart-wallet)
library WrappedDataHash {
    /// @dev Precomputed `typeHash` used to produce EIP-712 compliant typed datahash that wraps the underlying data.
    bytes32 private constant _UNISWAP_WALLET_MESSAGE_TYPEHASH = keccak256('UniswapWalletMessage(bytes32 data)');

    /// @notice Produces a EIP-712 hash of the `UniswapMinimalDelegationMessage(bytes32 hash)` data structure.
    /// @param data The underlying data to be wrapped in the typehash.
    /// @return The resulting hash to be hashed with the domain separator.
    function hashWithWrappedType(bytes32 data) internal pure returns (bytes32) {
        return keccak256(abi.encode(_UNISWAP_WALLET_MESSAGE_TYPEHASH, data));
    }
}

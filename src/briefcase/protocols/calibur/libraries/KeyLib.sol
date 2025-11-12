// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {P256} from '../../lib-external/openzeppelin-contracts/contracts/utils/cryptography/P256.sol';
import {ECDSA} from '../../lib-external/solady/src/utils/ECDSA.sol';
import {EfficientHashLib} from '../../lib-external/solady/src/utils/EfficientHashLib.sol';
import {WebAuthn} from '../../lib-external/webauthn-sol/src/WebAuthn.sol';

/// @dev The type of key.
enum KeyType {
    P256,
    WebAuthnP256,
    Secp256k1
}

struct Key {
    /// @dev Type of key. See the {KeyType} enum.
    KeyType keyType;
    /// @dev Public key in encoded form.
    bytes publicKey;
}

library KeyLib {
    /// @notice The sentinel hash value used to represent the root key
    bytes32 public constant ROOT_KEY_HASH = bytes32(0);

    /// @notice Hashes a key
    /// @dev uses the key type and the public key to produce a hash
    function hash(Key memory key) internal pure returns (bytes32) {
        return keccak256(abi.encode(key.keyType, keccak256(key.publicKey)));
    }

    /// @notice Returns whether the keyHash is the root key hash
    function isRootKey(bytes32 keyHash) internal pure returns (bool) {
        return keyHash == ROOT_KEY_HASH;
    }

    /// @notice Returns whether the key is the root key
    function isRootKey(Key memory key) internal view returns (bool) {
        return key.keyType == KeyType.Secp256k1 && abi.decode(key.publicKey, (address)) == address(this);
    }

    /// @notice A helper function to get the root key object.
    function toRootKey() internal view returns (Key memory) {
        return Key({keyType: KeyType.Secp256k1, publicKey: abi.encode(address(this))});
    }

    /// @notice Turns a calling address into a key hash.
    /// @dev This key must be a SECP256K1 key since it is calling the contract.
    function toKeyHash(address caller) internal view returns (bytes32) {
        if (caller == address(this)) return ROOT_KEY_HASH;
        return hash(Key({keyType: KeyType.Secp256k1, publicKey: abi.encode(caller)}));
    }

    /// @notice Verifies a signature from `key` over a `_hash`
    /// @dev Signatures from P256 are expected to be over the `sha256` hash of `_hash`
    function verify(Key memory key, bytes32 _hash, bytes calldata signature) internal view returns (bool isValid) {
        if (key.keyType == KeyType.Secp256k1) {
            address result = ECDSA.tryRecoverCalldata(_hash, signature);
            isValid = result == address(0) ? false : result == abi.decode(key.publicKey, (address));
        } else if (key.keyType == KeyType.P256) {
            // Extract x,y from the public key
            (bytes32 x, bytes32 y) = abi.decode(key.publicKey, (bytes32, bytes32));
            // Split signature into r and s values.
            (bytes32 r, bytes32 s) = abi.decode(signature, (bytes32, bytes32));
            isValid = P256.verify(EfficientHashLib.sha2(_hash), r, s, x, y);
        } else if (key.keyType == KeyType.WebAuthnP256) {
            // Extract x,y from the public key
            (uint256 x, uint256 y) = abi.decode(key.publicKey, (uint256, uint256));
            // Decode the signature into the WebAuthnAuth struct
            WebAuthn.WebAuthnAuth memory auth = abi.decode(signature, (WebAuthn.WebAuthnAuth));
            isValid = WebAuthn.verify({challenge: abi.encode(_hash), requireUV: false, webAuthnAuth: auth, x: x, y: y});
        } else {
            isValid = false;
        }
    }
}

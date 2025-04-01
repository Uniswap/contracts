// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {ECDSA} from '../../lib-external/openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol';
import {P256} from '../../lib-external/openzeppelin-contracts/contracts/utils/cryptography/P256.sol';

/// @dev The type of key.
enum KeyType {
    P256,
    WebAuthnP256,
    Secp256k1
}

struct Key {
    /// @dev Unix timestamp at which the key expires (0 = never).
    uint40 expiry;
    /// @dev Type of key. See the {KeyType} enum.
    KeyType keyType;
    /// @dev Whether the key is a super admin key.
    /// Super admin keys are allowed to execute any external call
    bool isSuperAdmin;
    /// @dev Public key in encoded form.
    bytes publicKey;
}

library KeyLib {
    function hash(Key memory key) internal pure returns (bytes32) {
        return keccak256(abi.encode(key.keyType, keccak256(key.publicKey)));
    }

    function verify(Key memory key, bytes32 _hash, bytes memory signature) internal view returns (bool isValid) {
        if (key.keyType == KeyType.Secp256k1) {
            isValid = ECDSA.recover(_hash, signature) == abi.decode(key.publicKey, (address));
        } else if (key.keyType == KeyType.P256) {
            // Extract x,y from the public key
            (bytes32 x, bytes32 y) = abi.decode(key.publicKey, (bytes32, bytes32));
            // Split signature into r and s values.
            (bytes32 r, bytes32 s) = abi.decode(signature, (bytes32, bytes32));
            isValid = P256.verify(_hash, r, s, x, y);
        } else {
            isValid = false;
        }
    }
}

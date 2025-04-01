// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.6.2;

import {Key} from '../libraries/KeyLib.sol';

interface IKeyManagement {
    /// @dev Emitted when a key is authorized.
    event Authorized(bytes32 indexed keyHash, Key key);

    /// @dev Emitted when a key is revoked.
    event Revoked(bytes32 indexed keyHash);

    /// @dev The key does not exist.
    error KeyDoesNotExist();

    /// @dev Authorizes the `key`.
    function authorize(Key memory key) external returns (bytes32 keyHash);

    /// @dev Revokes the key with the `keyHash`.
    function revoke(bytes32 keyHash) external;

    /// @dev Returns the number of authorized keys.
    function keyCount() external view returns (uint256);

    /// @dev Returns the key at the `i`-th position in the key list.
    function keyAt(uint256 i) external view returns (Key memory);

    /// @dev Returns the key corresponding to the `keyHash`. Reverts if the key does not exist.
    function getKey(bytes32 keyHash) external view returns (Key memory key);
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IHook} from '../interfaces/IHook.sol';

type Settings is uint256;

/// @title SettingsLib
/// @notice Key settings are packed into a uint256 where
/// - the least significant 20 bytes (0-19) specify an address to callout to for extra or overrideable validation.
/// - bytes 20-24 are used for the expiration timestamp.
/// - byte 25 is used to specify if the key is an admin key or not.
/// - the remaining bytes are reserved for future use.
///   6 bytes |   1 byte       | 5 bytes           | 20 bytes
///   UNUSED  |   isAdmin      | expiration        | VALIDATION_ADDRESS
library SettingsLib {
    uint160 constant MASK_20_BYTES = uint160(0xFFfFfFffFFfffFFfFFfFFFFFffFFFffffFfFFFfF);
    uint40 constant MASK_5_BYTES = uint40(0xFFFFFFFFFF);
    uint8 constant MASK_1_BYTE = uint8(0xFF);

    Settings constant DEFAULT = Settings.wrap(0);
    // RootKey has the settings: (isAdmin = true, 0 expiration, no hook)
    Settings constant ROOT_KEY_SETTINGS = Settings.wrap(uint256(1) << 200);

    /// @notice Returns whether the key is an admin key
    function isAdmin(Settings settings) internal pure returns (bool _isAdmin) {
        uint8 mask = MASK_1_BYTE;
        assembly {
            _isAdmin := and(shr(200, settings), mask)
        }
    }

    /// @notice Returns the expiration timestamp in unix time
    function expiration(Settings settings) internal pure returns (uint40 _expiration) {
        uint40 mask = MASK_5_BYTES;
        assembly {
            _expiration := and(shr(160, settings), mask)
        }
    }

    /// @notice Returns the hook address of the key
    function hook(Settings settings) internal pure returns (IHook _hook) {
        uint256 mask = MASK_20_BYTES;
        assembly {
            _hook := and(settings, mask)
        }
    }

    /// @notice A key is expired if its expiration is less than the current block timestamp
    ///         Strictly less than is inline with how expiry is handled in the ERC-4337 EntryPoint contract
    /// @dev Keys with expiry of 0 never expire.
    function isExpired(Settings settings) internal view returns (bool _isExpired, uint40 _expiration) {
        uint40 _exp = expiration(settings);
        if (_exp == 0) return (false, 0);
        return (_exp < block.timestamp, _exp);
    }
}

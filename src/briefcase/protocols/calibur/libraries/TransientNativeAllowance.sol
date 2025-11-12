// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice This is a temporary library that allows us to use transient storage (tstore/tload)
/// TODO: This library can be deleted when we have the transient keyword support in solidity.
/// @dev The custom storage layout keyword does not work for transient storage.
/// However, since transient storage is automatically cleared between transactions and does not persist, custom storage is not needed.
library TransientNativeAllowance {
    /// @notice calculates which storage slot a transient native allowance should be stored in for a given spender
    function _computeSlot(address spender) internal pure returns (bytes32 hashSlot) {
        assembly ('memory-safe') {
            mstore(0, and(spender, 0xffffffffffffffffffffffffffffffffffffffff))
            hashSlot := keccak256(0, 32)
        }
    }

    /// @notice Returns the transient allowance for a given spender
    function get(address spender) internal view returns (uint256 allowance) {
        bytes32 hashSlot = _computeSlot(spender);
        assembly ('memory-safe') {
            allowance := tload(hashSlot)
        }
    }

    /// @notice Sets the transient allowance for a given spender
    function set(address spender, uint256 allowance) internal {
        bytes32 hashSlot = _computeSlot(spender);
        assembly ('memory-safe') {
            tstore(hashSlot, allowance)
        }
    }
}

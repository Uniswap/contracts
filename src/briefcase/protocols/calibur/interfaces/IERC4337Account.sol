// SPDX-License-Identifier: MIT
pragma solidity >=0.6.2;

import {IAccount} from '../lib/account-abstraction/interfaces/IAccount.sol';

/// @title IERC4337Account Interface
/// @notice Interface for contracts that support updating the EntryPoint contract
/// @dev Extends the IAccount interface from the ERC4337 specification
interface IERC4337Account is IAccount {
    /// Thrown when the caller to validateUserOp is not the EntryPoint contract
    error NotEntryPoint();

    /// @notice Emitted when the EntryPoint address is updated
    /// @param newEntryPoint The new EntryPoint address
    event EntryPointUpdated(address indexed newEntryPoint);

    /// @notice Updates the EntryPoint address
    /// @dev By default, the EntryPoint is the zero address, meaning this must be called to enable 4337 support.
    /// @param entryPoint The new EntryPoint address
    function updateEntryPoint(address entryPoint) external;

    /// @notice Returns the address of the EntryPoint contract that this account uses
    /// @return The address of the EntryPoint contract
    function ENTRY_POINT() external view returns (address);
}

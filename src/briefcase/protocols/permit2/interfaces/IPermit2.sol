// SPDX-License-Identifier: MIT
pragma solidity >=0.6.2;

import {IAllowanceTransfer} from './IAllowanceTransfer.sol';
import {ISignatureTransfer} from './ISignatureTransfer.sol';

/// @notice Permit2 handles signature-based transfers in SignatureTransfer and allowance-based transfers in AllowanceTransfer.
/// @dev Users must approve Permit2 before calling any of the transfer functions.
interface IPermit2 is ISignatureTransfer, IAllowanceTransfer {
// IPermit2 unifies the two interfaces so users have maximal flexibility with their approval.
}

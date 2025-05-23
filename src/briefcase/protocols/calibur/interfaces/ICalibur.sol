// SPDX-License-Identifier: MIT
pragma solidity >=0.6.2;

import {IERC5267} from '../lib/openzeppelin-contracts/interfaces/IERC5267.sol';
import {BatchedCall} from '../libraries/BatchedCallLib.sol';
import {SignedBatchedCall} from '../libraries/SignedBatchedCallLib.sol';
import {IEIP712} from './IEIP712.sol';
import {IERC1271} from './IERC1271.sol';
import {IERC4337Account} from './IERC4337Account.sol';
import {IERC7201} from './IERC7201.sol';
import {IERC7821} from './IERC7821.sol';
import {IERC7914} from './IERC7914.sol';
import {IKeyManagement} from './IKeyManagement.sol';
import {IMulticall} from './IMulticall.sol';
import {INonceManager} from './INonceManager.sol';

/// A non-upgradeable contract that can be delegated to with a 7702 delegation transaction.
/// This implementation supports:
/// ERC-4337 relayable userOps, with version v0.8.0 of the Entrypoint contract.
/// ERC-7821 batched actions
/// EIP-712 typed data signature verification
/// ERC-7201 compliant storage use
/// ERC-1271 compliant signature verification
/// ERC-7914 transfer from native
/// Alternative key management and verification
/// Multicall
interface ICalibur is
    IKeyManagement,
    IERC4337Account,
    IERC7821,
    IERC1271,
    IEIP712,
    IERC5267,
    IERC7201,
    IERC7914,
    INonceManager,
    IMulticall
{
    /// @notice Generic error to bubble up errors from batched calls
    /// @param reason The revert data from the inner call
    error CallFailed(bytes reason);

    /// @dev Used when internally verifying signatures over batched calls
    error InvalidSignature();

    /// @dev Thrown when the signature has expired
    error SignatureExpired();

    /// @notice Execute entrypoint for trusted callers
    /// @dev This function is only callable by this account or an admin key
    /// @param batchedCall The batched call to execute
    function execute(BatchedCall memory batchedCall) external payable;

    /// @notice Execute entrypoint for relayed batched calls
    /// @param signedBatchedCall The signed batched call to execute
    /// @param wrappedSignature The signature along with any optional hook data, equivalent to abi.encode(bytes, bytes)
    function execute(SignedBatchedCall memory signedBatchedCall, bytes memory wrappedSignature) external payable;
}

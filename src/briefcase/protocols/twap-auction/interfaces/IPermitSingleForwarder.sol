// SPDX-License-Identifier: MIT
pragma solidity >=0.6.2;

import {IAllowanceTransfer} from '../../permit2/interfaces/IAllowanceTransfer.sol';

/// @title IPermitSingleForwarder
/// @notice Interface for the PermitSingleForwarder contract
interface IPermitSingleForwarder {
    /// @notice allows forwarding a single permit to permit2
    /// @dev this function is payable to allow multicall with NATIVE based actions
    /// @param owner the owner of the tokens
    /// @param permitSingle the permit data
    /// @param signature the signature of the permit; abi.encodePacked(r, s, v)
    /// @return err the error returned by a reverting permit call, empty if successful
    function permit(address owner, IAllowanceTransfer.PermitSingle calldata permitSingle, bytes calldata signature)
        external
        payable
        returns (bytes memory err);
}

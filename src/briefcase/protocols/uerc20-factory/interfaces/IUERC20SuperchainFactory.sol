// SPDX-License-Identifier: MIT
pragma solidity >=0.6.2;

import {UERC20Metadata} from '../libraries/UERC20Metadata.sol';
import {ITokenFactory} from './ITokenFactory.sol';

/// @title IUERC20SuperchainFactory
/// @notice Interface for the UERC20SuperchainFactory contract
interface IUERC20SuperchainFactory is ITokenFactory {
    /// @notice Parameters struct to be used by the UERC20Superchain during construction
    struct Parameters {
        string name;
        string symbol;
        uint256 totalSupply;
        uint256 homeChainId;
        address recipient;
        uint8 decimals;
        UERC20Metadata metadata;
    }

    /// @notice Thrown when the caller is not the creator in the initial deployment of a token
    error NotCreator(address sender, address creator);

    /// @notice Computes the deterministic address for a token based on its core parameters
    /// @param name The name of the token
    /// @param symbol The symbol of the token
    /// @param decimals The number of decimals the token uses
    /// @param homeChainId The hub chain ID of the token
    /// @param creator The creator of the token
    /// @return The deterministic address of the token
    function getUERC20SuperchainAddress(
        string memory name,
        string memory symbol,
        uint8 decimals,
        uint256 homeChainId,
        address creator
    ) external view returns (address);

    /// @notice Gets the parameters for token initialization
    /// @return The parameters structure with all token initialization data
    function getParameters() external view returns (Parameters memory);
}

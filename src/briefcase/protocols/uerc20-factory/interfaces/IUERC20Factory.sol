// SPDX-License-Identifier: MIT
pragma solidity >=0.6.2;

import {UERC20Metadata} from '../libraries/UERC20MetadataLibrary.sol';
import {ITokenFactory} from './ITokenFactory.sol';

/// @title IUERC20Factory
/// @notice Interface for the IUERC20Factory contract
interface IUERC20Factory is ITokenFactory {
    /// @notice Parameters struct to be used by the UERC20 during construction
    struct Parameters {
        uint256 totalSupply;
        bytes32 graffiti;
        address recipient;
        address creator;
        uint8 decimals;
        string name;
        string symbol;
        UERC20Metadata metadata;
    }

    /// @notice Computes the deterministic address for a token based on its core parameters
    /// @param name The name of the token
    /// @param symbol The symbol of the token
    /// @param decimals The number of decimals the token uses
    /// @param creator The creator of the token
    /// @param graffiti Additional data needed to compute the salt
    /// @return The deterministic address of the token
    function getUERC20Address(
        string memory name,
        string memory symbol,
        uint8 decimals,
        address creator,
        bytes32 graffiti
    ) external view returns (address);

    /// @notice Gets the parameters for token initialization
    /// @return The parameters structure with all token initialization data
    function getParameters() external view returns (Parameters memory);
}

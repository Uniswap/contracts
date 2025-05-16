// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Base64} from '../../lib-external/openzeppelin-contracts/contracts/utils/Base64.sol';
import {Strings} from '../../lib-external/openzeppelin-contracts/contracts/utils/Strings.sol';

struct UERC20Metadata {
    address creator;
    string description;
    string website;
    string image;
}

/// @title UERC20MetadataLibrary
/// @notice Library for generating base64 encoded JSON token metadata
library UERC20MetadataLibrary {
    using Strings for *;

    /// @notice Generates a base64 encoded JSON string of the token metadata
    /// @param metadata The token metadata
    /// @return The base64 encoded JSON string
    function toJSON(UERC20Metadata memory metadata) public pure returns (string memory) {
        return string(abi.encodePacked('data:application/json;base64,', Base64.encode(displayMetadata(metadata))));
    }

    /// @notice Generates an abi encoded JSON string of the token metadata
    /// @param metadata The token metadata
    /// @return The abi encoded JSON string
    function displayMetadata(UERC20Metadata memory metadata) private pure returns (bytes memory) {
        bytes memory json = abi.encodePacked('{"Creator":"', metadata.creator.toChecksumHexString(), '"');

        if (bytes(metadata.description).length > 0) {
            json = abi.encodePacked(json, ', "Description":"', metadata.description.escapeJSON(), '"');
        }
        if (bytes(metadata.website).length > 0) {
            json = abi.encodePacked(json, ', "Website":"', metadata.website.escapeJSON(), '"');
        }
        if (bytes(metadata.image).length > 0) {
            json = abi.encodePacked(json, ', "Image":"', metadata.image.escapeJSON(), '"');
        }

        return abi.encodePacked(json, '}');
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/// @title TypedDataSignLib
/// @notice Library supporting nesting of EIP-712 typed data signatures per ERC-7739
library TypedDataSignLib {
    /// @dev Generate the dynamic type string for the TypedDataSign struct
    /// @notice contentsName and contentsType MUST be checked for length before hashing
    function _toTypedDataSignTypeString(string memory contentsName, string memory contentsType)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodePacked(
            'TypedDataSign(',
            contentsName,
            ' contents,string name,string version,uint256 chainId,address verifyingContract,bytes32 salt)',
            contentsType
        );
    }

    /// @dev Create the type hash for a TypedDataSign struct
    /// @notice contentsName and contentsType MUST be checked for length before hashing
    function _toTypedDataSignTypeHash(string memory contentsName, string memory contentsType)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(_toTypedDataSignTypeString(contentsName, contentsType));
    }

    /// @notice EIP-712 hashStruct implementation for TypedDataSign
    /// @dev domainBytes is abi.encode(keccak256(bytes(name)), keccak256(bytes(version)), chainId, verifyingContract, salt)
    function hash(
        string memory contentsName,
        string memory contentsType,
        bytes32 contentsHash,
        bytes memory domainBytes
    ) internal pure returns (bytes32) {
        return keccak256(
            // Every element in domainBytes is statically sized, so we can do encodePacked here
            abi.encodePacked(_toTypedDataSignTypeHash(contentsName, contentsType), contentsHash, domainBytes)
        );
    }
}

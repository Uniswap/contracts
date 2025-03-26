// SPDX-License-Identifier: MIT
pragma solidity >=0.6.2;

/// @title IEIP712
interface IEIP712 {
    function domainSeparator() external view returns (bytes32);
    function hashTypedData(bytes32 hash) external view returns (bytes32);
}

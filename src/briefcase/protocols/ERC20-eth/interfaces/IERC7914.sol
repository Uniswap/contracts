// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.6.2;

interface IERC7914 {
    function transferFromNative(address from, address recipient, uint256 amount) external returns (bool);
    function approveNative(address spender, uint256 amount) external returns (bool);
}

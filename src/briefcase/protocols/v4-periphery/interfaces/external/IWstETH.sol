// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.6.2;

// SPDX-FileCopyrightText: 2021 Lido <info@lido.fi>
// https://github.com/lidofinance/core/blob/master/contracts/0.6.12/WstETH.sol

/* See contracts/COMPILERS.md */

interface IWstETH {
    function wrap(uint256 _stETHAmount) external returns (uint256);
    function unwrap(uint256 _wstETHAmount) external returns (uint256);
    function getStETHByWstETH(uint256 _wstETHAmount) external view returns (uint256);
    function getWstETHByStETH(uint256 _stETHAmount) external view returns (uint256);
    function stETH() external view returns (address);
}

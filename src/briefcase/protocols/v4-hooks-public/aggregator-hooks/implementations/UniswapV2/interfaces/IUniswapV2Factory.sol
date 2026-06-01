// SPDX-License-Identifier: MIT
pragma solidity >=0.6.2;

/// @notice Minimal subset of canonical Uniswap V2 factory surface
interface IUniswapV2Factory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

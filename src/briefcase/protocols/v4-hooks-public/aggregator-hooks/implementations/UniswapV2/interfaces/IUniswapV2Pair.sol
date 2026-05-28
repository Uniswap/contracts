// SPDX-License-Identifier: MIT
pragma solidity >=0.6.2;

/// @notice Minimal subset of canonical Uniswap V2 pair surface
interface IUniswapV2Pair {
    function token0() external view returns (address);
    function token1() external view returns (address);

    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);

    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

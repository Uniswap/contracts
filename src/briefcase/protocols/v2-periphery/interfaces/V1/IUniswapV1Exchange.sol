pragma solidity >=0.5.0;

interface IUniswapV1Exchange {
    function balanceOf(address owner) external view returns (uint256);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
    function removeLiquidity(uint256, uint256, uint256, uint256) external returns (uint256, uint256);
    function tokenToEthSwapInput(uint256, uint256, uint256) external returns (uint256);
    function ethToTokenSwapInput(uint256, uint256) external payable returns (uint256);
}

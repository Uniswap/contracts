// SPDX-License-Identifier: MIT
pragma solidity >=0.6.2;

import {IERC20} from '../../../lib-external/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';

/// @title Interface for WETH9
interface IWETH9 is IERC20 {
    /// @notice Deposit ether to get wrapped ether
    function deposit() external payable;

    /// @notice Withdraw wrapped ether to get ether
    function withdraw(uint256) external;
}

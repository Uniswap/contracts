// SPDX-License-Identifier: MIT
pragma solidity >=0.6.2;

/// @title ICurveStableSwapFactoryNG
/// @notice Interface for Curve StableSwap NG Factory
/// @dev Based on the Vyper implementation at https://github.com/curvefi/stableswap-ng
interface ICurveStableSwapFactoryNG {
    /// @notice Deploy a new plain pool
    /// @param _name Name of the new plain pool
    /// @param _symbol Symbol for the new plain pool
    /// @param _coins List of addresses of the coins being used in the pool
    /// @param _A Amplification coefficient (suggested: 5-10 for algo stables, 100 for non-redeemable, 200-400 for redeemable)
    /// @param _fee Trade fee with 1e10 precision (max 1% = 100000000)
    /// @param _offpeg_fee_multiplier Off-peg fee multiplier
    /// @param _ma_exp_time Moving average time window (e.g., 866 for 10 min EMA)
    /// @param _implementation_idx Index of the implementation to use
    /// @param _asset_types Asset types (0=Standard, 1=Oracle, 2=Rebasing, 3=ERC4626)
    /// @param _method_ids Method IDs for rate oracles (use bytes4(0) for standard tokens)
    /// @param _oracles Oracle addresses (use address(0) for standard tokens)
    /// @return The address of the deployed pool
    function deploy_plain_pool(
        string memory _name,
        string memory _symbol,
        address[] memory _coins,
        uint256 _A,
        uint256 _fee,
        uint256 _offpeg_fee_multiplier,
        uint256 _ma_exp_time,
        uint256 _implementation_idx,
        uint8[] memory _asset_types,
        bytes4[] memory _method_ids,
        address[] memory _oracles
    ) external returns (address);

    /// @notice Set implementation contracts for pools
    /// @param _implementation_index Implementation index where implementation is stored
    /// @param _implementation Implementation address to use when deploying plain pools
    function set_pool_implementations(uint256 _implementation_index, address _implementation) external;

    /// @notice Set implementation contracts for metapools
    /// @param _implementation_index Implementation index where implementation is stored
    /// @param _implementation Implementation address to use when deploying metapools
    function set_metapool_implementations(uint256 _implementation_index, address _implementation) external;

    /// @notice Set implementation contract for StableSwap Math
    /// @param _math_implementation Address of the math implementation contract
    function set_math_implementation(address _math_implementation) external;

    /// @notice Set implementation contract for Views methods
    /// @param _views_implementation Implementation address of views contract
    function set_views_implementation(address _views_implementation) external;

    /// @notice Set gauge implementation address
    /// @param _gauge_implementation Address of the gauge implementation
    function set_gauge_implementation(address _gauge_implementation) external;

    /// @notice Returns the admin address
    function admin() external view returns (address);

    /// @notice Returns the fee receiver address
    function fee_receiver() external view returns (address);

    /// @notice Returns the math implementation address
    function math_implementation() external view returns (address);

    /// @notice Returns the views implementation address
    function views_implementation() external view returns (address);

    /// @notice Returns the pool implementation at the given index
    function pool_implementations(uint256 index) external view returns (address);

    /// @notice Returns the number of deployed pools
    function pool_count() external view returns (uint256);

    /// @notice Returns the pool address at the given index
    function pool_list(uint256 index) external view returns (address);

    /// @notice Check if a pool is a metapool
    /// @param _pool Address of the pool
    /// @return True if the pool is a metapool
    function is_meta(address _pool) external view returns (bool);

    /// @notice Get the number of coins in a pool
    /// @param _pool Pool address (must be deployed by this factory)
    /// @return Number of coins in the pool
    /// @dev Reverts if pool was not deployed by this factory
    function get_n_coins(address _pool) external view returns (uint256);
}

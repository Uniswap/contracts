// SPDX-License-Identifier: MIT
pragma solidity >=0.6.2;

/// @title ICurveFactory
/// @notice Interface for Curve Metapool Factory
/// @dev Based on the factory at https://github.com/curvefi/curve-factory/blob/master/contracts/Factory.vy
interface ICurveFactory {
    /// @notice Deploy a new plain pool with all parameters (selector: 0x52f2db69)
    /// @param _name Name of the new plain pool
    /// @param _symbol Symbol for the new plain pool's LP token
    /// @param _coins Fixed array of 4 coin addresses (use address(0) for unused slots)
    /// @param _A Amplification coefficient
    /// @param _fee Trade fee with 1e10 precision (min 0.04% = 4000000, max 1% = 100000000)
    /// @param _asset_type Asset type (0=USD, 1=ETH, 2=BTC, 3=Other)
    /// @param _implementation_idx Index of the implementation to use
    /// @return The address of the deployed pool
    function deploy_plain_pool(
        string memory _name,
        string memory _symbol,
        address[4] memory _coins,
        uint256 _A,
        uint256 _fee,
        uint256 _asset_type,
        uint256 _implementation_idx
    ) external returns (address);

    /// @notice Deploy a new plain pool with asset_type, impl_idx defaults to 0 (selector: 0x5c16487b)
    function deploy_plain_pool(
        string memory _name,
        string memory _symbol,
        address[4] memory _coins,
        uint256 _A,
        uint256 _fee,
        uint256 _asset_type
    ) external returns (address);

    /// @notice Deploy a new plain pool with defaults for asset_type and impl_idx (selector: 0xcd419bb5)
    function deploy_plain_pool(
        string memory _name,
        string memory _symbol,
        address[4] memory _coins,
        uint256 _A,
        uint256 _fee
    ) external returns (address);

    /// @notice Deploy a new metapool
    /// @param _base_pool Address of the base pool to pair with
    /// @param _name Name of the new metapool
    /// @param _symbol Symbol for the new metapool's LP token
    /// @param _coin Address of the coin being used in the metapool
    /// @param _A Amplification coefficient
    /// @param _fee Trade fee with 1e10 precision
    /// @param _implementation_idx Index of the implementation to use
    /// @return The address of the deployed metapool
    function deploy_metapool(
        address _base_pool,
        string memory _name,
        string memory _symbol,
        address _coin,
        uint256 _A,
        uint256 _fee,
        uint256 _implementation_idx
    ) external returns (address);

    /// @notice Get plain pool implementation address
    /// @param n_coins Number of coins in the pool
    /// @param idx Implementation index
    /// @return Implementation address
    function plain_implementations(uint256 n_coins, uint256 idx) external view returns (address);

    /// @notice Get metapool implementations for a base pool
    /// @param _base_pool Base pool address
    /// @return Array of implementation addresses
    function metapool_implementations(address _base_pool) external view returns (address[10] memory);

    /// @notice Returns the admin address
    function admin() external view returns (address);

    /// @notice Returns the fee receiver address
    function fee_receiver() external view returns (address);

    /// @notice Returns the number of deployed pools
    function pool_count() external view returns (uint256);

    /// @notice Returns the pool address at the given index
    function pool_list(uint256 index) external view returns (address);

    /// @notice Get implementation address for a pool
    /// @param _pool Pool address
    /// @return Implementation address
    function get_implementation_address(address _pool) external view returns (address);

    /// @notice Get coins in a pool
    /// @param _pool Pool address
    /// @return Array of coin addresses
    function get_coins(address _pool) external view returns (address[4] memory);

    /// @notice Get number of coins in a pool
    /// @param _pool Pool address
    /// @return Number of coins and underlying coins
    function get_n_coins(address _pool) external view returns (uint256[2] memory);

    /// @notice Get balances of coins in a pool
    /// @param _pool Pool address
    /// @return Array of balances
    function get_balances(address _pool) external view returns (uint256[4] memory);
}

// SPDX-License-Identifier: MIT
pragma solidity >=0.6.2;

/// @title IMetaRegistry
/// @notice Minimal interface for Curve's MetaRegistry to check meta pool status
/// @dev See https://docs.curve.finance/developer/integration/meta-registry#is_meta
interface IMetaRegistry {
    /// @notice Check if a pool is a metapool
    /// @param _pool Address of the pool
    /// @param _handler_id ID of the RegistryHandler
    /// @return True if the pool is a metapool
    function is_meta(address _pool, uint256 _handler_id) external view returns (bool);

    /// @notice Check if a pool is registered in Curve's registry
    /// @param _pool Address of the pool
    /// @param _handler_id ID of the RegistryHandler (0 for default)
    /// @return True if the pool is registered
    /// @dev Reverts if the pool is not in any registry
    function is_registered(address _pool, uint256 _handler_id) external view returns (bool);
}

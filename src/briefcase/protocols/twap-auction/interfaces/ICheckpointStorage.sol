// SPDX-License-Identifier: MIT
pragma solidity >=0.6.2;

import {Checkpoint} from '../libraries/CheckpointLib.sol';

interface ICheckpointStorage {
    /// @notice Get the latest checkpoint at the last checkpointed block
    function latestCheckpoint() external view returns (Checkpoint memory);

    /// @notice Get the clearing price at the last checkpointed block
    function clearingPrice() external view returns (uint256);

    /// @notice Get the currency raised at the last checkpointed block
    /// @dev This may be less than the balance of this contract as tokens are sold at different prices
    function currencyRaised() external view returns (uint128);

    /// @notice Get the number of the last checkpointed block
    function lastCheckpointedBlock() external view returns (uint64);
}

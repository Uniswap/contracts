// SPDX-License-Identifier: MIT
pragma solidity >=0.6.2;

import {Checkpoint} from '../libraries/CheckpointLib.sol';
import {IAuctionStepStorage} from './IAuctionStepStorage.sol';
import {ICheckpointStorage} from './ICheckpointStorage.sol';
import {ITickStorage} from './ITickStorage.sol';
import {ITokenCurrencyStorage} from './ITokenCurrencyStorage.sol';
import {IDistributionContract} from './external/IDistributionContract.sol';

/// @notice Parameters for the auction
/// @dev token and totalSupply are passed as constructor arguments
struct AuctionParameters {
    address currency; // token to raise funds in. Use address(0) for ETH
    address tokensRecipient; // address to receive leftover tokens
    address fundsRecipient; // address to receive all raised funds
    uint64 startBlock; // Block which the first step starts
    uint64 endBlock; // When the auction finishes
    uint64 claimBlock; // Block when the auction can claimed
    uint24 graduationThresholdMps; // Minimum percentage of tokens that must be sold to graduate the auction
    uint256 tickSpacing; // Fixed granularity for prices
    address validationHook; // Optional hook called before a bid
    uint256 floorPrice; // Starting floor price for the auction
    bytes auctionStepsData; // Packed bytes describing token issuance schedule
    bytes fundsRecipientData; // Optional data to call the fundsRecipient with after the currency is swept
}

/// @notice Interface for the Auction contract
interface IAuction is
    IDistributionContract,
    ICheckpointStorage,
    ITickStorage,
    IAuctionStepStorage,
    ITokenCurrencyStorage
{
    /// @notice Error thrown when the amount received is invalid
    error IDistributionContract__InvalidAmountReceived();

    /// @notice Error thrown when not enough amount is deposited
    error InvalidAmount();
    /// @notice Error thrown when the auction is not started
    error AuctionNotStarted();
    /// @notice Error thrown when the floor price is zero
    error FloorPriceIsZero();
    /// @notice Error thrown when the tick spacing is zero
    error TickSpacingIsZero();
    /// @notice Error thrown when the claim block is before the end block
    error ClaimBlockIsBeforeEndBlock();
    /// @notice Error thrown when the bid has already been exited
    error BidAlreadyExited();
    /// @notice Error thrown when the bid is higher than the clearing price
    error CannotExitBid();
    /// @notice Error thrown when the checkpoint hint is invalid
    error InvalidCheckpointHint();
    /// @notice Error thrown when the bid is not claimable
    error NotClaimable();
    /// @notice Error thrown when the bid has not been exited
    error BidNotExited();
    /// @notice Error thrown when the token transfer fails
    error TokenTransferFailed();
    /// @notice Error thrown when the auction is not over
    error AuctionIsNotOver();
    /// @notice Error thrown when a new bid is less than or equal to the clearing price
    error InvalidBidPrice();

    /// @notice Emitted when a bid is submitted
    /// @param id The id of the bid
    /// @param owner The owner of the bid
    /// @param price The price of the bid
    /// @param exactIn Whether the bid is exact in
    /// @param amount The amount of the bid
    event BidSubmitted(uint256 indexed id, address indexed owner, uint256 price, bool exactIn, uint256 amount);

    /// @notice Emitted when a new checkpoint is created
    /// @param blockNumber The block number of the checkpoint
    /// @param clearingPrice The clearing price of the checkpoint
    /// @param totalCleared The total amount of tokens cleared
    /// @param cumulativeMps The cumulative percentage of total tokens allocated across all previous steps, represented in ten-millionths of the total supply (1e7 = 100%)
    event CheckpointUpdated(
        uint256 indexed blockNumber, uint256 clearingPrice, uint256 totalCleared, uint24 cumulativeMps
    );

    /// @notice Emitted when a bid is exited
    /// @param bidId The id of the bid
    /// @param owner The owner of the bid
    event BidExited(uint256 indexed bidId, address indexed owner);

    /// @notice Emitted when a bid is claimed
    /// @param owner The owner of the bid
    /// @param tokensFilled The amount of tokens claimed
    event TokensClaimed(address indexed owner, uint256 tokensFilled);

    /// @notice Submit a new bid
    /// @param maxPrice The maximum price the bidder is willing to pay
    /// @param exactIn Whether the bid is exact in
    /// @param amount The amount of the bid
    /// @param owner The owner of the bid
    /// @param prevTickPrice The price of the previous tick
    /// @param hookData Additional data to pass to the hook required for validation
    /// @return bidId The id of the bid
    function submitBid(
        uint256 maxPrice,
        bool exactIn,
        uint128 amount,
        address owner,
        uint256 prevTickPrice,
        bytes calldata hookData
    ) external payable returns (uint256 bidId);

    /// @notice Register a new checkpoint
    /// @dev This function is called every time a new bid is submitted above the current clearing price
    function checkpoint() external returns (Checkpoint memory _checkpoint);

    /// @notice Whether the auction has graduated as of the latest checkpoint (sold more than the graduation threshold)
    function isGraduated() external view returns (bool);

    /// @notice Exit a bid
    /// @dev This function can only be used for bids where the max price is above the final clearing price after the auction has ended
    /// @param bidId The id of the bid
    function exitBid(uint256 bidId) external;

    /// @notice Exit a bid which has been partially filled
    /// @dev This function can be used for fully filled or partially filled bids. For fully filled bids, `exitBid` is more efficient
    /// @param bidId The id of the bid
    /// @param lower The last checkpointed block where the clearing price is strictly < bid.maxPrice
    /// @param upper The first checkpointed block where the clearing price is strictly > bid.maxPrice, or 0 if the bid is partially filled at the end of the auction
    function exitPartiallyFilledBid(uint256 bidId, uint64 lower, uint64 upper) external;

    /// @notice Claim tokens after the auction's claim block
    /// @notice The bid must be exited before claiming tokens
    /// @dev Anyone can claim tokens for any bid, the tokens are transferred to the bid owner
    /// @param bidId The id of the bid
    function claimTokens(uint256 bidId) external;

    /// @notice Withdraw all of the currency raised
    /// @dev Can only be called by the funds recipient after the auction has ended
    ///      Must be called before the `claimBlock`
    function sweepCurrency() external;

    /// @notice Sweep any leftover tokens to the tokens recipient
    /// @dev This function can only be called after the auction has ended
    function sweepUnsoldTokens() external;
}

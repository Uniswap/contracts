// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.5.0;
pragma abicoder v2;

import {PoolKey} from '../../v4-core/types/PoolKey.sol';

/// @title MixedRouteQuoterV1 Interface
/// @notice Supports quoting the calculated amounts for exact input swaps. Is specialized for routes containing a mix of V2 and V3 and V4 liquidity.
/// @notice For each pool also tells you the number of initialized ticks crossed and the sqrt price of the pool after the swap.
/// @dev These functions are not marked view because they rely on calling non-view functions and reverting
/// to compute the result. They are also not gas efficient and should not be called on-chain.
interface IMixedRouteQuoterV2 {
    error InvalidProtocolVersion(uint256 protocolVersion);
    error NoLiquidityV3();

    struct QuoteExactInputSingleV2Params {
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
    }

    struct QuoteExactInputSingleV3Params {
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint24 fee;
    }

    struct QuoteExactInputSingleV4Params {
        PoolKey poolKey;
        bool zeroForOne;
        uint256 exactAmount;
        bytes hookData;
    }

    struct NonEncodableData {
        bytes hookData;
    }

    struct ExtraQuoteExactInputParams {
        NonEncodableData[] nonEncodableData;
    }

    /// @notice Returns the amount out received for a given exact input but for a swap of a single V2 pool
    /// @param params The params for the quote, encoded as `QuoteExactInputSingleV2Params`
    /// tokenIn The token being swapped in
    /// tokenOut The token being swapped out
    /// amountIn The desired input amount
    /// @return amountOut The amount of `tokenOut` that would be received
    function quoteExactInputSingleV2(QuoteExactInputSingleV2Params memory params)
        external
        view
        returns (uint256 amountOut);

    /// @notice Returns the amount out received for a given exact input but for a swap of a single pool
    /// @param params The params for the quote, encoded as `QuoteExactInputSingleParams`
    /// tokenIn The token being swapped in
    /// tokenOut The token being swapped out
    /// fee The fee of the token pool to consider for the pair
    /// amountIn The desired input amount
    /// @return amountOut The amount of `tokenOut` that would be received
    /// @return gasEstimate The estimate of the gas that the swap consumes
    function quoteExactInputSingleV3(QuoteExactInputSingleV3Params calldata params)
        external
        returns (uint256 amountOut, uint256 gasEstimate);

    /// @notice Returns the delta amounts for a given exact input swap of a single pool
    /// @param params The params for the quote, encoded as `QuoteExactSingleParams`
    /// poolKey The key for identifying a V4 pool
    /// zeroForOne If the swap is from currency0 to currency1
    /// exactAmount The desired input amount
    /// hookData arbitrary hookData to pass into the associated hooks
    /// @return amountOut The amount of `tokenOut` that would be received
    /// @return gasEstimate The estimate of the gas that the swap consumes
    function quoteExactInputSingleV4(QuoteExactInputSingleV4Params calldata params)
        external
        returns (uint256 amountOut, uint256 gasEstimate);

    /// @notice Returns the amount out received for a given exact input swap without executing the swap
    /// @param path The path of the swap, i.e. each token pair and the pool fee
    /// @param param the remaining non abi encodable data
    /// @param amountIn The amount of the first token to swap
    /// @return amountOut The amount of the last token that would be received
    /// @return gasEstimate The estimate of the gas that the v3 and v4 swaps in the path consume
    function quoteExactInput(bytes memory path, ExtraQuoteExactInputParams calldata param, uint256 amountIn)
        external
        returns (uint256 amountOut, uint256 gasEstimate);
}

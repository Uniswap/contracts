// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.6.2;

import {IHooks} from '../../v4-core/interfaces/IHooks.sol';
import {Currency} from '../../v4-core/types/Currency.sol';
import {PoolKey} from '../../v4-core/types/PoolKey.sol';

struct PathKey {
    Currency intermediateCurrency;
    uint24 fee;
    int24 tickSpacing;
    IHooks hooks;
    bytes hookData;
}

library PathKeyLib {
    function getPoolAndSwapDirection(PathKey memory params, Currency currencyIn)
        internal
        pure
        returns (PoolKey memory poolKey, bool zeroForOne)
    {
        Currency currencyOut = params.intermediateCurrency;
        (Currency currency0, Currency currency1) =
            currencyIn < currencyOut ? (currencyIn, currencyOut) : (currencyOut, currencyIn);

        zeroForOne = currencyIn == currency0;
        poolKey = PoolKey(currency0, currency1, params.fee, params.tickSpacing, params.hooks);
    }
}

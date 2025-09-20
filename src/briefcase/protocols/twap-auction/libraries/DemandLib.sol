// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {FixedPointMathLib} from '../../lib-external/solady/src/utils/FixedPointMathLib.sol';
import {AuctionStepLib} from './AuctionStepLib.sol';
import {FixedPoint96} from './FixedPoint96.sol';

struct Demand {
    uint128 currencyDemand;
    uint128 tokenDemand;
}

library DemandLib {
    using DemandLib for uint128;
    using FixedPointMathLib for uint128;
    using AuctionStepLib for uint128;

    function resolve(Demand memory _demand, uint256 price) internal pure returns (uint128) {
        return price == 0 ? 0 : _demand.currencyDemand.resolveCurrencyDemand(price) + _demand.tokenDemand;
    }

    function resolveCurrencyDemand(uint128 amount, uint256 price) internal pure returns (uint128) {
        return price == 0 ? 0 : uint128(amount.fullMulDiv(FixedPoint96.Q96, price));
    }

    function resolveTokenDemand(uint128 amount) internal pure returns (uint128) {
        return amount;
    }

    function sub(Demand memory _demand, Demand memory _other) internal pure returns (Demand memory) {
        return Demand({
            currencyDemand: _demand.currencyDemand - _other.currencyDemand,
            tokenDemand: _demand.tokenDemand - _other.tokenDemand
        });
    }

    function add(Demand memory _demand, Demand memory _other) internal pure returns (Demand memory) {
        return Demand({
            currencyDemand: _demand.currencyDemand + _other.currencyDemand,
            tokenDemand: _demand.tokenDemand + _other.tokenDemand
        });
    }

    function applyMps(Demand memory _demand, uint24 mps) internal pure returns (Demand memory) {
        return Demand({
            currencyDemand: _demand.currencyDemand.applyMps(mps),
            tokenDemand: _demand.tokenDemand.applyMps(mps)
        });
    }

    function addCurrencyAmount(Demand memory _demand, uint128 _amount) internal pure returns (Demand memory) {
        return Demand({currencyDemand: _demand.currencyDemand + _amount, tokenDemand: _demand.tokenDemand});
    }

    function addTokenAmount(Demand memory _demand, uint128 _amount) internal pure returns (Demand memory) {
        return Demand({currencyDemand: _demand.currencyDemand, tokenDemand: _demand.tokenDemand + _amount});
    }
}

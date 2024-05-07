// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "../interfaces/IPriceFeedAggregator.sol";

library PoolHelper {
  function getTotalPoolUSDValue(
    IUniswapV2Pair pair,
    IPriceFeedAggregator priceFeedAggregator
  ) internal view returns (uint256) {
    (uint112 token0amount, uint112 token1amount, ) = pair.getReserves();
    uint256 price0 = priceFeedAggregator.peek(pair.token0());
    uint256 price1 = priceFeedAggregator.peek(pair.token1());

    // assuming both tokens have 18 decimals!
    uint256 totalValue = Math.mulDiv(token0amount, price0, 1e18) + Math.mulDiv(token1amount, price1, 1e18);
    return totalValue;
  }

  function getUSDValueForLP(
    uint256 lpAmount,
    IUniswapV2Pair pair,
    IPriceFeedAggregator priceFeedAggregator
  ) internal view returns (uint256) {
    return Math.mulDiv(getTotalPoolUSDValue(pair, priceFeedAggregator), lpAmount, pair.totalSupply());
  }
}

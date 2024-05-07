// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IOracle.sol";

interface IUniswapV2TwapOracle is IOracle {
  struct CumulativePriceSnapshot {
    uint256 price0;
    uint256 price1;
    uint32 blockTimestamp;
  }

  event UpdateCumulativePricesSnapshot();

  error NoReserves();
  error InvalidToken();
  error PeriodNotPassed();

  /// @notice Takes cumulative price snapshot and updates previous and last snapshots
  /// @notice Cumulative price is in quote token
  /// @custom:usage This function should be called periodically by external keeper
  function updateCumulativePricesSnapshot() external;

  /// @notice Gets TWAP quote for given token
  /// @notice TWAP quote is in quote token
  /// @param token Token address
  /// @param amountIn Amount of token to get quote for
  /// @return amountOut Quote amount in quote token
  function getTwapQuote(address token, uint256 amountIn) external view returns (uint256 amountOut);

  /// @notice Gets TWAP quote for base token
  /// @dev This function is used by PriceFeedAggregator contract
  /// @return price price in USD for the 1 baseToken
  function peek() external view returns (uint256 price);
}

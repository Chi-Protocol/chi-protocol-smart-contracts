// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "contracts/interfaces/IUniswapV2TwapOracle.sol";
import "contracts/uniswap/libraries/FixedPoint.sol";
import "contracts/uniswap/libraries/UniswapV2OracleLibrary.sol";
import "contracts/uniswap/libraries/UniswapV2Library.sol";

/// @title Uniswap V2 TWAP Oracle
/// @notice PriceFeedAggregator uses this contract to be TWAP price of USC and CHI tokens
/// @notice One instance of this contract handles one Uniswap V2 pair
/// @notice This contract takes snapshots of cumulative prices and calculates TWAP price from them
contract UniswapV2TwapOracle is IUniswapV2TwapOracle {
  using FixedPoint for *;

  AggregatorV3Interface public immutable quoteTokenChainlinkFeed;
  IUniswapV2Pair public immutable pair;

  uint8 public immutable decimals;
  uint32 public immutable updatePeriod;
  uint32 public immutable minPeriodFromLastSnapshot;

  address public immutable baseToken;
  uint128 public immutable baseAmount; // should be 10^baseToken.decimals

  address public immutable token0;
  address public immutable token1;

  CumulativePriceSnapshot public previousSnapshot;
  CumulativePriceSnapshot public lastSnapshot;

  constructor(
    address _factory,
    address _baseToken,
    address _quoteToken,
    uint32 _updatePeriod,
    uint32 _minPeriodFromLastSnapshot,
    AggregatorV3Interface _quoteTokenChainlinkFeed
  ) {
    baseToken = _baseToken;
    baseAmount = uint128(10 ** (IERC20Metadata(baseToken).decimals()));

    updatePeriod = _updatePeriod;
    minPeriodFromLastSnapshot = _minPeriodFromLastSnapshot;

    quoteTokenChainlinkFeed = _quoteTokenChainlinkFeed;
    decimals = _quoteTokenChainlinkFeed.decimals();

    IUniswapV2Pair _pair = IUniswapV2Pair(UniswapV2Library.pairFor(_factory, _baseToken, _quoteToken));
    pair = _pair;
    token0 = _pair.token0();
    token1 = _pair.token1();

    (uint256 price0Cumulative, uint256 price1Cumulative, uint32 blockTimestamp) = UniswapV2OracleLibrary
      .currentCumulativePrices(address(pair));

    lastSnapshot = CumulativePriceSnapshot({
      price0: price0Cumulative,
      price1: price1Cumulative,
      blockTimestamp: blockTimestamp
    });
    previousSnapshot = lastSnapshot;

    uint112 reserve0;
    uint112 reserve1;
    (reserve0, reserve1, lastSnapshot.blockTimestamp) = _pair.getReserves();

    // ensure that there's liquidity in the pair
    if (reserve0 == 0 || reserve1 == 0) {
      revert NoReserves();
    }
  }

  /// @inheritdoc IOracle
  function name() external view returns (string memory) {
    return string(abi.encodePacked("UniV2 TWAP - ", IERC20Metadata(baseToken).symbol()));
  }

  /// @inheritdoc IUniswapV2TwapOracle
  function updateCumulativePricesSnapshot() public {
    (uint256 price0Cumulative, uint256 price1Cumulative, uint32 blockTimestamp) = UniswapV2OracleLibrary
      .currentCumulativePrices(address(pair));

    if (blockTimestamp - lastSnapshot.blockTimestamp < updatePeriod) {
      revert PeriodNotPassed();
    }

    previousSnapshot = lastSnapshot;
    lastSnapshot = CumulativePriceSnapshot({
      price0: price0Cumulative,
      price1: price1Cumulative,
      blockTimestamp: blockTimestamp
    });

    emit UpdateCumulativePricesSnapshot();
  }

  /// @inheritdoc IUniswapV2TwapOracle
  function getTwapQuote(address token, uint256 amountIn) public view returns (uint256 amountOut) {
    (uint256 price0Cumulative, uint256 price1Cumulative, uint32 blockTimestamp) = UniswapV2OracleLibrary
      .currentCumulativePrices(address(pair));

    uint32 timeElapsedFromLast = blockTimestamp - lastSnapshot.blockTimestamp;

    CumulativePriceSnapshot storage snapshot;
    if (timeElapsedFromLast >= minPeriodFromLastSnapshot) {
      snapshot = lastSnapshot;
    } else {
      snapshot = previousSnapshot;
    }

    uint32 timeElapsed = blockTimestamp - snapshot.blockTimestamp;

    if (token == token0) {
      // overflow is desired, casting never truncates
      // cumulative price is in (uq112x112 price * seconds) units so we simply wrap it after division by time elapsed
      FixedPoint.uq112x112 memory price0Average = FixedPoint.uq112x112(
        uint224((price0Cumulative - snapshot.price0) / timeElapsed)
      );
      amountOut = price0Average.mul(amountIn).decode144();
    } else {
      if (token != token1) {
        revert InvalidToken();
      }
      FixedPoint.uq112x112 memory price1Average = FixedPoint.uq112x112(
        uint224((price1Cumulative - snapshot.price1) / timeElapsed)
      );
      amountOut = price1Average.mul(amountIn).decode144();
    }

    return amountOut;
  }

  /// @inheritdoc IUniswapV2TwapOracle
  function peek() external view returns (uint256 price) {
    uint256 quotedAmount = getTwapQuote(baseToken, baseAmount);

    (, int256 quoteTokenPriceInUSD, , , ) = quoteTokenChainlinkFeed.latestRoundData();
    uint256 priceInUSD = (uint256(quoteTokenPriceInUSD) * quotedAmount) / baseAmount; // quote token price will be always greater than 0, so it's ok to convert int to uint

    return priceInUSD;
  }
}

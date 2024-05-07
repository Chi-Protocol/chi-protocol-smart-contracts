// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "../interfaces/IOracle.sol";

/// @title Oracle adapter for Chainlink price feeds
/// @notice PriceFeedAggregator contract uses this contract to get price for specific token
/// @notice One instance of this contract handles one Chainlink price feed
contract ChainlinkOracle is IOracle {
  uint128 public constant BASE_AMOUNT = 1e18; // Both WETH and stETH will have 18 decimals
  uint8 public immutable decimals;
  address public immutable baseToken;
  AggregatorV3Interface public immutable chainlinkFeed;

  constructor(address _baseToken, address _chainlinkFeed) {
    baseToken = _baseToken;
    chainlinkFeed = AggregatorV3Interface(_chainlinkFeed);
    decimals = chainlinkFeed.decimals();
  }

  /// @inheritdoc IOracle
  function name() external view returns (string memory) {
    return string(abi.encodePacked("Chainlink Price - ", IERC20Metadata(baseToken).symbol()));
  }

  /// @inheritdoc IOracle
  function peek() external view returns (uint256 price) {
    (, int256 priceInUSD, , , ) = chainlinkFeed.latestRoundData();
    assert(priceInUSD > 0); // prices for assets from chainlink should always be grater than 0
    return uint256(priceInUSD);
  }
}

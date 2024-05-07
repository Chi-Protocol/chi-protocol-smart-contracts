// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/IPriceFeedAggregator.sol";
import "../interfaces/IOracle.sol";

/// @title Contract for handling different price feeds
/// @notice Protocol uses this contract to get price feeds for different tokens
/// @notice Owner of contract can set price feed adapters for different tokens
contract PriceFeedAggregator is IPriceFeedAggregator, Ownable {
  mapping(address asset => IOracle oracle) public priceFeeds;

  /// @inheritdoc IPriceFeedAggregator
  function setPriceFeed(address base, address feed) external onlyOwner {
    if (base == address(0) || feed == address(0)) {
      revert ZeroAddress();
    }

    priceFeeds[base] = IOracle(feed);
    emit SetPriceFeed(base, feed);
  }

  /// @inheritdoc IPriceFeedAggregator
  function peek(address base) external view returns (uint256 price) {
    if (address(priceFeeds[base]) == address(0)) {
      revert ZeroAddress();
    }

    return (priceFeeds[base].peek());
  }
}

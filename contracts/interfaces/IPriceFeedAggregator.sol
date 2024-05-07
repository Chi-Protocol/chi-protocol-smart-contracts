// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IPriceFeedAggregator {
  event SetPriceFeed(address indexed base, address indexed feed);

  error ZeroAddress();

  /// @notice Sets price feed adapter for given token
  /// @param base Token address
  /// @param feed Price feed adapter address
  function setPriceFeed(address base, address feed) external;

  /// @notice Gets price for given token
  /// @param base Token address
  /// @return price Price for given token
  function peek(address base) external view returns (uint256 price);
}

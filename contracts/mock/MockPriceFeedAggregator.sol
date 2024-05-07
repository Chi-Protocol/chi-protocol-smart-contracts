// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/IPriceFeedAggregator.sol";
import "../interfaces/IOracle.sol";

contract MockPriceFeedAggregator is IPriceFeedAggregator, Ownable {
  mapping(address => IOracle) public priceFeeds;

  function setPriceFeed(address base, address feed) external onlyOwner {
    if (base == address(0) || feed == address(0)) {
      revert ZeroAddress();
    }

    priceFeeds[base] = IOracle(feed);
  }

  mapping(address => uint256) public mockPrice;

  function setMockPrice(address token, uint256 price) external {
    mockPrice[token] = price;
  }

  function peek(address base) external view override returns (uint256 price) {
    return mockPrice[base];
  }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IOracle {
  /// @notice Gets name of price adapter
  /// @return name Name of price adapter
  function name() external view returns (string memory name);

  /// @notice Gets decimals of price adapter
  /// @return decimals Decimals of price adapter
  function decimals() external view returns (uint8 decimals);

  /// @notice Gets price base token from Chainlink price feed
  /// @return price price in USD for the 1 baseToken
  function peek() external view returns (uint256 price);
}

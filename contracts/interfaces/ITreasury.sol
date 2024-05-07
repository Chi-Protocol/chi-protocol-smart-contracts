// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ITreasury {
  error EtherSendFailed(address to, uint256 amount);

  /// @notice transfers erc20 tokens or native tokens from the treasury vauler
  /// @param token address of the token to transfer, or address(0) for native token
  /// @param destination address to send tokens to
  /// @param amount amount of tokens to send
  function transfer(address token, address destination, uint256 amount) external;
}

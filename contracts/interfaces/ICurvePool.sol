// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ICurvePool {
  /// @notice Swaps tokens
  /// @param i Index of token to swap from
  /// @param j Index of token to swap to
  /// @param dx Amount of tokens to swap
  /// @param min_dy Minimum amount of tokens to receive
  /// @return dy Amount of tokens received
  function exchange(int128 i, int128 j, uint256 dx, uint256 min_dy) external payable returns (uint256 dy);
}

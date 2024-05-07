// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IChiLocking} from "./IChiLocking.sol";
import {IStaking} from "./IStaking.sol";

interface IChiStaking is IStaking {
  event Lock(address indexed account, uint256 amount, uint256 duration, bool useStakedTokens);
  event ClaimStETH(address indexed account, uint256 amount);
  event SetChiLocking(address indexed chiLocking);
  event SetRewardController(address indexed rewardController);

  error InvalidDuration(uint256 duration);

  /// @notice Sets address of chiLocking contract
  /// @param _chiLocking Address of chiLocking contract
  function setChiLocking(IChiLocking _chiLocking) external;

  /// @notice Updates epoch data
  /// @param stETHrewards Amount of stETH rewards for chi stakers that is emitted in current epoch
  /// @custom:usage This function should be called from rewardController contract in purpose of updating epoch data
  function updateEpoch(uint256 stETHrewards) external;

  /// @notice Locks given amount of chi tokens for given duration for caller
  /// @dev If caller want to use staked tokens for locking, function will unstake them first
  /// @param amount Amount of chi tokens to lock
  /// @param duration Locking duration in epochs
  /// @param useStakedTokens If true, then staked tokens will be used for locking
  function lock(uint256 amount, uint256 duration, bool useStakedTokens) external;
}

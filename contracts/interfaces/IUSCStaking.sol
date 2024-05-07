// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IStaking} from "./IStaking.sol";
import {IArbitrage} from "./IArbitrage.sol";

interface IUSCStaking is IStaking {
  event UpdateEpoch(uint256 indexed epoch, uint256 chiEmissions, uint256 uscRewards, uint256 stETHrewards);
  event LockChi(address indexed account, uint256 amount, uint256 duration);
  event ClaimUSCRewards(address indexed account, uint256 amount);
  event ClaimStETH(address indexed account, uint256 amount);

  error NotClaimable();
  error InvalidDuration(uint256 duration);

  /// @notice Updates epoch data
  /// @param chiEmissions Amount of CHI token incentives emitted in current epoch for USC stakers
  /// @param uscRewards Amount of USC token frozen in current epoch for USC stakers
  /// @param stETHrewards Amount of stETH token rewards in current epoch for USC stakers
  /// @custom:usage This function should be called from rewardController contract in purpose of updating epoch data
  function updateEpoch(uint256 chiEmissions, uint256 uscRewards, uint256 stETHrewards) external;

  /// @notice Locks CHI tokens that user earned from incentives for given duration
  /// @param duration Locking duration in epochs
  function lockChi(uint256 duration) external;

  /// @notice Claims USC rewards for caller
  /// @dev This function can be called only when price is above target and there is excess of reserves
  function claimUSCRewards() external;
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IStakingWithEpochs} from "./IStakingWithEpochs.sol";

interface IStaking is IStakingWithEpochs {
  /// @notice Sets address of rewardController contract
  /// @param rewardController Address of rewardController contract
  function setRewardController(address rewardController) external;

  /// @notice Gets total staked chi amount
  /// @return stakedChi Total staked chi amount
  function getStakedChi() external view returns (uint256 stakedChi);

  /// @notice Claims stETH rewards for given account
  /// @notice This contract does not send stETH rewards nor holds them, reserveHolder does that
  /// @notice This contract only calculates and updates unclaimed stETH amount for given account
  /// @param account Account to claim stETH rewards for
  /// @return amount Amount of stETH rewards that user can claim
  /// @custom:usage This function should be called from rewardController contract in purpose of claiming stETH rewards
  function claimStETH(address account) external returns (uint256 amount);

  /// @notice Calculates and returns unclaimed stETH rewards for given account
  /// @param account Account to calculate unclaimed stETH rewards for
  /// @return amount Amount of unclaimed stETH rewards
  function unclaimedStETHAmount(address account) external view returns (uint256 amount);
}

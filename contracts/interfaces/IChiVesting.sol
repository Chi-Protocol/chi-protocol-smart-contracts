// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IChiVesting {
  struct VestingData {
    uint256 startAmount;
    uint256 shares;
    uint256 unlockedChi;
    uint256 lastWithdrawnEpoch;
    uint256 unclaimedStETH;
    uint256 lastClaimedEpoch;
  }

  struct EpochData {
    uint256 cumulativeStETHRewardPerShare;
    uint256 cumulativeUnlockedPerShare;
  }

  event AddVesting(address indexed account, uint256 amount, uint256 shares);
  event UpdateEpoch(uint256 indexed epoch, uint256 stETHrewards, uint256 totalLockedChi);
  event WithdrawChi(address indexed account, uint256 amount);
  event ClaimStETH(address indexed account, uint256 amount);
  event SetRewardController(address indexed rewardController);
  event SetChiVester(address indexed chiVester, bool indexed toSet);

  error NotRewardController();
  error NotChiVester();
  error CliffPassed();
  error UnavailableWithdrawAmount(uint256 amount);

  /// @notice Gets cliff duration
  /// @return duration Cliff duration
  function cliffDuration() external view returns (uint256 duration);

  /// @notice Sets address of rewardController contract
  /// @param rewardController Address of rewardController contract
  function setRewardController(address rewardController) external;

  /// @notice Updates status of contract that can add vesting, TimeWeightedBonding contract in this case
  /// @param contractAddress Address of contract
  /// @param toSet Status to set
  function setChiVester(address contractAddress, bool toSet) external;

  /// @notice Gets total locked chi amount
  /// @return lockedChi Total locked chi amount
  function getLockedChi() external view returns (uint256 lockedChi);

  /// @notice Vests given amount of chi tokens for given account
  /// @param account Account to vest tokens for
  /// @param chiAmount Amount of chi tokens to vest
  /// @custom:usage This function should be called from TimeWeightedBonding contract in purpose of vesting chi tokens
  function addVesting(address account, uint256 chiAmount) external;

  /// @notice Updates epoch data
  /// @param chiEmissions Amount of chi incentives for vesters in current epoch
  /// @param stETHrewards Amount of stETH rewards for vesters that is emitted in current epoch
  /// @custom:usage This function should be called from rewardController contract in purpose of updating epoch data
  function updateEpoch(uint256 chiEmissions, uint256 stETHrewards) external;

  /// @notice Withdraws vested chi tokens for caller
  /// @dev Contract hold vested chi tokens and inside this function it transfers them to caller
  /// @param amount Amount of chi tokens to withdraw
  function withdrawChi(uint256 amount) external;

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

  /// @notice Calculates and returns voting power earned from vesting for given account
  /// @param account Account to calculate voting power for
  /// @return votingPower Voting power earned from vesting
  function getVotingPower(address account) external view returns (uint256 votingPower);

  /// @notice Gets total voting power
  /// @return totalVotingPower Total voting power
  function getTotalVotingPower() external view returns (uint256 totalVotingPower);

  /// @notice Calculates and returns chi amount that is available for withdrawing for given account
  /// @param account Account to calculate available chi amount for
  /// @return availableChi Total amount of chi that is available for withdrawing
  function availableChiWithdraw(address account) external view returns (uint256 availableChi);
}

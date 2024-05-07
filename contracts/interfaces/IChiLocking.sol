// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IChiLocking {
  struct LockedPosition {
    uint256 amount;
    uint256 startEpoch;
    uint256 duration; // in epochs
    uint256 shares;
    uint256 withdrawnChiAmount;
  }

  struct LockingData {
    uint256 lastUpdatedEpoch;
    uint256 unclaimedStETH;
    LockedPosition[] positions;
  }

  struct AllLockedPositionsOutput {
    LockedPosition position;
    uint256 votingPower;
    uint256 stETHreward;
    uint256 totalAccumulatedChi;
    uint256 totalChiRewards;
  }

  struct EpochData {
    uint256 lockedSharesInEpoch;
    uint256 totalLockedChiInEpoch;
    uint256 sharesToUnlock;
    uint256 cumulativeStETHPerLockedShare;
    uint256 cumulativeStETHPerUnlocked;
    uint256 numberOfEndingPositions;
  }

  event SetUscStaking(address indexed uscStaking);
  event SetRewardController(address indexed rewardController);
  event SetChiLocker(address indexed chiLocker, bool indexed status);
  event LockChi(address indexed account, uint256 amount, uint256 shares, uint256 startEpoch, uint256 endEpoch);
  event UpdateEpoch(
    uint256 indexed epoch,
    uint256 totalLockedChi,
    uint256 chiEmissions,
    uint256 stETHrewards,
    uint256 stEthPerLockedShare
  );
  event ClaimStETH(address indexed account, uint256 amount);
  event WithdrawChiFromAccount(address indexed account, address indexed toAddress, uint256 amount);

  error ZeroAmount();
  error NotRewardController();
  error NotChiLocker();
  error UnavailableWithdrawAmount(uint256 amount);

  /// @notice Sets address of uscStaking contract
  /// @param _uscStaking Address of uscStaking contract
  function setUscStaking(address _uscStaking) external;

  /// @notice Sets address of rewardController contract
  /// @param _rewardController Address of rewardController contract
  function setRewardController(address _rewardController) external;

  /// @notice Sets address of contract who can call lock function
  /// @param contractAddress Address of contract who calles lock function, chiStaking currently
  /// @param toSet true if contract can call lock function, false otherwise
  function setChiLocker(address contractAddress, bool toSet) external;

  /// @notice Gets locked position for given account and position index
  /// @param account Account to get locked position for
  /// @param pos Index of locked position
  /// @return position Locked position
  function getLockedPosition(address account, uint256 pos) external view returns (LockedPosition memory position);

  /// @notice Gets all locked position for given account
  /// @param account Account to get locked positions
  /// @return out Array of locked positions
  function getAllLockedPositions(address account) external view returns (AllLockedPositionsOutput[] memory out);

  /// @notice Gets total staked chi amount, locked amount is also considered staked
  /// @return stakedChi Total staked chi amount
  function getStakedChi() external view returns (uint256 stakedChi);

  /// @notice Gets total locked chi amount
  /// @return lockedChi Total locked chi amount
  function getLockedChi() external view returns (uint256 lockedChi);

  /// @notice Gets total voting power
  /// @return totalVotingPower Total voting power
  function getTotalVotingPower() external view returns (uint256 totalVotingPower);

  /// @notice Gets total chi amount that is available to withdraw for given account
  /// @param account Account to get available chi amount for
  /// @return availableTotal Total amount of chi that is available to withdraw
  function availableChiWithdraw(address account) external view returns (uint256 availableTotal);

  /// @notice Locks given amount of chi for given account for given duration
  /// @param account Account to lock chi for
  /// @param amount Amount of chi to lock
  /// @param duration Duration of locking in epochs
  /// @custom:usage This function should be called from chiStaking and uscStaking contracts in purpose of locking chi
  function lockChi(address account, uint256 amount, uint256 duration) external;

  /// @notice Updates epoch data
  /// @param chiEmissions Amount of chi incentives for chi lockers that is emitted in current epoch
  /// @param stETHrewards Amount of stETH rewards for chi lockers that is emitted in current epoch
  /// @custom:usage This function should be called from rewardController contract in purpose of updating epoch data
  function updateEpoch(uint256 chiEmissions, uint256 stETHrewards) external;

  /// @notice Claims stETH rewards for given account
  /// @notice This contract does not send stETH rewards nor holds them, reserveHolder does that
  /// @notice This contract only calculates and updates unclaimed stETH amount for given account
  /// @param account Account to claim stETH rewards for
  /// @return amount Amount of stETH rewards that user can claim
  /// @custom:usage This function should be called from rewardController contract in purpose of claiming stETH rewards
  function claimStETH(address account) external returns (uint256 amount);

  /// @notice Withdraws given amount of unlocked chi tokens for given account, sends to account by default
  /// @notice This contract hold CHI tokens and inside this function sends them back to user
  /// @param account Account to withdraw CHI for
  /// @param amount Amount of CHI tokens to withdraw
  /// @custom:usage This function should be called from chiStaking contract in purpose of withdrawing CHI tokens
  function withdrawChiFromAccount(address account, uint256 amount) external;

  /// @notice Withdraws given amount of unlocked chi tokens for given account, sends to account by default
  /// @notice This contract hold CHI tokens and inside this function sends them back to user
  /// @param account Account to withdraw CHI for
  /// @param toAddress Address to which to send tokens
  /// @param amount Amount of CHI tokens to withdraw
  /// @custom:usage This function should be called from chiStaking contract in purpose of withdrawing CHI tokens
  function withdrawChiFromAccountToAddress(address account, address toAddress, uint256 amount) external;

  /// @notice Calculates and returns unclaimed stETH amount for given account
  /// @param account Account to calculate unclaimed stETH amount for
  /// @return totalAmount Total amount of unclaimed stETH for given account
  function unclaimedStETHAmount(address account) external view returns (uint256 totalAmount);

  /// @notice Calculates and returns voting power for given account
  /// @param account Account to calculate voting power for
  /// @return votingPower Voting power for given account
  function getVotingPower(address account) external view returns (uint256 votingPower);
}

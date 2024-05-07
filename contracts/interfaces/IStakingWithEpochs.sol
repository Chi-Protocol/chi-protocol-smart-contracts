// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IStakingWithEpochs {
  enum RewardToken {
    USC,
    CHI,
    STETH
  }

  struct EpochData {
    uint256 shares;
    mapping(RewardToken => uint256) cumulativeRewardsPerShare;
  }

  struct StakeData {
    uint256 lastUpdatedEpoch;
    uint256 shares;
    uint256 addSharesNextEpoch;
    mapping(RewardToken => uint256) unclaimedRewards;
  }

  event Stake(address indexed account, uint256 amount);
  event Unstake(address indexed account, address indexed toAddress, uint256 amount);

  error ZeroAmount();
  error NotRewardController();
  error AmountBelowStakedBalance(uint256 stakedBalance, uint256 amount);

  /// @notice Gets current reward for given account and token
  /// @param account Account to get reward for
  /// @param token Token to get reward for
  /// @return amount Current reward for given account and token
  /// @custom:usage This function should be used in inheriting contracts to get current reward for given account and token
  function getUnclaimedRewards(address account, RewardToken token) external view returns (uint256 amount);

  /// @notice Gets cumulative reward per share for given account and token
  /// @param epoch Epoch to get cumulative reward per share for
  /// @param token Token to get cumulative reward per share for
  /// @return amount Cumulative reward per share for given epoch and token
  /// @custom:usage This function should be used in inheriting contracts to get cumulative reward per share for given epoch and token
  function getCumulativeRewardsPerShare(uint256 epoch, RewardToken token) external view returns (uint256 amount);

  /// @notice Stakes given amount of tokens
  /// @param amount Amount of tokens to stake
  /// @custom:usage This function should be called from inheriting contracts to stake tokens
  /// @custom:usage Logic should be the same for both uscStaking and chiStaking contracts
  function stake(uint256 amount) external;

  /// @notice Unstakes given amount of tokens, sends tokens to msg.sender by default
  /// @param amount Amount of tokens to unstake
  /// @custom:usage This function should be called from inheriting contracts to unstake tokens
  /// @custom:usage Logic should be the same for both uscStaking and chiStaking contracts
  function unstake(uint256 amount) external;

  /// @notice Unstakes given amount of tokens
  /// @param amount Amount of tokens to unstake
  /// @param toAddress Address to send tokens
  /// @custom:usage This function should be called from inheriting contracts to unstake tokens
  /// @custom:usage Logic should be the same for both uscStaking and chiStaking contracts
  function unstake(uint256 amount, address toAddress) external;
}

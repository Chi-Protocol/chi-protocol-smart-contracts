// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ILPRewards {
  struct LockingTokenData {
    uint256 amountLocked;
    uint64 lastClaimedEpoch;
    uint64 endingEpoch;
  }

  struct EpochData {
    int256 totalDeltaAmountLocked;
    int256 cumulativeProfit;
  }

  event LockLP(uint256 indexed lockingTokenId, uint256 amount, uint64 currentEpoch, uint64 endingEpoch);
  event ClaimRewards(uint256 indexed lockingTokenId, address indexed account, uint256 amount, int256 rewardUSD);
  event UpdateEpoch(uint64 indexed epoch, uint256 lpValue, int256 totalAmountLocked, int256 profitPerToken);
  event RecoverLPTokens(address indexed account, uint256 amount);
  event SetOCHI(address indexed ochi);

  error LockingTokenIdAlreadyUsed(uint256 lockingTokenId);
  error ClaimngRewardLessThanZero();
  error NotOCHI();

  /// @notice Gets current epoch
  /// @return currentEpoch Current epoch
  function currentEpoch() external view returns (uint64 currentEpoch);

  /// @notice Sets address of OCHI contract
  /// @param _ochi Address of OCHI contract
  /// @custom:usage This function should be called only once during deployment
  /// @custom:usage Caller must be owner
  function setOCHI(address _ochi) external;

  /// @notice Locks LP tokens for given period, user gets rewards until the end of the period
  /// @param lockingTokenId Unique OCHI id
  /// @param amount Amount of LP tokens to lock
  /// @param epochDuration Locking duration in epochs
  /// @custom:usage This function should be called from OCHI contract in purpose of locking LP tokens
  function lockLP(uint256 lockingTokenId, uint256 amount, uint64 epochDuration) external;

  /// @notice Claims rewards for given token id
  /// @param lockingTokenId Unique OCHI id
  /// @param account Account to send rewards to
  /// @custom:usage This function should be called from OCHI contract in purpose of claiming rewards
  function claimRewards(uint256 lockingTokenId, address account) external;

  /// @notice End current epoch and start new one
  /// @custom:usage This function should be called from OCHI contract when epoch is updated
  function updateEpoch() external;

  /// @notice Takes LP tokens from contract and sends them to receiver
  /// @param receiver Account to send LP tokens to
  /// @custom:usage This function should be called only in case of moving liquidity to another pool
  function recoverLPTokens(address receiver) external;

  /// @notice Calculates unclaimed rewards for given token id
  /// @param lockingTokenId Unique OCHI id
  /// @return rewardUSD Amount of unclaimed rewards in USD
  function calculateUnclaimedReward(uint256 lockingTokenId) external view returns (int256 rewardUSD);
  
  /// @notice returns profit in USD for the last epoch
  /// @return profit profit in USD
  function getLastEpochProfit() external view returns (int256 profit);
}

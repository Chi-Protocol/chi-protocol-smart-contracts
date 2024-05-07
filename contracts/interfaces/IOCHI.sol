// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IOCHI {
  struct ChiOption {
    uint256 amount;
    uint256 strikePrice;
    uint256 uscEthPairAmount;
    uint256 chiEthPairAmount;
    uint64 lockedUntil;
    uint64 validUntil;
  }

  event Mint(
    uint256 indexed tokenId,
    uint256 chiAmount,
    uint256 uscEthPairAmount,
    uint256 chiEthPairAmount,
    uint64 lockPeriodInEpochs,
    uint256 strikePrice,
    uint256 oChiAmount
  );
  event Burn(address indexed account, uint256 indexed tokenId, uint256 chiAmount);
  event UpdateEpoch(uint64 indexed epoch, uint256 timestamp);
  event ClaimRewardsOCHI(uint256 indexed tokenId);
  event RecoverLPTokens();

  error PolTargetRatioExceeded();
  error InvalidLockPeriod(uint256 lockPeriod);
  error NotAllowed(uint256 tokenId);
  error OptionLocked(uint256 tokenId);
  error OptionExpired(uint256 tokenId);
  error EpochNotFinished();

  /// @notice Mint OCHI tokens for given period, user gets rewards until the end of the period
  /// @param chiAmount Amount of CHI tokens user wants to burn in order to boost his discount in option
  /// @param uscEthPairAmount Amount of USC/ETH LP tokens user wants to lock and sell to protocol
  /// @param chiEthPairAmount Amount of CHI/ETH LP tokens user wants to lock and sell to protocol
  /// @param lockPeriodInEpochs Locking duration in epochs
  function mint(
    uint256 chiAmount,
    uint256 uscEthPairAmount,
    uint256 chiEthPairAmount,
    uint64 lockPeriodInEpochs
  ) external;

  /// @notice Burn OCHI token in order to execute option and get his discounted CHI
  /// @notice When lock period expires user has lock period window to execute option, after that option can not be executed
  /// @param tokenId Unique OCHI id
  function burn(uint256 tokenId) external;

  /// @notice Ends current epoch and start new one
  function updateEpoch() external;

  /// @notice Claims rewards for given token id
  /// @param tokenId Unique OCHI id
  function claimRewards(uint256 tokenId) external;

  /// @notice Returns unclaimed rewards value for given token id
  /// @param tokenId Unique OCHI id
  /// @return rewardsUSD rewards value in USD
  function getUnclaimedRewardsValue(uint256 tokenId) external view returns (int256 rewardsUSD);

  /// @notice Recovers LP tokens from rewards contract
  /// @custom:usage This function should be called only in case of moving liquidity to another pool
  function recoverLPTokens() external;

  function calculateOptionData(
    uint256 chiAmount,
    uint256 uscEthPairAmount,
    uint256 chiEthPairAmount,
    uint256 lockPeriodInEpochs
  ) external view returns (uint256 strikePrice, uint256 oChiAmount);

  function getAndValidatePositionsData(
    uint256 uscEthPairAmount,
    uint256 chiEthPairAmount
  ) external view returns (uint256 multiplier, uint256 value);

  function getLastEpochTotalReward() external view returns (int256 totalReward);

  function claimAllRewards() external;
}

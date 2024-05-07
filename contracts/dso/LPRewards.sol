// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "../interfaces/ILPRewards.sol";
import "../interfaces/IPriceFeedAggregator.sol";
import "./PoolHelper.sol";

/// @title Contract for handling LP rewards
/// @notice Each LP token has its own LPRewards contract
contract LPRewards is ILPRewards, Ownable {
  using SafeERC20 for IERC20;
  using SafeCast for uint256;

  uint8 public immutable decimals;
  IUniswapV2Pair public immutable lpToken;
  IPriceFeedAggregator public immutable priceFeedAggregator;

  address public ochi;
  uint64 public currentEpoch;
  int256 public totalAmountLocked;
  uint256 public epochMinLPBalance;
  uint256 public currentLPValue;
  int256 public cumulativeProfit;

  mapping(uint256 tokenId => LockingTokenData) public lockingTokenData;
  mapping(uint256 epochId => EpochData) public epochData;

  modifier onlyOCHI() {
    if (msg.sender != ochi) {
      revert NotOCHI();
    }
    _;
  }

  constructor(IUniswapV2Pair _lpToken, IPriceFeedAggregator _priceFeedAggregator) {
    lpToken = _lpToken;
    decimals = lpToken.decimals();
    priceFeedAggregator = _priceFeedAggregator;
    currentEpoch = 1;
    totalAmountLocked = 0;
  }

  function setOCHI(address _ochi) external onlyOwner {
    ochi = _ochi;
    emit SetOCHI(_ochi);
  }

  /// @notice Locks LP tokens for given period, user gets rewards until the end of the period
  /// @param lockingTokenId Unique OCHI id
  /// @param amount Amount of LP tokens to lock
  /// @param epochDuration Locking duration in epochs
  /// @custom:usage This function should be called from OCHI contract in purpose of locking LP tokens
  function lockLP(uint256 lockingTokenId, uint256 amount, uint64 epochDuration) external onlyOCHI {
    if (amount == 0) {
      return;
    }

    LockingTokenData storage position = lockingTokenData[lockingTokenId];

    if (position.amountLocked != 0) {
      revert LockingTokenIdAlreadyUsed(lockingTokenId);
    }

    uint64 nextEpoch = currentEpoch + 1;
    epochData[nextEpoch].totalDeltaAmountLocked += amount.toInt256();
    epochData[nextEpoch + epochDuration].totalDeltaAmountLocked -= amount.toInt256();

    position.amountLocked = amount;
    position.endingEpoch = nextEpoch + epochDuration;
    position.lastClaimedEpoch = currentEpoch;

    emit LockLP(lockingTokenId, amount, currentEpoch, position.endingEpoch);
  }

  /// @notice Claims rewards for given token id
  /// @param lockingTokenId Unique OCHI id
  /// @param account Account to send rewards to
  /// @custom:usage This function should be called from OCHI contract in purpose of claiming rewards
  function claimRewards(uint256 lockingTokenId, address account) external onlyOCHI {
    int256 rewardUSD = calculateUnclaimedReward(lockingTokenId);
    if (rewardUSD < 0) {
      return;
    }

    uint256 totalPoolValue = PoolHelper.getTotalPoolUSDValue(lpToken, priceFeedAggregator);
    uint256 lpTokensToBurn = Math.mulDiv(uint256(rewardUSD), lpToken.totalSupply(), totalPoolValue);
    if (lpTokensToBurn == 0) {
      return;
    }

    IERC20(address(lpToken)).safeTransfer(address(lpToken), lpTokensToBurn);
    lpToken.burn(account);

    uint256 newBalance = lpToken.balanceOf(address(this));
    if (newBalance < epochMinLPBalance) epochMinLPBalance = newBalance;

    lockingTokenData[lockingTokenId].lastClaimedEpoch = currentEpoch - 1;

    emit ClaimRewards(lockingTokenId, account, lpTokensToBurn, rewardUSD);
  }

  /// @notice End current epoch and start new one
  /// @custom:usage This function should be called from OCHI contract when epoch is updated
  function updateEpoch() external onlyOCHI {
    EpochData storage epoch = epochData[currentEpoch];

    totalAmountLocked += epoch.totalDeltaAmountLocked;

    uint256 prevLPValue = currentLPValue;
    currentLPValue = PoolHelper.getUSDValueForLP(10 ** decimals, lpToken, priceFeedAggregator);

    int256 totalProfit = (currentLPValue.toInt256() - prevLPValue.toInt256()) * epochMinLPBalance.toInt256();
    int256 profitPerLockedToken;
    if (totalAmountLocked != 0) {
      profitPerLockedToken = totalProfit / totalAmountLocked;
    }

    cumulativeProfit += profitPerLockedToken;
    epoch.cumulativeProfit = cumulativeProfit;

    epochMinLPBalance = lpToken.balanceOf(address(this));
    currentEpoch++;

    emit UpdateEpoch(currentEpoch - 1, currentLPValue, totalAmountLocked, profitPerLockedToken);
  }

  /// @notice Takes LP tokens from contract and sends them to receiver
  /// @param receiver Account to send LP tokens to
  /// @custom:usage This function should be called only in case of moving liquidity to another pool
  function recoverLPTokens(address receiver) external onlyOCHI {
    uint256 amount = lpToken.balanceOf(address(this));
    IERC20(address(lpToken)).safeTransfer(receiver, amount);
    emit RecoverLPTokens(receiver, amount);
  }

  /// @notice Calculates unclaimed rewards for given token id
  /// @param lockingTokenId Unique OCHI id
  function calculateUnclaimedReward(uint256 lockingTokenId) public view returns (int256) {
    LockingTokenData storage position = lockingTokenData[lockingTokenId];
    if (position.endingEpoch == 0) {
      return 0;
    }

    uint64 fromEpoch = position.lastClaimedEpoch;
    uint64 toEpoch = currentEpoch - 1;
    if (position.endingEpoch - 1 < toEpoch) toEpoch = position.endingEpoch - 1;
    if (toEpoch <= fromEpoch) return 0;

    int256 profitDelta = epochData[toEpoch].cumulativeProfit - epochData[fromEpoch].cumulativeProfit;
    int256 totalUSDreward = (position.amountLocked.toInt256() * profitDelta) / (10 ** decimals).toInt256();
    return totalUSDreward;
  }

  /// @notice Calculates the profit in last epoch in usd value
  function getLastEpochProfit() external view returns (int256) {
    if (currentEpoch < 2) return 0;
    return epochData[currentEpoch - 1].cumulativeProfit - epochData[currentEpoch - 2].cumulativeProfit;
  }
}

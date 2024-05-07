// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../library/ExternalContractAddresses.sol";
import "../interfaces/IPriceFeedAggregator.sol";
import "../interfaces/IStakingWithEpochs.sol";
import "../interfaces/IOCHI.sol";
import "../staking/RewardControllerV2.sol";
import "../staking/ChiStaking.sol";
import "../staking/ChiLocking.sol";
import "../staking/LPStaking.sol";
import "../staking/ChiVesting.sol";
import "../dso/PoolHelper.sol";
import "../dso/OCHI.sol";
import "../interfaces/IOCHI.sol";
import "../staking/USCStaking.sol";
import "../ReserveHolder.sol";
import "../dso/LPRewards.sol";

/// @title Data provider
/// @notice Data provider containing view functions used by frontend
contract DataProvider {
  using SafeCast for uint256;

  struct StEthReward {
    uint256 tokenValue;
    uint256 usdValue;
  }

  struct ChiReward {
    uint256 tokenValue;
    uint256 usdValue;
  }

  struct UscReward {
    uint256 tokenValue;
    uint256 usdValue;
  }

  struct Reward {
    StEthReward stEthReward;
    ChiReward chiReward;
    UscReward uscReward;
    uint256 totalReward;
  }

  struct Rewards {
    Reward stUscRewards;
    Reward stChiRewards;
    Reward veChiRewards;
    Reward uscEthLpRewards;
    Reward chiEthLpRewards;
    uint256 totalStEthReward;
    uint256 totalStEthRewardUsd;
    uint256 totalChiReward;
    uint256 totalChiRewardUsd;
  }

  function POLdata(
    OCHI dso,
    IUniswapV2Pair uniPair,
    IPriceFeedAggregator priceFeed
  ) external view returns (uint256 polUsdValue, uint256 polPercent) {
    uint256 lpAmount = uniPair.balanceOf(address(dso.lpRewards(uniPair)));
    polUsdValue = PoolHelper.getUSDValueForLP(lpAmount, uniPair, priceFeed);
    polPercent = Math.mulDiv(lpAmount, 10 ** 18, uniPair.totalSupply());
  }

  function getLPTokenPrice(
    IUniswapV2Pair pair,
    IPriceFeedAggregator priceFeedAggregator
  ) public view returns (uint256) {
    return PoolHelper.getUSDValueForLP(1 ether, pair, priceFeedAggregator);
  }

  function getTotalPoolValue(
    IUniswapV2Pair pair,
    IPriceFeedAggregator priceFeedAggregator
  ) public view returns (uint256) {
    return PoolHelper.getTotalPoolUSDValue(pair, priceFeedAggregator);
  }

  function chiStakingAPR(
    address chi,
    ChiStaking chiStaking,
    ChiLocking chiLocking,
    USCStaking uscStaking,
    LPStaking uscEthLpStaking,
    LPStaking chiEthLpStaking,
    ChiVesting chiVesting,
    RewardControllerV2 rewardController,
    IPriceFeedAggregator priceFeedAggregator,
    ReserveHolder reserveHolder
  ) public view returns (uint256) {
    uint256 stEthPrice = priceFeedAggregator.peek(ExternalContractAddresses.stETH);
    uint256 chiPrice = priceFeedAggregator.peek(chi);
    uint256 totalStakedChi = chiStaking.getStakedChi() +
      chiLocking.getStakedChi() +
      uscStaking.getStakedChi() +
      uscEthLpStaking.getStakedChi() +
      chiEthLpStaking.getStakedChi() +
      chiVesting.getLockedChi();
    uint256 chiStakedValue = Math.mulDiv(totalStakedChi, chiPrice, 1e8);

    uint256 currentEpoch = chiStaking.currentEpoch();

    (, uint256 totalRewardsTwoEpochsAgo) = currentEpoch >= 2 ? rewardController.epochs(currentEpoch - 2) : (0, 0);
    (, uint256 totalRewardsLastEpoch) = rewardController.epochs(currentEpoch - 1);

    uint256 totalEthReward;
    if (currentEpoch < 4) {
      totalEthReward = (reserveHolder.totalStEthDeposited() * 4) / 100 / 52;
    } else {
      totalEthReward = totalRewardsLastEpoch - totalRewardsTwoEpochsAgo;
    }

    uint256 totalEthRewardValue = Math.mulDiv(totalEthReward, stEthPrice, 1e8);

    return Math.mulDiv(totalEthRewardValue * 52, 1e18, chiStakedValue);
  }

  function uscStakingAPR(
    address chi,
    ChiStaking chiStaking,
    ChiLocking chiLocking,
    USCStaking uscStaking,
    LPStaking uscEthLpStaking,
    LPStaking chiEthLpStaking,
    ChiVesting chiVesting,
    RewardControllerV2 rewardController,
    IPriceFeedAggregator priceFeedAggregator,
    ReserveHolder reserveHolder
  ) external view returns (uint256 totalApr, uint256 uscApr, uint256 chiApr, uint256 boostedStChiApr) {
    uint256 currentEpoch = rewardController.currentEpoch();
    uint256 stChiApr = chiStakingAPR(
      chi,
      chiStaking,
      chiLocking,
      uscStaking,
      uscEthLpStaking,
      chiEthLpStaking,
      chiVesting,
      rewardController,
      priceFeedAggregator,
      reserveHolder
    );
    uint256 chiEmissions = rewardController.chiIncentivesForUscStaking();
    uint256 totalUscStaked = uscStaking.totalSupply();
    boostedStChiApr = (stChiApr * chiEmissions * 52) / totalUscStaked;

    uint256 chiPrice = priceFeedAggregator.peek(chi);
    uint256 chiEmissionsValue = Math.mulDiv(chiEmissions, chiPrice, 1e8);
    chiApr = Math.mulDiv(chiEmissionsValue * 52, 1e18, totalUscStaked);

    (uint256 uscRewardAmount, ) = rewardController.epochs(currentEpoch - 1);
    uscApr = Math.mulDiv(uscRewardAmount * 52, 1e18, totalUscStaked);

    return (boostedStChiApr + chiApr + uscApr, uscApr, chiApr, boostedStChiApr);
  }

  function chiLockingAPR(
    address chi,
    ChiStaking chiStaking,
    ChiLocking chiLocking,
    USCStaking uscStaking,
    LPStaking uscEthLpStaking,
    LPStaking chiEthLpStaking,
    ChiVesting chiVesting,
    RewardControllerV2 rewardController,
    IPriceFeedAggregator priceFeedAggregator,
    ReserveHolder reserveHolder
  ) public view returns (uint256 totalApr, uint256 chiApr, uint256 stChiApr, uint256 boostedStChiApr) {
    uint256 chiPrice = priceFeedAggregator.peek(chi);
    uint256 totalLockedChiValue = Math.mulDiv(chiLocking.getLockedChi() + chiVesting.getLockedChi(), chiPrice, 1e8);
    uint256 chiEmissions = rewardController.chiIncentivesForChiLocking();
    uint256 chiEmissionsValue = Math.mulDiv(chiEmissions, chiPrice, 1e8);
    chiApr = Math.mulDiv(chiEmissionsValue * 52, 1e18, totalLockedChiValue);
    stChiApr = chiStakingAPR(
      chi,
      chiStaking,
      chiLocking,
      uscStaking,
      uscEthLpStaking,
      chiEthLpStaking,
      chiVesting,
      rewardController,
      priceFeedAggregator,
      reserveHolder
    );

    boostedStChiApr = Math.mulDiv(chiEmissionsValue, stChiApr * 52, totalLockedChiValue);

    return (chiApr + stChiApr + boostedStChiApr, chiApr, stChiApr, boostedStChiApr);
  }

  function dsoAPR(
    address chi,
    OCHI ochi,
    IPriceFeedAggregator priceFeedAggregator
  ) external view returns (uint256 apr, int256 tradingFees) {
    LPRewards uscEthLpRewards = LPRewards(address(ochi.lpRewards(ochi.uscEthPair())));
    LPRewards chiEthLpRewards = LPRewards(address(ochi.lpRewards(ochi.chiEthPair())));

    int256 profitPerTokenUscEth = uscEthLpRewards.getLastEpochProfit();
    int256 profitPerTokenChiEth = chiEthLpRewards.getLastEpochProfit();

    int256 lpBalanceUscEth = uscEthLpRewards.epochMinLPBalance().toInt256();
    int256 lpBalanceChiEth = chiEthLpRewards.epochMinLPBalance().toInt256();

    int256 totalProfitPrevWeek = ((profitPerTokenUscEth * lpBalanceUscEth) / 1e18) +
      ((profitPerTokenChiEth * lpBalanceChiEth) / 1e18);

    if (totalProfitPrevWeek < 0) {
      return (0, 0);
    }

    uint256 totalChiLocked = ochi.totalOCHIlocked();
    uint256 chiPrice = priceFeedAggregator.peek(chi);
    uint256 totalChiLockedValue = Math.mulDiv(totalChiLocked, chiPrice, 1e18);

    return (Math.mulDiv(uint256(totalProfitPrevWeek) * 52, 1e18, totalChiLockedValue), totalProfitPrevWeek);
  }

  function uscEthLPAPR(
    address chi,
    ChiStaking chiStaking,
    ChiLocking chiLocking,
    USCStaking uscStaking,
    LPStaking uscEthLpStaking,
    LPStaking chiEthLpStaking,
    ChiVesting chiVesting,
    RewardControllerV2 rewardController,
    IPriceFeedAggregator priceFeedAggregator,
    IUniswapV2Pair uscEthPair,
    ReserveHolder reserveHolder
  ) external view returns (uint256 totalApr, uint256 chiApr, uint256 stChiApr) {
    uint256 chiPrice = priceFeedAggregator.peek(chi);
    uint256 chiEmissions = rewardController.chiIncentivesForUscEthLPStaking();
    uint256 chiEmissionsValue = Math.mulDiv(chiEmissions, chiPrice, 1e8);

    uint256 totalStaked = uscEthLpStaking.totalSupply();
    uint256 uscEthPairPrice = getLPTokenPrice(uscEthPair, priceFeedAggregator);
    uint256 totalStakedValue = Math.mulDiv(totalStaked, uscEthPairPrice, 1e8);
    chiApr = Math.mulDiv(chiEmissionsValue * 52, 1e18, totalStakedValue);

    uint256 chiStakingAPR = chiStakingAPR(
      chi,
      chiStaking,
      chiLocking,
      uscStaking,
      uscEthLpStaking,
      chiEthLpStaking,
      chiVesting,
      rewardController,
      priceFeedAggregator,
      reserveHolder
    );
    stChiApr = Math.mulDiv(chiEmissionsValue, chiStakingAPR * 52, totalStakedValue);

    return (chiApr + stChiApr, chiApr, stChiApr);
  }

  function chiEthLPAPR(
    address chi,
    ChiStaking chiStaking,
    ChiLocking chiLocking,
    USCStaking uscStaking,
    LPStaking uscEthLpStaking,
    LPStaking chiEthLpStaking,
    ChiVesting chiVesting,
    RewardControllerV2 rewardController,
    IPriceFeedAggregator priceFeedAggregator,
    IUniswapV2Pair chiEthPair,
    ReserveHolder reserveHolder
  ) external view returns (uint256 totalApr, uint256 chiApr, uint256 stChiApr) {
    uint256 chiPrice = priceFeedAggregator.peek(chi);
    uint256 chiEmissions = rewardController.chiIncentivesForChiEthLPStaking();
    uint256 chiEmissionsValue = Math.mulDiv(chiEmissions, chiPrice, 1e8);

    uint256 totalStaked = chiEthLpStaking.totalSupply();
    uint256 chiEthPairPrice = getLPTokenPrice(chiEthPair, priceFeedAggregator);
    uint256 totalStakedValue = Math.mulDiv(totalStaked, chiEthPairPrice, 1e8);
    chiApr = Math.mulDiv(chiEmissionsValue * 52, 1e18, totalStakedValue);

    uint256 chiStakingAPR = chiStakingAPR(
      chi,
      chiStaking,
      chiLocking,
      uscStaking,
      uscEthLpStaking,
      chiEthLpStaking,
      chiVesting,
      rewardController,
      priceFeedAggregator,
      reserveHolder
    );
    stChiApr = Math.mulDiv(chiEmissionsValue, chiStakingAPR * 52, totalStakedValue);

    return (chiApr + stChiApr, chiApr, stChiApr);
  }

  function estimatedYieldPerWeek(
    address chi,
    ChiStaking chiStaking,
    ChiLocking chiLocking,
    USCStaking uscStaking,
    LPStaking uscEthLpStaking,
    LPStaking chiEthLpStaking,
    ChiVesting chiVesting,
    RewardControllerV2 rewardController,
    IPriceFeedAggregator priceFeedAggregator,
    ReserveHolder reserveHolder
  ) external view returns (uint256) {
    (uint256 chiLockingApr, , , ) = chiLockingAPR(
      chi,
      chiStaking,
      chiLocking,
      uscStaking,
      uscEthLpStaking,
      chiEthLpStaking,
      chiVesting,
      rewardController,
      priceFeedAggregator,
      reserveHolder
    );
    uint256 totalLockedChi = chiLocking.getLockedChi() + chiVesting.getLockedChi();
    uint256 chiPrice = priceFeedAggregator.peek(chi);
    uint256 totalLockedChiValue = Math.mulDiv(totalLockedChi, chiPrice, 1e18);
    uint256 chiLockingWeeklyAPR = chiLockingApr / 52;

    return Math.mulDiv(totalLockedChiValue, chiLockingWeeklyAPR, 1e18);
  }

  function totalValueOfLockedChi(
    IPriceFeedAggregator priceFeedAggregator,
    ChiLocking chiLocking,
    ChiVesting chiVesting,
    address chi,
    address account
  ) external view returns (uint256) {
    IChiLocking.AllLockedPositionsOutput[] memory lockedPositions = chiLocking.getAllLockedPositions(account);

    uint256 totalChi;
    for (uint256 i = 0; i < lockedPositions.length; i++) {
      totalChi += lockedPositions[i].totalAccumulatedChi;
    }

    (uint256 totalVestedChi, , , , , ) = chiVesting.vestingData(account);
    totalChi += totalVestedChi;

    uint256 chiPrice = priceFeedAggregator.peek(address(chi));

    return Math.mulDiv(totalChi, chiPrice, 1e18);
  }

  function rewards(
    address chi,
    address usc,
    ChiStaking chiStaking,
    ChiLocking chiLocking,
    USCStaking uscStaking,
    LPStaking uscEthLPStaking,
    LPStaking chiEthLPStaking,
    ChiVesting chiVesting,
    RewardControllerV2 rewardController,
    IPriceFeedAggregator priceFeedAggregator,
    ReserveHolder reserveHolder
  ) external view returns (Rewards memory) {
    uint256 chiIncentivesForUscStaking = rewardController.chiIncentivesForUscStaking();
    uint256 chiIncentivesForChiLocking = rewardController.chiIncentivesForChiLocking();
    uint256 chiIncentivesForUscEthLPStaking = rewardController.chiIncentivesForUscEthLPStaking();
    uint256 chiIncentivesForChiEthLPStaking = rewardController.chiIncentivesForChiEthLPStaking();
    uint256 uscRewards = IERC20(usc).balanceOf(address(rewardController));
    uint256 uscRewardsUsd = Math.mulDiv(uscRewards, 1e8, 1e18);

    uint256 chiPrice = priceFeedAggregator.peek(chi);

    uint256 chiIncentivesForUscStakingUsd = Math.mulDiv(chiIncentivesForUscStaking, chiPrice, 1e18);
    uint256 chiIncentivesForChiLockingUsd = Math.mulDiv(chiIncentivesForChiLocking, chiPrice, 1e18);
    uint256 chiIncentivesForUscEthLPStakingUsd = Math.mulDiv(chiIncentivesForUscEthLPStaking, chiPrice, 1e18);
    uint256 chiIncentivesForChiEthLPStakingUsd = Math.mulDiv(chiIncentivesForChiEthLPStaking, chiPrice, 1e18);

    uint256 stETHEpochrewards = reserveHolder.getCurrentRewards();
    uint256 stETHEcpohrewardsUsd = Math.mulDiv(
      stETHEpochrewards,
      priceFeedAggregator.peek(ExternalContractAddresses.stETH),
      1e18
    );

    uint256 uscStakedChi = uscStaking.getStakedChi();
    uint256 chiStakedChi = chiStaking.getStakedChi();
    uint256 chiLockedChi = chiLocking.getStakedChi();
    uint256 chiVestingChi = chiVesting.getLockedChi();
    uint256 uscEthLPStakingChi = uscEthLPStaking.getStakedChi();
    uint256 chiEthLPStakingChi = chiEthLPStaking.getStakedChi();
    uint256 totalChi = uscStakedChi +
      chiStakedChi +
      chiLockedChi +
      chiVestingChi +
      uscEthLPStakingChi +
      chiEthLPStakingChi;

    uint256 uscStakingStEthReward;
    uint256 chiStakingStEthReward;
    uint256 chiLockingStEthReward;
    uint256 chiVestingStEthReward;
    uint256 uscEthLPStakingStEthReward;
    uint256 chiEthLPStakingStEthReward;
    uint256 chiVestingStEthRewardUsd;
    uint256 chiLockingStEthRewardUsd;
    uint256 chiStakingStEthRewardUsd;
    uint256 uscStakingStEthRewardUsd;
    uint256 uscEthLPStakingStEthRewardUsd;
    uint256 chiEthLPStakingStEthRewardUsd;
    if (totalChi != 0) {
      uint256 stEthPrice = priceFeedAggregator.peek(ExternalContractAddresses.stETH);

      uscStakingStEthReward = Math.mulDiv(uscStakedChi, stETHEpochrewards, totalChi);
      chiStakingStEthReward = Math.mulDiv(chiStakedChi, stETHEpochrewards, totalChi);
      chiLockingStEthReward = Math.mulDiv(chiLockedChi, stETHEpochrewards, totalChi);
      chiVestingStEthReward = Math.mulDiv(chiVestingChi, stETHEpochrewards, totalChi);
      uscEthLPStakingStEthReward = Math.mulDiv(uscEthLPStakingChi, stETHEpochrewards, totalChi);
      chiEthLPStakingStEthReward = Math.mulDiv(chiEthLPStakingStEthReward, stETHEpochrewards, totalChi);

      uscStakingStEthRewardUsd = Math.mulDiv(uscStakingStEthReward, stEthPrice, 1e18);
      chiStakingStEthRewardUsd = Math.mulDiv(chiStakingStEthReward, stEthPrice, 1e18);
      chiLockingStEthRewardUsd = Math.mulDiv(chiLockingStEthReward, stEthPrice, 1e18);
      chiVestingStEthRewardUsd = Math.mulDiv(chiVestingStEthReward, stEthPrice, 1e18);
      uscEthLPStakingStEthRewardUsd = Math.mulDiv(uscEthLPStakingStEthReward, stEthPrice, 1e18);
      chiEthLPStakingStEthRewardUsd = Math.mulDiv(chiEthLPStakingStEthReward, stEthPrice, 1e18);
    }

    uint256 totalStEthReward = uscStakingStEthReward +
      chiStakingStEthReward +
      chiLockingStEthReward +
      chiVestingStEthReward +
      uscEthLPStakingStEthReward +
      chiEthLPStakingStEthReward;

    uint totalStEthRewardUsd = uscStakingStEthRewardUsd +
      chiStakingStEthRewardUsd +
      chiLockingStEthRewardUsd +
      chiVestingStEthRewardUsd +
      uscEthLPStakingStEthRewardUsd +
      chiEthLPStakingStEthRewardUsd;

    uint256 totalChiReward = chiIncentivesForUscStaking +
      chiIncentivesForChiLocking +
      chiIncentivesForUscEthLPStaking +
      chiIncentivesForChiEthLPStaking;

    uint256 totalChiRewardUsd = chiIncentivesForUscStakingUsd +
      chiIncentivesForChiLockingUsd +
      chiIncentivesForUscEthLPStakingUsd +
      chiIncentivesForChiEthLPStakingUsd;

    return (
      Rewards({
        stUscRewards: Reward({
          stEthReward: StEthReward({tokenValue: uscStakingStEthReward, usdValue: uscStakingStEthRewardUsd}),
          chiReward: ChiReward({tokenValue: chiIncentivesForUscStaking, usdValue: chiIncentivesForUscStakingUsd}),
          uscReward: UscReward({tokenValue: uscRewards, usdValue: uscRewardsUsd}),
          totalReward: uscStakingStEthRewardUsd + chiIncentivesForUscStakingUsd + uscRewardsUsd
        }),
        stChiRewards: Reward({
          stEthReward: StEthReward({tokenValue: stETHEpochrewards, usdValue: stETHEcpohrewardsUsd}),
          chiReward: ChiReward({tokenValue: 0, usdValue: 0}),
          uscReward: UscReward({tokenValue: 0, usdValue: 0}),
          totalReward: stETHEcpohrewardsUsd
        }),
        veChiRewards: Reward({
          stEthReward: StEthReward({
            tokenValue: chiVestingStEthReward + chiLockingStEthReward,
            usdValue: chiVestingStEthRewardUsd + chiLockingStEthRewardUsd
          }),
          chiReward: ChiReward({tokenValue: chiIncentivesForChiLocking, usdValue: chiIncentivesForChiLockingUsd}),
          uscReward: UscReward({tokenValue: 0, usdValue: 0}),
          totalReward: chiVestingStEthRewardUsd + chiLockingStEthRewardUsd + chiIncentivesForChiLockingUsd
        }),
        uscEthLpRewards: Reward({
          stEthReward: StEthReward({tokenValue: uscEthLPStakingStEthReward, usdValue: uscEthLPStakingStEthRewardUsd}),
          chiReward: ChiReward({
            tokenValue: chiIncentivesForUscEthLPStaking,
            usdValue: chiIncentivesForUscEthLPStakingUsd
          }),
          uscReward: UscReward({tokenValue: 0, usdValue: 0}),
          totalReward: uscEthLPStakingStEthRewardUsd + chiIncentivesForUscEthLPStakingUsd
        }),
        chiEthLpRewards: Reward({
          stEthReward: StEthReward({tokenValue: chiEthLPStakingStEthReward, usdValue: chiEthLPStakingStEthRewardUsd}),
          chiReward: ChiReward({
            tokenValue: chiIncentivesForChiEthLPStaking,
            usdValue: chiIncentivesForChiEthLPStakingUsd
          }),
          uscReward: UscReward({tokenValue: 0, usdValue: 0}),
          totalReward: chiEthLPStakingStEthRewardUsd + chiIncentivesForChiEthLPStakingUsd
        }),
        totalStEthReward: totalStEthReward,
        totalStEthRewardUsd: totalStEthRewardUsd,
        totalChiReward: totalChiReward,
        totalChiRewardUsd: totalChiRewardUsd
      })
    );
  }
}

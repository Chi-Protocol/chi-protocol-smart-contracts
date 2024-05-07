// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IArbitrage} from "./IArbitrage.sol";

interface IRewardController {
  struct EpochData {
    uint256 totalUscReward;
    uint256 reserveHolderTotalRewards;
  }

  struct StETHRewards {
    uint256 uscStakingStEthReward;
    uint256 chiStakingStEthReward;
    uint256 chiLockingStEthReward;
    uint256 chiVestingStEthReward;
    uint256 uscEthLPStakingStEthReward;
    uint256 chiEthLPStakingStEthReward;
  }

  struct ChiIncentives {
    uint256 uscStakingChiIncentives;
    uint256 chiLockingChiIncentives;
    uint256 chiVestingChiIncentives;
  }

  event RewardUSC(address indexed account, uint256 amount);
  event UpdateEpoch(uint256 indexed epoch, uint256 totalStEthReward, uint256 totalChiIncentives);
  event ClaimStEth(address indexed account, uint256 amount);
  event SetChiIncentivesPerEpoch(uint256 indexed chiIncentivesPerEpoch);
  event SetArbitrager(address indexed arbitrager);
  event UpdateArbitrager(address indexed account, bool isArbitrager);

  error ZeroAmount();
  error NotArbitrager();
  error EpochNotFinished();

  /// @notice Set amount of chi incentives per epoch for chi lockers
  /// @param _chiIncentivesForChiLocking Amount of chi incentives per epoch
  function setChiIncentivesForChiLocking(uint256 _chiIncentivesForChiLocking) external;

  /// @notice Set amount of chi incentives per epoch for USC staking
  /// @param _chiIncentivesForUscStaking Amount of chi incentives per epoch
  function setChiIncentivesForUscStaking(uint256 _chiIncentivesForUscStaking) external;

  /// @notice Set amount of chi incentives per epoch for USC-ETH LP staking contracts
  /// @param _chiIncentivesForUscEthLPStaking Amount of chi incentives per epoch
  function setChiIncentivesForUscEthLPStaking(uint256 _chiIncentivesForUscEthLPStaking) external;

  /// @notice Set amount of chi incentives per epoch for CHI-ETH LP staking contracts
  /// @param _chiIncentivesForChiEthLPStaking Amount of chi incentives per epoch
  function setChiIncentivesForChiEthLPStaking(uint256 _chiIncentivesForChiEthLPStaking) external;

  /// @notice Sets arbitrager contract, deprecated in favor of updateArbitrager
  /// @param _arbitrager Arbitrager contract
  function setArbitrager(IArbitrage _arbitrager) external;

  /// @notice Sets arbitrager contract
  /// @param account Account to update arbitrager status for
  /// @param status True if account is arbitrager, false otherwise
  function updateArbitrager(address account, bool status) external;

  /// @notice Freezes given amount of USC token
  /// @dev Frozen tokens are not transfered they are burned and later minted again when conditions are met
  /// @param amount Amount of USC tokens to freeze
  /// @custom:usage This function should be called from Arbitrager contract in purpose of freezing USC tokens
  function rewardUSC(uint256 amount) external;

  /// @notice Updates epoch data
  /// @dev This functio will update epochs in all subcontracts and will distribute chi incentives and stETH rewards
  /// @custom:usage This function should be called once a week in order to end current epoch and start new one
  /// @custom:usage Thsi function ends current epoch and distributes chi incentives and stETH rewards to all contracts in this epoch
  function updateEpoch() external;

  /// @notice Claims stETH rewards for caller
  /// @dev This function will claim stETH rewards from all subcontracts and will send them to caller
  /// @dev Thsi contract does not hold stETH, instead it sends it through reserveHolder contract
  function claimStEth() external;

  /// @notice Calculates and returns unclaimed stETH amount for given account in all subcontracts
  /// @param account Account to calculate unclaimed stETH amount for
  /// @return totalAmount Total amount of unclaimed stETH for given account
  function unclaimedStETHAmount(address account) external view returns (uint256 totalAmount);
}

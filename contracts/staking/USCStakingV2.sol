// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "../interfaces/IUSCStaking.sol";
import "../interfaces/IArbitrage.sol";
import "../interfaces/IChiLocking.sol";
import "./StakingWithEpochs.sol";

/// @title Contract for staking USC tokens
/// @notice Staking is done in epochs
/// @dev Contract is upgradeable and used to rescue lost tokens frozen from epoch 1
contract USCStakingV2 is IUSCStaking, OwnableUpgradeable, StakingWithEpochs {
  using SafeERC20 for IERC20;

  uint256 public constant MIN_LOCK_DURATION = 4; // 4 epochs = 4 weeks = 1 month
  uint256 public constant MAX_LOCK_DURATION = 208; // 208 epochs = 208 weeks = 4 years

  IERC20 public chi;
  IChiLocking public chiLockingContract;

  uint256 public chiAmountFromEmissions;

  function initialize(IERC20 _usc, IERC20 _chi, IChiLocking _chiLockingContract) external initializer {
    __Ownable_init();
    __StakingWithEpochs_init("Staked USC", "stUSC", _usc);
    chi = _chi;
    chiLockingContract = _chiLockingContract;
  }

  function initializeUscRescue() external reinitializer(3) {
    stakeToken.safeTransfer(0xcdB8d92FA641106fdAEe3CCC6B53a029eDb9c458, 326000 ether);
  }

  /// @inheritdoc IStaking
  function setRewardController(address _rewardController) external onlyOwner {
    _setRewardController(_rewardController);
  }

  /// @inheritdoc IUSCStaking
  function updateEpoch(uint256 chiEmissions, uint256 uscRewards, uint256 stETHrewards) external onlyRewardController {
    EpochData storage epoch = epochs[currentEpoch];
    EpochData storage prevEpoch = epochs[currentEpoch - 1];

    _updateCumulativeRewardsForToken(epoch, prevEpoch, RewardToken.CHI, chiEmissions);
    _updateCumulativeRewardsForToken(epoch, prevEpoch, RewardToken.USC, uscRewards);
    _updateCumulativeRewardsForToken(epoch, prevEpoch, RewardToken.STETH, stETHrewards);
    _updateEpoch();

    chiAmountFromEmissions += chiEmissions;

    emit UpdateEpoch(currentEpoch - 1, chiEmissions, uscRewards, stETHrewards);
  }

  /// @inheritdoc IUSCStaking
  function lockChi(uint256 duration) external {
    if (duration < MIN_LOCK_DURATION || duration > MAX_LOCK_DURATION) {
      revert InvalidDuration(duration);
    }

    uint256 amount = _claimAndUpdateReward(msg.sender, RewardToken.CHI);
    chiLockingContract.lockChi(msg.sender, amount, duration);

    chiAmountFromEmissions -= amount;
    chi.safeTransfer(address(chiLockingContract), amount);

    emit LockChi(msg.sender, amount, duration);
  }

  /// @inheritdoc IUSCStaking
  function claimUSCRewards() external {
    uint256 amount = _claimAndUpdateReward(msg.sender, RewardToken.USC);
    stakeToken.safeTransfer(msg.sender, amount);

    emit ClaimUSCRewards(msg.sender, amount);
  }

  /// @inheritdoc IStaking
  function claimStETH(address account) external onlyRewardController returns (uint256) {
    uint256 amount = _claimAndUpdateReward(account, RewardToken.STETH);
    emit ClaimStETH(account, amount);
    return amount;
  }

  /// @inheritdoc IStaking
  function unclaimedStETHAmount(address account) public view returns (uint256) {
    return _getCurrentReward(account, RewardToken.STETH);
  }

  /// @inheritdoc IStaking
  function getStakedChi() external view returns (uint256) {
    return chiAmountFromEmissions;
  }

  function _calculatingRewards(RewardToken token) internal pure override returns (bool) {
    if (token == RewardToken.USC) return true;
    if (token == RewardToken.CHI) return true;
    if (token == RewardToken.STETH) return true;
    return false;
  }
}

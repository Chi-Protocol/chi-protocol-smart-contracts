// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "../interfaces/ILPStaking.sol";
import "../interfaces/IChiLocking.sol";
import "./StakingWithEpochs.sol";

/// @title Contract for staking USC/ETH and CHI/ETH LP tokens
/// @notice Staking is done in epochs
/// @dev Contract is upgradeable
contract LPStaking is ILPStaking, OwnableUpgradeable, StakingWithEpochs {
  using SafeERC20 for IERC20;

  uint256 public constant MIN_LOCK_DURATION = 4;
  uint256 public constant MAX_LOCK_DURATION = 208;

  IERC20 public chi;
  IChiLocking public chiLockingContract;

  uint256 public chiAmountFromEmissions;

  function initialize(
    IERC20 _chi,
    IChiLocking _chiLockingContract,
    IERC20 _token,
    string memory _name,
    string memory _symbol
  ) external initializer {
    __Ownable_init();
    __StakingWithEpochs_init(_name, _symbol, _token);

    chi = _chi;
    chiLockingContract = _chiLockingContract;
  }

  /// @notice Sets reward controller contract address
  /// @param _rewardController Reward controller contract address
  function setRewardController(address _rewardController) external onlyOwner {
    _setRewardController(_rewardController);
  }

  /// @notice Updates epoch data
  /// @param chiEmissions Amount of CHI token incentives emitted in current epoch for USC stakers
  /// @custom:usage This function should be called from rewardController contract in purpose of updating epoch data
  function updateEpoch(uint256 chiEmissions, uint256 stETHrewards) external onlyRewardController {
    EpochData storage epoch = epochs[currentEpoch];
    EpochData storage prevEpoch = epochs[currentEpoch - 1];

    _updateCumulativeRewardsForToken(epoch, prevEpoch, RewardToken.CHI, chiEmissions);
    _updateCumulativeRewardsForToken(epoch, prevEpoch, RewardToken.STETH, stETHrewards);
    _updateEpoch();

    chiAmountFromEmissions += chiEmissions;

    emit UpdateEpoch(currentEpoch - 1, chiEmissions);
  }

  /// @inheritdoc IStaking
  function claimStETH(address account) external onlyRewardController returns (uint256) {
    uint256 amount = _claimAndUpdateReward(account, RewardToken.STETH);
    emit ClaimStETH(account, amount);
    return amount;
  }

  /// @inheritdoc IStaking
  function getStakedChi() external view returns (uint256) {
    return chiAmountFromEmissions;
  }

  /// @inheritdoc IStaking
  function unclaimedStETHAmount(address account) public view returns (uint256) {
    return _getCurrentReward(account, RewardToken.STETH);
  }

  /// @notice Locks CHI tokens that user earned from incentives for given duration
  /// @param duration Locking duration in epochs
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

  function _calculatingRewards(RewardToken token) internal pure override returns (bool) {
    if (token == RewardToken.CHI) return true;
    if (token == RewardToken.STETH) return true;
    return false;
  }
}

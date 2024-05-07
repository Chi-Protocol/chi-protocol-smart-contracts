// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "../interfaces/IChiStaking.sol";
import "../interfaces/IChiLocking.sol";
import "./StakingWithEpochs.sol";

/// @title Contract for staking chi tokens
/// @notice This contract holds staked CHI tokens, staking is done per epoch
/// @dev This contract is upgradeable
contract ChiStaking is IChiStaking, OwnableUpgradeable, StakingWithEpochs {
  using SafeERC20 for IERC20;

  uint256 public constant MIN_LOCK_DURATION = 4; // 4 epochs = 4 weeks = 1 month
  uint256 public constant MAX_LOCK_DURATION = 208; // 208 epochs = 208 weeks = 4 years

  IChiLocking public chiLocking;

  function initialize(IERC20 _chiAddress) external initializer {
    __Ownable_init();
    __StakingWithEpochs_init("Staked CHI", "stCHI", _chiAddress);
  }

  /// @inheritdoc IChiStaking
  function setChiLocking(IChiLocking _chiLocking) external onlyOwner {
    chiLocking = _chiLocking;
    emit SetChiLocking(address(_chiLocking));
  }

  /// @inheritdoc IStaking
  function setRewardController(address _rewardController) external onlyOwner {
    _setRewardController(_rewardController);
    emit SetRewardController(_rewardController);
  }

  /// @inheritdoc IStaking
  function getStakedChi() external view returns (uint256) {
    return epochs[currentEpoch].shares;
  }

  /// @inheritdoc IChiStaking
  function updateEpoch(uint256 stETHrewards) external onlyRewardController {
    _updateCumulativeRewardsForToken(epochs[currentEpoch], epochs[currentEpoch - 1], RewardToken.STETH, stETHrewards);
    _updateEpoch();
  }

  /// @inheritdoc IStakingWithEpochs
  function unstake(uint256 amount) public override(IStakingWithEpochs, StakingWithEpochs) {
    unstake(amount, msg.sender);
  }

  /// @inheritdoc IStakingWithEpochs
  function unstake(uint256 amount, address toAddress) public override(IStakingWithEpochs, StakingWithEpochs) {
    uint256 availableOnLocking = chiLocking.availableChiWithdraw(msg.sender);
    if (amount <= availableOnLocking) {
      chiLocking.withdrawChiFromAccountToAddress(msg.sender, toAddress, amount);
    } else {
      chiLocking.withdrawChiFromAccountToAddress(msg.sender, toAddress, availableOnLocking);
      StakingWithEpochs.unstake(amount - availableOnLocking, toAddress);
    }
  }

  /// @inheritdoc IChiStaking
  function lock(uint256 amount, uint256 duration, bool useStakedTokens) external {
    if (duration < MIN_LOCK_DURATION || duration > MAX_LOCK_DURATION) {
      revert InvalidDuration(duration);
    }

    if (!useStakedTokens) {
      stakeToken.safeTransferFrom(msg.sender, address(chiLocking), amount);
      chiLocking.lockChi(msg.sender, amount, duration);
    } else {
      unstake(amount, address(chiLocking));
      chiLocking.lockChi(msg.sender, amount, duration + 1);
    }

    emit Lock(msg.sender, amount, duration, useStakedTokens);
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

  function _calculatingRewards(RewardToken token) internal pure override returns (bool) {
    if (token == RewardToken.STETH) return true;
    return false;
  }
}

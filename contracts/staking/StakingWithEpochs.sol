// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "../interfaces/IStakingWithEpochs.sol";
import "../interfaces/IMintableERC20.sol";
import "../interfaces/IBurnableERC20.sol";
import "../interfaces/IArbitrage.sol";

/// @title Contract for staking tokens
/// @notice Staking logic is placed inside this contract
/// @dev This contract is abstract and CHIStaking and USCStaking should inherit from him
abstract contract StakingWithEpochs is IStakingWithEpochs, ERC20Upgradeable {
  using SafeERC20 for IERC20;

  IERC20 public stakeToken;

  address public rewardController;
  uint256 public currentEpoch;

  mapping(address account => StakeData) public stakes;
  mapping(uint256 id => EpochData) public epochs;

  modifier onlyRewardController() {
    if (msg.sender != rewardController) {
      revert NotRewardController();
    }
    _;
  }

  function __StakingWithEpochs_init(
    string memory _name,
    string memory _symbol,
    IERC20 _stakeToken
  ) internal onlyInitializing {
    __ERC20_init(_name, _symbol);
    stakeToken = _stakeToken;
    currentEpoch = 1;
  }

  /// @inheritdoc IStakingWithEpochs
  function getUnclaimedRewards(address account, RewardToken token) external view returns (uint256) {
    return stakes[account].unclaimedRewards[token];
  }

  /// @inheritdoc IStakingWithEpochs
  function getCumulativeRewardsPerShare(uint256 epoch, RewardToken token) external view returns (uint256) {
    return epochs[epoch].cumulativeRewardsPerShare[token];
  }

  function unclaimedStChiAmount(address account) public view returns (uint256) {
    return _getCurrentReward(account, RewardToken.CHI);
  }

  /// @inheritdoc IStakingWithEpochs
  function stake(uint256 amount) external {
    if (amount == 0) {
      revert ZeroAmount();
    }

    stakeToken.safeTransferFrom(msg.sender, address(this), amount);
    _updateUnclaimedRewards(msg.sender);

    stakes[msg.sender].addSharesNextEpoch += amount;
    epochs[currentEpoch + 1].shares += amount;
    _mint(msg.sender, amount);

    emit Stake(msg.sender, amount);
  }

  /// @inheritdoc IStakingWithEpochs
  function unstake(uint256 amount) public virtual {
    unstake(amount, msg.sender);
  }

  /// @inheritdoc IStakingWithEpochs
  function unstake(uint256 amount, address toAddress) public virtual {
    if (amount == 0) {
      revert ZeroAmount();
    }

    StakeData storage stakeData = stakes[msg.sender];

    uint256 addSharesNextEpoch = stakeData.addSharesNextEpoch;
    if (stakeData.shares + addSharesNextEpoch < amount) {
      revert AmountBelowStakedBalance(stakeData.shares + addSharesNextEpoch, amount);
    }

    _updateUnclaimedRewards(msg.sender);
    addSharesNextEpoch = stakeData.addSharesNextEpoch;

    if (addSharesNextEpoch > amount) {
      stakeData.addSharesNextEpoch -= amount;
      epochs[currentEpoch + 1].shares -= amount;
    } else {
      uint256 fromCurrentShares = amount - addSharesNextEpoch;
      stakeData.shares -= fromCurrentShares;
      epochs[currentEpoch].shares -= fromCurrentShares;
      epochs[currentEpoch + 1].shares -= addSharesNextEpoch;
      stakeData.addSharesNextEpoch = 0;
    }

    stakeToken.safeTransfer(toAddress, amount);
    _burn(msg.sender, amount);

    emit Unstake(msg.sender, toAddress, amount);
  }

  function _updateUnclaimedRewards(address account) internal {
    StakeData storage stakeData = stakes[account];

    if (currentEpoch == stakeData.lastUpdatedEpoch) return;

    uint256 fromEpoch = stakeData.lastUpdatedEpoch > 0 ? stakeData.lastUpdatedEpoch - 1 : 0;
    _updateUnclaimedRewardsFromTo(stakeData, epochs[fromEpoch], epochs[currentEpoch - 1], stakeData.shares);

    if (stakeData.addSharesNextEpoch > 0) {
      _updateUnclaimedRewardsFromTo(
        stakeData,
        epochs[stakeData.lastUpdatedEpoch],
        epochs[currentEpoch - 1],
        stakeData.addSharesNextEpoch
      );
      stakeData.shares += stakeData.addSharesNextEpoch;
      stakeData.addSharesNextEpoch = 0;
    }

    stakeData.lastUpdatedEpoch = currentEpoch;
  }

  function _updateUnclaimedRewardsFromTo(
    StakeData storage stakeData,
    EpochData storage fromEpoch,
    EpochData storage toEpoch,
    uint256 shares
  ) internal {
    for (uint8 i = 0; i <= uint8(type(RewardToken).max); i++) {
      RewardToken token = RewardToken(i);
      if (_calculatingRewards(token)) {
        stakeData.unclaimedRewards[token] += Math.mulDiv(
          toEpoch.cumulativeRewardsPerShare[token] - fromEpoch.cumulativeRewardsPerShare[token],
          shares,
          1e18
        );
      }
    }
  }

  function _updateCumulativeRewardsForToken(
    EpochData storage epoch,
    EpochData storage prevEpoch,
    RewardToken token,
    uint256 amount
  ) internal {
    if (epoch.shares == 0) return;

    epoch.cumulativeRewardsPerShare[token] =
      prevEpoch.cumulativeRewardsPerShare[token] +
      Math.mulDiv(amount, 1e18, epoch.shares);
  }

  function _updateEpoch() internal {
    epochs[currentEpoch + 1].shares += epochs[currentEpoch].shares;
    currentEpoch++;
  }

  function _claimAndUpdateReward(address account, RewardToken token) internal returns (uint256) {
    _updateUnclaimedRewards(account);
    uint256 amount = stakes[account].unclaimedRewards[token];
    stakes[account].unclaimedRewards[token] = 0;
    return amount;
  }

  function _getCurrentReward(address account, RewardToken token) public view returns (uint256) {
    StakeData storage stakeData = stakes[account];
    uint256 totalAmount = stakeData.unclaimedRewards[token];

    if (currentEpoch == stakeData.lastUpdatedEpoch) return totalAmount;
    totalAmount += Math.mulDiv(
      epochs[currentEpoch - 1].cumulativeRewardsPerShare[token] -
        epochs[stakeData.lastUpdatedEpoch - 1].cumulativeRewardsPerShare[token],
      stakeData.shares,
      1e18
    );

    if (stakeData.addSharesNextEpoch > 0 && currentEpoch > stakeData.lastUpdatedEpoch + 1) {
      totalAmount += Math.mulDiv(
        epochs[currentEpoch - 1].cumulativeRewardsPerShare[token] -
          epochs[stakeData.lastUpdatedEpoch].cumulativeRewardsPerShare[token],
        stakeData.addSharesNextEpoch,
        1e18
      );
    }

    return totalAmount;
  }

  function _setRewardController(address _rewardController) internal {
    rewardController = _rewardController;
  }

  function _calculatingRewards(RewardToken token) internal virtual returns (bool);

  uint256[50] private __gap;
}

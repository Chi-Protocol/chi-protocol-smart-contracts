// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "../interfaces/IChiLocking.sol";
import "../library/ExternalContractAddresses.sol";

/// @title Contract for locking CHI tokens
/// @notice This contract holds CHI tokens that are locked
/// @notice Locking of reward distribution of CHI tokens is done per epoch
contract ChiLocking is IChiLocking, OwnableUpgradeable {
  using SafeERC20 for IERC20;

  uint256 public constant MAX_LOCK_DURATION = 208; // 4 years in weeks
  IERC20 public constant stETH = IERC20(ExternalContractAddresses.stETH);

  IERC20 public chi;
  address public rewardController;
  uint256 public currentEpoch;
  uint256 public totalLockedChi;
  uint256 public totalUnlockedChi;
  uint256 public totalLockedShares;
  uint256 public totalVotingPower;
  uint256 public sumOfLockedDurations;
  uint256 public numberOfLockedPositions;
  uint256 public addVotingPowerInEpoch;
  uint256 public sumShareDurationProduct;
  uint256 public addedAmountInEpoch;

  mapping(address account => bool status) public chiLockers;
  mapping(address account => LockingData) public locks;
  mapping(uint256 id => EpochData) public epochs;

  modifier onlyRewardController() {
    if (msg.sender != rewardController) {
      revert NotRewardController();
    }
    _;
  }

  modifier onlyChiLockers() {
    if (!chiLockers[msg.sender]) {
      revert NotChiLocker();
    }
    _;
  }

  function initialize(IERC20 _chi, address _chiStaking) external initializer {
    __Ownable_init();
    chiLockers[_chiStaking] = true;
    chi = _chi;
    currentEpoch = 1;
  }

  /// @inheritdoc IChiLocking
  function setUscStaking(address _uscStaking) external onlyOwner {
    chiLockers[_uscStaking] = true;
    emit SetUscStaking(_uscStaking);
  }

  /// @inheritdoc IChiLocking
  function setRewardController(address _rewardController) external onlyOwner {
    rewardController = _rewardController;
    emit SetRewardController(_rewardController);
  }

  /// @inheritdoc IChiLocking
  function setChiLocker(address contractAddress, bool toSet) external onlyOwner {
    chiLockers[contractAddress] = toSet;
    emit SetChiLocker(contractAddress, toSet);
  }

  /// @inheritdoc IChiLocking
  function getLockedPosition(address account, uint256 pos) external view returns (LockedPosition memory) {
    return locks[account].positions[pos];
  }

  function getAllLockedPositions(address account) external view returns (AllLockedPositionsOutput[] memory out) {
    LockingData storage lockData = locks[account];

    out = new AllLockedPositionsOutput[](lockData.positions.length);

    for (uint256 i = 0; i < lockData.positions.length; i++) {
      LockedPosition storage position = lockData.positions[i];
      out[i].position = position;
      out[i].votingPower = _getCurrentVotingPowerForPosition(position);
      out[i].stETHreward = _getUnclaimedStETHPositionAmount(lockData.positions[i], lockData.lastUpdatedEpoch);
      out[i].totalAccumulatedChi = _totalAccumulatedAtEpoch(currentEpoch, lockData.positions[i]);
      out[i].totalChiRewards = (out[i].totalAccumulatedChi > position.amount)
        ? out[i].totalAccumulatedChi - position.amount
        : 0;
    }
  }

  /// @inheritdoc IChiLocking
  function getStakedChi() public view returns (uint256) {
    return totalLockedChi + totalUnlockedChi;
  }

  /// @inheritdoc IChiLocking
  function getLockedChi() public view returns (uint256) {
    return totalLockedChi;
  }

  /// @inheritdoc IChiLocking
  function getTotalVotingPower() external view returns (uint256) {
    return totalVotingPower;
  }

  /// @inheritdoc IChiLocking
  function availableChiWithdraw(address account) public view returns (uint256 availableTotal) {
    LockingData storage lockData = locks[account];
    for (uint256 i = 0; i < lockData.positions.length; i++) {
      availableTotal += _availableToWithdrawFromPosition(lockData.positions[i]);
    }
  }

  /// @inheritdoc IChiLocking
  function lockChi(address account, uint256 amount, uint256 duration) external onlyChiLockers {
    if (amount == 0) {
      revert ZeroAmount();
    }

    uint256 shares = _getNumberOfShares(amount);
    duration++;

    EpochData storage currentEpochData = epochs[currentEpoch];
    EpochData storage afterEndEpoch = epochs[currentEpoch + duration];

    locks[account].positions.push(
      LockedPosition({
        amount: amount,
        startEpoch: currentEpoch,
        duration: duration,
        shares: shares,
        withdrawnChiAmount: 0
      })
    );

    totalLockedChi += amount;
    totalLockedShares += shares;
    currentEpochData.lockedSharesInEpoch += shares;
    currentEpochData.totalLockedChiInEpoch += amount;
    afterEndEpoch.sharesToUnlock += shares;

    totalVotingPower += Math.mulDiv(amount, duration, MAX_LOCK_DURATION);
    sumShareDurationProduct += Math.mulDiv(shares, duration, MAX_LOCK_DURATION);
    sumOfLockedDurations += duration + 1;
    numberOfLockedPositions += 1;
    afterEndEpoch.numberOfEndingPositions += 1;

    emit LockChi(account, amount, shares, currentEpoch, currentEpoch + duration);
  }

  /// @inheritdoc IChiLocking
  function updateEpoch(uint256 chiEmissions, uint256 stETHrewards) external onlyRewardController {
    EpochData storage epoch = epochs[currentEpoch];

    uint256 stETHrewardsForLocked;
    uint256 stakedChi = getStakedChi();
    if (stakedChi != 0) {
      stETHrewardsForLocked = Math.mulDiv(stETHrewards, totalLockedChi, stakedChi);
    }
    uint256 stETHrewardsForUnlocked = stETHrewards - stETHrewardsForLocked;

    uint256 stEthPerLockedShare;
    if (epoch.lockedSharesInEpoch != 0) {
      stEthPerLockedShare = Math.mulDiv(stETHrewardsForLocked, 1e18, epoch.lockedSharesInEpoch);
    }
    epoch.cumulativeStETHPerLockedShare = epochs[currentEpoch - 1].cumulativeStETHPerLockedShare + stEthPerLockedShare;

    uint256 stEthPerUnlocked;
    if (totalUnlockedChi != 0) {
      stEthPerUnlocked = Math.mulDiv(stETHrewardsForUnlocked, 1e18, totalUnlockedChi);
    }

    epoch.cumulativeStETHPerUnlocked = epochs[currentEpoch - 1].cumulativeStETHPerUnlocked + stEthPerUnlocked;

    totalVotingPower -= totalLockedChi / MAX_LOCK_DURATION;
    sumShareDurationProduct -= totalLockedShares / MAX_LOCK_DURATION;

    if (totalLockedShares != 0) {
      totalVotingPower += Math.mulDiv(chiEmissions, sumShareDurationProduct, totalLockedShares);
    }

    totalLockedChi += chiEmissions;
    epoch.totalLockedChiInEpoch += chiEmissions;

    EpochData storage nextEpoch = epochs[currentEpoch + 1];

    uint256 amountToUnlock;
    if (totalLockedShares != 0) {
      amountToUnlock = Math.mulDiv(epoch.totalLockedChiInEpoch, nextEpoch.sharesToUnlock, epoch.lockedSharesInEpoch);
    }

    totalLockedChi = totalLockedChi - amountToUnlock;
    totalUnlockedChi = totalUnlockedChi + amountToUnlock;
    totalLockedShares -= nextEpoch.sharesToUnlock;

    nextEpoch.lockedSharesInEpoch = totalLockedShares;
    nextEpoch.totalLockedChiInEpoch = totalLockedChi;

    currentEpoch++;
    emit UpdateEpoch(currentEpoch - 1, totalLockedChi, chiEmissions, stETHrewards, stEthPerLockedShare);
  }

  /// @inheritdoc IChiLocking
  function claimStETH(address account) external onlyRewardController returns (uint256 amount) {
    _updateUnclaimedStETH(account);
    amount = locks[account].unclaimedStETH;
    locks[account].unclaimedStETH = 0;

    emit ClaimStETH(account, amount);
  }

  /// @inheritdoc IChiLocking
  function withdrawChiFromAccount(address account, uint256 amount) public onlyChiLockers {
    withdrawChiFromAccountToAddress(account, account, amount);
  }

  /// @inheritdoc IChiLocking
  function withdrawChiFromAccountToAddress(address account, address toAddress, uint256 amount) public onlyChiLockers {
    if (amount == 0) {
      return;
    }

    _updateUnclaimedStETH(account);

    uint256 toWithdraw = amount;

    LockingData storage lockData = locks[account];

    uint256 pos = 0;
    while (toWithdraw > 0) {
      if (pos >= lockData.positions.length) {
        revert UnavailableWithdrawAmount(amount);
      }

      LockedPosition storage position = lockData.positions[pos];

      if (currentEpoch < position.startEpoch + position.duration) {
        pos++;
      } else {
        uint256 availableToWithdraw = _availableToWithdrawFromPosition(position);

        if (availableToWithdraw > toWithdraw) {
          position.withdrawnChiAmount += toWithdraw;
          toWithdraw = 0;
        } else {
          position.withdrawnChiAmount += toWithdraw;
          toWithdraw -= availableToWithdraw;
          _removePosition(lockData, pos);
        }
      }
    }

    totalUnlockedChi -= amount;
    chi.safeTransfer(toAddress, amount);

    emit WithdrawChiFromAccount(account, toAddress, amount);
  }

  /// @inheritdoc IChiLocking
  function unclaimedStETHAmount(address account) public view returns (uint256 totalAmount) {
    LockingData storage lockData = locks[account];
    totalAmount = lockData.unclaimedStETH;
    if (lockData.lastUpdatedEpoch == currentEpoch) return totalAmount;

    for (uint256 i = 0; i < lockData.positions.length; i++) {
      totalAmount += _getUnclaimedStETHPositionAmount(lockData.positions[i], lockData.lastUpdatedEpoch);
    }
  }

  /// @inheritdoc IChiLocking
  function getVotingPower(address account) public view returns (uint256) {
    uint256 votingPower = 0;
    LockingData storage lockData = locks[account];
    for (uint256 i = 0; i < lockData.positions.length; i++) {
      votingPower += _getCurrentVotingPowerForPosition(lockData.positions[i]);
    }
    return votingPower;
  }

  function _getNumberOfShares(uint256 chiAmount) internal view returns (uint256) {
    if (totalLockedChi == 0) return chiAmount;
    return Math.mulDiv(chiAmount, totalLockedShares, totalLockedChi);
  }

  function _updateUnclaimedStETH(address account) internal {
    locks[account].unclaimedStETH = unclaimedStETHAmount(account);
    locks[account].lastUpdatedEpoch = currentEpoch;
  }

  function _getUnclaimedStETHPositionAmount(
    LockedPosition storage position,
    uint256 lastUpdated
  ) internal view returns (uint256 unclaimedAmount) {
    if (lastUpdated == currentEpoch) return 0;

    uint256 fromEpoch = lastUpdated < position.startEpoch ? position.startEpoch : lastUpdated;
    uint256 toEpoch = currentEpoch - 1;

    uint256 lockEndsInEpoch = position.startEpoch + position.duration - 1;
    if (fromEpoch <= lockEndsInEpoch) {
      if (toEpoch <= lockEndsInEpoch) {
        unclaimedAmount += _unclaiemdStETHDuringLocked(position, fromEpoch, toEpoch);
        return unclaimedAmount;
      } else {
        unclaimedAmount += _unclaiemdStETHDuringLocked(position, fromEpoch, lockEndsInEpoch);
      }

      fromEpoch = lockEndsInEpoch + 1;
    }

    unclaimedAmount += _unclaiemdStETHAfterLocked(position, fromEpoch, toEpoch);
  }

  function _unclaiemdStETHDuringLocked(
    LockedPosition storage position,
    uint256 fromEpoch,
    uint256 toEpoch
  ) internal view returns (uint256) {
    uint256 rewardPerShare = epochs[toEpoch].cumulativeStETHPerLockedShare -
      epochs[fromEpoch - 1].cumulativeStETHPerLockedShare;

    return Math.mulDiv(rewardPerShare, position.shares, 1e18);
  }

  function _unclaiemdStETHAfterLocked(
    LockedPosition storage position,
    uint256 fromEpoch,
    uint256 toEpoch
  ) internal view returns (uint256) {
    uint256 unlockedChiAmount = _availableToWithdrawFromPosition(position);
    uint256 rewardPerChi = epochs[toEpoch].cumulativeStETHPerUnlocked -
      epochs[fromEpoch - 1].cumulativeStETHPerUnlocked;
    return Math.mulDiv(rewardPerChi, unlockedChiAmount, 1e18);
  }

  function _getCurrentVotingPowerForPosition(LockedPosition storage position) internal view returns (uint256) {
    if (currentEpoch >= position.startEpoch + position.duration || currentEpoch < position.startEpoch) return 0;
    uint256 epochsUntilEnd = position.startEpoch + position.duration - currentEpoch;

    if (currentEpoch == position.startEpoch) {
      return Math.mulDiv(position.amount, epochsUntilEnd, MAX_LOCK_DURATION);
    } else {
      return Math.mulDiv(_totalAccumulatedAtEpoch(currentEpoch - 1, position), epochsUntilEnd, MAX_LOCK_DURATION);
    }
  }

  function _availableToWithdrawFromPosition(LockedPosition storage position) internal view returns (uint256) {
    uint256 endLockingEpoch = position.startEpoch + position.duration - 1;
    if (currentEpoch <= endLockingEpoch) return 0;
    return _totalAccumulatedAtEpoch(endLockingEpoch, position) - position.withdrawnChiAmount;
  }

  function _totalAccumulatedAtEpoch(uint256 epochNum, LockedPosition storage position) internal view returns (uint256) {
    uint256 endEpoch = position.startEpoch + position.duration - 1;
    if (endEpoch < epochNum) epochNum = endEpoch;

    EpochData storage epoch = epochs[epochNum];
    return Math.mulDiv(position.shares, epoch.totalLockedChiInEpoch, epoch.lockedSharesInEpoch);
  }

  function _removePosition(LockingData storage lockData, uint256 pos) internal {
    lockData.positions[pos] = lockData.positions[lockData.positions.length - 1];
    lockData.positions.pop();
  }
}

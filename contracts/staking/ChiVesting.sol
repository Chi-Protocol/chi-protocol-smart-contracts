// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "../interfaces/IChiVesting.sol";

/// @title Contract for vesting chi tokens
/// @notice This contract holds chi tokens that are vested
/// @notice This contract hold vested chi tokens, vesting is done on epochs
/// @dev This contract is upgradeable
contract ChiVesting is IChiVesting, OwnableUpgradeable {
  using SafeERC20 for IERC20;

  uint256 public constant MAX_LOCK_DURATION = 208;
  IERC20 public chi;

  uint256 public cliffDuration;
  uint256 public vestingDuration;
  uint256 public totalLockedChi;
  uint256 public totalUnlockedChi;
  uint256 public totalShares;
  uint256 public currentEpoch;
  uint256 public totalVotingPower;
  address public rewardController;

  mapping(address account => bool status) public chiVesters;
  mapping(address account => VestingData) public vestingData;
  mapping(uint256 id => EpochData) public epochs;

  modifier onlyRewardController() {
    if (msg.sender != rewardController) {
      revert NotRewardController();
    }
    _;
  }

  modifier onlyChiVesters() {
    if (!chiVesters[msg.sender]) {
      revert NotChiVester();
    }
    _;
  }

  function initialize(IERC20 _chi, uint256 _cliffDuration, uint256 _vestingDuration) external initializer {
    __Ownable_init();

    chi = _chi;
    cliffDuration = _cliffDuration;
    vestingDuration = _vestingDuration;
    currentEpoch = 1;
  }

  /// @inheritdoc IChiVesting
  function setRewardController(address _rewardController) external onlyOwner {
    rewardController = _rewardController;
    emit SetRewardController(_rewardController);
  }

  /// @inheritdoc IChiVesting
  function setChiVester(address contractAddress, bool toSet) external onlyOwner {
    chiVesters[contractAddress] = toSet;
    emit SetChiVester(contractAddress, toSet);
  }

  /// @inheritdoc IChiVesting
  function getLockedChi() public view returns (uint256) {
    return totalLockedChi;
  }

  /// @inheritdoc IChiVesting
  function addVesting(address account, uint256 chiAmount) external onlyChiVesters {
    if (currentEpoch > cliffDuration) {
      revert CliffPassed();
    }

    _updateUnclaimedStETH(account);

    uint256 shares = _getNumberOfShares(chiAmount);
    VestingData storage vesting = vestingData[account];
    vesting.shares += shares;
    vesting.startAmount += chiAmount;

    totalLockedChi += chiAmount;
    totalShares += shares;

    totalVotingPower += Math.mulDiv(chiAmount, _epochsUntilEnd(), MAX_LOCK_DURATION);

    emit AddVesting(account, chiAmount, shares);
  }

  /// @inheritdoc IChiVesting
  function updateEpoch(uint256 chiEmissions, uint256 stETHrewards) external onlyRewardController {
    EpochData storage epoch = epochs[currentEpoch];

    uint256 stETHRewardPerShare;
    if (totalShares != 0) {
      stETHRewardPerShare = Math.mulDiv(stETHrewards, 1e18, totalShares);
    }
    epoch.cumulativeStETHRewardPerShare = epochs[currentEpoch - 1].cumulativeStETHRewardPerShare + stETHRewardPerShare;

    uint256 epochsUntilEnd = _epochsUntilEnd();

    totalLockedChi += chiEmissions;

    if (epochsUntilEnd > 0) {
      totalVotingPower += Math.mulDiv(chiEmissions, _epochsUntilEnd(), MAX_LOCK_DURATION);
    }

    uint256 amountToUnlock;
    if (totalLockedChi > 0 && currentEpoch > cliffDuration && epochsUntilEnd > 0) {
      amountToUnlock = totalLockedChi / _epochsUntilEnd();
    }

    uint256 amountUnlockedPerShare;
    if (totalShares > 0) {
      amountUnlockedPerShare = Math.mulDiv(amountToUnlock, 1e18, totalShares);
    }
    epoch.cumulativeUnlockedPerShare = epochs[currentEpoch - 1].cumulativeUnlockedPerShare + amountUnlockedPerShare;

    totalLockedChi -= amountToUnlock;
    totalUnlockedChi += amountToUnlock;

    if (epochsUntilEnd > 0) {
      // decrease for unlocked tokens
      uint256 decreaseVotingPower = Math.mulDiv(amountToUnlock, epochsUntilEnd, MAX_LOCK_DURATION);
      if (decreaseVotingPower > totalVotingPower) {
        totalVotingPower = 0;
      } else {
        totalVotingPower -= decreaseVotingPower;
      }

      // regular decrease in voting power because of less time until end of locking
      totalVotingPower = Math.mulDiv(totalVotingPower, epochsUntilEnd - 1, epochsUntilEnd);
    }

    currentEpoch++;
    emit UpdateEpoch(currentEpoch - 1, stETHrewards, totalLockedChi);
  }

  /// @inheritdoc IChiVesting
  function withdrawChi(uint256 amount) external {
    VestingData storage vesting = vestingData[msg.sender];

    _updateAvailabeWithdraw(msg.sender);
    if (amount > vesting.unlockedChi) {
      revert UnavailableWithdrawAmount(amount);
    }

    vesting.unlockedChi -= amount;
    totalUnlockedChi -= amount;

    chi.safeTransfer(msg.sender, amount);

    emit WithdrawChi(msg.sender, amount);
  }

  /// @inheritdoc IChiVesting
  function claimStETH(address account) external onlyRewardController returns (uint256) {
    _updateUnclaimedStETH(account);
    uint256 amount = vestingData[account].unclaimedStETH;
    vestingData[account].unclaimedStETH = 0;

    emit ClaimStETH(account, amount);
    return amount;
  }

  /// @inheritdoc IChiVesting
  function unclaimedStETHAmount(address account) public view returns (uint256) {
    VestingData storage vesting = vestingData[account];
    uint256 totalAmount = vesting.unclaimedStETH;

    uint256 rewardPerShare = epochs[currentEpoch - 1].cumulativeStETHRewardPerShare -
      epochs[vesting.lastClaimedEpoch].cumulativeStETHRewardPerShare;
    totalAmount += Math.mulDiv(rewardPerShare, vesting.shares, 1e18);

    return totalAmount;
  }

  /// @inheritdoc IChiVesting
  function getVotingPower(address account) external view returns (uint256) {
    if (currentEpoch > cliffDuration + vestingDuration) return 0;
    VestingData storage vesting = vestingData[account];
    return vesting.shares != 0 ? Math.mulDiv(totalVotingPower, vesting.shares, totalShares) : 0;
  }

  /// @inheritdoc IChiVesting
  function getTotalVotingPower() external view returns (uint256) {
    return totalVotingPower;
  }

  /// @inheritdoc IChiVesting
  function availableChiWithdraw(address account) public view returns (uint256) {
    VestingData storage vesting = vestingData[account];
    return vesting.unlockedChi + _availableUnlockFromTo(vesting.lastWithdrawnEpoch, currentEpoch - 1, vesting.shares);
  }

  // includes available amount in `toEpoch`
  function _availableUnlockFromTo(uint256 fromEpoch, uint256 toEpoch, uint256 shares) internal view returns (uint256) {
    uint256 availableWithdrawPerShare = epochs[toEpoch].cumulativeUnlockedPerShare -
      epochs[fromEpoch].cumulativeUnlockedPerShare;
    return Math.mulDiv(availableWithdrawPerShare, shares, 1e18);
  }

  function _getNumberOfShares(uint256 chiAmount) internal view returns (uint256) {
    if (totalLockedChi == 0) return chiAmount;
    return Math.mulDiv(chiAmount, totalShares, totalLockedChi);
  }

  function _updateAvailabeWithdraw(address account) internal {
    vestingData[account].unlockedChi = availableChiWithdraw(account);
    vestingData[account].lastWithdrawnEpoch = currentEpoch - 1;
  }

  function _updateUnclaimedStETH(address account) internal {
    vestingData[account].unclaimedStETH = unclaimedStETHAmount(account);
    vestingData[account].lastClaimedEpoch = currentEpoch - 1;
  }

  function _epochsUntilEnd() internal view returns (uint256) {
    if (currentEpoch > cliffDuration + vestingDuration + 1) return 0;
    return cliffDuration + vestingDuration + 1 - currentEpoch;
  }
}

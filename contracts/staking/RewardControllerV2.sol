// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "../interfaces/IRewardController.sol";
import "../interfaces/IMintableERC20.sol";
import "../interfaces/IBurnableERC20.sol";
import "../interfaces/IArbitrage.sol";
import "../interfaces/IReserveHolder.sol";
import "../interfaces/IStaking.sol";
import "../interfaces/IUSCStaking.sol";
import "../interfaces/IChiStaking.sol";
import "../interfaces/IChiLocking.sol";
import "../interfaces/IChiVesting.sol";
import "../interfaces/ILPStaking.sol";

/// @title Contract for managing rewards
/// @notice This contract manages rewards for chi lockers, chi stakers, chi vesters and usc stakers
/// @notice This contract holds chi incentives for all contracts and distributes then at the end of epoch
/// @dev This contract is upgradeable
contract RewardControllerV2 is IRewardController, OwnableUpgradeable {
  using SafeERC20 for IERC20;

  uint256 public constant EPOCH_DURATION = 1 weeks;

  IERC20 public chi;
  IERC20 public usc;
  IReserveHolder public reserveHolder;
  IArbitrage public arbitrager;
  IUSCStaking public uscStaking;
  IChiStaking public chiStaking;
  IChiLocking public chiLocking;
  IChiVesting public chiVesting;
  ILPStaking public uscEthLPStaking;
  ILPStaking public chiEthLPStaking;

  uint256 public currentEpoch;
  uint256 public firstEpochTimestamp;
  uint256 public chiIncentivesForChiLocking;
  uint256 public chiIncentivesForUscStaking;
  uint256 public chiIncentivesForUscEthLPStaking;
  uint256 public chiIncentivesForChiEthLPStaking;

  mapping(uint256 id => EpochData) public epochs;

  // Upgrade
  uint256 public constant MAX_PERCENTAGE = 100_00;
  uint256 public uscStakingProtocolFee; // Protocol fee from USC staking rewards, maximum 100_00 = 100%

  // Upgrade
  mapping(address => bool) public isArbitrager;

  modifier onlyArbitrager() {
    if (!isArbitrager[msg.sender] && address(arbitrager) != msg.sender) {
      revert NotArbitrager();
    }
    _;
  }

  function initialize(
    IERC20 _chi,
    IERC20 _usc,
    IReserveHolder _reserveHolder,
    IUSCStaking _uscStaking,
    IChiStaking _chiStaking,
    IChiLocking _chiLocking,
    IChiVesting _chiVesting,
    ILPStaking _uscEthLPStaking,
    ILPStaking _chiEthLPStaking,
    uint256 _firstEpochTimestamp
  ) external initializer {
    __Ownable_init();
    chi = _chi;
    usc = _usc;
    reserveHolder = _reserveHolder;
    uscStaking = _uscStaking;
    chiStaking = _chiStaking;
    chiLocking = _chiLocking;
    chiVesting = _chiVesting;
    uscEthLPStaking = _uscEthLPStaking;
    chiEthLPStaking = _chiEthLPStaking;
    firstEpochTimestamp = _firstEpochTimestamp;
    currentEpoch = 1;
  }

  /// @inheritdoc IRewardController
  function setChiIncentivesForChiLocking(uint256 _chiIncentivesForChiLocking) external onlyOwner {
    chiIncentivesForChiLocking = _chiIncentivesForChiLocking;
  }

  /// @inheritdoc IRewardController
  function setChiIncentivesForUscStaking(uint256 _chiIncentivesForUscStaking) external onlyOwner {
    chiIncentivesForUscStaking = _chiIncentivesForUscStaking;
  }

  /// @inheritdoc IRewardController
  function setChiIncentivesForUscEthLPStaking(uint256 _chiIncentivesForUscEthLPStaking) external onlyOwner {
    chiIncentivesForUscEthLPStaking = _chiIncentivesForUscEthLPStaking;
  }

  /// @inheritdoc IRewardController
  function setChiIncentivesForChiEthLPStaking(uint256 _chiIncentivesForChiEthLPStaking) external onlyOwner {
    chiIncentivesForChiEthLPStaking = _chiIncentivesForChiEthLPStaking;
  }

  /// @inheritdoc IRewardController
  function setArbitrager(IArbitrage _arbitrager) external onlyOwner {
    arbitrager = _arbitrager;
    emit SetArbitrager(address(_arbitrager));
  }

  function updateArbitrager(address account, bool status) external onlyOwner {
    isArbitrager[account] = status;
    emit UpdateArbitrager(account, status);
  }

  function setUscStakingProtocolFee(uint256 _uscStakingProtocolFee) external onlyOwner {
    uscStakingProtocolFee = _uscStakingProtocolFee;
  }

  /// @inheritdoc IRewardController
  function rewardUSC(uint256 amount) external onlyArbitrager {
    if (amount == 0) {
      revert ZeroAmount();
    }

    usc.safeTransferFrom(msg.sender, address(this), amount);
    epochs[currentEpoch].totalUscReward += amount;

    emit RewardUSC(msg.sender, amount);
  }

  /// @inheritdoc IRewardController
  function updateEpoch() public {
    if (block.timestamp < firstEpochTimestamp + currentEpoch * EPOCH_DURATION) {
      revert EpochNotFinished();
    }

    uint256 totalUscRewards = epochs[currentEpoch].totalUscReward;
    uint256 uscProtocolFee = Math.mulDiv(totalUscRewards, uscStakingProtocolFee, MAX_PERCENTAGE);
    usc.safeTransfer(owner(), uscProtocolFee);

    epochs[currentEpoch].totalUscReward -= uscProtocolFee;

    StETHRewards memory stEthRewards = _updateAndGetStETHRewards();
    ChiIncentives memory chiIncentives = _updateAndGetChiIncentives();

    _updateEpochsInSubcontracts(stEthRewards, chiIncentives, epochs[currentEpoch].totalUscReward);

    usc.safeTransfer(address(uscStaking), epochs[currentEpoch].totalUscReward);
    chi.safeTransfer(address(uscStaking), chiIncentives.uscStakingChiIncentives);
    chi.safeTransfer(address(chiLocking), chiIncentives.chiLockingChiIncentives);
    chi.safeTransfer(address(chiVesting), chiIncentives.chiVestingChiIncentives);
    chi.safeTransfer(address(uscEthLPStaking), chiIncentivesForUscEthLPStaking);
    chi.safeTransfer(address(chiEthLPStaking), chiIncentivesForChiEthLPStaking);

    currentEpoch++;

    uint256 totalStEthRewards = stEthRewards.uscStakingStEthReward +
      stEthRewards.chiStakingStEthReward +
      stEthRewards.chiLockingStEthReward +
      stEthRewards.chiVestingStEthReward;
    uint256 totalChiIncentives = chiIncentives.uscStakingChiIncentives +
      chiIncentives.chiLockingChiIncentives +
      chiIncentives.chiVestingChiIncentives +
      chiIncentivesForUscEthLPStaking +
      chiIncentivesForChiEthLPStaking;
    emit UpdateEpoch(currentEpoch - 1, totalStEthRewards, totalChiIncentives);
  }

  /// @inheritdoc IRewardController
  function claimStEth() external {
    uint256 totalAmount;
    totalAmount += IStaking(address(uscStaking)).claimStETH(msg.sender);
    totalAmount += IStaking(address(chiStaking)).claimStETH(msg.sender);
    totalAmount += IStaking(address(chiLocking)).claimStETH(msg.sender);
    totalAmount += IStaking(address(chiVesting)).claimStETH(msg.sender);
    totalAmount += IStaking(address(uscEthLPStaking)).claimStETH(msg.sender);
    totalAmount += IStaking(address(chiEthLPStaking)).claimStETH(msg.sender);

    reserveHolder.claimRewards(msg.sender, totalAmount);

    emit ClaimStEth(msg.sender, totalAmount);
  }

  /// @inheritdoc IRewardController
  function unclaimedStETHAmount(address account) external view returns (uint256) {
    uint256 totalAmount;
    totalAmount += IStaking(address(uscStaking)).unclaimedStETHAmount(account);
    totalAmount += IStaking(address(chiStaking)).unclaimedStETHAmount(account);
    totalAmount += IStaking(address(chiLocking)).unclaimedStETHAmount(account);
    totalAmount += IStaking(address(chiVesting)).unclaimedStETHAmount(account);
    totalAmount += IStaking(address(uscEthLPStaking)).unclaimedStETHAmount(account);
    totalAmount += IStaking(address(chiEthLPStaking)).unclaimedStETHAmount(account);

    return totalAmount;
  }

  function _updateAndGetChiIncentives() internal view returns (ChiIncentives memory) {
    uint256 chiLockingLocked = chiLocking.getLockedChi();
    uint256 chiVestingLocked = chiVesting.getLockedChi();
    uint256 totalLockedChi = chiLockingLocked + chiVestingLocked;

    uint256 chiLockingChiIncentives;
    uint256 chiVestingChiIncentives;
    if (totalLockedChi != 0) {
      chiLockingChiIncentives = Math.mulDiv(chiLockingLocked, chiIncentivesForChiLocking, totalLockedChi);
      chiVestingChiIncentives = Math.mulDiv(chiVestingLocked, chiIncentivesForChiLocking, totalLockedChi);
    }

    return
      ChiIncentives({
        uscStakingChiIncentives: chiIncentivesForUscStaking,
        chiLockingChiIncentives: chiLockingChiIncentives,
        chiVestingChiIncentives: chiVestingChiIncentives
      });
  }

  function _updateEpochsInSubcontracts(
    StETHRewards memory stEthRewards,
    ChiIncentives memory chiIncentives,
    uint256 uscReward
  ) internal {
    uscStaking.updateEpoch(chiIncentives.uscStakingChiIncentives, uscReward, stEthRewards.uscStakingStEthReward);
    chiStaking.updateEpoch(stEthRewards.chiStakingStEthReward);
    chiLocking.updateEpoch(chiIncentives.chiLockingChiIncentives, stEthRewards.chiLockingStEthReward);
    chiVesting.updateEpoch(chiIncentives.chiVestingChiIncentives, stEthRewards.chiVestingStEthReward);
    uscEthLPStaking.updateEpoch(chiIncentivesForUscEthLPStaking, stEthRewards.uscEthLPStakingStEthReward);
    chiEthLPStaking.updateEpoch(chiIncentivesForChiEthLPStaking, stEthRewards.chiEthLPStakingStEthReward);
  }

  function _updateAndGetStETHRewards() internal returns (StETHRewards memory) {
    epochs[currentEpoch].reserveHolderTotalRewards = reserveHolder.getCumulativeRewards();
    uint256 stETHEpochrewards = epochs[currentEpoch].reserveHolderTotalRewards -
      epochs[currentEpoch - 1].reserveHolderTotalRewards;

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
    if (totalChi != 0) {
      uscStakingStEthReward = Math.mulDiv(uscStakedChi, stETHEpochrewards, totalChi);
      chiStakingStEthReward = Math.mulDiv(chiStakedChi, stETHEpochrewards, totalChi);
      chiLockingStEthReward = Math.mulDiv(chiLockedChi, stETHEpochrewards, totalChi);
      chiVestingStEthReward = Math.mulDiv(chiVestingChi, stETHEpochrewards, totalChi);
      uscEthLPStakingStEthReward = Math.mulDiv(uscEthLPStakingChi, stETHEpochrewards, totalChi);
      chiEthLPStakingStEthReward = Math.mulDiv(chiEthLPStakingStEthReward, stETHEpochrewards, totalChi);
    }

    return
      StETHRewards({
        uscStakingStEthReward: uscStakingStEthReward,
        chiStakingStEthReward: chiStakingStEthReward,
        chiLockingStEthReward: chiLockingStEthReward,
        chiVestingStEthReward: chiVestingStEthReward,
        uscEthLPStakingStEthReward: uscEthLPStakingStEthReward,
        chiEthLPStakingStEthReward: chiEthLPStakingStEthReward
      });
  }
}

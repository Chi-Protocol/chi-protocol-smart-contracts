// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IChiLocking} from "contracts/interfaces/IChiLocking.sol";
import {USC} from "contracts/tokens/USC.sol";
import {CHI} from "contracts/tokens/CHI.sol";
import {ChiStaking} from "contracts/staking/ChiStaking.sol";
import {ChiLocking} from "contracts/staking/ChiLocking.sol";
import {ChiLocker} from "./helpers/ChiLocker.sol";
import "forge-std/console.sol";

contract ChiLockingTest is Test {
  uint256 public constant TOLERANCE = 0.00001 ether;
  uint256 public constant USC_INITIAL_SUPPLY = 100000000 ether;
  uint256 public constant CHI_INITIAL_SUPPLY = 100000000 ether;

  USC public usc;
  CHI public chi;
  ChiStaking public chiStaking;
  ChiLocking public chiLocking;

  address public user1;
  address public user2;
  address public user3;

  function setUp() public {
    usc = new USC();
    chi = new CHI(CHI_INITIAL_SUPPLY);

    chiStaking = new ChiStaking();
    chiStaking.initialize(IERC20(address(chi)));

    chiLocking = new ChiLocking();
    chiLocking.initialize(IERC20(address(chi)), address(chiStaking));
    chiStaking.setChiLocking(IChiLocking(address(chiLocking)));
    chi.transfer(address(chiLocking), CHI_INITIAL_SUPPLY);

    user1 = makeAddr("user1");
    user2 = makeAddr("user2");
    user3 = makeAddr("user3");
  }

  function test_SetUp() public {
    assertEq(chiLocking.owner(), address(this));
    assertEq(chiLocking.chiLockers(address(chiStaking)), true);
    assertEq(chiLocking.currentEpoch(), 1);
  }

  function testFuzz_SetUscStaking(address _uscStaking) public {
    chiLocking.setUscStaking(_uscStaking);
    assertEq(chiLocking.chiLockers(_uscStaking), true);
  }

  function testFuzz_SetUscStaking_Revert_NotOwner(address _caller, address _uscStaking) public {
    vm.assume(_caller != address(this));
    vm.startPrank(_caller);
    vm.expectRevert("Ownable: caller is not the owner");
    chiLocking.setUscStaking(_uscStaking);
    vm.stopPrank();
  }

  function testFuzz_SetRewardController(address _rewardController) public {
    chiLocking.setRewardController(_rewardController);
    assertEq(chiLocking.rewardController(), _rewardController);
  }

  function testFuzz_SetRewardController_Revert_NotOwner(address _caller, address _rewardController) public {
    vm.assume(_caller != address(this));
    vm.startPrank(_caller);
    vm.expectRevert("Ownable: caller is not the owner");
    chiLocking.setRewardController(_rewardController);
    vm.stopPrank();
  }

  function testFuzz_SetChiLocker(address _contractAddress, bool _toSet) public {
    chiLocking.setChiLocker(_contractAddress, _toSet);
    assertEq(chiLocking.chiLockers(_contractAddress), _toSet);
  }

  function testFuzz_SetChiLocker_Revert_NotOwner(address _caller, address _contractAddress, bool _toSet) public {
    vm.assume(_caller != address(this));
    vm.startPrank(_caller);
    vm.expectRevert("Ownable: caller is not the owner");
    chiLocking.setChiLocker(_contractAddress, _toSet);
    vm.stopPrank();
  }

  function test_LockChi() public {
    chiLocking.setChiLocker(address(this), true);
    chiLocking.setRewardController(address(this));
    uint256 chiIncentivesEpoch1 = 500 ether;

    chiLocking.lockChi(user1, 1000 ether, 8);

    IChiLocking.LockedPosition memory position = chiLocking.getLockedPosition(user1, 0);
    assertEq(position.amount, 1000 ether);
    assertEq(position.startEpoch, 1);
    assertEq(position.duration, 9);
    assertEq(position.shares, 1000 ether);
    assertEq(position.withdrawnChiAmount, 0);
    assertEq(chiLocking.totalLockedChi(), 1000 ether);
    assertEq(chiLocking.totalLockedShares(), 1000 ether);

    {
      (uint256 lockedSharesInEpoch, uint256 totalLockedInEpoc, , , , ) = chiLocking.epochs(1);
      assertEq(lockedSharesInEpoch, 1000 ether);
      assertEq(totalLockedInEpoc, 1000 ether);

      (, , uint256 sharesToUnlock, , , ) = chiLocking.epochs(10);
      assertEq(sharesToUnlock, 1000 ether);
    }

    chiLocking.updateEpoch(chiIncentivesEpoch1, 0);

    uint256 chiIncentivesEpoch2 = 5000 ether;
    chiLocking.lockChi(user2, 1500 ether, 8);
    chiLocking.lockChi(user3, 3000 ether, 1);
    chiLocking.lockChi(user1, 12000 ether, 1);
    chiLocking.updateEpoch(chiIncentivesEpoch2, 0);

    position = chiLocking.getLockedPosition(user1, 1);
    assertEq(position.amount, 12000 ether);
    assertEq(position.startEpoch, 2);
    assertEq(position.duration, 2);
    assertEq(position.shares, 8000 ether);
    assertEq(position.withdrawnChiAmount, 0);

    position = chiLocking.getLockedPosition(user2, 0);
    assertEq(position.amount, 1500 ether);
    assertEq(position.startEpoch, 2);
    assertEq(position.duration, 9);
    assertEq(position.shares, 1000 ether);
    assertEq(position.withdrawnChiAmount, 0);

    position = chiLocking.getLockedPosition(user3, 0);
    assertEq(position.amount, 3000 ether);
    assertEq(position.startEpoch, 2);
    assertEq(position.duration, 2);
    assertEq(position.shares, 2000 ether);
    assertEq(position.withdrawnChiAmount, 0);

    assertEq(chiLocking.totalLockedChi(), 23000 ether);
    assertEq(chiLocking.totalLockedShares(), 12000 ether);

    {
      (uint256 lockedSharesInEpoch, uint256 totalLockedInEpoc, , , , ) = chiLocking.epochs(2);
      assertEq(lockedSharesInEpoch, 12000 ether);
      assertEq(totalLockedInEpoc, 23000 ether);

      (, , uint256 sharesToUnclock, , , ) = chiLocking.epochs(4);
      assertEq(sharesToUnclock, 10000 ether);

      (, , sharesToUnclock, , , ) = chiLocking.epochs(11);
      assertEq(sharesToUnclock, 1000 ether);
    }

    uint256 chiIncentivesEpoch3 = 3000 ether;
    uint256 lockingAmount = chiLocking.totalLockedChi();
    chiLocking.lockChi(user3, lockingAmount, 2);
    chiLocking.updateEpoch(chiIncentivesEpoch3, 0);

    position = chiLocking.getLockedPosition(user3, 1);
    assertEq(position.amount, lockingAmount);
    assertEq(position.startEpoch, 3);
    assertEq(position.duration, 3);
    assertEq(position.shares, 12000 ether);
    assertEq(position.withdrawnChiAmount, 0);

    {
      (uint256 lockedSharesInEpoch, uint256 totalLockedInEpoc, , , , ) = chiLocking.epochs(3);
      assertEq(lockedSharesInEpoch, 24000 ether);
      assertEq(totalLockedInEpoc, 49000 ether);

      (, , uint256 sharesToUnclock, , , ) = chiLocking.epochs(6);
      assertEq(sharesToUnclock, 12000 ether);
    }
  }

  function test_UpdateEpoch() public {
    chiLocking.setChiLocker(address(this), true);
    chiLocking.setRewardController(address(this));

    uint256 chiIncentivesEpoch1 = 500 ether;
    uint256 stEthRewardEpoch1 = 500 ether;
    chiLocking.lockChi(user1, 1000 ether, 8);
    chiLocking.updateEpoch(chiIncentivesEpoch1, stEthRewardEpoch1);

    assertEq(chiLocking.currentEpoch(), 2);
    assertEq(chiLocking.totalLockedChi(), 1000 ether + chiIncentivesEpoch1);
    assertEq(chiLocking.totalUnlockedChi(), 0);
    assertEq(chiLocking.totalLockedShares(), 1000 ether);
    {
      (uint256 lockedSharesInEpoch, uint256 totalLockedInEpoch, uint256 sharesToUnlock, , , ) = chiLocking.epochs(1);

      assertEq(lockedSharesInEpoch, 1000 ether);
      assertEq(totalLockedInEpoch, 1000 ether + chiIncentivesEpoch1);
      assertEq(sharesToUnlock, 0);

      (lockedSharesInEpoch, totalLockedInEpoch, sharesToUnlock, , , ) = chiLocking.epochs(2);
      assertEq(lockedSharesInEpoch, 1000 ether);
      assertEq(totalLockedInEpoch, 1000 ether + chiIncentivesEpoch1);
      assertEq(sharesToUnlock, 0);
    }

    uint256 chiIncentivesEpoch2 = 5000 ether;
    uint256 stEthRewardEpoch2 = 5000 ether;
    chiLocking.lockChi(user2, 1500 ether, 8);
    chiLocking.lockChi(user3, 3000 ether, 1);
    chiLocking.lockChi(user1, 12000 ether, 1);
    chiLocking.updateEpoch(chiIncentivesEpoch2, stEthRewardEpoch2);

    assertEq(chiLocking.currentEpoch(), 3);
    assertEq(chiLocking.totalLockedShares(), 12000 ether);
    assertEq(chiLocking.totalUnlockedChi(), 0);
    assertEq(chiLocking.totalLockedChi(), 23000 ether);
    assertEq(chiLocking.getStakedChi(), 23000 ether);

    {
      (uint256 lockedSharesInEpoch, uint256 totalLockedInEpoch, uint256 sharesToUnlock, , , ) = chiLocking.epochs(2);

      assertEq(lockedSharesInEpoch, 12000 ether);
      assertEq(totalLockedInEpoch, 23000 ether);
      assertEq(sharesToUnlock, 0);
    }

    uint256 chiIncentivesEpoch3 = 3000 ether;
    uint256 stEthRewardEpoch3 = 3000 ether;
    uint256 lockingAmount = chiLocking.totalLockedChi();
    chiLocking.lockChi(user3, lockingAmount, 2);
    chiLocking.updateEpoch(chiIncentivesEpoch3, stEthRewardEpoch3);

    uint256 availableChiWithdraw = chiLocking.availableChiWithdraw(user3) + chiLocking.availableChiWithdraw(user1);
    uint256 totalLockedChi = (1000 ether + chiIncentivesEpoch1 + 1500 ether) +
      ((chiIncentivesEpoch2 * 2) / 12 + lockingAmount + (chiIncentivesEpoch3 * 14) / 24);

    assertEq(chiLocking.currentEpoch(), 4);
    assertApproxEqRel(chiLocking.totalLockedChi(), totalLockedChi, TOLERANCE);
    assertEq(chiLocking.totalUnlockedChi(), availableChiWithdraw);
    assertEq(chiLocking.totalLockedShares(), 14000 ether);
    assertEq(chiLocking.getStakedChi(), chiLocking.totalLockedChi() + availableChiWithdraw);
    {
      (uint256 lockedSharesInEpoch, uint256 totalLockedInEpoch, uint256 sharesToUnlock, , , ) = chiLocking.epochs(3);

      assertEq(lockedSharesInEpoch, 24000 ether);
      assertEq(totalLockedInEpoch, 49000 ether);
      assertEq(sharesToUnlock, 0);
    }

    uint256 chiIncentivesEpoch4 = 6000 ether;
    uint256 stEthRewardEpoch4 = 6000 ether;
    chiLocking.updateEpoch(chiIncentivesEpoch4, stEthRewardEpoch4);
    chiLocking.updateEpoch(0, 0);

    availableChiWithdraw = chiLocking.availableChiWithdraw(user3) + chiLocking.availableChiWithdraw(user1);
    totalLockedChi =
      (1000 ether + chiIncentivesEpoch1 + 1500 ether) +
      ((chiIncentivesEpoch2 * 2) / 12 + (chiIncentivesEpoch3 * 2) / 24 + (chiIncentivesEpoch4 * 2) / 14);
    assertEq(chiLocking.currentEpoch(), 6);
    assertApproxEqRel(chiLocking.totalLockedChi(), totalLockedChi, TOLERANCE);
    assertEq(chiLocking.totalUnlockedChi(), availableChiWithdraw);
    assertEq(chiLocking.totalLockedShares(), 2000 ether);
    assertEq(chiLocking.getStakedChi(), chiLocking.totalLockedChi() + availableChiWithdraw);

    {
      (uint256 lockedSharesInEpoch, uint256 totalLockedInEpoch, uint256 sharesToUnlock, , , ) = chiLocking.epochs(6);

      totalLockedChi =
        (1000 ether + chiIncentivesEpoch1 + 1500 ether) +
        ((chiIncentivesEpoch2 * 2) / 12 + (chiIncentivesEpoch3 * 2) / 24 + (chiIncentivesEpoch4 * 2) / 14);
      assertEq(lockedSharesInEpoch, 2000 ether);
      assertApproxEqRel(totalLockedInEpoch, totalLockedChi, TOLERANCE);
      assertEq(sharesToUnlock, 12000 ether);
    }
  }

  function test_AvailableChiWithdraw() public {
    chiLocking.setChiLocker(address(this), true);
    chiLocking.setRewardController(address(this));

    uint256 chiIncentivesEpoch1 = 500 ether;
    chiLocking.lockChi(user1, 1000 ether, 8);
    chiLocking.updateEpoch(chiIncentivesEpoch1, 0);

    assertEq(chiLocking.availableChiWithdraw(user1), 0);

    uint256 chiIncentivesEpoch2 = 5000 ether;
    chiLocking.lockChi(user2, 1500 ether, 8);
    chiLocking.lockChi(user3, 3000 ether, 1);
    chiLocking.lockChi(user1, 12000 ether, 1);
    chiLocking.updateEpoch(chiIncentivesEpoch2, 0);

    assertEq(chiLocking.availableChiWithdraw(user1), 0);
    assertEq(chiLocking.availableChiWithdraw(user2), 0);
    assertEq(chiLocking.availableChiWithdraw(user3), 0);

    uint256 chiIncentivesEpoch3 = 3000 ether;
    uint256 lockingAmount = chiLocking.totalLockedChi();
    chiLocking.lockChi(user3, lockingAmount, 2);
    chiLocking.updateEpoch(chiIncentivesEpoch3, 0);

    uint256 user1ChiIncentives = (chiIncentivesEpoch2 * 2) / 3 + (chiIncentivesEpoch3 * 2) / 6;
    uint256 user3ChiIncentives = (chiIncentivesEpoch2 * 2) / 12 + (chiIncentivesEpoch3 * 2) / 24;
    uint256 user1AvailableToWithdraw = 12000 ether + user1ChiIncentives;
    uint256 user3AvailableToWithdraw = 3000 ether + user3ChiIncentives;
    assertEq(chiLocking.availableChiWithdraw(user1), user1AvailableToWithdraw);
    assertEq(chiLocking.availableChiWithdraw(user2), 0);
    assertEq(chiLocking.availableChiWithdraw(user3), user3AvailableToWithdraw);

    uint256 chiIncentivesEpoch4 = 6000 ether;
    chiLocking.updateEpoch(chiIncentivesEpoch4, 0);
    chiLocking.updateEpoch(0, 0);

    user3AvailableToWithdraw += lockingAmount + (chiIncentivesEpoch3 * 12) / 24 + (chiIncentivesEpoch4 * 12) / 14;
    assertEq(chiLocking.availableChiWithdraw(user1), user1AvailableToWithdraw);
    assertEq(chiLocking.availableChiWithdraw(user2), 0);
    assertApproxEqRel(chiLocking.availableChiWithdraw(user3), user3AvailableToWithdraw, TOLERANCE);
  }

  function test_WithdrawChiFromAccount() public {
    chiLocking.setChiLocker(address(this), true);
    chiLocking.setRewardController(address(this));

    uint256 chiIncentivesEpoch1 = 500 ether;
    uint256 stEthRewardEpoch1 = 500 ether;
    chiLocking.lockChi(user1, 1000 ether, 8);
    chiLocking.updateEpoch(chiIncentivesEpoch1, stEthRewardEpoch1);

    vm.expectRevert(abi.encodeWithSelector(IChiLocking.UnavailableWithdrawAmount.selector, 1));
    chiLocking.withdrawChiFromAccount(user1, 1);

    uint256 chiIncentivesEpoch2 = 5000 ether;
    chiLocking.lockChi(user2, 1500 ether, 8);
    chiLocking.lockChi(user3, 3000 ether, 1);
    chiLocking.lockChi(user1, 12000 ether, 1);
    chiLocking.updateEpoch(chiIncentivesEpoch2, 0);

    vm.expectRevert(abi.encodeWithSelector(IChiLocking.UnavailableWithdrawAmount.selector, 1));
    chiLocking.withdrawChiFromAccount(user1, 1);
    vm.expectRevert(abi.encodeWithSelector(IChiLocking.UnavailableWithdrawAmount.selector, 1));
    chiLocking.withdrawChiFromAccount(user2, 1);
    vm.expectRevert(abi.encodeWithSelector(IChiLocking.UnavailableWithdrawAmount.selector, 1));
    chiLocking.withdrawChiFromAccount(user3, 1);

    uint256 chiIncentivesEpoch3 = 3000 ether;
    uint256 lockingAmount = chiLocking.totalLockedChi();
    chiLocking.lockChi(user3, lockingAmount, 2);
    chiLocking.updateEpoch(chiIncentivesEpoch3, 0);

    uint256 chiIncentivesEpoch4 = 6000 ether;
    chiLocking.updateEpoch(chiIncentivesEpoch4, 0);
    chiLocking.updateEpoch(0, 0);

    uint256 totalStakedBefore = chiLocking.getStakedChi();
    uint256 user1AvailableWithdraw = chiLocking.availableChiWithdraw(user1);
    uint256 user1UnclaimedStEth = chiLocking.unclaimedStETHAmount(user1);

    vm.expectRevert(abi.encodeWithSelector(IChiLocking.UnavailableWithdrawAmount.selector, user1AvailableWithdraw + 1));
    chiLocking.withdrawChiFromAccount(user1, user1AvailableWithdraw + 1);

    chiLocking.withdrawChiFromAccount(user1, user1AvailableWithdraw);
    assertEq(chi.balanceOf(user1), user1AvailableWithdraw);
    assertEq(chiLocking.getStakedChi(), totalStakedBefore - user1AvailableWithdraw);
    assertEq(chiLocking.unclaimedStETHAmount(user1), user1UnclaimedStEth);
  }

  function test_UnclaimedStEthAmount() public {
    chiLocking.setChiLocker(address(this), true);
    chiLocking.setRewardController(address(this));

    uint256 chiIncentivesEpoch1 = 500 ether;
    uint256 stEthRewardEpoch1 = 500 ether;
    chiLocking.lockChi(user1, 1000 ether, 8);
    chiLocking.updateEpoch(chiIncentivesEpoch1, stEthRewardEpoch1);

    assertEq(chiLocking.unclaimedStETHAmount(user1), 500 ether);

    uint256 chiIncentivesEpoch2 = 5000 ether;
    uint256 stEthRewardEpoch2 = 5000 ether;
    chiLocking.lockChi(user2, 1500 ether, 8);
    chiLocking.lockChi(user3, 3000 ether, 1);
    chiLocking.lockChi(user1, 12000 ether, 1);
    chiLocking.updateEpoch(chiIncentivesEpoch2, stEthRewardEpoch2);

    uint256 totalStaked = 18000 ether;
    uint256 user1TotalStaked = 1000 ether + 500 ether + 12000 ether;
    uint256 user2TotalStaked = 1500 ether;
    uint256 user3TotalStaked = 3000 ether;
    uint256 user1Reward = stEthRewardEpoch1 + ((stEthRewardEpoch2 * user1TotalStaked) / totalStaked);
    uint256 user2Reward = (stEthRewardEpoch2 * user2TotalStaked) / totalStaked;
    uint256 user3Reward = (stEthRewardEpoch2 * user3TotalStaked) / totalStaked;
    assertApproxEqRel(chiLocking.unclaimedStETHAmount(user1), user1Reward, TOLERANCE);
    assertApproxEqRel(chiLocking.unclaimedStETHAmount(user2), user2Reward, TOLERANCE);
    assertApproxEqRel(chiLocking.unclaimedStETHAmount(user3), user3Reward, TOLERANCE);

    uint256 chiIncentivesEpoch3 = 3000 ether;
    uint256 stEthRewardEpoch3 = 3000 ether;
    uint256 lockingAmount = chiLocking.totalLockedChi();
    chiLocking.lockChi(user3, lockingAmount, 2);
    chiLocking.updateEpoch(chiIncentivesEpoch3, stEthRewardEpoch3);

    totalStaked += chiIncentivesEpoch2 + lockingAmount;
    user1TotalStaked += (chiIncentivesEpoch2 * 9) / 12;
    user2TotalStaked += chiIncentivesEpoch2 / 12;
    user3TotalStaked += (chiIncentivesEpoch2 * 2) / 12 + lockingAmount;
    user1Reward += (stEthRewardEpoch3 * user1TotalStaked) / totalStaked;
    user2Reward += (stEthRewardEpoch3 * user2TotalStaked) / totalStaked;
    user3Reward += (stEthRewardEpoch3 * user3TotalStaked) / totalStaked;
    assertApproxEqRel(chiLocking.unclaimedStETHAmount(user1), user1Reward, TOLERANCE);
    assertApproxEqRel(chiLocking.unclaimedStETHAmount(user2), user2Reward, TOLERANCE);
    assertApproxEqRel(chiLocking.unclaimedStETHAmount(user3), user3Reward, TOLERANCE);

    uint256 chiIncentivesEpoch4 = 6000 ether;
    uint256 stEthRewardEpoch4 = 6000 ether;
    chiLocking.updateEpoch(chiIncentivesEpoch4, stEthRewardEpoch4);

    totalStaked += chiIncentivesEpoch3;
    user1TotalStaked += (chiIncentivesEpoch3 * 9) / 24;
    user2TotalStaked += chiIncentivesEpoch3 / 24;
    user3TotalStaked += (chiIncentivesEpoch3 * 14) / 24;
    user1Reward += (stEthRewardEpoch4 * user1TotalStaked) / totalStaked;
    user2Reward += (stEthRewardEpoch4 * user2TotalStaked) / totalStaked;
    user3Reward += (stEthRewardEpoch4 * user3TotalStaked) / totalStaked;
    assertApproxEqRel(chiLocking.unclaimedStETHAmount(user1), user1Reward, TOLERANCE);
    assertApproxEqRel(chiLocking.unclaimedStETHAmount(user2), user2Reward, TOLERANCE);
    assertApproxEqRel(chiLocking.unclaimedStETHAmount(user3), user3Reward, TOLERANCE);

    uint256 stEthRewardForEpoch5 = 9000 ether;
    chiLocking.updateEpoch(0, stEthRewardForEpoch5);

    totalStaked += chiIncentivesEpoch4;
    user1TotalStaked += chiIncentivesEpoch4 / 14;
    user2TotalStaked += chiIncentivesEpoch4 / 14;
    user3TotalStaked += (chiIncentivesEpoch4 * 12) / 14;
    user1Reward += (stEthRewardForEpoch5 * user1TotalStaked) / totalStaked;
    user2Reward += (stEthRewardForEpoch5 * user2TotalStaked) / totalStaked;
    user3Reward += (stEthRewardForEpoch5 * user3TotalStaked) / totalStaked;
    assertApproxEqRel(chiLocking.unclaimedStETHAmount(user1), user1Reward, TOLERANCE);
    assertApproxEqRel(chiLocking.unclaimedStETHAmount(user2), user2Reward, TOLERANCE);
    assertApproxEqRel(chiLocking.unclaimedStETHAmount(user3), user3Reward, TOLERANCE);
  }

  function test_ClaimStEth() public {
    chiLocking.setChiLocker(address(this), true);
    chiLocking.setRewardController(address(this));

    uint256 chiIncentivesEpoch1 = 500 ether;
    uint256 stEthRewardEpoch1 = 500 ether;
    chiLocking.lockChi(user1, 1000 ether, 8);
    chiLocking.updateEpoch(chiIncentivesEpoch1, stEthRewardEpoch1);

    assertEq(chiLocking.unclaimedStETHAmount(user1), chiLocking.claimStETH(user1));
    assertEq(chiLocking.unclaimedStETHAmount(user1), 0);

    uint256 chiIncentivesEpoch2 = 5000 ether;
    uint256 stEthRewardEpoch2 = 5000 ether;
    chiLocking.lockChi(user2, 1500 ether, 8);
    chiLocking.lockChi(user3, 3000 ether, 1);
    chiLocking.lockChi(user1, 12000 ether, 1);
    chiLocking.updateEpoch(chiIncentivesEpoch2, stEthRewardEpoch2);

    uint256 chiIncentivesEpoch3 = 3000 ether;
    uint256 stEthRewardEpoch3 = 3000 ether;
    uint256 lockingAmount = chiLocking.totalLockedChi();
    chiLocking.lockChi(user3, lockingAmount, 2);
    chiLocking.updateEpoch(chiIncentivesEpoch3, stEthRewardEpoch3);

    uint256 chiIncentivesEpoch4 = 6000 ether;
    uint256 stEthRewardEpoch4 = 6000 ether;
    chiLocking.updateEpoch(chiIncentivesEpoch4, stEthRewardEpoch4);

    uint256 stEthRewardForEpoch5 = 9000 ether;
    chiLocking.updateEpoch(0, stEthRewardForEpoch5);

    assertEq(chiLocking.unclaimedStETHAmount(user1), chiLocking.claimStETH(user1));
    assertEq(chiLocking.unclaimedStETHAmount(user2), chiLocking.claimStETH(user2));
    assertEq(chiLocking.unclaimedStETHAmount(user3), chiLocking.claimStETH(user3));
    assertEq(chiLocking.unclaimedStETHAmount(user1), 0);
    assertEq(chiLocking.unclaimedStETHAmount(user2), 0);
    assertEq(chiLocking.unclaimedStETHAmount(user3), 0);
  }

  function test_GetVotingPower() public {
    chiLocking.setChiLocker(address(this), true);
    chiLocking.setRewardController(address(this));

    uint256 chiIncentivesEpoch1 = 500 ether;
    uint256 user1LockAmountEpoch1 = 1000 ether;
    chiLocking.lockChi(user1, user1LockAmountEpoch1, 104);

    assertApproxEqRel(chiLocking.getVotingPower(user1), 0, TOLERANCE);
    assertApproxEqRel(chiLocking.totalVotingPower(), chiLocking.getVotingPower(user1), TOLERANCE);

    chiLocking.updateEpoch(chiIncentivesEpoch1, 0);
    assertApproxEqRel(chiLocking.getVotingPower(user1), (user1LockAmountEpoch1 + chiIncentivesEpoch1) / 2, TOLERANCE);
    assertApproxEqRel(chiLocking.totalVotingPower(), chiLocking.getVotingPower(user1), TOLERANCE);

    uint256 user1LockAmountEpoch2 = 4000 ether;
    uint256 user2LockAmountEpoch2 = 2000 ether;
    chiLocking.lockChi(user1, user1LockAmountEpoch2, 3);
    chiLocking.lockChi(user2, user2LockAmountEpoch2, 5);

    assertApproxEqRel(chiLocking.getVotingPower(user1), (user1LockAmountEpoch1 + chiIncentivesEpoch1) / 2, TOLERANCE);
    assertApproxEqRel(chiLocking.getVotingPower(user2), 0, TOLERANCE);
    assertApproxEqRel(
      chiLocking.totalVotingPower(),
      chiLocking.getVotingPower(user1) + chiLocking.getVotingPower(user2),
      TOLERANCE
    );

    uint256 chiEmissionEpoch3 = 10000 ether;
    chiLocking.updateEpoch(chiEmissionEpoch3, 0);

    uint256 correctVotingPowerUser1 = (((user1LockAmountEpoch1 + chiIncentivesEpoch1) * 103) / 208) +
      ((user1LockAmountEpoch2 * 3) / 208) +
      ((((chiEmissionEpoch3 * 4000) / 7500) * 3) / 208) +
      ((((chiEmissionEpoch3 * 1500) / 7500) * 103) / 208);
    uint256 correctVotingPowerUser2 = ((user2LockAmountEpoch2 * 5) / 208) +
      ((((chiEmissionEpoch3 * 2000) / 7500) * 5) / 208);
    assertApproxEqRel(chiLocking.getVotingPower(user1), correctVotingPowerUser1, TOLERANCE);
    assertApproxEqRel(chiLocking.getVotingPower(user2), correctVotingPowerUser2, TOLERANCE);
    assertApproxEqRel(
      chiLocking.totalVotingPower(),
      chiLocking.getVotingPower(user1) + chiLocking.getVotingPower(user2),
      TOLERANCE
    );

    uint256 chiEmissionEpoch4 = 5000 ether;
    chiLocking.updateEpoch(chiEmissionEpoch4, 0);

    correctVotingPowerUser1 =
      (((user1LockAmountEpoch1 + chiIncentivesEpoch1) * 102) / 208) +
      ((user1LockAmountEpoch2 * 2) / 208) +
      ((((chiEmissionEpoch3 * 4000) / 7500) * 2) / 208) +
      ((((chiEmissionEpoch3 * 1500) / 7500) * 102) / 208) +
      ((((chiEmissionEpoch4 * 4000) / 7500) * 2) / 208) +
      ((((chiEmissionEpoch4 * 1500) / 7500) * 102) / 208);
    correctVotingPowerUser2 =
      ((user2LockAmountEpoch2 * 4) / 208) +
      ((((chiEmissionEpoch3 * 2000) / 7500) * 4) / 208) +
      ((((chiEmissionEpoch4 * 2000) / 7500) * 4) / 208);
    assertApproxEqRel(chiLocking.getVotingPower(user1), correctVotingPowerUser1, TOLERANCE);
    assertApproxEqRel(chiLocking.getVotingPower(user2), correctVotingPowerUser2, TOLERANCE);
    assertApproxEqRel(
      chiLocking.totalVotingPower(),
      chiLocking.getVotingPower(user1) + chiLocking.getVotingPower(user2),
      TOLERANCE
    );

    chiLocking.updateEpoch(0, 0);
    correctVotingPowerUser1 =
      ((uint256(1000 ether + 500 ether) * 101) / 208) +
      (user1LockAmountEpoch2 / 208) +
      (((chiEmissionEpoch3 * 4000) / 7500) / 208) +
      ((((chiEmissionEpoch3 * 1500) / 7500) * 101) / 208) +
      (((chiEmissionEpoch4 * 4000) / 7500) / 208) +
      ((((chiEmissionEpoch4 * 1500) / 7500) * 101) / 208);
    correctVotingPowerUser2 =
      ((user2LockAmountEpoch2 * 3) / 208) +
      ((((chiEmissionEpoch3 * 2000) / 7500) * 3) / 208) +
      ((((chiEmissionEpoch4 * 2000) / 7500) * 3) / 208);
    assertApproxEqRel(chiLocking.getVotingPower(user1), correctVotingPowerUser1, TOLERANCE);
    assertApproxEqRel(chiLocking.getVotingPower(user2), correctVotingPowerUser2, TOLERANCE);
    assertApproxEqRel(
      chiLocking.totalVotingPower(),
      chiLocking.getVotingPower(user1) + chiLocking.getVotingPower(user2),
      TOLERANCE
    );

    uint256 chiEmissionEpoch5 = 5000 ether;
    chiLocking.updateEpoch(chiEmissionEpoch5, 0);

    correctVotingPowerUser1 =
      ((uint256(1000 ether + 500 ether) * 100) / 208) +
      ((((chiEmissionEpoch3 * 1500) / 7500) * 100) / 208) +
      ((((chiEmissionEpoch4 * 1500) / 7500) * 100) / 208) +
      ((((chiEmissionEpoch5 * 1500) / 7500) * 100) / 208);
    correctVotingPowerUser2 =
      ((user2LockAmountEpoch2 * 2) / 208) +
      ((((chiEmissionEpoch3 * 2000) / 7500) * 2) / 208) +
      ((((chiEmissionEpoch4 * 2000) / 7500) * 2) / 208) +
      ((((chiEmissionEpoch5 * 2000) / 7500) * 2) / 208);
    assertApproxEqRel(chiLocking.getVotingPower(user1), correctVotingPowerUser1, TOLERANCE);
    assertApproxEqRel(chiLocking.getVotingPower(user2), correctVotingPowerUser2, TOLERANCE);
    assertApproxEqRel(
      chiLocking.getTotalVotingPower(),
      chiLocking.getVotingPower(user1) + chiLocking.getVotingPower(user2),
      TOLERANCE
    );

    uint256 chiEmissionEpoch6 = 10000 ether;
    chiLocking.updateEpoch(chiEmissionEpoch6, 0);

    correctVotingPowerUser1 =
      ((uint256(1000 ether + 500 ether) * 99) / 208) +
      ((((chiEmissionEpoch3 * 1500) / 7500) * 99) / 208) +
      ((((chiEmissionEpoch4 * 1500) / 7500) * 99) / 208) +
      ((((chiEmissionEpoch5 * 1500) / 7500) * 99) / 208) +
      ((((chiEmissionEpoch6 * 1500) / 3500) * 99) / 208);
    correctVotingPowerUser2 =
      (user2LockAmountEpoch2 / 208) +
      (((chiEmissionEpoch3 * 2000) / 7500) / 208) +
      (((chiEmissionEpoch4 * 2000) / 7500) / 208) +
      (((chiEmissionEpoch5 * 2000) / 7500) / 208) +
      (((chiEmissionEpoch6 * 2000) / 3500) / 208);
    assertApproxEqRel(chiLocking.getVotingPower(user1), correctVotingPowerUser1, TOLERANCE);
    assertApproxEqRel(chiLocking.getVotingPower(user2), correctVotingPowerUser2, TOLERANCE);
    assertApproxEqRel(
      chiLocking.getTotalVotingPower(),
      chiLocking.getVotingPower(user1) + chiLocking.getVotingPower(user2),
      TOLERANCE
    );
  }
}

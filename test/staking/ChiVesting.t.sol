// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {CHI} from "contracts/tokens/CHI.sol";
import {ChiVesting} from "contracts/staking/ChiVesting.sol";

contract ChiVestingTest is Test {
  uint256 public constant TOLERANCE = 0.00001 ether;
  uint256 public constant CHI_INITIAL_SUPPLY = 100000000 ether;

  uint256 public CLIFF_DURATION = 4;
  uint256 public VESTING_DURATION = 4;

  CHI public chi;
  ChiVesting public chiVesting;

  address public vester1;
  address public vester2;
  address public vester3;

  function setUp() public {
    chi = new CHI(CHI_INITIAL_SUPPLY);
    chiVesting = new ChiVesting();
    chiVesting.initialize(IERC20(address(chi)), CLIFF_DURATION, VESTING_DURATION);
    chi.transfer(address(chiVesting), CHI_INITIAL_SUPPLY);

    vester1 = makeAddr("vester1");
    vester2 = makeAddr("vester2");
    vester3 = makeAddr("vester3");
  }

  function test_SetUp() public {
    assertEq(address(chiVesting.chi()), address(chi));
    assertEq(chiVesting.cliffDuration(), CLIFF_DURATION);
    assertEq(chiVesting.vestingDuration(), VESTING_DURATION);
    assertEq(chiVesting.currentEpoch(), 1);
  }

  function testFuzz_setRewardController(address _rewardController) public {
    chiVesting.setRewardController(_rewardController);
    assertEq(chiVesting.rewardController(), _rewardController);
  }

  function testFuzz_SetRewardController_Revert_NotOwner(address _caller, address _rewardController) public {
    vm.assume(_caller != address(this));
    vm.startPrank(_caller);
    vm.expectRevert("Ownable: caller is not the owner");
    chiVesting.setRewardController(_rewardController);
    vm.stopPrank();
  }

  function testFuzz_SetVester(address _vester, bool _toSet) public {
    chiVesting.setChiVester(_vester, _toSet);
    assertEq(chiVesting.chiVesters(_vester), _toSet);
  }

  function testFuzz_SetVester_Revert_NotOwner(address _caller, address _vester, bool _toSet) public {
    vm.assume(_caller != address(this));
    vm.startPrank(_caller);
    vm.expectRevert("Ownable: caller is not the owner");
    chiVesting.setChiVester(_vester, _toSet);
    vm.stopPrank();
  }

  function test_AddVesting() public {
    chiVesting.setChiVester(address(this), true);
    chiVesting.setRewardController(address(this));

    uint256 chiEmissionsEpoch1 = 500 ether;
    uint256 stEthRewardEpoch1 = 500 ether;
    chiVesting.addVesting(vester1, 1000 ether);
    chiVesting.updateEpoch(chiEmissionsEpoch1, stEthRewardEpoch1);

    chiVesting.addVesting(vester2, 1500 ether);
    chiVesting.addVesting(vester3, 3000 ether);
    chiVesting.addVesting(vester1, 12000 ether);

    {
      (uint256 startAmount, uint256 shares, , , uint256 unclaimedStEth, ) = chiVesting.vestingData(vester1);
      assertApproxEqRel(startAmount, 13000 ether, TOLERANCE);
      assertApproxEqRel(shares, 9000 ether, TOLERANCE);
      assertApproxEqRel(unclaimedStEth, stEthRewardEpoch1, TOLERANCE);

      (startAmount, shares, , , unclaimedStEth, ) = chiVesting.vestingData(vester2);
      assertApproxEqRel(startAmount, 1500 ether, TOLERANCE);
      assertApproxEqRel(shares, 1000 ether, TOLERANCE);
      assertApproxEqRel(unclaimedStEth, 0, TOLERANCE);

      (startAmount, shares, , , unclaimedStEth, ) = chiVesting.vestingData(vester3);
      assertApproxEqRel(startAmount, 3000 ether, TOLERANCE);
      assertApproxEqRel(shares, 2000 ether, TOLERANCE);
      assertApproxEqRel(unclaimedStEth, 0, TOLERANCE);

      assertEq(chiVesting.totalLockedChi(), 18000 ether);
      assertEq(chiVesting.totalUnlockedChi(), 0);
      assertEq(chiVesting.totalShares(), 12000 ether);
    }

    uint256 chiEmissionsEpoch2 = 5000 ether;
    uint256 stEthRewardEpoch2 = 5000 ether;
    chiVesting.updateEpoch(chiEmissionsEpoch2, stEthRewardEpoch2);

    uint256 amount = chiVesting.totalLockedChi();
    chiVesting.addVesting(vester3, amount);

    {
      uint256 vester3StEthRewards = (stEthRewardEpoch2 * 2000 ether) / 12000 ether;
      (uint256 startAmount, uint256 shares, , , uint256 unclaimedStEth, ) = chiVesting.vestingData(vester3);
      assertApproxEqRel(startAmount, 26000 ether, TOLERANCE);
      assertApproxEqRel(shares, 14000 ether, TOLERANCE);
      assertApproxEqRel(unclaimedStEth, vester3StEthRewards, TOLERANCE);

      assertEq(chiVesting.totalLockedChi(), 46000 ether);
      assertEq(chiVesting.totalUnlockedChi(), 0);
      assertEq(chiVesting.totalShares(), 24000 ether);
    }
  }

  function test_UnclaimedStETHAmount() public {
    chiVesting.setChiVester(address(this), true);
    chiVesting.setRewardController(address(this));

    uint256 chiEmissionsEpoch1 = 500 ether;
    uint256 stEthRewardEpoch1 = 500 ether;
    chiVesting.addVesting(vester1, 1000 ether);
    chiVesting.updateEpoch(chiEmissionsEpoch1, stEthRewardEpoch1);

    assertEq(chiVesting.unclaimedStETHAmount(vester1), stEthRewardEpoch1);

    uint256 chiEmissionsEpoch2 = 5000 ether;
    uint256 stEthRewardEpoch2 = 5000 ether;
    chiVesting.addVesting(vester2, 1500 ether);
    chiVesting.addVesting(vester3, 3000 ether);
    chiVesting.addVesting(vester1, 12000 ether);
    chiVesting.updateEpoch(chiEmissionsEpoch2, stEthRewardEpoch2);

    uint256 stEthRewardVester1 = stEthRewardEpoch1 + (stEthRewardEpoch2 * 13500 ether) / 18000 ether;
    uint256 stEthRewardVester2 = (stEthRewardEpoch2 * 1500 ether) / 18000 ether;
    uint256 stEthRewardVester3 = (stEthRewardEpoch2 * 3000 ether) / 18000 ether;
    assertApproxEqRel(chiVesting.unclaimedStETHAmount(vester1), stEthRewardVester1, TOLERANCE);
    assertApproxEqRel(chiVesting.unclaimedStETHAmount(vester2), stEthRewardVester2, TOLERANCE);
    assertApproxEqRel(chiVesting.unclaimedStETHAmount(vester3), stEthRewardVester3, TOLERANCE);

    uint256 chiEmissionsEpoch3 = 3000 ether;
    uint256 stEthRewardEpoch3 = 3000 ether;
    uint256 vestingAmount = chiVesting.totalLockedChi();
    chiVesting.addVesting(vester3, vestingAmount);
    chiVesting.updateEpoch(chiEmissionsEpoch3, stEthRewardEpoch3);

    stEthRewardVester1 += (stEthRewardEpoch3 * 9) / 24;
    stEthRewardVester2 += (stEthRewardEpoch3 * 1) / 24;
    stEthRewardVester3 += (stEthRewardEpoch3 * 14) / 24;
    assertApproxEqRel(chiVesting.unclaimedStETHAmount(vester1), stEthRewardVester1, TOLERANCE);
    assertApproxEqRel(chiVesting.unclaimedStETHAmount(vester2), stEthRewardVester2, TOLERANCE);
    assertApproxEqRel(chiVesting.unclaimedStETHAmount(vester3), stEthRewardVester3, TOLERANCE);

    uint256 chiEmissionsEpoch4 = 6000 ether;
    uint256 stEthRewardEpoch4 = 6000 ether;
    chiVesting.updateEpoch(chiEmissionsEpoch4, stEthRewardEpoch4);

    uint256 amount = chiVesting.availableChiWithdraw(vester2);
    vm.startPrank(vester1);
    chiVesting.withdrawChi(amount);
    vm.stopPrank();

    stEthRewardVester1 += (stEthRewardEpoch4 * 9) / 24;
    stEthRewardVester2 += (stEthRewardEpoch4 * 1) / 24;
    stEthRewardVester3 += (stEthRewardEpoch4 * 14) / 24;
    assertApproxEqRel(chiVesting.unclaimedStETHAmount(vester1), stEthRewardVester1, TOLERANCE);
    assertApproxEqRel(chiVesting.unclaimedStETHAmount(vester2), stEthRewardVester2, TOLERANCE);
    assertApproxEqRel(chiVesting.unclaimedStETHAmount(vester3), stEthRewardVester3, TOLERANCE);

    uint256 chiEmissionsEpoch5 = 8000 ether;
    uint256 stEthRewardEpoch5 = 8000 ether;
    chiVesting.updateEpoch(chiEmissionsEpoch5, stEthRewardEpoch5);
    chiVesting.updateEpoch(0, 0);

    amount = chiVesting.availableChiWithdraw(vester1);
    vm.startPrank(vester1);
    chiVesting.withdrawChi(amount);
    vm.stopPrank();

    stEthRewardVester1 += (stEthRewardEpoch5 * 9) / 24;
    stEthRewardVester2 += (stEthRewardEpoch5 * 1) / 24;
    stEthRewardVester3 += (stEthRewardEpoch5 * 14) / 24;
    assertApproxEqRel(chiVesting.unclaimedStETHAmount(vester1), stEthRewardVester1, TOLERANCE);
    assertApproxEqRel(chiVesting.unclaimedStETHAmount(vester2), stEthRewardVester2, TOLERANCE);
    assertApproxEqRel(chiVesting.unclaimedStETHAmount(vester3), stEthRewardVester3, TOLERANCE);
  }

  function test_ClaimStEth() public {
    chiVesting.setChiVester(address(this), true);
    chiVesting.setRewardController(address(this));

    uint256 chiEmissionsEpoch1 = 500 ether;
    uint256 stEthRewardEpoch1 = 500 ether;
    chiVesting.addVesting(vester1, 1000 ether);
    chiVesting.updateEpoch(chiEmissionsEpoch1, stEthRewardEpoch1);

    assertEq(chiVesting.unclaimedStETHAmount(vester1), chiVesting.claimStETH(vester1));
    assertEq(chiVesting.unclaimedStETHAmount(vester1), 0);

    uint256 chiEmissionsEpoch2 = 5000 ether;
    uint256 stEthRewardEpoch2 = 5000 ether;
    chiVesting.addVesting(vester2, 1500 ether);
    chiVesting.addVesting(vester3, 3000 ether);
    chiVesting.addVesting(vester1, 12000 ether);
    chiVesting.updateEpoch(chiEmissionsEpoch2, stEthRewardEpoch2);

    assertEq(chiVesting.unclaimedStETHAmount(vester1), chiVesting.claimStETH(vester1));
    assertEq(chiVesting.unclaimedStETHAmount(vester2), chiVesting.claimStETH(vester2));
    assertEq(chiVesting.unclaimedStETHAmount(vester3), chiVesting.claimStETH(vester3));
    assertEq(chiVesting.unclaimedStETHAmount(vester1), 0);
    assertEq(chiVesting.unclaimedStETHAmount(vester2), 0);
    assertEq(chiVesting.unclaimedStETHAmount(vester3), 0);

    uint256 chiEmissionsEpoch3 = 3000 ether;
    uint256 stEthRewardEpoch3 = 3000 ether;
    uint256 vestingAmount = chiVesting.totalLockedChi();
    chiVesting.addVesting(vester3, vestingAmount);
    chiVesting.updateEpoch(chiEmissionsEpoch3, stEthRewardEpoch3);

    assertEq(chiVesting.unclaimedStETHAmount(vester1), chiVesting.claimStETH(vester1));
    assertEq(chiVesting.unclaimedStETHAmount(vester2), chiVesting.claimStETH(vester2));
    assertEq(chiVesting.unclaimedStETHAmount(vester3), chiVesting.claimStETH(vester3));
    assertEq(chiVesting.unclaimedStETHAmount(vester1), 0);
    assertEq(chiVesting.unclaimedStETHAmount(vester2), 0);
    assertEq(chiVesting.unclaimedStETHAmount(vester3), 0);

    uint256 chiEmissionsEpoch4 = 6000 ether;
    uint256 stEthRewardEpoch4 = 6000 ether;
    chiVesting.updateEpoch(chiEmissionsEpoch4, stEthRewardEpoch4);

    uint256 amount = chiVesting.availableChiWithdraw(vester2);
    vm.startPrank(vester1);
    chiVesting.withdrawChi(amount);
    vm.stopPrank();

    uint256 chiEmissionsEpoch5 = 8000 ether;
    uint256 stEthRewardEpoch5 = 8000 ether;
    chiVesting.updateEpoch(chiEmissionsEpoch5, stEthRewardEpoch5);
    chiVesting.updateEpoch(0, 0);

    amount = chiVesting.availableChiWithdraw(vester1);
    vm.startPrank(vester1);
    chiVesting.withdrawChi(amount);
    vm.stopPrank();

    assertEq(chiVesting.unclaimedStETHAmount(vester1), chiVesting.claimStETH(vester1));
    assertEq(chiVesting.unclaimedStETHAmount(vester2), chiVesting.claimStETH(vester2));
    assertEq(chiVesting.unclaimedStETHAmount(vester3), chiVesting.claimStETH(vester3));
    assertEq(chiVesting.unclaimedStETHAmount(vester1), 0);
    assertEq(chiVesting.unclaimedStETHAmount(vester2), 0);
    assertEq(chiVesting.unclaimedStETHAmount(vester3), 0);
  }

  function test_AvailableChi() public {
    chiVesting.setChiVester(address(this), true);
    chiVesting.setRewardController(address(this));

    uint256 chiEmissionsEpoch1 = 500 ether;
    uint256 stEthRewardEpoch1 = 500 ether;
    chiVesting.addVesting(vester1, 1000 ether);
    chiVesting.updateEpoch(chiEmissionsEpoch1, stEthRewardEpoch1);

    assertEq(chiVesting.availableChiWithdraw(vester1), 0);

    uint256 chiEmissionsEpoch2 = 5000 ether;
    uint256 stEthRewardEpoch2 = 5000 ether;
    chiVesting.addVesting(vester2, 1500 ether);
    chiVesting.addVesting(vester3, 3000 ether);
    chiVesting.addVesting(vester1, 12000 ether);
    chiVesting.updateEpoch(chiEmissionsEpoch2, stEthRewardEpoch2);

    assertEq(chiVesting.availableChiWithdraw(vester1), 0);
    assertEq(chiVesting.availableChiWithdraw(vester2), 0);
    assertEq(chiVesting.availableChiWithdraw(vester3), 0);

    uint256 chiEmissionsEpoch3 = 3000 ether;
    uint256 stEthRewardEpoch3 = 3000 ether;
    uint256 vestingAmount = chiVesting.totalLockedChi();
    chiVesting.addVesting(vester3, vestingAmount);
    chiVesting.updateEpoch(chiEmissionsEpoch3, stEthRewardEpoch3);

    assertEq(chiVesting.availableChiWithdraw(vester1), 0);
    assertEq(chiVesting.availableChiWithdraw(vester2), 0);
    assertEq(chiVesting.availableChiWithdraw(vester3), 0);

    uint256 chiEmissionsEpoch4 = 6000 ether;
    uint256 stEthRewardEpoch4 = 6000 ether;
    chiVesting.updateEpoch(chiEmissionsEpoch4, stEthRewardEpoch4);

    assertEq(chiVesting.availableChiWithdraw(vester1), 0);
    assertEq(chiVesting.availableChiWithdraw(vester2), 0);
    assertEq(chiVesting.availableChiWithdraw(vester3), 0);

    uint256 chiEmissionsEpoch5 = 8000 ether;
    uint256 stEthRewardEpoch5 = 8000 ether;
    chiVesting.updateEpoch(chiEmissionsEpoch5, stEthRewardEpoch5);

    uint256 vester1TotalVested = (1000 ether + chiEmissionsEpoch1 + 12000 ether) +
      ((chiEmissionsEpoch2 * 9) / 12 + ((chiEmissionsEpoch3 + chiEmissionsEpoch4 + chiEmissionsEpoch5) * 9) / 24);
    uint256 vester2TotalVested = (1500 ether + (chiEmissionsEpoch2 * 1) / 12) +
      ((chiEmissionsEpoch3 + chiEmissionsEpoch4 + chiEmissionsEpoch5) * 1) /
      24;
    uint256 vester3TotalVested = (3000 ether + (chiEmissionsEpoch2 * 2) / 12 + vestingAmount) +
      (((chiEmissionsEpoch3 + chiEmissionsEpoch4 + chiEmissionsEpoch5) * 14) / 24);
    assertApproxEqRel(chiVesting.availableChiWithdraw(vester1), vester1TotalVested / 4, TOLERANCE);
    assertApproxEqRel(chiVesting.availableChiWithdraw(vester2), vester2TotalVested / 4, TOLERANCE);
    assertApproxEqRel(chiVesting.availableChiWithdraw(vester3), vester3TotalVested / 4, TOLERANCE);

    chiVesting.updateEpoch(0, 0);
    assertApproxEqRel(chiVesting.availableChiWithdraw(vester1), (vester1TotalVested * 2) / 4, TOLERANCE);
    assertApproxEqRel(chiVesting.availableChiWithdraw(vester2), (vester2TotalVested * 2) / 4, TOLERANCE);
    assertApproxEqRel(chiVesting.availableChiWithdraw(vester3), (vester3TotalVested * 2) / 4, TOLERANCE);

    uint256 amount = chiVesting.availableChiWithdraw(vester1);
    vm.startPrank(vester1);
    chiVesting.withdrawChi(amount);
    vm.stopPrank();
    assertEq(chi.balanceOf(vester1), amount);

    uint256 chiEmissionsEpoch6 = 10000 ether;
    uint256 stEthRewardEpoch6 = 10000 ether;
    chiVesting.updateEpoch(chiEmissionsEpoch6, stEthRewardEpoch6);

    uint256 vester1AvailableChi = vester1TotalVested / 4 + (chiEmissionsEpoch6 * 9) / 24 / 2;
    uint256 vester2AvailableChi = (vester2TotalVested * 3) / 4 + (chiEmissionsEpoch6 * 1) / 24 / 2;
    uint256 vester3AvailableChi = (vester3TotalVested * 3) / 4 + (chiEmissionsEpoch6 * 14) / 24 / 2;
    assertApproxEqRel(chiVesting.availableChiWithdraw(vester1), vester1AvailableChi, TOLERANCE);
    assertApproxEqRel(chiVesting.availableChiWithdraw(vester2), vester2AvailableChi, TOLERANCE);
    assertApproxEqRel(chiVesting.availableChiWithdraw(vester3), vester3AvailableChi, TOLERANCE);

    chiVesting.updateEpoch(0, 0);

    vester1AvailableChi = (vester1TotalVested * 2) / 4 + (chiEmissionsEpoch6 * 9) / 24;
    vester2AvailableChi = vester2TotalVested + (chiEmissionsEpoch6 * 1) / 24;
    vester3AvailableChi = vester3TotalVested + (chiEmissionsEpoch6 * 14) / 24;
    assertApproxEqRel(chiVesting.availableChiWithdraw(vester1), vester1AvailableChi, TOLERANCE);
    assertApproxEqRel(chiVesting.availableChiWithdraw(vester2), vester2AvailableChi, TOLERANCE);
    assertApproxEqRel(chiVesting.availableChiWithdraw(vester3), vester3AvailableChi, TOLERANCE);
  }

  function test_WithdrawChi() public {
    chiVesting.setChiVester(address(this), true);
    chiVesting.setRewardController(address(this));

    uint256 chiEmissionsEpoch1 = 500 ether;
    uint256 stEthRewardEpoch1 = 500 ether;
    chiVesting.addVesting(vester1, 1000 ether);
    chiVesting.updateEpoch(chiEmissionsEpoch1, stEthRewardEpoch1);

    uint256 amount = chiVesting.availableChiWithdraw(vester1) / 2;
    vm.startPrank(vester1);
    chiVesting.withdrawChi(amount);
    vm.stopPrank();

    assertEq(chi.balanceOf(vester1), amount);
    assertEq(chiVesting.availableChiWithdraw(vester1), amount / 2);

    uint256 chiEmissionsEpoch2 = 5000 ether;
    uint256 stEthRewardEpoch2 = 5000 ether;
    chiVesting.addVesting(vester2, 1500 ether);
    chiVesting.addVesting(vester3, 3000 ether);
    chiVesting.addVesting(vester1, 12000 ether);
    chiVesting.updateEpoch(chiEmissionsEpoch2, stEthRewardEpoch2);

    uint256 chiEmissionsEpoch3 = 3000 ether;
    uint256 stEthRewardEpoch3 = 3000 ether;
    uint256 vestingAmount = chiVesting.totalLockedChi();
    chiVesting.addVesting(vester3, vestingAmount);
    chiVesting.updateEpoch(chiEmissionsEpoch3, stEthRewardEpoch3);

    uint256 chiEmissionsEpoch4 = 6000 ether;
    uint256 stEthRewardEpoch4 = 6000 ether;
    chiVesting.updateEpoch(chiEmissionsEpoch4, stEthRewardEpoch4);

    amount = chiVesting.availableChiWithdraw(vester2);
    vm.startPrank(vester2);
    chiVesting.withdrawChi(amount);
    vm.stopPrank();
    assertEq(chi.balanceOf(vester2), amount);
    assertEq(chiVesting.availableChiWithdraw(vester2), 0);

    uint256 chiEmissionsEpoch5 = 8000 ether;
    uint256 stEthRewardEpoch5 = 8000 ether;
    chiVesting.updateEpoch(chiEmissionsEpoch5, stEthRewardEpoch5);
    chiVesting.updateEpoch(0, 0);

    amount = chiVesting.availableChiWithdraw(vester1);
    vm.startPrank(vester1);
    chiVesting.withdrawChi(amount);
    vm.stopPrank();

    assertEq(chi.balanceOf(vester1), amount);
    assertEq(chiVesting.availableChiWithdraw(vester1), 0);

    uint256 chiEmissionsEpoch6 = 10000 ether;
    chiVesting.updateEpoch(chiEmissionsEpoch6, 0);
    chiVesting.updateEpoch(0, 0);

    amount = chiVesting.availableChiWithdraw(vester1);
    vm.startPrank(vester1);
    chiVesting.withdrawChi(amount);
    vm.stopPrank();
    assertEq(chiVesting.availableChiWithdraw(vester1), 0);

    amount = chiVesting.availableChiWithdraw(vester3);
    vm.startPrank(vester3);
    chiVesting.withdrawChi(amount);
    vm.stopPrank();
    assertEq(chi.balanceOf(vester3), amount);
    assertEq(chiVesting.availableChiWithdraw(vester3), 0);
  }

  function test_UpdateEpoch() public {
    chiVesting.setChiVester(address(this), true);
    chiVesting.setRewardController(address(this));

    uint256 chiEmissionsEpoch1 = 500 ether;
    uint256 stEthRewardEpoch1 = 500 ether;
    chiVesting.addVesting(vester1, 1000 ether);
    chiVesting.updateEpoch(chiEmissionsEpoch1, stEthRewardEpoch1);

    uint256 cumulativeRewards = (stEthRewardEpoch1 * 1 ether) / 1000 ether;
    assertEq(chiVesting.currentEpoch(), 2);
    assertEq(chiVesting.totalLockedChi(), 1000 ether + chiEmissionsEpoch1);
    {
      (uint256 cumulativeStEthRewardPerShare, ) = chiVesting.epochs(1);
      assertEq(cumulativeStEthRewardPerShare, cumulativeRewards);
    }
    uint256 chiEmissionsEpoch2 = 5000 ether;
    uint256 stEthRewardEpoch2 = 5000 ether;
    chiVesting.addVesting(vester2, 1500 ether);
    chiVesting.addVesting(vester3, 3000 ether);
    chiVesting.addVesting(vester1, 12000 ether);
    chiVesting.updateEpoch(chiEmissionsEpoch2, stEthRewardEpoch2);

    cumulativeRewards += (stEthRewardEpoch2 * 1 ether) / 12000 ether;
    assertEq(chiVesting.currentEpoch(), 3);
    assertEq(chiVesting.totalLockedChi(), 23000 ether);
    {
      (uint256 cumulativeStEthRewardPerShare, ) = chiVesting.epochs(2);
      assertEq(cumulativeStEthRewardPerShare, cumulativeRewards);
    }

    uint256 chiEmissionsEpoch3 = 3000 ether;
    uint256 stEthRewardEpoch3 = 3000 ether;
    uint256 vestingAmount = chiVesting.totalLockedChi();
    chiVesting.addVesting(vester3, vestingAmount);
    chiVesting.updateEpoch(chiEmissionsEpoch3, stEthRewardEpoch3);

    cumulativeRewards += (stEthRewardEpoch3 * 1 ether) / 24000 ether;
    assertEq(chiVesting.currentEpoch(), 4);
    assertEq(chiVesting.totalLockedChi(), 49000 ether);
    {
      (uint256 cumulativeStEthRewardPerShare, ) = chiVesting.epochs(3);
      assertEq(cumulativeStEthRewardPerShare, cumulativeRewards);
    }

    uint256 chiIncentivesEpoch4 = 6000 ether;
    uint256 stEthRewardEpoch4 = 6000 ether;
    chiVesting.updateEpoch(chiIncentivesEpoch4, stEthRewardEpoch4);

    cumulativeRewards += (stEthRewardEpoch4 * 1 ether) / 24000 ether;
    assertEq(chiVesting.currentEpoch(), 5);
    assertEq(chiVesting.totalLockedChi(), 55000 ether);
    {
      (uint256 cumulativeStEthRewardPerShare, ) = chiVesting.epochs(4);
      assertEq(cumulativeStEthRewardPerShare, cumulativeRewards);
    }

    uint256 chiEmissionsEpoch5 = 8000 ether;
    uint256 stEthRewardEpoch5 = 8000 ether;
    chiVesting.updateEpoch(chiEmissionsEpoch5, stEthRewardEpoch5);

    uint256 amountToUnlock = 63000 ether / 4;
    cumulativeRewards += ((stEthRewardEpoch5 * 1 ether) / 24000 ether);
    assertEq(chiVesting.currentEpoch(), 6);
    assertEq(chiVesting.totalLockedChi(), 63000 ether - amountToUnlock);
    {
      (uint256 cumulativeStEthRewardPerShare, ) = chiVesting.epochs(5);
      assertEq(cumulativeStEthRewardPerShare, cumulativeRewards);
    }
  }

  function test_GetVotingPower() public {
    chiVesting.setChiVester(address(this), true);
    chiVesting.setRewardController(address(this));

    uint256 vestingAmountEpoch1Vester1 = 1000 ether;
    uint256 chiEmissionsEpoch1 = 500 ether;
    chiVesting.addVesting(vester1, vestingAmountEpoch1Vester1);

    assertApproxEqRel(chiVesting.getVotingPower(vester1), (vestingAmountEpoch1Vester1 * 8) / 208, TOLERANCE);
    assertEq(chiVesting.totalVotingPower(), chiVesting.getVotingPower(vester1));

    chiVesting.updateEpoch(chiEmissionsEpoch1, 0);

    uint256 correctVotingPowerVester1 = (vestingAmountEpoch1Vester1 * 7) / 208 + (chiEmissionsEpoch1 * 7) / 208;
    assertApproxEqRel(chiVesting.getVotingPower(vester1), correctVotingPowerVester1, TOLERANCE);
    assertEq(chiVesting.totalVotingPower(), chiVesting.getVotingPower(vester1));

    uint256 vestingAmountEpoch2Vester1 = 12000 ether;
    uint256 vestingAmountEpoch2Vester2 = 1500 ether;
    uint256 vestingAmountEpoch2Vester3 = 3000 ether;
    uint256 chiEmissionsEpoch2 = 5000 ether;
    chiVesting.addVesting(vester2, vestingAmountEpoch2Vester2);
    chiVesting.addVesting(vester3, vestingAmountEpoch2Vester3);
    chiVesting.addVesting(vester1, vestingAmountEpoch2Vester1);
    chiVesting.updateEpoch(chiEmissionsEpoch2, 0);

    correctVotingPowerVester1 =
      (((vestingAmountEpoch1Vester1 + vestingAmountEpoch2Vester1 + chiEmissionsEpoch1) * 6) / 208) +
      ((((chiEmissionsEpoch2 * (vestingAmountEpoch1Vester1 + chiEmissionsEpoch1 + vestingAmountEpoch2Vester1)) /
        18000 ether) * 6) / 208);
    uint256 correctVotingPowerVester2 = ((vestingAmountEpoch2Vester2 * 6) / 208) +
      ((((chiEmissionsEpoch2 * vestingAmountEpoch2Vester2) / 18000 ether) * 6) / 208);
    uint256 correctVotingPowerVester3 = ((vestingAmountEpoch2Vester3 * 6) / 208) +
      ((((chiEmissionsEpoch2 * vestingAmountEpoch2Vester3) / 18000 ether) * 6) / 208);

    assertApproxEqRel(chiVesting.getVotingPower(vester1), correctVotingPowerVester1, TOLERANCE);
    assertApproxEqRel(chiVesting.getVotingPower(vester2), correctVotingPowerVester2, TOLERANCE);
    assertApproxEqRel(chiVesting.getVotingPower(vester3), correctVotingPowerVester3, TOLERANCE);
    assertApproxEqRel(
      chiVesting.totalVotingPower(),
      chiVesting.getVotingPower(vester1) + chiVesting.getVotingPower(vester2) + chiVesting.getVotingPower(vester3),
      TOLERANCE
    );

    uint256 chiEmissionsEpoch3 = 3000 ether;
    uint256 vestingAmount = chiVesting.totalLockedChi();
    chiVesting.addVesting(vester3, vestingAmount);

    assertApproxEqRel(
      chiVesting.totalVotingPower(),
      chiVesting.getVotingPower(vester1) + chiVesting.getVotingPower(vester2) + chiVesting.getVotingPower(vester3),
      TOLERANCE
    );

    chiVesting.updateEpoch(chiEmissionsEpoch3, 0);

    correctVotingPowerVester1 -= correctVotingPowerVester1 / 6;
    correctVotingPowerVester1 += (((chiEmissionsEpoch3 * 9) / 24) * 5) / 208;
    assertApproxEqRel(chiVesting.getVotingPower(vester1), correctVotingPowerVester1, TOLERANCE);

    correctVotingPowerVester2 -= correctVotingPowerVester2 / 6;
    correctVotingPowerVester2 += (((chiEmissionsEpoch3 * 1) / 24) * 5) / 208;
    assertApproxEqRel(chiVesting.getVotingPower(vester2), correctVotingPowerVester2, TOLERANCE);

    correctVotingPowerVester3 -= correctVotingPowerVester3 / 6;
    correctVotingPowerVester3 += ((vestingAmount + (chiEmissionsEpoch3 * 14) / 24) * 5) / 208;
    assertApproxEqRel(chiVesting.getVotingPower(vester3), correctVotingPowerVester3, TOLERANCE);

    assertApproxEqRel(
      chiVesting.totalVotingPower(),
      chiVesting.getVotingPower(vester1) + chiVesting.getVotingPower(vester2) + chiVesting.getVotingPower(vester3),
      TOLERANCE
    );

    chiVesting.updateEpoch(0, 0);
    correctVotingPowerVester1 -= correctVotingPowerVester1 / 5;
    correctVotingPowerVester2 -= correctVotingPowerVester2 / 5;
    correctVotingPowerVester3 -= correctVotingPowerVester3 / 5;
    assertApproxEqRel(chiVesting.getVotingPower(vester1), correctVotingPowerVester1, TOLERANCE);
    assertApproxEqRel(chiVesting.getVotingPower(vester2), correctVotingPowerVester2, TOLERANCE);
    assertApproxEqRel(chiVesting.getVotingPower(vester3), correctVotingPowerVester3, TOLERANCE);
    assertApproxEqRel(
      chiVesting.totalVotingPower(),
      chiVesting.getVotingPower(vester1) + chiVesting.getVotingPower(vester2) + chiVesting.getVotingPower(vester3),
      TOLERANCE
    );

    uint256 chiEmissionsEpoch5 = 8000 ether;
    chiVesting.updateEpoch(chiEmissionsEpoch5, 0);

    correctVotingPowerVester1 -= (correctVotingPowerVester1 / 4);
    correctVotingPowerVester1 += (((chiEmissionsEpoch5 * 9) / 24) * 3) / 208;
    correctVotingPowerVester1 = (correctVotingPowerVester1 * 3) / 4;
    assertApproxEqRel(chiVesting.getVotingPower(vester1), correctVotingPowerVester1, TOLERANCE);

    correctVotingPowerVester2 -= (correctVotingPowerVester2 / 4);
    correctVotingPowerVester2 += (((chiEmissionsEpoch5 * 1) / 24) * 3) / 208;
    correctVotingPowerVester2 = (correctVotingPowerVester2 * 3) / 4;
    assertApproxEqRel(chiVesting.getVotingPower(vester2), correctVotingPowerVester2, TOLERANCE);

    correctVotingPowerVester3 -= (correctVotingPowerVester3 / 4);
    correctVotingPowerVester3 += (((chiEmissionsEpoch5 * 14) / 24) * 3) / 208;
    correctVotingPowerVester3 = (correctVotingPowerVester3 * 3) / 4;
    assertApproxEqRel(chiVesting.getVotingPower(vester3), correctVotingPowerVester3, TOLERANCE);

    assertApproxEqRel(
      chiVesting.totalVotingPower(),
      chiVesting.getVotingPower(vester1) + chiVesting.getVotingPower(vester2) + chiVesting.getVotingPower(vester3),
      TOLERANCE
    );

    chiVesting.updateEpoch(0, 0);

    correctVotingPowerVester1 -= (correctVotingPowerVester1 / 3);
    correctVotingPowerVester1 = (correctVotingPowerVester1 * 2) / 3;
    assertApproxEqRel(chiVesting.getVotingPower(vester1), correctVotingPowerVester1, TOLERANCE);

    correctVotingPowerVester2 -= (correctVotingPowerVester2 / 3);
    correctVotingPowerVester2 = (correctVotingPowerVester2 * 2) / 3;
    assertApproxEqRel(chiVesting.getVotingPower(vester2), correctVotingPowerVester2, TOLERANCE);

    correctVotingPowerVester3 -= (correctVotingPowerVester3 / 3);
    correctVotingPowerVester3 = (correctVotingPowerVester3 * 2) / 3;
    assertApproxEqRel(chiVesting.getVotingPower(vester3), correctVotingPowerVester3, TOLERANCE);

    assertApproxEqRel(
      chiVesting.totalVotingPower(),
      chiVesting.getVotingPower(vester1) + chiVesting.getVotingPower(vester2) + chiVesting.getVotingPower(vester3),
      TOLERANCE
    );

    chiVesting.updateEpoch(0, 0);

    correctVotingPowerVester1 -= (correctVotingPowerVester1 / 2);
    correctVotingPowerVester1 = (correctVotingPowerVester1 * 1) / 2;
    assertApproxEqRel(chiVesting.getVotingPower(vester1), correctVotingPowerVester1, TOLERANCE);

    correctVotingPowerVester2 -= (correctVotingPowerVester2 / 2);
    correctVotingPowerVester2 = (correctVotingPowerVester2 * 1) / 2;
    assertApproxEqRel(chiVesting.getVotingPower(vester2), correctVotingPowerVester2, TOLERANCE);

    correctVotingPowerVester3 -= (correctVotingPowerVester3 / 2);
    correctVotingPowerVester3 = (correctVotingPowerVester3 * 1) / 2;
    assertApproxEqRel(chiVesting.getVotingPower(vester3), correctVotingPowerVester3, TOLERANCE);

    assertApproxEqRel(
      chiVesting.totalVotingPower(),
      chiVesting.getVotingPower(vester1) + chiVesting.getVotingPower(vester2) + chiVesting.getVotingPower(vester3),
      TOLERANCE
    );

    chiVesting.updateEpoch(0, 0);

    assertEq(chiVesting.getVotingPower(vester1), 0);
    assertEq(chiVesting.getVotingPower(vester2), 0);
    assertEq(chiVesting.getVotingPower(vester3), 0);
    assertEq(chiVesting.totalVotingPower(), 0);
  }
}

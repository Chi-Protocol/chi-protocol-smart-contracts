// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IStakingWithEpochs} from "contracts/interfaces/IStakingWithEpochs.sol";
import {IUSCStaking} from "contracts/interfaces/IUSCStaking.sol";
import {IChiLocking} from "contracts/interfaces/IChiLocking.sol";
import {IArbitrage} from "contracts/interfaces/IArbitrage.sol";
import {USC} from "contracts/tokens/USC.sol";
import {CHI} from "contracts/tokens/CHI.sol";
import {USCStaking} from "contracts/staking/USCStaking.sol";
import {Staker} from "./helpers/Staker.sol";

contract USCStakingTest is Test {
  uint256 public constant USC_INITIAL_SUPPLY = 100000000 ether;
  uint256 public constant CHI_INITIAL_SUPPLY = 100000000 ether;

  USC public usc;
  CHI public chi;
  USCStaking public uscStaking;
  address public chiLockingAddress;

  Staker public staker1;
  Staker public staker2;
  Staker public staker3;

  function setUp() public {
    usc = new USC();
    usc.updateMinter(address(this), true);
    usc.mint(address(this), USC_INITIAL_SUPPLY);
    chi = new CHI(CHI_INITIAL_SUPPLY);

    chiLockingAddress = makeAddr("chiLockingAddress");

    uscStaking = new USCStaking();
    uscStaking.initialize(IERC20(address(usc)), IERC20(address(chi)), IChiLocking(chiLockingAddress));
    usc.mint(address(uscStaking), 10000 ether);

    staker1 = new Staker(IERC20(address(usc)), IERC20(address(0x0)), address(uscStaking), address(0x0));
    staker2 = new Staker(IERC20(address(usc)), IERC20(address(0x0)), address(uscStaking), address(0x0));
    staker3 = new Staker(IERC20(address(usc)), IERC20(address(0x0)), address(uscStaking), address(0x0));
    usc.transfer(address(staker1), 1000 ether);
    usc.transfer(address(staker2), 1000 ether);
    usc.transfer(address(staker3), 1000 ether);
  }

  function test_SetUp() public {
    assertEq(uscStaking.owner(), address(this));
    assertEq(uscStaking.currentEpoch(), 1);
    assertEq(address(uscStaking.stakeToken()), address(usc));
    assertEq(address(uscStaking.chi()), address(chi));
    assertEq(address(uscStaking.chiLockingContract()), chiLockingAddress);
  }

  function testFuzz_SetRewardController(address rewardController) public {
    uscStaking.setRewardController(rewardController);
    assertEq(uscStaking.rewardController(), rewardController);
  }

  function testFuzz_SetRewardController_Revert_NotOwner(address caller, address rewardController) public {
    vm.assume(caller != address(this));
    vm.startPrank(caller);
    vm.expectRevert("Ownable: caller is not the owner");
    uscStaking.setRewardController(rewardController);
    vm.stopPrank();
  }

  function test_Stake_OnlyOneStaker_OnlyOneEpoch() public {
    uint256 uscBalanceBefore = usc.balanceOf(address(staker1));
    uint256 uscStakingBalanceBefore = usc.balanceOf(address(uscStaking));
    uint256 stakeAmount = 100 ether;
    staker1.stake(stakeAmount);

    (uint256 lastUpdatedEpoch, uint256 shares, uint256 addSharesNextEpoch) = uscStaking.stakes(address(staker1));
    assertEq(lastUpdatedEpoch, uscStaking.currentEpoch());
    assertEq(shares, 0);
    assertEq(addSharesNextEpoch, stakeAmount);
    assertEq(uscStaking.getUnclaimedRewards(address(staker1), IStakingWithEpochs.RewardToken.USC), 0);
    assertEq(uscStaking.getUnclaimedRewards(address(staker1), IStakingWithEpochs.RewardToken.CHI), 0);
    assertEq(uscStaking.getUnclaimedRewards(address(staker1), IStakingWithEpochs.RewardToken.STETH), 0);
    assertEq(uscStaking.epochs(uscStaking.currentEpoch()), 0);
    assertEq(uscStaking.epochs(uscStaking.currentEpoch() + 1), stakeAmount);
    assertEq(usc.balanceOf(address(staker1)), uscBalanceBefore - stakeAmount);
    assertEq(usc.balanceOf(address(uscStaking)), uscStakingBalanceBefore + stakeAmount);

    stakeAmount = 200 ether;
    staker1.stake(stakeAmount);
    (lastUpdatedEpoch, shares, addSharesNextEpoch) = uscStaking.stakes(address(staker1));
    assertEq(lastUpdatedEpoch, uscStaking.currentEpoch());
    assertEq(shares, 0);
    assertEq(addSharesNextEpoch, 300 ether);
    assertEq(uscStaking.getUnclaimedRewards(address(staker1), IStakingWithEpochs.RewardToken.USC), 0);
    assertEq(uscStaking.getUnclaimedRewards(address(staker1), IStakingWithEpochs.RewardToken.CHI), 0);
    assertEq(uscStaking.getUnclaimedRewards(address(staker1), IStakingWithEpochs.RewardToken.STETH), 0);
    assertEq(uscStaking.epochs(uscStaking.currentEpoch()), 0);
    assertEq(uscStaking.epochs(uscStaking.currentEpoch() + 1), 300 ether);
    assertEq(usc.balanceOf(address(staker1)), uscBalanceBefore - 300 ether);
    assertEq(usc.balanceOf(address(uscStaking)), uscStakingBalanceBefore + 300 ether);
  }

  function test_Stake_OnlyOneStaker_MultipleEpochs_WithoutRewards() public {
    uint256 uscBalanceBefore = usc.balanceOf(address(staker1));
    uint256 uscStakingBalanceBefore = usc.balanceOf(address(uscStaking));
    staker1.stake(100 ether);

    uscStaking.setRewardController(address(this));
    uint256 numberOfEpochs = 3;
    for (uint256 i = 0; i < numberOfEpochs; i++) {
      uscStaking.updateEpoch(0, 0, 0);
    }

    staker1.stake(200 ether);

    (uint256 lastUpdatedEpoch, uint256 shares, uint256 addSharesNextEpoch) = uscStaking.stakes(address(staker1));
    assertEq(lastUpdatedEpoch, uscStaking.currentEpoch());
    assertEq(shares, 100 ether);
    assertEq(addSharesNextEpoch, 200 ether);
    assertEq(uscStaking.getUnclaimedRewards(address(staker1), IStakingWithEpochs.RewardToken.USC), 0);
    assertEq(uscStaking.getUnclaimedRewards(address(staker1), IStakingWithEpochs.RewardToken.CHI), 0);
    assertEq(uscStaking.getUnclaimedRewards(address(staker1), IStakingWithEpochs.RewardToken.STETH), 0);
    assertEq(uscStaking.epochs(uscStaking.currentEpoch()), 100 ether);
    assertEq(uscStaking.epochs(uscStaking.currentEpoch() + 1), 200 ether);
    assertEq(usc.balanceOf(address(staker1)), uscBalanceBefore - 300 ether);
    assertEq(usc.balanceOf(address(uscStaking)), uscStakingBalanceBefore + 300 ether);
  }

  function test_Stake_MultipleStakers_MultipleEpochs() public {
    uint256 staker1BalanceBefore = usc.balanceOf(address(staker1));
    staker1.stake(100 ether);

    uscStaking.setRewardController(address(this));
    uscStaking.updateEpoch(0, 0, 0);

    uint256 staker2BalanceBefore = usc.balanceOf(address(staker2));
    staker2.stake(200 ether);
    uscStaking.updateEpoch(0, 0, 0);

    (uint256 lastUpdatedEpoch, uint256 shares, uint256 addSharesNextEpoch) = uscStaking.stakes(address(staker1));
    assertEq(lastUpdatedEpoch, 1);
    assertEq(shares, 0);
    assertEq(addSharesNextEpoch, 100 ether);
    assertEq(uscStaking.getUnclaimedRewards(address(staker1), IStakingWithEpochs.RewardToken.USC), 0);
    assertEq(uscStaking.getUnclaimedRewards(address(staker1), IStakingWithEpochs.RewardToken.CHI), 0);
    assertEq(uscStaking.getUnclaimedRewards(address(staker1), IStakingWithEpochs.RewardToken.STETH), 0);
    assertEq(usc.balanceOf(address(staker1)), staker1BalanceBefore - 100 ether);

    uint256 staker3BalanceBefore = usc.balanceOf(address(staker3));
    staker3.stake(300 ether);
    uscStaking.updateEpoch(0, 0, 0);

    (lastUpdatedEpoch, shares, addSharesNextEpoch) = uscStaking.stakes(address(staker2));
    assertEq(lastUpdatedEpoch, 2);
    assertEq(shares, 0);
    assertEq(addSharesNextEpoch, 200 ether);
    assertEq(uscStaking.getUnclaimedRewards(address(staker2), IStakingWithEpochs.RewardToken.USC), 0);
    assertEq(uscStaking.getUnclaimedRewards(address(staker2), IStakingWithEpochs.RewardToken.CHI), 0);
    assertEq(uscStaking.getUnclaimedRewards(address(staker2), IStakingWithEpochs.RewardToken.STETH), 0);
    assertEq(usc.balanceOf(address(staker2)), staker2BalanceBefore - 200 ether);

    uscStaking.updateEpoch(0, 0, 0);
    (lastUpdatedEpoch, shares, addSharesNextEpoch) = uscStaking.stakes(address(staker3));
    assertEq(lastUpdatedEpoch, 3);
    assertEq(shares, 0);
    assertEq(addSharesNextEpoch, 300 ether);
    assertEq(uscStaking.getUnclaimedRewards(address(staker3), IStakingWithEpochs.RewardToken.USC), 0);
    assertEq(uscStaking.getUnclaimedRewards(address(staker3), IStakingWithEpochs.RewardToken.CHI), 0);
    assertEq(uscStaking.getUnclaimedRewards(address(staker3), IStakingWithEpochs.RewardToken.STETH), 0);
    assertEq(usc.balanceOf(address(staker3)), staker3BalanceBefore - 300 ether);
  }

  function test_Stake_MultipleStakers_MultipleEpochs_WithRewards() public {
    staker1.stake(100 ether);

    uscStaking.setRewardController(address(this));
    uscStaking.updateEpoch(0, 0, 0);

    staker2.stake(200 ether);
    uscStaking.updateEpoch(100 ether, 200 ether, 400 ether);

    staker3.stake(500 ether);
    uscStaking.updateEpoch(150 ether, 600 ether, 75 ether);

    uscStaking.updateEpoch(400 ether, 800 ether, 1600 ether);
    staker1.stake(200 ether);

    (uint256 lastUpdatedEpoch, uint256 shares, uint256 addSharesNextEpoch) = uscStaking.stakes(address(staker1));
    assertEq(lastUpdatedEpoch, 5);
    assertEq(shares, 100 ether);
    assertEq(addSharesNextEpoch, 200 ether);
    assertEq(uscStaking.getUnclaimedRewards(address(staker1), IStakingWithEpochs.RewardToken.CHI), 200 ether);
    assertEq(uscStaking.getUnclaimedRewards(address(staker1), IStakingWithEpochs.RewardToken.USC), 500 ether);
    assertEq(uscStaking.getUnclaimedRewards(address(staker1), IStakingWithEpochs.RewardToken.STETH), 625 ether);

    staker2.stake(300 ether);
    (lastUpdatedEpoch, shares, addSharesNextEpoch) = uscStaking.stakes(address(staker2));
    assertEq(lastUpdatedEpoch, 5);
    assertEq(shares, 200 ether);
    assertEq(addSharesNextEpoch, 300 ether);
    assertEq(uscStaking.getUnclaimedRewards(address(staker2), IStakingWithEpochs.RewardToken.CHI), 200 ether);
    assertEq(uscStaking.getUnclaimedRewards(address(staker2), IStakingWithEpochs.RewardToken.USC), 600 ether);
    assertEq(uscStaking.getUnclaimedRewards(address(staker2), IStakingWithEpochs.RewardToken.STETH), 450 ether);

    staker3.stake(400 ether);
    (lastUpdatedEpoch, shares, addSharesNextEpoch) = uscStaking.stakes(address(staker3));
    assertEq(lastUpdatedEpoch, 5);
    assertEq(shares, 500 ether);
    assertEq(addSharesNextEpoch, 400 ether);
    assertEq(uscStaking.getUnclaimedRewards(address(staker3), IStakingWithEpochs.RewardToken.CHI), 250 ether);
    assertEq(uscStaking.getUnclaimedRewards(address(staker3), IStakingWithEpochs.RewardToken.USC), 500 ether);
    assertEq(uscStaking.getUnclaimedRewards(address(staker3), IStakingWithEpochs.RewardToken.STETH), 1000 ether);

    uscStaking.updateEpoch(0, 0, 0);
    uscStaking.updateEpoch(1700 ether, 1700 ether, 1700 ether);
    staker1.stake(100 ether);
    assertEq(uscStaking.getUnclaimedRewards(address(staker1), IStakingWithEpochs.RewardToken.CHI), 500 ether);
    assertEq(uscStaking.getUnclaimedRewards(address(staker1), IStakingWithEpochs.RewardToken.USC), 800 ether);
    assertEq(uscStaking.getUnclaimedRewards(address(staker1), IStakingWithEpochs.RewardToken.STETH), 925 ether);

    staker2.stake(200 ether);
    assertEq(uscStaking.getUnclaimedRewards(address(staker2), IStakingWithEpochs.RewardToken.CHI), 700 ether);
    assertEq(uscStaking.getUnclaimedRewards(address(staker2), IStakingWithEpochs.RewardToken.USC), 1100 ether);
    assertEq(uscStaking.getUnclaimedRewards(address(staker2), IStakingWithEpochs.RewardToken.STETH), 950 ether);

    staker3.stake(50 ether);
    assertEq(uscStaking.getUnclaimedRewards(address(staker3), IStakingWithEpochs.RewardToken.CHI), 1150 ether);
    assertEq(uscStaking.getUnclaimedRewards(address(staker3), IStakingWithEpochs.RewardToken.USC), 1400 ether);
    assertEq(uscStaking.getUnclaimedRewards(address(staker3), IStakingWithEpochs.RewardToken.STETH), 1900 ether);
  }

  function test_Stake_Revert_ZeroAmount() public {
    vm.expectRevert(IStakingWithEpochs.ZeroAmount.selector);
    uscStaking.stake(0);
  }

  function test_UpdateEpoch_WithoutStakersWithoutRewards() public {
    uscStaking.setRewardController(address(this));
    uscStaking.updateEpoch(0, 0, 0);

    assertEq(uscStaking.currentEpoch(), 2);
    assertEq(uscStaking.epochs(1), 0);
    assertEq(uscStaking.epochs(2), 0);
    assertEq(uscStaking.chiAmountFromEmissions(), 0);
    assertEq(uscStaking.getCumulativeRewardsPerShare(1, IStakingWithEpochs.RewardToken.USC), 0);
    assertEq(uscStaking.getCumulativeRewardsPerShare(2, IStakingWithEpochs.RewardToken.USC), 0);
    assertEq(uscStaking.getCumulativeRewardsPerShare(1, IStakingWithEpochs.RewardToken.CHI), 0);
    assertEq(uscStaking.getCumulativeRewardsPerShare(2, IStakingWithEpochs.RewardToken.CHI), 0);
    assertEq(uscStaking.getCumulativeRewardsPerShare(1, IStakingWithEpochs.RewardToken.STETH), 0);
    assertEq(uscStaking.getCumulativeRewardsPerShare(2, IStakingWithEpochs.RewardToken.STETH), 0);
  }

  function test_UpdateEpoch_WithStakersWithoutRewards() public {
    staker1.stake(100 ether);
    uscStaking.setRewardController(address(this));
    uscStaking.updateEpoch(0, 0, 0);

    assertEq(uscStaking.currentEpoch(), 2);
    assertEq(uscStaking.epochs(1), 0);
    assertEq(uscStaking.epochs(2), 100 ether);
    assertEq(uscStaking.chiAmountFromEmissions(), 0);
    assertEq(uscStaking.getCumulativeRewardsPerShare(1, IStakingWithEpochs.RewardToken.USC), 0);
    assertEq(uscStaking.getCumulativeRewardsPerShare(1, IStakingWithEpochs.RewardToken.CHI), 0);
    assertEq(uscStaking.getCumulativeRewardsPerShare(1, IStakingWithEpochs.RewardToken.STETH), 0);

    staker2.stake(200 ether);
    uscStaking.updateEpoch(0, 0, 0);
    assertEq(uscStaking.currentEpoch(), 3);
    assertEq(uscStaking.epochs(2), 100 ether);
    assertEq(uscStaking.epochs(3), 300 ether);
    assertEq(uscStaking.chiAmountFromEmissions(), 0);
    assertEq(uscStaking.getCumulativeRewardsPerShare(2, IStakingWithEpochs.RewardToken.USC), 0);
    assertEq(uscStaking.getCumulativeRewardsPerShare(2, IStakingWithEpochs.RewardToken.CHI), 0);
    assertEq(uscStaking.getCumulativeRewardsPerShare(2, IStakingWithEpochs.RewardToken.STETH), 0);

    uscStaking.updateEpoch(0, 0, 0);
    assertEq(uscStaking.currentEpoch(), 4);
    assertEq(uscStaking.epochs(3), 300 ether);
    assertEq(uscStaking.epochs(4), 300 ether);
    assertEq(uscStaking.chiAmountFromEmissions(), 0);
    assertEq(uscStaking.getCumulativeRewardsPerShare(3, IStakingWithEpochs.RewardToken.USC), 0);
    assertEq(uscStaking.getCumulativeRewardsPerShare(3, IStakingWithEpochs.RewardToken.CHI), 0);
    assertEq(uscStaking.getCumulativeRewardsPerShare(3, IStakingWithEpochs.RewardToken.STETH), 0);
  }

  function test_UpdateEpoch_WithStakersWithRewards() public {
    staker1.stake(100 ether);

    uscStaking.setRewardController(address(this));
    uscStaking.updateEpoch(0, 0, 0);

    staker2.stake(200 ether);
    uscStaking.updateEpoch(100 ether, 200 ether, 400 ether);

    assertEq(uscStaking.currentEpoch(), 3);
    assertEq(uscStaking.epochs(2), 100 ether);
    assertEq(uscStaking.chiAmountFromEmissions(), 100 ether);
    assertEq(uscStaking.getCumulativeRewardsPerShare(2, IStakingWithEpochs.RewardToken.CHI), 1 ether);
    assertEq(uscStaking.getCumulativeRewardsPerShare(2, IStakingWithEpochs.RewardToken.USC), 2 ether);
    assertEq(uscStaking.getCumulativeRewardsPerShare(2, IStakingWithEpochs.RewardToken.STETH), 4 ether);

    staker3.stake(500 ether);
    uscStaking.updateEpoch(150 ether, 600 ether, 75 ether);

    assertEq(uscStaking.currentEpoch(), 4);
    assertEq(uscStaking.epochs(3), 300 ether);
    assertEq(uscStaking.chiAmountFromEmissions(), 250 ether);
    assertEq(uscStaking.getCumulativeRewardsPerShare(3, IStakingWithEpochs.RewardToken.CHI), 0.5 ether + 1 ether);
    assertEq(uscStaking.getCumulativeRewardsPerShare(3, IStakingWithEpochs.RewardToken.USC), 2 ether + 2 ether);
    assertEq(uscStaking.getCumulativeRewardsPerShare(3, IStakingWithEpochs.RewardToken.STETH), 0.25 ether + 4 ether);

    uscStaking.updateEpoch(400 ether, 800 ether, 1600 ether);

    assertEq(uscStaking.currentEpoch(), 5);
    assertEq(uscStaking.epochs(4), 800 ether);
    assertEq(uscStaking.chiAmountFromEmissions(), 650 ether);
    assertEq(
      uscStaking.getCumulativeRewardsPerShare(4, IStakingWithEpochs.RewardToken.CHI),
      0.5 ether + 0.5 ether + 1 ether
    );
    assertEq(
      uscStaking.getCumulativeRewardsPerShare(4, IStakingWithEpochs.RewardToken.USC),
      1 ether + 2 ether + 2 ether
    );
    assertEq(
      uscStaking.getCumulativeRewardsPerShare(4, IStakingWithEpochs.RewardToken.STETH),
      2 ether + 0.25 ether + 4 ether
    );
  }

  function test_ClaimStEth() public {
    staker1.stake(100 ether);

    uscStaking.setRewardController(address(this));
    uscStaking.updateEpoch(0, 0, 0);

    staker2.stake(200 ether);
    uscStaking.updateEpoch(100 ether, 200 ether, 400 ether);

    staker3.stake(500 ether);
    uscStaking.updateEpoch(150 ether, 600 ether, 75 ether);
    uscStaking.updateEpoch(400 ether, 800 ether, 1600 ether);

    staker1.stake(200 ether);
    staker2.stake(300 ether);
    staker3.stake(400 ether);

    uscStaking.updateEpoch(0, 0, 0);
    uscStaking.updateEpoch(1700 ether, 1700 ether, 1700 ether);

    uint256 stEthRewards = uscStaking.claimStETH(address(staker1));
    (uint256 lastUpdatedEpoch, uint256 shares, uint256 addSharesNextEpoch) = uscStaking.stakes(address(staker1));

    assertEq(stEthRewards, 925 ether);
    assertEq(lastUpdatedEpoch, 7);
    assertEq(shares, 300 ether);
    assertEq(addSharesNextEpoch, 0);
    assertEq(uscStaking.getUnclaimedRewards(address(staker1), IStakingWithEpochs.RewardToken.STETH), 0);

    stEthRewards = uscStaking.claimStETH(address(staker2));
    (lastUpdatedEpoch, shares, addSharesNextEpoch) = uscStaking.stakes(address(staker2));

    assertEq(stEthRewards, 950 ether);
    assertEq(lastUpdatedEpoch, 7);
    assertEq(shares, 500 ether);
    assertEq(addSharesNextEpoch, 0);
    assertEq(uscStaking.getUnclaimedRewards(address(staker2), IStakingWithEpochs.RewardToken.STETH), 0);

    stEthRewards = uscStaking.claimStETH(address(staker3));
    (lastUpdatedEpoch, shares, addSharesNextEpoch) = uscStaking.stakes(address(staker3));

    assertEq(stEthRewards, 1900 ether);
    assertEq(lastUpdatedEpoch, 7);
    assertEq(shares, 900 ether);
    assertEq(addSharesNextEpoch, 0);
    assertEq(uscStaking.getUnclaimedRewards(address(staker3), IStakingWithEpochs.RewardToken.STETH), 0);
  }

  function test_ClaimStEth_StakeBetweenClaim() public {
    staker1.stake(100 ether);

    uscStaking.setRewardController(address(this));
    uscStaking.updateEpoch(0, 0, 0);

    staker2.stake(200 ether);
    uscStaking.updateEpoch(100 ether, 200 ether, 400 ether);

    staker3.stake(500 ether);
    uscStaking.updateEpoch(150 ether, 600 ether, 75 ether);
    uscStaking.updateEpoch(400 ether, 800 ether, 1600 ether);

    staker1.stake(200 ether);
    staker2.stake(300 ether);
    staker3.stake(400 ether);

    uscStaking.updateEpoch(0, 0, 0);
    staker1.stake(500 ether);
    uscStaking.updateEpoch(1700 ether, 1700 ether, 1700 ether);

    uint256 stEthRewards = uscStaking.claimStETH(address(staker1));
    assertEq(stEthRewards, 925 ether);

    uscStaking.updateEpoch(0, 0, 2200 ether);
    stEthRewards = uscStaking.claimStETH(address(staker1));
    assertEq(stEthRewards, 800 ether);
  }

  function test_ClaimStEth_WithoutRewards() public {
    staker1.stake(100 ether);

    uscStaking.setRewardController(address(this));
    uscStaking.updateEpoch(0, 0, 0);

    staker2.stake(200 ether);
    uscStaking.updateEpoch(100 ether, 200 ether, 0);

    staker3.stake(500 ether);
    uscStaking.updateEpoch(150 ether, 600 ether, 0);

    uint256 staker1Rewards = uscStaking.claimStETH(address(staker1));
    uint256 staker2Rewards = uscStaking.claimStETH(address(staker2));
    uint256 staker3Rewards = uscStaking.claimStETH(address(staker3));
    assertEq(staker1Rewards, 0);
    assertEq(staker2Rewards, 0);
    assertEq(staker3Rewards, 0);
  }

  function test_ClaimUSCRewards() public {
    staker1.stake(100 ether);

    uscStaking.setRewardController(address(this));
    uscStaking.updateEpoch(0, 0, 0);

    staker2.stake(200 ether);
    uscStaking.updateEpoch(100 ether, 200 ether, 400 ether);

    staker3.stake(500 ether);
    uscStaking.updateEpoch(150 ether, 600 ether, 75 ether);
    uscStaking.updateEpoch(400 ether, 800 ether, 1600 ether);

    staker1.stake(200 ether);
    staker2.stake(300 ether);
    staker3.stake(400 ether);

    uscStaking.updateEpoch(0, 0, 0);
    uscStaking.updateEpoch(1700 ether, 1700 ether, 1700 ether);

    uint256 balanceBefore = usc.balanceOf(address(staker1));
    uint256 uscStakingBalanceBefore = usc.balanceOf(address(uscStaking));

    staker1.claimUSCRewards();
    assertEq(usc.balanceOf(address(staker1)), balanceBefore + 800 ether);

    balanceBefore = usc.balanceOf(address(staker2));
    staker2.claimUSCRewards();
    assertEq(usc.balanceOf(address(staker2)), balanceBefore + 1100 ether);

    balanceBefore = usc.balanceOf(address(staker3));
    staker3.claimUSCRewards();
    assertEq(usc.balanceOf(address(staker3)), balanceBefore + 1400 ether);
    assertEq(usc.balanceOf(address(uscStaking)), uscStakingBalanceBefore - 800 ether - 1100 ether - 1400 ether);
  }

  function test_Unstake_OnlyOneStakerWithoutRewards() public {
    staker1.stake(100 ether);

    uscStaking.setRewardController(address(this));
    uscStaking.updateEpoch(0, 0, 0);
    uscStaking.updateEpoch(0, 0, 0);

    staker1.unstake(70 ether);

    (uint256 lastUpdatedEpoch, uint256 shares, uint256 addSharesNextEpoch) = uscStaking.stakes(address(staker1));
    assertEq(lastUpdatedEpoch, uscStaking.currentEpoch());
    assertEq(shares, 30 ether);
    assertEq(addSharesNextEpoch, 0);
    assertEq(uscStaking.epochs(uscStaking.currentEpoch()), 30 ether);
    assertEq(uscStaking.getUnclaimedRewards(address(staker1), IStakingWithEpochs.RewardToken.CHI), 0);
    assertEq(uscStaking.getUnclaimedRewards(address(staker1), IStakingWithEpochs.RewardToken.USC), 0);
    assertEq(uscStaking.getUnclaimedRewards(address(staker1), IStakingWithEpochs.RewardToken.STETH), 0);
  }

  function test_Unstake_OnlyOneStakerWithRewards() public {
    staker1.stake(100 ether);

    uscStaking.setRewardController(address(this));
    uscStaking.updateEpoch(0, 0, 0);
    uscStaking.updateEpoch(100 ether, 200 ether, 400 ether);

    staker1.stake(200 ether);
    staker1.unstake(70 ether);

    (uint256 lastUpdatedEpoch, uint256 shares, uint256 addSharesNextEpoch) = uscStaking.stakes(address(staker1));
    assertEq(lastUpdatedEpoch, uscStaking.currentEpoch());
    assertEq(shares, 100 ether);
    assertEq(addSharesNextEpoch, 130 ether);
    assertEq(uscStaking.epochs(uscStaking.currentEpoch()), 100 ether);
    assertEq(uscStaking.getUnclaimedRewards(address(staker1), IStakingWithEpochs.RewardToken.CHI), 100 ether);
    assertEq(uscStaking.getUnclaimedRewards(address(staker1), IStakingWithEpochs.RewardToken.USC), 200 ether);
    assertEq(uscStaking.getUnclaimedRewards(address(staker1), IStakingWithEpochs.RewardToken.STETH), 400 ether);
  }

  function test_Unstake_MultipleStakers() public {
    staker1.stake(100 ether);

    uscStaking.setRewardController(address(this));
    uscStaking.updateEpoch(0, 0, 0);

    staker2.stake(200 ether);
    uscStaking.updateEpoch(100 ether, 200 ether, 400 ether);

    staker1.stake(200 ether);
    staker1.unstake(250 ether);
    uscStaking.updateEpoch(300 ether, 300 ether, 600 ether);
    uscStaking.updateEpoch(600 ether, 600 ether, 600 ether);

    (uint256 lastUpdatedEpoch, uint256 shares, uint256 addSharesNextEpoch) = uscStaking.stakes(address(staker1));
    assertEq(lastUpdatedEpoch, 3);
    assertEq(shares, 50 ether);
    assertEq(addSharesNextEpoch, 0);
    assertEq(uscStaking.getUnclaimedRewards(address(staker1), IStakingWithEpochs.RewardToken.CHI), 100 ether);
    assertEq(uscStaking.getUnclaimedRewards(address(staker1), IStakingWithEpochs.RewardToken.USC), 200 ether);
    assertEq(uscStaking.getUnclaimedRewards(address(staker1), IStakingWithEpochs.RewardToken.STETH), 400 ether);

    uint256 stETHRewards = uscStaking.claimStETH(address(staker1));
    assertEq(stETHRewards, 640 ether);

    vm.mockCall(
      address(this),
      abi.encodeWithSelector(IArbitrage.getArbitrageData.selector),
      abi.encode(true, true, 0, 0, 0)
    );
    uint256 uscBalanceBefore = usc.balanceOf(address(staker1));
    staker1.claimUSCRewards();
    assertEq(usc.balanceOf(address(staker1)), uscBalanceBefore + 380 ether);

    stETHRewards = uscStaking.claimStETH(address(staker2));
    assertEq(stETHRewards, 960 ether);

    uscBalanceBefore = usc.balanceOf(address(staker2));
    staker2.claimUSCRewards();
    assertEq(usc.balanceOf(address(staker2)), uscBalanceBefore + 720 ether);
  }
}

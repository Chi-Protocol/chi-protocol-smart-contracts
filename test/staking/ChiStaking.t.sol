// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IStakingWithEpochs} from "contracts/interfaces/IStakingWithEpochs.sol";
import {IChiLocking} from "contracts/interfaces/IChiLocking.sol";
import {CHI} from "contracts/tokens/CHI.sol";
import {ChiStaking} from "contracts/staking/ChiStaking.sol";
import {USCStaking} from "contracts/staking/USCStaking.sol";
import {Staker} from "./helpers/Staker.sol";

contract ChiStakingTest is Test {
  uint256 public constant TOLERANCE = 0.0001 ether;
  uint256 public constant CHI_INITIAL_SUPPLY = 100000000 ether;

  CHI public chi;
  ChiStaking public chiStaking;

  Staker public staker1;
  Staker public staker2;
  Staker public staker3;

  function setUp() public {
    chi = new CHI(CHI_INITIAL_SUPPLY);
    chiStaking = new ChiStaking();
    chiStaking.initialize(IERC20(address(chi)));

    staker1 = new Staker(IERC20(address(0x0)), IERC20(address(chi)), address(0x0), address(chiStaking));
    staker2 = new Staker(IERC20(address(0x0)), IERC20(address(chi)), address(0x0), address(chiStaking));
    staker3 = new Staker(IERC20(address(0x0)), IERC20(address(chi)), address(0x0), address(chiStaking));
    chi.transfer(address(staker1), 1000 ether);
    chi.transfer(address(staker2), 1000 ether);
    chi.transfer(address(staker3), 1000 ether);
  }

  function test_SetUp() public {
    assertEq(address(chi), address(chiStaking.stakeToken()));
    assertEq(address(this), chiStaking.owner());
  }

  function test_UpdateEpoch_WithoutStakersWithoutRewards() public {
    chiStaking.setRewardController(address(this));
    chiStaking.updateEpoch(0);

    assertEq(chiStaking.currentEpoch(), 2);
    assertEq(chiStaking.epochs(1), 0);
    assertEq(chiStaking.epochs(2), 0);
    assertEq(chiStaking.getCumulativeRewardsPerShare(1, IStakingWithEpochs.RewardToken.STETH), 0);
    assertEq(chiStaking.getCumulativeRewardsPerShare(2, IStakingWithEpochs.RewardToken.STETH), 0);
  }

  function test_UpdateEpoch_WithStakersWithoutRewards() public {
    staker1.stakeChi(100 ether);
    chiStaking.setRewardController(address(this));
    chiStaking.updateEpoch(0);

    assertEq(chiStaking.currentEpoch(), 2);
    assertEq(chiStaking.epochs(1), 0);
    assertEq(chiStaking.epochs(2), 100 ether);
    assertEq(chiStaking.getCumulativeRewardsPerShare(1, IStakingWithEpochs.RewardToken.STETH), 0);

    staker2.stakeChi(200 ether);
    chiStaking.updateEpoch(0);
    assertEq(chiStaking.currentEpoch(), 3);
    assertEq(chiStaking.epochs(2), 100 ether);
    assertEq(chiStaking.epochs(3), 300 ether);
    assertEq(chiStaking.getCumulativeRewardsPerShare(2, IStakingWithEpochs.RewardToken.STETH), 0);

    chiStaking.updateEpoch(0);
    assertEq(chiStaking.currentEpoch(), 4);
    assertEq(chiStaking.epochs(3), 300 ether);
    assertEq(chiStaking.epochs(4), 300 ether);
    assertEq(chiStaking.getCumulativeRewardsPerShare(3, IStakingWithEpochs.RewardToken.STETH), 0);
  }

  function test_UpdateEpoch_WithStakersWithRewards() public {
    staker1.stakeChi(100 ether);

    chiStaking.setRewardController(address(this));
    chiStaking.updateEpoch(0);

    staker2.stakeChi(200 ether);
    chiStaking.updateEpoch(400 ether);

    assertEq(chiStaking.currentEpoch(), 3);
    assertEq(chiStaking.epochs(2), 100 ether);
    assertEq(chiStaking.getCumulativeRewardsPerShare(2, IStakingWithEpochs.RewardToken.STETH), 4 ether);

    staker3.stakeChi(500 ether);
    chiStaking.updateEpoch(75 ether);

    assertEq(chiStaking.currentEpoch(), 4);
    assertEq(chiStaking.epochs(3), 300 ether);
    assertEq(chiStaking.getCumulativeRewardsPerShare(3, IStakingWithEpochs.RewardToken.STETH), 0.25 ether + 4 ether);

    chiStaking.updateEpoch(1600 ether);

    assertEq(chiStaking.currentEpoch(), 5);
    assertEq(chiStaking.epochs(4), 800 ether);
    assertEq(
      chiStaking.getCumulativeRewardsPerShare(4, IStakingWithEpochs.RewardToken.STETH),
      2 ether + 0.25 ether + 4 ether
    );
  }

  function test_Unstake_OnlyOneStakerWithoutRewards() public {
    staker1.stakeChi(100 ether);

    chiStaking.setRewardController(address(this));
    chiStaking.updateEpoch(0);
    chiStaking.updateEpoch(0);

    vm.mockCall(
      address(chiStaking.chiLocking()),
      abi.encodeWithSelector(IChiLocking.availableChiWithdraw.selector),
      abi.encode(0)
    );
    vm.mockCall(
      address(chiStaking.chiLocking()),
      abi.encodeWithSelector(IChiLocking.withdrawChiFromAccount.selector),
      abi.encode(0)
    );

    staker1.unstakeChi(70 ether);

    (uint256 lastUpdatedEpoch, uint256 shares, uint256 addSharesNextEpoch) = chiStaking.stakes(address(staker1));
    assertEq(lastUpdatedEpoch, chiStaking.currentEpoch());
    assertEq(shares, 30 ether);
    assertEq(addSharesNextEpoch, 0);
    assertEq(chiStaking.epochs(chiStaking.currentEpoch()), 30 ether);
    assertEq(chiStaking.getUnclaimedRewards(address(staker1), IStakingWithEpochs.RewardToken.STETH), 0);
  }

  function test_Unstake_OnlyOneStakerWithRewards() public {
    staker1.stakeChi(100 ether);

    chiStaking.setRewardController(address(this));
    chiStaking.updateEpoch(0);
    chiStaking.updateEpoch(400 ether);

    vm.mockCall(
      address(chiStaking.chiLocking()),
      abi.encodeWithSelector(IChiLocking.availableChiWithdraw.selector),
      abi.encode(0)
    );
    vm.mockCall(
      address(chiStaking.chiLocking()),
      abi.encodeWithSelector(IChiLocking.withdrawChiFromAccount.selector),
      abi.encode(0)
    );

    staker1.stakeChi(200 ether);
    staker1.unstakeChi(70 ether);

    (uint256 lastUpdatedEpoch, uint256 shares, uint256 addSharesNextEpoch) = chiStaking.stakes(address(staker1));
    assertEq(lastUpdatedEpoch, chiStaking.currentEpoch());
    assertEq(shares, 100 ether);
    assertEq(addSharesNextEpoch, 130 ether);
    assertEq(chiStaking.epochs(chiStaking.currentEpoch()), 100 ether);
    assertEq(chiStaking.getUnclaimedRewards(address(staker1), IStakingWithEpochs.RewardToken.STETH), 400 ether);
  }

  function test_Unstake_MultipleStakers() public {
    staker1.stakeChi(100 ether);

    chiStaking.setRewardController(address(this));
    chiStaking.updateEpoch(0);

    staker2.stakeChi(200 ether);
    chiStaking.updateEpoch(400 ether);

    vm.mockCall(
      address(chiStaking.chiLocking()),
      abi.encodeWithSelector(IChiLocking.availableChiWithdraw.selector),
      abi.encode(0)
    );
    vm.mockCall(
      address(chiStaking.chiLocking()),
      abi.encodeWithSelector(IChiLocking.withdrawChiFromAccount.selector),
      abi.encode(0)
    );

    staker1.stakeChi(200 ether);
    staker1.unstakeChi(250 ether);

    chiStaking.updateEpoch(600 ether);
    chiStaking.updateEpoch(600 ether);

    (uint256 lastUpdatedEpoch, uint256 shares, uint256 addSharesNextEpoch) = chiStaking.stakes(address(staker1));
    assertEq(lastUpdatedEpoch, 3);
    assertEq(shares, 50 ether);
    assertEq(addSharesNextEpoch, 0);
    assertEq(chiStaking.getUnclaimedRewards(address(staker1), IStakingWithEpochs.RewardToken.STETH), 400 ether);

    uint256 stETHRewards = chiStaking.claimStETH(address(staker1));
    assertEq(stETHRewards, 640 ether);

    stETHRewards = chiStaking.claimStETH(address(staker2));
    assertEq(stETHRewards, 960 ether);
  }

  function test_Unstake_MultipleStakers_UnstakeFromChiLocking() public {
    staker1.stakeChi(100 ether);

    chiStaking.setRewardController(address(this));
    chiStaking.updateEpoch(0);

    staker2.stakeChi(200 ether);
    chiStaking.updateEpoch(400 ether);

    vm.mockCall(
      address(chiStaking.chiLocking()),
      abi.encodeWithSelector(IChiLocking.availableChiWithdraw.selector),
      abi.encode(100 ether)
    );
    vm.mockCall(
      address(chiStaking.chiLocking()),
      abi.encodeWithSelector(IChiLocking.withdrawChiFromAccount.selector),
      abi.encode(0)
    );

    staker1.stakeChi(200 ether);
    staker1.unstakeChi(250 ether);

    chiStaking.updateEpoch(600 ether);
    chiStaking.updateEpoch(600 ether);

    (uint256 lastUpdatedEpoch, uint256 shares, uint256 addSharesNextEpoch) = chiStaking.stakes(address(staker1));
    assertEq(lastUpdatedEpoch, 3);
    assertEq(shares, 100 ether);
    assertEq(addSharesNextEpoch, 50 ether);
    assertEq(chiStaking.getUnclaimedRewards(address(staker1), IStakingWithEpochs.RewardToken.STETH), 400 ether);

    uint256 correctStEthRewards = 400 ether + uint256(600 ether) / 3 + uint256(600 ether * 150) / 350;
    uint256 stETHRewards = chiStaking.claimStETH(address(staker1));

    assertApproxEqRel(stETHRewards, correctStEthRewards, TOLERANCE);

    correctStEthRewards = uint256(600 ether * 2) / 3 + uint256(600 ether * 200) / 350;
    stETHRewards = chiStaking.claimStETH(address(staker2));
    assertApproxEqRel(stETHRewards, correctStEthRewards, TOLERANCE);
  }

  function test_Lock_DontUseStakedTokens() public {
    address chiLockingAddress = makeAddr("chiLocking");
    chiStaking.setChiLocking(IChiLocking(chiLockingAddress));

    vm.mockCall(address(chiStaking.chiLocking()), abi.encodeWithSelector(IChiLocking.lockChi.selector), abi.encode(0));
    vm.mockCall(
      address(chiStaking.chiLocking()),
      abi.encodeWithSelector(IChiLocking.availableChiWithdraw.selector),
      abi.encode(0)
    );
    vm.expectCall(
      address(chiStaking.chiLocking()),
      abi.encodeWithSelector(IChiLocking.lockChi.selector, address(staker1), 100 ether, 4)
    );
    staker1.lockChi(100 ether, 4, false);
    assertEq(chi.balanceOf(chiLockingAddress), 100 ether);

    staker1.stakeChi(100 ether);

    vm.expectCall(
      address(chiStaking.chiLocking()),
      abi.encodeWithSelector(IChiLocking.lockChi.selector, address(staker1), 50 ether, 5)
    );
    staker1.lockChi(50 ether, 4, true);
    assertEq(chi.balanceOf(chiLockingAddress), 150 ether);
  }
}

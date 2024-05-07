// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

// import {Test} from "forge-std/Test.sol";
// import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import {IStakingWithEpochs} from "contracts/interfaces/IStakingWithEpochs.sol";
// import {IChiLocking} from "contracts/interfaces/IChiLocking.sol";
// import {IArbitrage} from "contracts/interfaces/IArbitrage.sol";
// import {USC} from "contracts/tokens/USC.sol";
// import {CHI} from "contracts/tokens/CHI.sol";
// import {USCStaking} from "contracts/staking/USCStaking.sol";
// import {Staker} from "./helpers/Staker.sol";
// import {LPStaking} from "contracts/staking/LPStaking.sol";

// contract LPStakingTest is Test {
//   uint256 public constant USC_INITIAL_SUPPLY = 100000000 ether;
//   uint256 public constant CHI_INITIAL_SUPPLY = 100000000 ether;

//   USC public usc;
//   CHI public chi;
//   LPStaking public lpStaking;
//   address public chiLockingAddress;

//   Staker public staker1;
//   Staker public staker2;
//   Staker public staker3;

//   function setUp() public {
//     usc = new USC();
//     usc.updateMinter(address(this), true);
//     usc.mint(address(this), USC_INITIAL_SUPPLY);
//     chi = new CHI(CHI_INITIAL_SUPPLY);

//     chiLockingAddress = makeAddr("chiLockingAddress");

//     lpStaking = new LPStaking();
//     lpStaking.initialize(
//       IERC20(address(chi)),
//       IChiLocking(chiLockingAddress),
//       IERC20(address(usc)),
//       "USC/ETH LP Staking",
//       "USC/ETH LP"
//     );

//     staker1 = new Staker(IERC20(address(usc)), IERC20(address(0x0)), address(lpStaking), address(0x0));
//     staker2 = new Staker(IERC20(address(usc)), IERC20(address(0x0)), address(lpStaking), address(0x0));
//     staker3 = new Staker(IERC20(address(usc)), IERC20(address(0x0)), address(lpStaking), address(0x0));
//     usc.transfer(address(staker1), 1000 ether);
//     usc.transfer(address(staker2), 1000 ether);
//     usc.transfer(address(staker3), 1000 ether);
//   }

//   function test_SetUp() public {
//     assertEq(lpStaking.owner(), address(this));
//     assertEq(lpStaking.currentEpoch(), 1);
//     assertEq(lpStaking.name(), "USC/ETH LP Staking");
//     assertEq(lpStaking.symbol(), "USC/ETH LP");
//     assertEq(address(lpStaking.stakeToken()), address(usc));
//     assertEq(address(lpStaking.chi()), address(chi));
//     assertEq(address(lpStaking.chiLockingContract()), chiLockingAddress);
//   }

//   function testFuzz_SetRewardController(address rewardController) public {
//     lpStaking.setRewardController(rewardController);
//     assertEq(lpStaking.rewardController(), rewardController);
//   }

//   function testFuzz_SetRewardController_Revert_NotOwner(address caller, address rewardController) public {
//     vm.assume(caller != address(this));
//     vm.startPrank(caller);
//     vm.expectRevert("Ownable: caller is not the owner");
//     lpStaking.setRewardController(rewardController);
//     vm.stopPrank();
//   }

//   function test_Stake_OnlyOneStaker_OnlyOneEpoch() public {
//     uint256 uscBalanceBefore = usc.balanceOf(address(staker1));
//     uint256 lpStakingBalanceBefore = usc.balanceOf(address(lpStaking));
//     uint256 stakeAmount = 100 ether;
//     staker1.stake(stakeAmount);

//     (uint256 lastUpdatedEpoch, uint256 shares, uint256 addSharesNextEpoch) = lpStaking.stakes(address(staker1));
//     assertEq(lastUpdatedEpoch, lpStaking.currentEpoch());
//     assertEq(shares, 0);
//     assertEq(addSharesNextEpoch, stakeAmount);
//     assertEq(lpStaking.getUnclaimedRewards(address(staker1), IStakingWithEpochs.RewardToken.USC), 0);
//     assertEq(lpStaking.getUnclaimedRewards(address(staker1), IStakingWithEpochs.RewardToken.CHI), 0);
//     assertEq(lpStaking.getUnclaimedRewards(address(staker1), IStakingWithEpochs.RewardToken.STETH), 0);
//     assertEq(lpStaking.epochs(lpStaking.currentEpoch()), 0);
//     assertEq(lpStaking.epochs(lpStaking.currentEpoch() + 1), stakeAmount);
//     assertEq(usc.balanceOf(address(staker1)), uscBalanceBefore - stakeAmount);
//     assertEq(usc.balanceOf(address(lpStaking)), lpStakingBalanceBefore + stakeAmount);

//     stakeAmount = 200 ether;
//     staker1.stake(stakeAmount);
//     (lastUpdatedEpoch, shares, addSharesNextEpoch) = lpStaking.stakes(address(staker1));
//     assertEq(lastUpdatedEpoch, lpStaking.currentEpoch());
//     assertEq(shares, 0);
//     assertEq(addSharesNextEpoch, 300 ether);
//     assertEq(lpStaking.getUnclaimedRewards(address(staker1), IStakingWithEpochs.RewardToken.USC), 0);
//     assertEq(lpStaking.getUnclaimedRewards(address(staker1), IStakingWithEpochs.RewardToken.CHI), 0);
//     assertEq(lpStaking.getUnclaimedRewards(address(staker1), IStakingWithEpochs.RewardToken.STETH), 0);
//     assertEq(lpStaking.epochs(lpStaking.currentEpoch()), 0);
//     assertEq(lpStaking.epochs(lpStaking.currentEpoch() + 1), 300 ether);
//     assertEq(usc.balanceOf(address(staker1)), uscBalanceBefore - 300 ether);
//     assertEq(usc.balanceOf(address(lpStaking)), lpStakingBalanceBefore + 300 ether);
//   }

//   function test_Stake_OnlyOneStaker_MultipleEpochs_WithoutRewards() public {
//     uint256 uscBalanceBefore = usc.balanceOf(address(staker1));
//     uint256 lpStakingBalanceBefore = usc.balanceOf(address(lpStaking));
//     staker1.stake(100 ether);

//     lpStaking.setRewardController(address(this));
//     uint256 numberOfEpochs = 3;
//     for (uint256 i = 0; i < numberOfEpochs; i++) {
//       lpStaking.updateEpoch(0);
//     }

//     staker1.stake(200 ether);

//     (uint256 lastUpdatedEpoch, uint256 shares, uint256 addSharesNextEpoch) = lpStaking.stakes(address(staker1));
//     assertEq(lastUpdatedEpoch, lpStaking.currentEpoch());
//     assertEq(shares, 100 ether);
//     assertEq(addSharesNextEpoch, 200 ether);
//     assertEq(lpStaking.getUnclaimedRewards(address(staker1), IStakingWithEpochs.RewardToken.USC), 0);
//     assertEq(lpStaking.getUnclaimedRewards(address(staker1), IStakingWithEpochs.RewardToken.CHI), 0);
//     assertEq(lpStaking.getUnclaimedRewards(address(staker1), IStakingWithEpochs.RewardToken.STETH), 0);
//     assertEq(lpStaking.epochs(lpStaking.currentEpoch()), 100 ether);
//     assertEq(lpStaking.epochs(lpStaking.currentEpoch() + 1), 200 ether);
//     assertEq(usc.balanceOf(address(staker1)), uscBalanceBefore - 300 ether);
//     assertEq(usc.balanceOf(address(lpStaking)), lpStakingBalanceBefore + 300 ether);
//   }

//   function test_Stake_MultipleStakers_MultipleEpochs() public {
//     uint256 staker1BalanceBefore = usc.balanceOf(address(staker1));
//     staker1.stake(100 ether);

//     lpStaking.setRewardController(address(this));
//     lpStaking.updateEpoch(0);

//     uint256 staker2BalanceBefore = usc.balanceOf(address(staker2));
//     staker2.stake(200 ether);
//     lpStaking.updateEpoch(0);

//     (uint256 lastUpdatedEpoch, uint256 shares, uint256 addSharesNextEpoch) = lpStaking.stakes(address(staker1));
//     assertEq(lastUpdatedEpoch, 1);
//     assertEq(shares, 0);
//     assertEq(addSharesNextEpoch, 100 ether);
//     assertEq(lpStaking.getUnclaimedRewards(address(staker1), IStakingWithEpochs.RewardToken.USC), 0);
//     assertEq(lpStaking.getUnclaimedRewards(address(staker1), IStakingWithEpochs.RewardToken.CHI), 0);
//     assertEq(lpStaking.getUnclaimedRewards(address(staker1), IStakingWithEpochs.RewardToken.STETH), 0);
//     assertEq(usc.balanceOf(address(staker1)), staker1BalanceBefore - 100 ether);

//     uint256 staker3BalanceBefore = usc.balanceOf(address(staker3));
//     staker3.stake(300 ether);
//     lpStaking.updateEpoch(0);

//     (lastUpdatedEpoch, shares, addSharesNextEpoch) = lpStaking.stakes(address(staker2));
//     assertEq(lastUpdatedEpoch, 2);
//     assertEq(shares, 0);
//     assertEq(addSharesNextEpoch, 200 ether);
//     assertEq(lpStaking.getUnclaimedRewards(address(staker2), IStakingWithEpochs.RewardToken.USC), 0);
//     assertEq(lpStaking.getUnclaimedRewards(address(staker2), IStakingWithEpochs.RewardToken.CHI), 0);
//     assertEq(lpStaking.getUnclaimedRewards(address(staker2), IStakingWithEpochs.RewardToken.STETH), 0);
//     assertEq(usc.balanceOf(address(staker2)), staker2BalanceBefore - 200 ether);

//     lpStaking.updateEpoch(0);
//     (lastUpdatedEpoch, shares, addSharesNextEpoch) = lpStaking.stakes(address(staker3));
//     assertEq(lastUpdatedEpoch, 3);
//     assertEq(shares, 0);
//     assertEq(addSharesNextEpoch, 300 ether);
//     assertEq(lpStaking.getUnclaimedRewards(address(staker3), IStakingWithEpochs.RewardToken.USC), 0);
//     assertEq(lpStaking.getUnclaimedRewards(address(staker3), IStakingWithEpochs.RewardToken.CHI), 0);
//     assertEq(lpStaking.getUnclaimedRewards(address(staker3), IStakingWithEpochs.RewardToken.STETH), 0);
//     assertEq(usc.balanceOf(address(staker3)), staker3BalanceBefore - 300 ether);
//   }

//   function test_Stake_MultipleStakers_MultipleEpochs_WithRewards() public {
//     staker1.stake(100 ether);

//     lpStaking.setRewardController(address(this));
//     lpStaking.updateEpoch(0);

//     staker2.stake(200 ether);
//     lpStaking.updateEpoch(100 ether);

//     staker3.stake(500 ether);
//     lpStaking.updateEpoch(150 ether);

//     lpStaking.updateEpoch(400 ether);
//     staker1.stake(200 ether);

//     (uint256 lastUpdatedEpoch, uint256 shares, uint256 addSharesNextEpoch) = lpStaking.stakes(address(staker1));
//     assertEq(lastUpdatedEpoch, 5);
//     assertEq(shares, 100 ether);
//     assertEq(addSharesNextEpoch, 200 ether);
//     assertEq(lpStaking.getUnclaimedRewards(address(staker1), IStakingWithEpochs.RewardToken.CHI), 200 ether);

//     staker2.stake(300 ether);
//     (lastUpdatedEpoch, shares, addSharesNextEpoch) = lpStaking.stakes(address(staker2));
//     assertEq(lastUpdatedEpoch, 5);
//     assertEq(shares, 200 ether);
//     assertEq(addSharesNextEpoch, 300 ether);
//     assertEq(lpStaking.getUnclaimedRewards(address(staker2), IStakingWithEpochs.RewardToken.CHI), 200 ether);

//     staker3.stake(400 ether);
//     (lastUpdatedEpoch, shares, addSharesNextEpoch) = lpStaking.stakes(address(staker3));
//     assertEq(lastUpdatedEpoch, 5);
//     assertEq(shares, 500 ether);
//     assertEq(addSharesNextEpoch, 400 ether);
//     assertEq(lpStaking.getUnclaimedRewards(address(staker3), IStakingWithEpochs.RewardToken.CHI), 250 ether);

//     lpStaking.updateEpoch(0);
//     lpStaking.updateEpoch(1700 ether);
//     staker1.stake(100 ether);
//     assertEq(lpStaking.getUnclaimedRewards(address(staker1), IStakingWithEpochs.RewardToken.CHI), 500 ether);

//     staker2.stake(200 ether);
//     assertEq(lpStaking.getUnclaimedRewards(address(staker2), IStakingWithEpochs.RewardToken.CHI), 700 ether);

//     staker3.stake(50 ether);
//     assertEq(lpStaking.getUnclaimedRewards(address(staker3), IStakingWithEpochs.RewardToken.CHI), 1150 ether);
//   }

//   function test_Stake_Revert_ZeroAmount() public {
//     vm.expectRevert(IStakingWithEpochs.ZeroAmount.selector);
//     lpStaking.stake(0);
//   }

//   function test_UpdateEpoch_WithoutStakersWithoutRewards() public {
//     lpStaking.setRewardController(address(this));
//     lpStaking.updateEpoch(0);

//     assertEq(lpStaking.currentEpoch(), 2);
//     assertEq(lpStaking.epochs(1), 0);
//     assertEq(lpStaking.epochs(2), 0);
//     assertEq(lpStaking.getCumulativeRewardsPerShare(1, IStakingWithEpochs.RewardToken.USC), 0);
//     assertEq(lpStaking.getCumulativeRewardsPerShare(2, IStakingWithEpochs.RewardToken.USC), 0);
//     assertEq(lpStaking.getCumulativeRewardsPerShare(1, IStakingWithEpochs.RewardToken.CHI), 0);
//     assertEq(lpStaking.getCumulativeRewardsPerShare(2, IStakingWithEpochs.RewardToken.CHI), 0);
//     assertEq(lpStaking.getCumulativeRewardsPerShare(1, IStakingWithEpochs.RewardToken.STETH), 0);
//     assertEq(lpStaking.getCumulativeRewardsPerShare(2, IStakingWithEpochs.RewardToken.STETH), 0);
//   }

//   function test_UpdateEpoch_WithStakersWithoutRewards() public {
//     staker1.stake(100 ether);
//     lpStaking.setRewardController(address(this));
//     lpStaking.updateEpoch(0);

//     assertEq(lpStaking.currentEpoch(), 2);
//     assertEq(lpStaking.epochs(1), 0);
//     assertEq(lpStaking.epochs(2), 100 ether);
//     assertEq(lpStaking.getCumulativeRewardsPerShare(1, IStakingWithEpochs.RewardToken.USC), 0);
//     assertEq(lpStaking.getCumulativeRewardsPerShare(1, IStakingWithEpochs.RewardToken.CHI), 0);
//     assertEq(lpStaking.getCumulativeRewardsPerShare(1, IStakingWithEpochs.RewardToken.STETH), 0);

//     staker2.stake(200 ether);
//     lpStaking.updateEpoch(0);
//     assertEq(lpStaking.currentEpoch(), 3);
//     assertEq(lpStaking.epochs(2), 100 ether);
//     assertEq(lpStaking.epochs(3), 300 ether);
//     assertEq(lpStaking.getCumulativeRewardsPerShare(2, IStakingWithEpochs.RewardToken.USC), 0);
//     assertEq(lpStaking.getCumulativeRewardsPerShare(2, IStakingWithEpochs.RewardToken.CHI), 0);
//     assertEq(lpStaking.getCumulativeRewardsPerShare(2, IStakingWithEpochs.RewardToken.STETH), 0);

//     lpStaking.updateEpoch(0);
//     assertEq(lpStaking.currentEpoch(), 4);
//     assertEq(lpStaking.epochs(3), 300 ether);
//     assertEq(lpStaking.epochs(4), 300 ether);
//     assertEq(lpStaking.getCumulativeRewardsPerShare(3, IStakingWithEpochs.RewardToken.USC), 0);
//     assertEq(lpStaking.getCumulativeRewardsPerShare(3, IStakingWithEpochs.RewardToken.CHI), 0);
//     assertEq(lpStaking.getCumulativeRewardsPerShare(3, IStakingWithEpochs.RewardToken.STETH), 0);
//   }

//   function test_UpdateEpoch_WithStakersWithRewards() public {
//     staker1.stake(100 ether);

//     lpStaking.setRewardController(address(this));
//     lpStaking.updateEpoch(0);

//     staker2.stake(200 ether);
//     lpStaking.updateEpoch(100 ether);

//     assertEq(lpStaking.currentEpoch(), 3);
//     assertEq(lpStaking.epochs(2), 100 ether);
//     assertEq(lpStaking.getCumulativeRewardsPerShare(2, IStakingWithEpochs.RewardToken.CHI), 1 ether);

//     staker3.stake(500 ether);
//     lpStaking.updateEpoch(150 ether);

//     assertEq(lpStaking.currentEpoch(), 4);
//     assertEq(lpStaking.epochs(3), 300 ether);
//     assertEq(lpStaking.getCumulativeRewardsPerShare(3, IStakingWithEpochs.RewardToken.CHI), 0.5 ether + 1 ether);

//     lpStaking.updateEpoch(400 ether);

//     assertEq(lpStaking.currentEpoch(), 5);
//     assertEq(lpStaking.epochs(4), 800 ether);
//     assertEq(
//       lpStaking.getCumulativeRewardsPerShare(4, IStakingWithEpochs.RewardToken.CHI),
//       0.5 ether + 0.5 ether + 1 ether
//     );
//   }

//   function test_Unstake_OnlyOneStakerWithoutRewards() public {
//     staker1.stake(100 ether);

//     lpStaking.setRewardController(address(this));
//     lpStaking.updateEpoch(0);
//     lpStaking.updateEpoch(0);

//     staker1.unstake(70 ether);

//     (uint256 lastUpdatedEpoch, uint256 shares, uint256 addSharesNextEpoch) = lpStaking.stakes(address(staker1));
//     assertEq(lastUpdatedEpoch, lpStaking.currentEpoch());
//     assertEq(shares, 30 ether);
//     assertEq(addSharesNextEpoch, 0);
//     assertEq(lpStaking.epochs(lpStaking.currentEpoch()), 30 ether);
//     assertEq(lpStaking.getUnclaimedRewards(address(staker1), IStakingWithEpochs.RewardToken.CHI), 0);
//     assertEq(lpStaking.getUnclaimedRewards(address(staker1), IStakingWithEpochs.RewardToken.USC), 0);
//     assertEq(lpStaking.getUnclaimedRewards(address(staker1), IStakingWithEpochs.RewardToken.STETH), 0);
//   }

//   function test_Unstake_OnlyOneStakerWithRewards() public {
//     staker1.stake(100 ether);

//     lpStaking.setRewardController(address(this));
//     lpStaking.updateEpoch(0);
//     lpStaking.updateEpoch(100 ether);

//     staker1.stake(200 ether);
//     staker1.unstake(70 ether);

//     (uint256 lastUpdatedEpoch, uint256 shares, uint256 addSharesNextEpoch) = lpStaking.stakes(address(staker1));
//     assertEq(lastUpdatedEpoch, lpStaking.currentEpoch());
//     assertEq(shares, 100 ether);
//     assertEq(addSharesNextEpoch, 130 ether);
//     assertEq(lpStaking.epochs(lpStaking.currentEpoch()), 100 ether);
//     assertEq(lpStaking.getUnclaimedRewards(address(staker1), IStakingWithEpochs.RewardToken.CHI), 100 ether);
//   }

//   function test_Unstake_MultipleStakers() public {
//     staker1.stake(100 ether);

//     lpStaking.setRewardController(address(this));
//     lpStaking.updateEpoch(0);

//     staker2.stake(200 ether);
//     lpStaking.updateEpoch(100 ether);

//     staker1.stake(200 ether);
//     staker1.unstake(250 ether);
//     lpStaking.updateEpoch(300 ether);
//     lpStaking.updateEpoch(600 ether);

//     (uint256 lastUpdatedEpoch, uint256 shares, uint256 addSharesNextEpoch) = lpStaking.stakes(address(staker1));
//     assertEq(lastUpdatedEpoch, 3);
//     assertEq(shares, 50 ether);
//     assertEq(addSharesNextEpoch, 0);
//     assertEq(lpStaking.getUnclaimedRewards(address(staker1), IStakingWithEpochs.RewardToken.CHI), 100 ether);

//     (lastUpdatedEpoch, shares, addSharesNextEpoch) = lpStaking.stakes(address(staker2));
//     assertEq(lastUpdatedEpoch, 2);
//     assertEq(shares, 0);
//     assertEq(addSharesNextEpoch, 200 ether);
//     assertEq(lpStaking.getUnclaimedRewards(address(staker2), IStakingWithEpochs.RewardToken.CHI), 0);
//   }
// }

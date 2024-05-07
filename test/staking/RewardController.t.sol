// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IBurnableERC20} from "contracts/interfaces/IBurnableERC20.sol";
import {IArbitrage} from "contracts/interfaces/IArbitrage.sol";
import {IStaking} from "contracts/interfaces/IStaking.sol";
import {IUSCStaking} from "contracts/interfaces/IUSCStaking.sol";
import {IChiStaking} from "contracts/interfaces/IChiStaking.sol";
import {IChiLocking} from "contracts/interfaces/IChiLocking.sol";
import {IChiVesting} from "contracts/interfaces/IChiVesting.sol";
import {ILPStaking} from "contracts/interfaces/ILPStaking.sol";
import {IReserveHolder} from "contracts/interfaces/IReserveHolder.sol";
import {IRewardController} from "contracts/interfaces/IRewardController.sol";
import {Arbitrager} from "./helpers/Arbitrager.sol";
import {USC} from "contracts/tokens/USC.sol";
import {CHI} from "contracts/tokens/CHI.sol";
import {USCStaking} from "contracts/staking/USCStaking.sol";
import {ChiStaking} from "contracts/staking/ChiStaking.sol";
import {ChiLocking} from "contracts/staking/ChiLocking.sol";
import {ChiVesting} from "contracts/staking/ChiVesting.sol";
import {LPStaking} from "contracts/staking/LPStaking.sol";
import {RewardControllerV2} from "contracts/staking/RewardControllerV2.sol";
import {ExternalContractAddresses} from "contracts/library/ExternalContractAddresses.sol";

contract RewardControllerTest is Test {
  uint256 public constant USC_INITIAL_SUPPLY = 100000000 ether;
  uint256 public constant CHI_INITIAL_SUPPLY = 100000000 ether;
  uint256 public constant CHI_INCENTIVES_PER_EPOCH = 38461 * 1 ether;
  address public constant STETH = ExternalContractAddresses.stETH;

  address public reserveHolderAddr;

  USC public usc;
  CHI public chi;
  USCStaking public uscStaking;
  ChiStaking public chiStaking;
  ChiLocking public chiLocking;
  ChiVesting public chiVesting;
  LPStaking public uscEthLPStaking;
  LPStaking public chiEthLPStaking;
  RewardControllerV2 public rewardController;
  Arbitrager public arbitrager;

  function setUp() public {
    chi = new CHI(CHI_INITIAL_SUPPLY);
    chiStaking = new ChiStaking();
    chiStaking.initialize(IERC20(address(chi)));

    usc = new USC();
    chiLocking = new ChiLocking();
    chiLocking.initialize(IERC20(address(chi)), address(chiStaking));

    chiVesting = new ChiVesting();
    chiVesting.initialize(IERC20(address(chi)), 1 weeks, 1 weeks);

    uscStaking = new USCStaking();
    uscStaking.initialize(IERC20(address(usc)), IERC20(address(chi)), chiLocking);

    uscEthLPStaking = new LPStaking();
    uscEthLPStaking.initialize(IERC20(address(chi)), chiLocking, chi, "CHI-ETH LP Staking", "CHI-ETH LP");

    chiEthLPStaking = new LPStaking();
    chiEthLPStaking.initialize(IERC20(address(chi)), chiLocking, usc, "USC-ETH LP Staking", "USC-ETH LP");

    reserveHolderAddr = makeAddr("reserveHolder");

    rewardController = new RewardControllerV2();
    rewardController.initialize(
      chi,
      usc,
      IReserveHolder(reserveHolderAddr),
      IUSCStaking(address(uscStaking)),
      IChiStaking(address(chiStaking)),
      IChiLocking(address(chiLocking)),
      IChiVesting(address(chiVesting)),
      ILPStaking(address(uscEthLPStaking)),
      ILPStaking(address(chiEthLPStaking)),
      block.timestamp
    );
    chi.transfer(address(rewardController), 1000000 ether);

    arbitrager = new Arbitrager(usc, rewardController);
    usc.updateMinter(address(this), true);
    usc.updateMinter(address(rewardController), true);
    usc.mint(address(arbitrager), 10000 ether);

    uscStaking.setRewardController(address(rewardController));
    chiStaking.setRewardController(address(rewardController));
    chiLocking.setRewardController(address(rewardController));
    chiVesting.setRewardController(address(rewardController));
    chiEthLPStaking.setRewardController(address(rewardController));
    uscEthLPStaking.setRewardController(address(rewardController));
  }

  function testFuzz_SetChiIncentivesForChiLocking(uint256 value) public {
    rewardController.setChiIncentivesForChiLocking(value);
    assertEq(rewardController.chiIncentivesForChiLocking(), value);
  }

  function testFuzz_SetChiIncentivesForChiLocking_Revert_NotOwner(address caller, uint256 value) public {
    vm.assume(caller != address(this));
    vm.startPrank(caller);
    vm.expectRevert("Ownable: caller is not the owner");
    rewardController.setChiIncentivesForChiLocking(value);
  }

  function testFuzz_SetChiIncentivesForUscStaking(uint256 value) public {
    rewardController.setChiIncentivesForUscStaking(value);
    assertEq(rewardController.chiIncentivesForUscStaking(), value);
  }

  function testFuzz_SetChiIncentivesForUscStaking_Revert_NotOwner(address caller, uint256 value) public {
    vm.assume(caller != address(this));
    vm.startPrank(caller);
    vm.expectRevert("Ownable: caller is not the owner");
    rewardController.setChiIncentivesForUscStaking(value);
  }

  function testFuzz_SetChiIncentivesForUscEthLPStaking(uint256 value) public {
    rewardController.setChiIncentivesForUscEthLPStaking(value);
    assertEq(rewardController.chiIncentivesForUscEthLPStaking(), value);
  }

  function testFuzz_SetChiIncentivesForUscEthLPStaking_Revert_NotOwner(address caller, uint256 value) public {
    vm.assume(caller != address(this));
    vm.startPrank(caller);
    vm.expectRevert("Ownable: caller is not the owner");
    rewardController.setChiIncentivesForUscEthLPStaking(value);
  }

  function testFuzz_SetChiIncentivesForChiEthLPStaking(uint256 value) public {
    rewardController.setChiIncentivesForChiEthLPStaking(value);
    assertEq(rewardController.chiIncentivesForChiEthLPStaking(), value);
  }

  function testFuzz_SetChiIncentivesForChiEthLPStaking_Revert_NotOwner(address caller, uint256 value) public {
    vm.assume(caller != address(this));
    vm.startPrank(caller);
    vm.expectRevert("Ownable: caller is not the owner");
    rewardController.setChiIncentivesForChiEthLPStaking(value);
  }

  function testFuzz_SetArbitrager(address _arbitrager) public {
    rewardController.setArbitrager(IArbitrage(_arbitrager));
    assertEq(address(rewardController.arbitrager()), _arbitrager);
  }

  function testFuzz_SetArbitrager_Revert_NotOwner(address _caller, address _arbitrager) public {
    vm.assume(_caller != address(this));
    vm.startPrank(_caller);
    vm.expectRevert("Ownable: caller is not the owner");
    rewardController.setArbitrager(IArbitrage(_arbitrager));
  }

  function test_RewardUSC() public {
    uint256 uscBalanceBefore = usc.balanceOf(address(arbitrager));
    rewardController.setArbitrager(IArbitrage(address(arbitrager)));
    arbitrager.rewardUSC(1234 ether);

    (uint256 totalUscReward, ) = rewardController.epochs(1);
    assertEq(totalUscReward, 1234 ether);
    assertEq(usc.balanceOf(address(rewardController)), 1234 ether);
    assertEq(usc.balanceOf(address(arbitrager)), uscBalanceBefore - 1234 ether);
  }

  function test_RewardUSC_Revert_ZeroAmount() public {
    rewardController.setArbitrager(IArbitrage(address(arbitrager)));
    vm.expectRevert(IRewardController.ZeroAmount.selector);
    arbitrager.rewardUSC(0);
  }

  function test_RewardUSC_Revert_NotArbitrager() public {
    vm.expectRevert(IRewardController.NotArbitrager.selector);
    rewardController.rewardUSC(1234 ether);
  }

  function test_UpdateEpoch() public {
    rewardController.setArbitrager(IArbitrage(address(arbitrager)));
    arbitrager.rewardUSC(1234 ether);

    rewardController.setChiIncentivesForChiLocking(9000 ether);
    rewardController.setChiIncentivesForUscStaking(1000 ether);
    rewardController.setChiIncentivesForUscEthLPStaking(7000 ether);
    rewardController.setChiIncentivesForChiEthLPStaking(8000 ether);

    vm.warp(block.timestamp + 1 weeks);
    vm.mockCall(
      reserveHolderAddr,
      abi.encodeWithSelector(IReserveHolder.getCumulativeRewards.selector),
      abi.encode(1000 ether)
    );
    vm.mockCall(address(uscStaking), abi.encodeWithSelector(IStaking.getStakedChi.selector), abi.encode(1000 ether));
    vm.mockCall(address(chiStaking), abi.encodeWithSelector(IStaking.getStakedChi.selector), abi.encode(2000 ether));
    vm.mockCall(address(chiLocking), abi.encodeWithSelector(IChiLocking.getStakedChi.selector), abi.encode(3000 ether));
    vm.mockCall(address(chiVesting), abi.encodeWithSelector(IChiVesting.getLockedChi.selector), abi.encode(4000 ether));
    vm.mockCall(address(chiLocking), abi.encodeWithSelector(IChiLocking.getLockedChi.selector), abi.encode(5000 ether));

    vm.expectCall(
      address(uscStaking),
      abi.encodeWithSelector(IUSCStaking.updateEpoch.selector, 1000 ether, 1234 ether, 100 ether)
    );
    vm.expectCall(address(chiStaking), abi.encodeWithSelector(IChiStaking.updateEpoch.selector, 200 ether));

    vm.expectCall(address(chiLocking), abi.encodeWithSelector(IChiLocking.updateEpoch.selector, 5000 ether, 300 ether));
    vm.expectCall(address(chiVesting), abi.encodeWithSelector(IChiVesting.updateEpoch.selector, 4000 ether, 400 ether));
    vm.expectCall(address(uscEthLPStaking), abi.encodeWithSelector(ILPStaking.updateEpoch.selector, 7000 ether));
    vm.expectCall(address(chiEthLPStaking), abi.encodeWithSelector(ILPStaking.updateEpoch.selector, 8000 ether));

    rewardController.updateEpoch();

    (uint256 totalUscReward, uint256 reserveHolderTotalRewards) = rewardController.epochs(1);
    assertEq(totalUscReward, 1234 ether);
    assertEq(usc.balanceOf(address(rewardController)), 0);
    assertEq(usc.balanceOf(address(uscStaking)), 1234 ether);
    assertEq(reserveHolderTotalRewards, 1000 ether);
    assertEq(rewardController.currentEpoch(), 2);
  }

  function test_UpdateEpoch_Revert_EpochNotFinished() public {
    vm.warp(block.timestamp + 1 weeks - 1);
    vm.expectRevert(IRewardController.EpochNotFinished.selector);
    rewardController.updateEpoch();
  }

  function test_ClaimStEth() external {
    vm.mockCall(address(uscStaking), abi.encodeWithSelector(IStaking.claimStETH.selector), abi.encode(100 ether));
    vm.mockCall(address(chiStaking), abi.encodeWithSelector(IStaking.claimStETH.selector), abi.encode(200 ether));
    vm.mockCall(address(chiLocking), abi.encodeWithSelector(IStaking.claimStETH.selector), abi.encode(300 ether));
    vm.mockCall(reserveHolderAddr, abi.encodeWithSelector(IReserveHolder.claimRewards.selector), abi.encode(1 ether));

    vm.expectCall(
      reserveHolderAddr,
      abi.encodeWithSelector(IReserveHolder.claimRewards.selector, address(this), 600 ether)
    );
    rewardController.claimStEth();
  }

  function testFuzz_UnclaimedStETHAmount(address account) public {
    vm.mockCall(
      address(uscStaking),
      abi.encodeWithSelector(IStaking.unclaimedStETHAmount.selector, account),
      abi.encode(100 ether)
    );
    vm.mockCall(
      address(chiStaking),
      abi.encodeWithSelector(IStaking.unclaimedStETHAmount.selector, account),
      abi.encode(200 ether)
    );
    vm.mockCall(
      address(chiLocking),
      abi.encodeWithSelector(IStaking.unclaimedStETHAmount.selector, account),
      abi.encode(300 ether)
    );
    vm.mockCall(
      address(chiVesting),
      abi.encodeWithSelector(IStaking.unclaimedStETHAmount.selector, account),
      abi.encode(400 ether)
    );
    vm.mockCall(
      address(uscEthLPStaking),
      abi.encodeWithSelector(IStaking.unclaimedStETHAmount.selector, account),
      abi.encode(500 ether)
    );
    vm.mockCall(
      address(chiEthLPStaking),
      abi.encodeWithSelector(IStaking.unclaimedStETHAmount.selector, account),
      abi.encode(600 ether)
    );

    assertEq(rewardController.unclaimedStETHAmount(account), 2100 ether);
  }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IChiVesting} from "contracts/interfaces/IChiVesting.sol";
import {IPriceFeedAggregator} from "contracts/interfaces/IPriceFeedAggregator.sol";
import {TimeWeightedBonding} from "contracts/sale/TimeWeightedBonding.sol";
import {CHI} from "contracts/tokens/CHI.sol";
import {ExternalContractAddresses} from "contracts/library/ExternalContractAddresses.sol";

contract TimeWeightedBondingTest is Test {
  uint256 public constant TOLERANCE = 0.0001 ether;
  uint256 public constant INITIAL_CHI_SUPPLY = 1000000000 ether;
  uint256 public constant CHI_VESTING_CLIFF_DURATION = 52;
  uint256 public constant EPOCH_DURATION = 1 weeks;
  uint256 public constant CHI_PRICE = 1000 ether;
  uint256 public constant ETH_PRICE = 2000 ether;
  address public constant WETH = ExternalContractAddresses.WETH;

  CHI public chi;
  TimeWeightedBonding public bonding;

  address public chiVesting;
  address public priceFeedAggregator;
  address public treasury;

  address public user;

  function setUp() public {
    priceFeedAggregator = makeAddr("priceFeedAggregator");
    chiVesting = makeAddr("chiVesting");
    treasury = makeAddr("treasury");
    user = makeAddr("user");

    chi = new CHI(INITIAL_CHI_SUPPLY);
    bonding = new TimeWeightedBonding(
      IERC20(address(chi)),
      IPriceFeedAggregator(priceFeedAggregator),
      IChiVesting(chiVesting),
      block.timestamp + CHI_VESTING_CLIFF_DURATION * EPOCH_DURATION,
      treasury
    );

    chi.transfer(address(bonding), INITIAL_CHI_SUPPLY / 3);
    chi.transfer(user, INITIAL_CHI_SUPPLY / 3);

    vm.deal(user, 100000 ether);
  }

  function test_SetUp() public {
    assertEq(address(chi), address(bonding.chi()));
    assertEq(address(priceFeedAggregator), address(bonding.priceFeedAggregator()));
    assertEq(address(chiVesting), address(bonding.chiVesting()));
    assertEq(address(this), bonding.owner());
    assertEq(treasury, bonding.treasury());
  }

  function test_Buy() public {
    vm.mockCall(
      priceFeedAggregator,
      abi.encodeWithSelector(IPriceFeedAggregator.peek.selector, address(chi)),
      abi.encode(CHI_PRICE, 0)
    );
    vm.mockCall(
      priceFeedAggregator,
      abi.encodeWithSelector(IPriceFeedAggregator.peek.selector, WETH),
      abi.encode(ETH_PRICE, 0)
    );
    vm.mockCall(
      chiVesting,
      abi.encodeWithSelector(IChiVesting.cliffDuration.selector),
      abi.encode(CHI_VESTING_CLIFF_DURATION)
    );

    uint256 buyAmount = 100 ether;
    uint256 userEthBalanceBefore = user.balance;
    uint256 chiBondingBalanceBefore = chi.balanceOf(address(bonding));

    vm.startPrank(user);
    chi.approve(address(bonding), buyAmount);

    vm.expectCall(chiVesting, abi.encodeWithSelector(IChiVesting.addVesting.selector, user, buyAmount));
    bonding.buy{value: user.balance}(buyAmount);
    vm.stopPrank();

    uint256 correctPriceInEth = (((buyAmount * CHI_PRICE) / ETH_PRICE) * 3) / 4;
    assertEq(chi.balanceOf(chiVesting), buyAmount);
    assertEq(chi.balanceOf(address(bonding)), chiBondingBalanceBefore - buyAmount);
    assertEq(treasury.balance, correctPriceInEth);
    assertApproxEqRel(user.balance, userEthBalanceBefore - correctPriceInEth, TOLERANCE);

    userEthBalanceBefore = user.balance;
    chiBondingBalanceBefore = chi.balanceOf(address(bonding));
    uint256 treasuryEthBalanceBefore = treasury.balance;

    vm.warp(block.timestamp + (CHI_VESTING_CLIFF_DURATION * EPOCH_DURATION) / 2);
    vm.startPrank(user);
    chi.approve(address(bonding), buyAmount);

    vm.expectCall(chiVesting, abi.encodeWithSelector(IChiVesting.addVesting.selector, user, buyAmount));
    bonding.buy{value: user.balance}(buyAmount);

    correctPriceInEth = (((buyAmount * CHI_PRICE) / ETH_PRICE) * 7) / 8;
    assertEq(chi.balanceOf(chiVesting), 2 * buyAmount);
    assertEq(chi.balanceOf(address(bonding)), chiBondingBalanceBefore - buyAmount);
    assertEq(treasury.balance, treasuryEthBalanceBefore + correctPriceInEth);
    assertApproxEqRel(user.balance, userEthBalanceBefore - correctPriceInEth, TOLERANCE);
  }

  function test_Vest() public {
    vm.mockCall(
      chiVesting,
      abi.encodeWithSelector(IChiVesting.cliffDuration.selector),
      abi.encode(CHI_VESTING_CLIFF_DURATION)
    );

    uint256 vestAmount = 100 ether;
    uint256 vesterBalanceBefore = chi.balanceOf(address(this));

    chi.approve(address(bonding), vestAmount);
    vm.expectCall(chiVesting, abi.encodeWithSelector(IChiVesting.addVesting.selector, user, vestAmount));
    bonding.vest(user, vestAmount);

    assertEq(chi.balanceOf(chiVesting), vestAmount);
    assertEq(chi.balanceOf(address(this)), vesterBalanceBefore - vestAmount);

    vesterBalanceBefore = chi.balanceOf(address(this));
    chi.approve(address(bonding), vestAmount);
    vm.warp(block.timestamp + (CHI_VESTING_CLIFF_DURATION * EPOCH_DURATION) / 2);
    vm.expectCall(chiVesting, abi.encodeWithSelector(IChiVesting.addVesting.selector, user, vestAmount));
    bonding.vest(user, vestAmount);

    assertEq(chi.balanceOf(chiVesting), 2 * vestAmount);
    assertEq(chi.balanceOf(address(this)), vesterBalanceBefore - vestAmount);
  }

  function testFuzz_Vest_Revert_NotOwner(address caller, address onBehalfOf, uint256 amount) public {
    vm.assume(caller != address(this));
    vm.startPrank(caller);
    vm.expectRevert("Ownable: caller is not the owner");
    bonding.vest(onBehalfOf, amount);
    vm.stopPrank();
  }

  function testFuzz_RecoverChi(uint256 amount) public {
    amount = bound(amount, 1, chi.balanceOf(address(bonding)));
    uint256 chiBalanceBefore = chi.balanceOf(address(this));
    uint256 chiBondingBalanceBefore = chi.balanceOf(address(bonding));

    bonding.recoverChi(amount);

    assertEq(chi.balanceOf(address(this)), chiBalanceBefore + amount);
    assertEq(chi.balanceOf(address(bonding)), chiBondingBalanceBefore - amount);
  }

  function testFuzz_RecoverChi_Revert_NotOwner(address caller, uint256 amount) public {
    vm.assume(caller != address(this));
    vm.startPrank(caller);
    vm.expectRevert("Ownable: caller is not the owner");
    bonding.recoverChi(amount);
    vm.stopPrank();
  }
}

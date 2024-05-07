// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IUniswapV2Pair} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import {IPriceFeedAggregator} from "contracts/interfaces/IPriceFeedAggregator.sol";
import {IReserveHolder} from "contracts/interfaces/IReserveHolder.sol";
import {ISTETH} from "contracts/interfaces/ISTETH.sol";
import {UniswapV2Library} from "contracts/uniswap/libraries/UniswapV2Library.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ReserveHolder} from "contracts/ReserveHolder.sol";
import {Owner} from "./Owner.sol";
import {IWETH} from "contracts/interfaces/IWETH.sol";
import {ExternalContractAddresses} from "contracts/library/ExternalContractAddresses.sol";
import "forge-std/console.sol";

contract ReserveHolderTest is Test {
  uint256 public constant ETH_THRESHOLD = 10_00;
  uint256 public constant MAX_THRESHOLD = 100_00;
  uint256 public constant STETH_THRESHOLD = MAX_THRESHOLD - ETH_THRESHOLD;
  uint256 public constant CURVE_STETH_SAFE_GUARD_PERCENTAGE = 10_00;
  uint256 public constant LIDO_STAKE_LIMIT = 120000 ether;
  uint256 public constant UNISWAP_MAX_SWAP = 1500 ether;
  uint256 public constant STETH_FEE_TOLERANCE = 0.001 ether;
  IWETH public constant WETH = IWETH(ExternalContractAddresses.WETH);
  ISTETH public constant stETH = ISTETH(ExternalContractAddresses.stETH);

  address public claimer;
  address public arbitrager;
  address public priceFeedAggregator;
  Owner public owner;
  ReserveHolder public reserveHolder;

  event Deposit(address indexed _account, uint256 _amount);
  event Redeem(address indexed _account, uint256 _amount);

  function setUp() public {
    string memory mainnetRpcUrl = vm.envString("MAINNET_RPC_URL");
    uint256 mainnetFork = vm.createFork(mainnetRpcUrl);
    vm.selectFork(mainnetFork);

    claimer = makeAddr("claimer");
    priceFeedAggregator = makeAddr("priceFeedAggregator");
    arbitrager = makeAddr("arbitrager");

    owner = new Owner();
    address payable reserveHolderAddress = payable(
      owner.deployReserveHolder(priceFeedAggregator, claimer, ETH_THRESHOLD, CURVE_STETH_SAFE_GUARD_PERCENTAGE)
    );
    reserveHolder = ReserveHolder(reserveHolderAddress);

    _getStEthAndWeth();
  }

  function testFork_SetUp() public {
    assertEq(reserveHolder.owner(), address(owner));
    assertEq(address(reserveHolder.priceFeedAggregator()), priceFeedAggregator);
    assertEq(reserveHolder.claimer(), claimer);
    assertEq(reserveHolder.ethThreshold(), 1000);
  }

  function testForkFuzz_SetArbitrager(address newArbitrager, bool status) public {
    owner.setArbitrager(newArbitrager, status);
    assertEq(reserveHolder.isArbitrager(newArbitrager), status);
  }

  function testForkFuzz_SetArbitrager_Revert_NotOwner(address caller, address newArbitrager, bool status) public {
    vm.assume(caller != address(owner));
    vm.expectRevert("Ownable: caller is not the owner");
    reserveHolder.setArbitrager(newArbitrager, status);
  }

  function testForkFuzz_SetClaimer(address newClaimer) public {
    owner.setClaimer(newClaimer);
    assertEq(reserveHolder.claimer(), newClaimer);
  }

  function testForkFuzz_SetClaimer_Revert_NotOwner(address caller, address newClaimer) public {
    vm.assume(caller != address(owner));
    vm.expectRevert("Ownable: caller is not the owner");
    reserveHolder.setClaimer(newClaimer);
  }

  function testForkFuzz_SetSwapEthTolerance(uint256 ethTolerance) public {
    owner.setSwapEthTolerance(ethTolerance);
    assertEq(reserveHolder.swapEthTolerance(), ethTolerance);
  }

  function testForkFuzz_SetSwapEthTolerance_Revert_NotOwner(address caller, uint256 tolerance) public {
    vm.assume(caller != address(owner));
    vm.expectRevert("Ownable: caller is not the owner");
    reserveHolder.setSwapEthTolerance(tolerance);
  }

  function testForkFuzz_SetEthThreshold(uint256 ethThreshold) public {
    ethThreshold = bound(ethThreshold, 0, 10000);
    owner.setEthThreshold(ethThreshold);
    assertEq(reserveHolder.ethThreshold(), ethThreshold);
  }

  function testForkFuzz_SetEthThreshold_Revert_ThresholdTooHigh(uint256 ethThreshold) public {
    ethThreshold = bound(ethThreshold, 10001, type(uint256).max);
    vm.expectRevert(abi.encodeWithSelector(IReserveHolder.ThresholdTooHigh.selector, ethThreshold));
    owner.setEthThreshold(ethThreshold);
  }

  function testForkFuzz_SetEthThreshold_Revert_NotOwner(address caller, uint256 ethThreshold) public {
    vm.assume(caller != address(owner));
    vm.expectRevert("Ownable: caller is not the owner");
    reserveHolder.setEthThreshold(ethThreshold);
  }

  function testForkFuzz_Deposit(uint256 amount) public {
    amount = bound(amount, 1, stETH.balanceOf(address(this)));
    stETH.approve(address(reserveHolder), amount);

    vm.expectEmit(true, true, false, true);
    emit Deposit(address(this), amount);
    reserveHolder.deposit(amount);

    assertEq(reserveHolder.totalStEthDeposited(), stETH.balanceOf(address(reserveHolder)));
    assertApproxEqAbs(stETH.balanceOf(address(reserveHolder)), amount, STETH_FEE_TOLERANCE);
  }

  function testForkFuzz_Deposit_Revert_TransferFailed(uint256 amount) public {
    vm.mockCall(address(reserveHolder.stETH()), abi.encodeWithSelector(stETH.transferFrom.selector), abi.encode(false));
    vm.expectRevert("SafeERC20: ERC20 operation did not succeed");
    reserveHolder.deposit(amount);
  }

  function testForkFuzz_RedeemWithoutSwap(uint256 reserveBalance, uint256 amountToRedeem) public {
    reserveBalance = bound(reserveBalance, 1, type(uint256).max / 2);
    amountToRedeem = bound(amountToRedeem, 1, reserveBalance);
    WETH.transfer(address(reserveHolder), reserveBalance);
    owner.setArbitrager(arbitrager, true);

    vm.startPrank(arbitrager);
    vm.expectEmit(true, true, false, true);
    emit Redeem(arbitrager, amountToRedeem);
    uint256 amountSent = reserveHolder.redeem(amountToRedeem);

    assertEq(WETH.balanceOf(address(reserveHolder)), reserveBalance - amountToRedeem);
    assertEq(WETH.balanceOf(arbitrager), amountToRedeem);
    assertEq(amountSent, amountToRedeem);
  }

  function testForkFuzz_RedeemWithSwap(uint256 extraAmountToRedeem, uint256 reserveBalance) public {
    extraAmountToRedeem = bound(extraAmountToRedeem, 10, UNISWAP_MAX_SWAP - 1 ether);
    reserveBalance = bound(reserveBalance, 1, type(uint256).max / 2 - extraAmountToRedeem - 10);
    WETH.transfer(address(reserveHolder), reserveBalance);
    _deposit(LIDO_STAKE_LIMIT);
    owner.setArbitrager(arbitrager, true);

    vm.startPrank(arbitrager);
    uint256 reserveStEthBefore = stETH.balanceOf(address(reserveHolder));
    uint256 stEthAmountToSwap = (extraAmountToRedeem * 11) / 10;
    uint256 amountSent = reserveHolder.redeem(reserveBalance + extraAmountToRedeem);
    vm.stopPrank();

    assertEq(WETH.balanceOf(arbitrager), reserveBalance + extraAmountToRedeem);
    assertEq(amountSent, reserveBalance + extraAmountToRedeem);
    assertEq(reserveHolder.totalStEthDeposited(), stETH.balanceOf(address(reserveHolder)));
    assertApproxEqAbs(
      stETH.balanceOf(address(reserveHolder)),
      reserveStEthBefore - stEthAmountToSwap,
      STETH_FEE_TOLERANCE
    );
  }

  function testForkFuzz_Rebalance_EthBellowThreshold(uint256 stEthReserveBalance) public {
    stEthReserveBalance = bound(stEthReserveBalance, 1 ether, 1000 ether);
    _deposit(stEthReserveBalance);
    owner.setArbitrager(arbitrager, true);
    uint256 ethAmountToReceive = (stEthReserveBalance * (MAX_THRESHOLD - STETH_THRESHOLD)) / MAX_THRESHOLD;

    vm.startPrank(arbitrager);
    vm.mockCall(
      priceFeedAggregator,
      abi.encodeWithSelector(IPriceFeedAggregator.peek.selector),
      abi.encode(200000000000, 8)
    );
    reserveHolder.rebalance();
    vm.stopPrank();

    assertApproxEqAbs(
      stETH.balanceOf(address(reserveHolder)),
      (stEthReserveBalance * STETH_THRESHOLD) / MAX_THRESHOLD,
      STETH_FEE_TOLERANCE
    );
    assertApproxEqRel(WETH.balanceOf(address(reserveHolder)), ethAmountToReceive, STETH_FEE_TOLERANCE);
    assertEq(stETH.balanceOf(address(reserveHolder)), reserveHolder.totalStEthDeposited());
  }

  function testForkFuzz_Rebalance_EthAboveThreshold(uint256 ethReserveBalance) public {
    ethReserveBalance = bound(ethReserveBalance, 1 ether, 10000 ether);
    WETH.transfer(address(reserveHolder), ethReserveBalance);
    owner.setArbitrager(arbitrager, true);

    vm.startPrank(arbitrager);
    vm.mockCall(
      priceFeedAggregator,
      abi.encodeWithSelector(IPriceFeedAggregator.peek.selector),
      abi.encode(200000000000, 8)
    );
    reserveHolder.rebalance();
    vm.stopPrank();

    assertApproxEqAbs(
      stETH.balanceOf(address(reserveHolder)),
      (ethReserveBalance * STETH_THRESHOLD) / MAX_THRESHOLD,
      STETH_FEE_TOLERANCE
    );
    assertApproxEqAbs(
      WETH.balanceOf(address(reserveHolder)),
      (ethReserveBalance * ETH_THRESHOLD) / MAX_THRESHOLD,
      STETH_FEE_TOLERANCE
    );
    assertEq(stETH.balanceOf(address(reserveHolder)), reserveHolder.totalStEthDeposited());
  }

  function testForkFuzz_Redeem_Revert_NotArbitrager(address caller, uint256 amount) public {
    vm.startPrank(caller);
    vm.expectRevert(abi.encodeWithSelector(IReserveHolder.NotArbitrager.selector, caller));
    reserveHolder.redeem(amount);
    vm.stopPrank();
  }

  function _getStEthAndWeth() private {
    vm.deal(address(this), LIDO_STAKE_LIMIT);
    stETH.submit{value: LIDO_STAKE_LIMIT}(address(this));

    uint256 amount = type(uint256).max / 2;
    vm.deal(address(this), amount);
    WETH.deposit{value: amount}();
  }

  function _deposit(uint256 amount) private {
    stETH.approve(address(reserveHolder), amount);
    reserveHolder.deposit(amount);
  }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {Test} from "forge-std/Test.sol";
import {IUniswapV2Factory} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IUniswapV2Pair} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import {IPriceFeedAggregator} from "contracts/interfaces/IPriceFeedAggregator.sol";
import {IArbitrageERC20} from "contracts/interfaces/IArbitrageERC20.sol";
import {IReserveHolder} from "contracts/interfaces/IReserveHolder.sol";
import {IUSCStaking} from "contracts/interfaces/IUSCStaking.sol";
import {IChiStaking} from "contracts/interfaces/IChiStaking.sol";
import {IChiLocking} from "contracts/interfaces/IChiLocking.sol";
import {IChiVesting} from "contracts/interfaces/IChiVesting.sol";
import {IWETH} from "contracts/interfaces/IWETH.sol";
import {ArbitrageV3} from "contracts/ArbitrageV3.sol";
import {ReserveHolder} from "contracts/ReserveHolder.sol";
import {USC} from "contracts/tokens/USC.sol";
import {CHI} from "contracts/tokens/CHI.sol";
import {MockPriceFeedAggregator} from "contracts/mock/MockPriceFeedAggregator.sol";
import {UniswapV2Library} from "contracts/uniswap/libraries/UniswapV2Library.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IArbitrageV3} from "contracts/interfaces/IArbitrageV3.sol";
import {IArbitrageV2} from "contracts/interfaces/IArbitrageV2.sol";
import {IArbitrage} from "contracts/interfaces/IArbitrage.sol";
import {RewardController, IRewardController} from "contracts/staking/RewardController.sol";
import {IBurnableERC20} from "contracts/interfaces/IBurnableERC20.sol";
import {ISTETH} from "contracts/interfaces/ISTETH.sol";
import {ILPStaking} from "contracts/interfaces/ILPStaking.sol";
import {ExternalContractAddresses} from "contracts/library/ExternalContractAddresses.sol";
import "forge-std/console.sol";

contract ArbitrageTest is Test {
  uint256 public constant BASE_PRICE = 10 ** 8;

  uint256 public constant RESERVE_ETH_THRESHOLD = 10_00;
  uint256 public constant RESERVE_CURVE_SAFE_GUARD_PERCENTAGE = 10_00;
  uint256 public constant CHI_EMISSION_PER_SECOND = 1 ether;
  uint256 public constant INITIAL_ETH_LIQUIDITY = 10 ether;
  uint256 public constant INITIAL_SUPPLY = 1000000 ether;
  uint256 public constant INITIAL_CHI_AMOUNT = INITIAL_SUPPLY * 10;
  address public constant WETH = ExternalContractAddresses.WETH;
  ISTETH public constant STETH = ISTETH(ExternalContractAddresses.stETH);
  IUniswapV2Factory public constant UNISWAP_V2_FACTORY =
    IUniswapV2Factory(ExternalContractAddresses.UNI_V2_POOL_FACTORY);
  IUniswapV2Router02 public constant UNISWAP_V2_ROUTER =
    IUniswapV2Router02(ExternalContractAddresses.UNI_V2_SWAP_ROUTER);

  uint256 public constant INITIAL_USC_ETH_PRICE = 1500;
  uint256 public constant INITIAL_CHI_ETH_PRICE = 3000;

  // max price diff on mint allowed 0.007$
  uint256 public constant MAX_MINT_DIFF = 7 * 1e5;

  // Mint and burn fees in percents, 0.3%
  uint16 public constant MINT_FEE = 30;
  uint16 public constant BURN_FEE = 30;

  // acceptable difference in usd values
  uint256 public constant USD_EPS = 10 wei;

  IUniswapV2Pair public uscEthPair;
  IUniswapV2Pair public chiEthPair;

  USC public usc;
  CHI public chi;
  RewardController public rewardController;
  ReserveHolder public reserveHolder;
  MockPriceFeedAggregator public priceFeedAggregator;
  ArbitrageV3 public arbitrage;

  address public uscStakingAddress;

  event ExecuteArbitrage(
    address indexed account,
    uint256 indexed arbNum,
    uint256 deltaUsd,
    uint256 reserveDiff,
    uint256 ethPrice,
    uint256 rewardValue
  );

  receive() external payable {}

  function setUp() public {
    string memory mainnetRpcUrl = vm.envString("MAINNET_RPC_URL");
    uint256 mainnetFork = vm.createFork(mainnetRpcUrl);
    vm.selectFork(mainnetFork);

    deal(address(this), 5000 ether);
    IWETH(WETH).deposit{value: 2000 ether}();

    usc = new USC();
    chi = new CHI(INITIAL_CHI_AMOUNT);

    usc.updateMinter(address(this), true);
    usc.mint(address(this), INITIAL_SUPPLY);

    _deployPoolsAndAddLiquidity();

    uscStakingAddress = makeAddr("uscStaking");

    rewardController = new RewardController();
    rewardController.initialize(
      chi,
      usc,
      reserveHolder,
      // addresses of staking/locking/vesting contracts are not needed in arbitrage tests
      IUSCStaking(uscStakingAddress),
      IChiStaking(address(0)),
      IChiLocking(address(0)),
      IChiVesting(address(0)),
      ILPStaking(address(0)),
      ILPStaking(address(0)),
      block.timestamp
    );

    _setupMockPriceFeedAggreagtor(
      INITIAL_USC_ETH_PRICE * 1e8,
      1e8,
      (INITIAL_USC_ETH_PRICE * 1e8) / INITIAL_CHI_ETH_PRICE,
      INITIAL_USC_ETH_PRICE * 1e8
    );

    reserveHolder = new ReserveHolder();
    reserveHolder.initialize(
      IPriceFeedAggregator(address(priceFeedAggregator)),
      address(this),
      RESERVE_ETH_THRESHOLD,
      RESERVE_CURVE_SAFE_GUARD_PERCENTAGE
    );

    arbitrage = new ArbitrageV3(
      IArbitrageERC20(address(usc)),
      IArbitrageERC20(address(chi)),
      IRewardController(address(rewardController)),
      IPriceFeedAggregator(address(priceFeedAggregator)),
      IReserveHolder(address(reserveHolder))
    );

    // twap vs spot max tolerance %
    arbitrage.setPriceTolerance(50_00);

    // chi twap vs spot price tolerance %
    arbitrage.setChiPriceTolerance(1_00);

    // max mint diff allowed on 5
    arbitrage.setMaxMintBurnPriceDiff(MAX_MINT_DIFF);

    // max burn reserve diff allowed on 1%
    arbitrage.setMaxMintBurnReserveTolerance(1_00); // 1%

    // mint and burn fees
    arbitrage.setMintBurnFee(MINT_FEE);
    arbitrage.updateArbitrager(address(this), true);

    usc.updateMinter(address(arbitrage), true);
    usc.updateMinter(address(rewardController), true);

    chi.updateMinter(address(arbitrage), true);

    rewardController.setArbitrager(IArbitrage(address(arbitrage)));
    reserveHolder.setArbitrager(address(arbitrage), true);
  }

  function testFuzz_SetPegPriceToleranceAbs(uint256 tolerance) public {
    arbitrage.setPegPriceToleranceAbs(tolerance);
    assertEq(arbitrage.pegPriceToleranceAbs(), tolerance);
  }

  function testFuzz_SetPegPriceToleranceAbs_RevertNotOwner(address caller, uint256 tolerance) public {
    vm.assume(caller != address(this));
    vm.startPrank(caller);
    vm.expectRevert("Ownable: caller is not the owner");
    arbitrage.setPegPriceToleranceAbs(tolerance);
    vm.stopPrank();
  }

  function testFuzz_SetPriceTolerance(uint16 tolerance) public {
    tolerance = uint16(bound(uint256(tolerance), 0, uint256(arbitrage.MAX_PRICE_TOLERANCE())));
    arbitrage.setPriceTolerance(tolerance);
    assertEq(arbitrage.priceTolerance(), tolerance);
  }

  function testFuzz_SetPriceTolerance_RevertToleranceTooBig(uint16 tolerance) public {
    vm.assume(tolerance > arbitrage.MAX_PRICE_TOLERANCE());
    vm.expectRevert(abi.encodeWithSelector(IArbitrage.ToleranceTooBig.selector, tolerance));
    arbitrage.setPriceTolerance(tolerance);
  }

  function testFuzz_SetPriceTolerance_RevertNotOwner(address caller, uint16 tolerance) public {
    vm.assume(caller != address(this));
    vm.startPrank(caller);
    vm.expectRevert("Ownable: caller is not the owner");
    arbitrage.setPriceTolerance(tolerance);
    vm.stopPrank();
  }

  function testFuzz_SetChiPriceTolerance(uint16 tolerance) public {
    tolerance = uint16(bound(uint256(tolerance), 0, uint256(arbitrage.MAX_PRICE_TOLERANCE())));
    arbitrage.setChiPriceTolerance(tolerance);
    assertEq(arbitrage.chiPriceTolerance(), tolerance);
  }

  function testFuzz_SetChiPriceTolerance_RevertToleranceTooBig(uint16 tolerance) public {
    vm.assume(tolerance > arbitrage.MAX_PRICE_TOLERANCE());
    vm.expectRevert(abi.encodeWithSelector(IArbitrage.ToleranceTooBig.selector, tolerance));
    arbitrage.setChiPriceTolerance(tolerance);
  }

  function testFuzz_SetChiPriceTolerance_RevertNotOwner(address caller, uint16 tolerance) public {
    vm.assume(caller != address(this));
    vm.startPrank(caller);
    vm.expectRevert("Ownable: caller is not the owner");
    arbitrage.setChiPriceTolerance(tolerance);
    vm.stopPrank();
  }

  function testFuzz_SetMaxMintBurnPriceDiff(uint256 priceDiff) public {
    arbitrage.setMaxMintBurnPriceDiff(priceDiff);
    assertEq(arbitrage.maxMintBurnPriceDiff(), priceDiff);
  }

  function testFuzz_SetMaxMintBurnPriceDiff_RevertNotOwner(address caller, uint256 priceDiff) public {
    vm.assume(caller != address(this));
    vm.startPrank(caller);
    vm.expectRevert("Ownable: caller is not the owner");
    arbitrage.setMaxMintBurnPriceDiff(priceDiff);
    vm.stopPrank();
  }

  function testFuzz_SetMaxMintBurnReserveTolerance(uint16 tolerance) public {
    tolerance = uint16(bound(uint256(tolerance), 0, uint256(arbitrage.MAX_PRICE_TOLERANCE())));
    arbitrage.setMaxMintBurnReserveTolerance(tolerance);
    assertEq(arbitrage.maxMintBurnReserveTolerance(), tolerance);
  }

  function testFuzz_SetMaxMintBurnReserveTolerance_RevertToleranceTooBig(uint16 tolerance) public {
    vm.assume(tolerance > arbitrage.MAX_PRICE_TOLERANCE());
    vm.expectRevert(abi.encodeWithSelector(IArbitrage.ToleranceTooBig.selector, tolerance));
    arbitrage.setMaxMintBurnReserveTolerance(tolerance);
  }

  function testFuzz_SetMaxMintBurnReserveTolerance_RevertNotOwner(address caller, uint16 tolerance) public {
    vm.assume(caller != address(this));
    vm.startPrank(caller);
    vm.expectRevert("Ownable: caller is not the owner");
    arbitrage.setMaxMintBurnReserveTolerance(tolerance);
    vm.stopPrank();
  }

  function testFuzz_UpdateArbitrager(address account, bool status) public {
    arbitrage.updateArbitrager(account, status);
    assertEq(arbitrage.isArbitrager(account), status);
  }

  function testFuzz_UpdateArbitrager_RevertNotOwner(address caller, address account, bool status) public {
    vm.assume(caller != address(this));
    vm.startPrank(caller);
    vm.expectRevert("Ownable: caller is not the owner");
    arbitrage.updateArbitrager(account, status);
    vm.stopPrank();
  }

  function testFuzz_UpdatePrivileged(address account, bool status) public {
    arbitrage.updatePrivileged(account, status);
    assertEq(arbitrage.isPrivileged(account), status);
  }

  function testFuzz_UpdatePrivileged_RevertNotOwner(address caller, address account, bool status) public {
    vm.assume(caller != address(this));
    vm.startPrank(caller);
    vm.expectRevert("Ownable: caller is not the owner");
    arbitrage.updatePrivileged(account, status);
    vm.stopPrank();
  }

  function testFuzz_SetMintBurnFee(uint16 fee) public {
    fee = uint16(bound(uint256(fee), 0, uint256(arbitrage.MAX_FEE())));
    arbitrage.setMintBurnFee(fee);
    assertEq(arbitrage.mintBurnFee(), fee);
  }

  function testFuzz_SetMintBurnFee_RevertFeeTooBig(uint16 fee) public {
    vm.assume(fee > arbitrage.MAX_FEE());
    vm.expectRevert(abi.encodeWithSelector(IArbitrageV3.FeeTooBig.selector, fee));
    arbitrage.setMintBurnFee(fee);
  }

  function testFuzz_SetMintBurnFee_RevertNotOwner(address caller, uint16 fee) public {
    vm.assume(caller != address(this));
    vm.startPrank(caller);
    vm.expectRevert("Ownable: caller is not the owner");
    arbitrage.setMintBurnFee(fee);
    vm.stopPrank();
  }

  function test_MintPause() public {
    arbitrage.setMintPause(true);
    assertTrue(arbitrage.mintPaused());

    vm.expectRevert(IArbitrageV3.ContractIsPaused.selector);
    arbitrage.mint{value: 1 ether}();
  }

  function test_SetBurnPause() public {
    arbitrage.setBurnPause(true);
    assertTrue(arbitrage.burnPaused());
  }

  // tests minting with various usc prices, reserve diffs, and eth prices
  // tokenId is:  0 - ETH,  1 - WETH,  2 - stETH
  function testFuzz_Mint(
    uint256 uscDexPriceBefore,
    uint256 ethPriceBefore,
    uint256 ethAmountMul,
    uint256 tokenId
  ) public {
    uint256 ethAmount;
    (uscDexPriceBefore, ethPriceBefore, ethAmount, tokenId) = _prepareStateForMint(
      uscDexPriceBefore,
      ethPriceBefore,
      ethAmountMul,
      tokenId
    );

    address alice = makeAddr("alice");
    deal(alice, 10 * ethAmount);
    vm.startPrank(alice);

    address token;
    uint256 tokenPrice;
    uint256 callerBalanceBefore = alice.balance;
    uint256 callerBalanceAfter;
    uint256 reserveHolderBalanceBefore;
    uint256 reserveHolderBalanceAfter;

    if (tokenId == 0) {
      callerBalanceBefore = alice.balance;
      reserveHolderBalanceBefore = IERC20(WETH).balanceOf(address(reserveHolder));

      arbitrage.mint{value: ethAmount}();

      token = WETH;
      tokenPrice = priceFeedAggregator.peek(WETH);

      callerBalanceAfter = alice.balance;
      reserveHolderBalanceAfter = IERC20(WETH).balanceOf(address(reserveHolder));
    } else if (tokenId == 1) {
      IWETH(WETH).deposit{value: ethAmount}();
      callerBalanceBefore = IERC20(WETH).balanceOf(alice);
      reserveHolderBalanceBefore = IERC20(WETH).balanceOf(address(reserveHolder));

      IERC20(WETH).approve(address(arbitrage), ethAmount);
      arbitrage.mintWithWETH(ethAmount);

      token = WETH;
      tokenPrice = priceFeedAggregator.peek(WETH);

      callerBalanceAfter = IERC20(WETH).balanceOf(alice);
      reserveHolderBalanceAfter = IERC20(WETH).balanceOf(address(reserveHolder));
    } else if (tokenId == 2) {
      STETH.submit{value: ethAmount}(alice);
      ethAmount = STETH.balanceOf(alice);
      callerBalanceBefore = STETH.balanceOf(alice);
      reserveHolderBalanceBefore = STETH.balanceOf(address(reserveHolder));

      IERC20(address(STETH)).approve(address(arbitrage), ethAmount);
      arbitrage.mintWithStETH(ethAmount);

      token = address(STETH);
      tokenPrice = priceFeedAggregator.peek(address(STETH));

      callerBalanceAfter = STETH.balanceOf(alice);
      reserveHolderBalanceAfter = STETH.balanceOf(address(reserveHolder));
    }

    vm.stopPrank();

    uint256 expectedUSC = Math.mulDiv(tokenPrice, ethAmount, BASE_PRICE);
    uint256 expectedFee = Math.mulDiv(ethAmount, arbitrage.mintBurnFee(), arbitrage.MAX_FEE());
    expectedUSC = Math.mulDiv(expectedUSC, arbitrage.MAX_FEE() - arbitrage.mintBurnFee(), arbitrage.MAX_FEE());

    assertEq(IERC20(address(usc)).balanceOf(alice), expectedUSC);
    assertEq(IERC20(token).balanceOf(address(arbitrage)), expectedFee);
    assertEq(reserveHolderBalanceAfter, reserveHolderBalanceBefore + ethAmount - expectedFee);
    assertApproxEqAbs(callerBalanceAfter, callerBalanceBefore - ethAmount, 9 wei);
  }

  function testFuzz_Mint_RevertUscPriceNotPegged(
    uint256 extraPriceDiff,
    uint256 ethAmount,
    uint256 tokenId,
    bool upOrDown
  ) public {
    extraPriceDiff = bound(extraPriceDiff, arbitrage.maxMintBurnPriceDiff() + 2, arbitrage.maxMintBurnPriceDiff() * 2);
    ethAmount = bound(ethAmount, 1000, 10_000 ether);
    tokenId = bound(tokenId, 0, 2);

    upOrDown
      ? _uscPriceDexMoveUp(arbitrage.USC_TARGET_PRICE() + extraPriceDiff)
      : _uscPriceDexMoveDown(arbitrage.USC_TARGET_PRICE() - extraPriceDiff);

    address alice = makeAddr("alice");
    deal(alice, 2 * ethAmount);

    vm.startPrank(alice);

    vm.expectRevert(IArbitrageV2.PriceIsNotPegged.selector);
    arbitrage.mint{value: ethAmount}();

    vm.expectRevert(IArbitrageV2.PriceIsNotPegged.selector);
    arbitrage.mintWithWETH(ethAmount);

    vm.expectRevert(IArbitrageV2.PriceIsNotPegged.selector);
    arbitrage.mintWithStETH(ethAmount);

    vm.stopPrank();
  }

  function testFuzz_Mint_RevertReserveDiffTooBig(uint256 ethAmount, uint256 reserveDiff, uint256 tokenId) public {
    ethAmount = bound(ethAmount, 1000, 10_000 ether);
    reserveDiff = bound(reserveDiff, 1, 10 ether);
    tokenId = bound(tokenId, 0, 2);

    _moveReserveDiffTo(int256(usc.totalSupply() / (10 ** 10 * 99) + reserveDiff)); // x = (r + x) / 100

    address alice = makeAddr("alice");
    deal(alice, 2 * ethAmount);

    vm.startPrank(alice);

    vm.expectRevert(IArbitrageV3.ReserveDiffTooBig.selector);
    arbitrage.mint{value: ethAmount}();

    vm.expectRevert(IArbitrageV3.ReserveDiffTooBig.selector);
    arbitrage.mintWithWETH(ethAmount);

    vm.expectRevert(IArbitrageV3.ReserveDiffTooBig.selector);
    arbitrage.mintWithStETH(ethAmount);

    vm.stopPrank();
  }

  function testFuzz_Burn(uint256 amount) public {
    amount = bound(amount, 1e18, usc.balanceOf(address(this)));

    _moveReserveDiffTo(0);

    uint256 uscTotalSupplyBefore = usc.totalSupply();
    uint256 uscBalanceBefore = usc.balanceOf(address(this));
    uint256 wethBalanceBefore = IERC20(WETH).balanceOf(address(this));
    uint256 wethReserveHolderBalanceBefore = IERC20(WETH).balanceOf(address(reserveHolder));
    uint256 fee = Math.mulDiv(amount, arbitrage.mintBurnFee(), arbitrage.MAX_FEE());

    usc.approve(address(arbitrage), amount);
    arbitrage.burn(amount);

    uint256 wethPrice = priceFeedAggregator.peek(WETH);
    uint256 expectedEth = Math.mulDiv(BASE_PRICE, amount - fee, wethPrice);

    assertEq(usc.balanceOf(address(this)), uscBalanceBefore - amount);
    assertEq(usc.totalSupply(), uscTotalSupplyBefore - amount + fee);
    assertEq(usc.balanceOf(address(arbitrage)), fee);
    assertEq(IERC20(WETH).balanceOf(address(this)), wethBalanceBefore + expectedEth);
    assertEq(IERC20(WETH).balanceOf(address(reserveHolder)), wethReserveHolderBalanceBefore - expectedEth);
  }

  function testFuzz_CalculateDeltaUSC(uint256 ethAmount) public {
    vm.assume(ethAmount > 0.1 ether);
    vm.assume(ethAmount < INITIAL_ETH_LIQUIDITY / 2);

    IWETH(WETH).deposit{value: ethAmount}();
    uint256 ethPrice = priceFeedAggregator.peek(WETH);

    // move price of USC up
    _swap(WETH, address(usc), ethAmount);
    uint256 uscSpotPrice = _calculateUscSpotPrice(ethPrice);

    // calc delta and see if it is at 1$ after swap
    uint256 deltaUSC = arbitrage._calculateDeltaUSC(ethPrice);
    _swap(address(usc), WETH, deltaUSC);
    uscSpotPrice = _calculateUscSpotPrice(ethPrice);

    assertApproxEqAbs(uscSpotPrice, arbitrage.USC_TARGET_PRICE(), USD_EPS);
  }

  function testFuzz_CalculateDeltaETH(uint256 uscAmount) public {
    vm.assume(uscAmount > 1 ether);
    vm.assume(uscAmount < INITIAL_USC_ETH_PRICE * (INITIAL_ETH_LIQUIDITY / 2));

    uint256 ethPrice = priceFeedAggregator.peek(WETH);

    // move price of USC down
    _swap(address(usc), WETH, uscAmount);
    uint256 uscSpotPrice = _calculateUscSpotPrice(ethPrice);

    uint256 deltaETH = arbitrage._calculateDeltaETH(ethPrice);
    _swap(WETH, address(usc), deltaETH);
    uscSpotPrice = _calculateUscSpotPrice(ethPrice);

    assertApproxEqAbs(uscSpotPrice, arbitrage.USC_TARGET_PRICE(), USD_EPS);
  }

  function test_ExecuteArbitrage_RevertChiPriceNotPegged(uint16 chiSpotPriceTolerance) public {
    uint16 maxPriceTolerance = arbitrage.MAX_PRICE_TOLERANCE();
    chiSpotPriceTolerance = uint16(bound(chiSpotPriceTolerance, 2, maxPriceTolerance));

    _moveReserveDiffTo(0);

    uint256 ethPrice = priceFeedAggregator.peek(WETH);
    uint256 chiSpotPrice = _calculateChiSpotPrice(ethPrice);

    uint256 difference = (chiSpotPrice * chiSpotPriceTolerance) / (maxPriceTolerance - chiSpotPriceTolerance);
    uint256 chiTwapPrice = chiSpotPrice + difference + 1;

    priceFeedAggregator.setMockPrice(address(chi), chiTwapPrice);
    arbitrage.setChiPriceTolerance(chiSpotPriceTolerance);

    vm.expectRevert(abi.encodeWithSelector(IArbitrageV3.ChiPriceNotPegged.selector, chiSpotPrice, chiTwapPrice));
    arbitrage.executeArbitrage(0);

    difference = (chiSpotPrice * chiSpotPriceTolerance) / maxPriceTolerance;
    chiTwapPrice = chiSpotPrice - difference - 1;
    priceFeedAggregator.setMockPrice(address(chi), chiTwapPrice);

    vm.expectRevert(abi.encodeWithSelector(IArbitrageV3.ChiPriceNotPegged.selector, chiSpotPrice, chiTwapPrice));
    arbitrage.executeArbitrage(0);
  }

  function testFuzz_ExecuteArbitrage_RevertChiSpotPriceTooBig(uint256 chiSpotPriceDifference) public {
    uint256 chiSpotPrice = _calculateChiSpotPrice(priceFeedAggregator.peek(WETH));
    chiSpotPriceDifference = bound(chiSpotPriceDifference, 1, chiSpotPrice - 1);

    vm.expectRevert(IArbitrageV3.ChiSpotPriceTooBig.selector);
    arbitrage.executeArbitrage(chiSpotPrice - chiSpotPriceDifference);
  }

  function testFuzz_ExecuteArbitrage_PrivilegedSpotPriceTooBig(uint256 chiSpotPriceDifference) public {
    uint256 chiSpotPrice = _calculateChiSpotPrice(priceFeedAggregator.peek(WETH));
    chiSpotPriceDifference = bound(chiSpotPriceDifference, 1, chiSpotPrice - 1);

    arbitrage.updatePrivileged(address(this), true);
    test_ExecuteArbitrage_Arbitrage1_BigDelta();
  }

  // usc > 1$, excess reserves, delta > reserveDiff
  function test_ExecuteArbitrage_Arbitrage1_BigDelta() public {
    // usc = 1.253$
    _uscPriceDexMoveUp(Math.mulDiv(BASE_PRICE, 1253, 1000));

    int256 targetDiff = int256(1000 * BASE_PRICE);
    _moveReserveDiffTo(targetDiff);

    _checkReservesAndDeltaValue(true, true, true);

    _runAndCheckArbitrage(1);
  }

  // usc > 1$, excess reserves, delta < reserveDiff
  function test_ExecuteAribtrage_Arbitrage1_SmallDelta() public {
    // usc = 1.032$
    _uscPriceDexMoveUp(Math.mulDiv(BASE_PRICE, 1032, 1000));

    int256 targetDiff = int256(1000 * BASE_PRICE);
    _moveReserveDiffTo(targetDiff);

    _checkReservesAndDeltaValue(true, false, true);

    _runAndCheckArbitrage(1);
  }

  // usc > 1$, deficit reserves
  function test_ExecuteArbitrage_Arbitrage2() public {
    // usc = 1.032$
    _uscPriceDexMoveUp(Math.mulDiv(BASE_PRICE, 1032, 1000));

    int256 targetDiff = -1000 * int256(BASE_PRICE);
    _moveReserveDiffTo(targetDiff);

    (bool isExcessOfReserves, , ) = arbitrage._getReservesData();
    assertEq(isExcessOfReserves, false);

    _runAndCheckArbitrage(2);
  }

  // usc < 1$, excess reserves, delta > reserveDiff
  function test_ExecuteArbitrage_Arbitrage3_BigDelta() public {
    // usc = 0.835$
    _uscPriceDexMoveDown(Math.mulDiv(BASE_PRICE, 835, 1000));

    int256 targetDiff = int256(1000 * BASE_PRICE);
    _moveReserveDiffTo(targetDiff);

    _checkReservesAndDeltaValue(true, true, false);

    _runAndCheckArbitrage(3);
  }

  // usc < 1$, excess reserves, delta < reserveDiff
  function test_ExecuteArbitrage_Arbitrage3_SmallDelta() public {
    // usc = 0.983$
    _uscPriceDexMoveDown(Math.mulDiv(BASE_PRICE, 983, 1000));

    int256 targetDiff = int256(1000 * BASE_PRICE);
    _moveReserveDiffTo(targetDiff);

    _checkReservesAndDeltaValue(true, false, false);

    _runAndCheckArbitrage(3);
  }

  // usc < 1$, deficit reserves, delta > reserveDiff
  function test_ExecuteArbitrage_Arbitrage4_BigDelta() public {
    // usc = 0.835$
    _uscPriceDexMoveDown(Math.mulDiv(BASE_PRICE, 835, 1000));

    int256 targetDiff = -1000 * int256(BASE_PRICE);
    _moveReserveDiffTo(targetDiff);

    _checkReservesAndDeltaValue(false, true, false);

    _runAndCheckArbitrage(4);
  }

  // usc < 1$, deficit reserves, delta < reserveDiff
  function test_ExecuteArbitrage_Arbitrage4_SmallDelta() public {
    // usc = 0.983$
    _uscPriceDexMoveDown(Math.mulDiv(BASE_PRICE, 983, 1000));

    int256 targetDiff = -1000 * int256(BASE_PRICE);
    _moveReserveDiffTo(targetDiff);

    _checkReservesAndDeltaValue(false, false, false);

    _runAndCheckArbitrage(4);
  }

  // usc = 1$, deficit reserves
  function test_ExecuteArbitrage_Arbitrage5() public {
    int256 targetDiff = 1000 * int256(BASE_PRICE);
    _moveReserveDiffTo(targetDiff);

    _runAndCheckArbitrage(5);
  }

  // usc = 1$, excess reserves
  function test_ExecuteArbitrage_Arbitrage6() public {
    int256 targetDiff = -1000 * int256(BASE_PRICE);
    _moveReserveDiffTo(targetDiff);

    _runAndCheckArbitrage(6);
  }

  function _prepareStateForMint(
    uint256 uscDexPriceBefore,
    uint256 ethPriceBefore,
    uint256 ethAmountMul,
    uint256 tokenId
  ) internal returns (uint256, uint256, uint256, uint256) {
    uscDexPriceBefore = Math.mulDiv(BASE_PRICE, bound(uscDexPriceBefore, 997, 1003), 1000);
    ethPriceBefore = bound(ethPriceBefore, 1000, 2000) * BASE_PRICE;
    tokenId = bound(tokenId, 0, 1);
    uint256 ethAmount = 0.001 ether * bound(ethAmountMul, 1, 1000);

    priceFeedAggregator.setMockPrice(WETH, ethPriceBefore);
    uint256 uscSpotPrice = _calculateUscSpotPrice(ethPriceBefore);

    if (uscDexPriceBefore < uscSpotPrice) {
      _uscPriceDexMoveDown(uscDexPriceBefore);
    } else if (uscDexPriceBefore > uscSpotPrice) {
      _uscPriceDexMoveUp(uscDexPriceBefore);
    }

    _moveReserveDiffTo(0);

    return (uscDexPriceBefore, ethPriceBefore, ethAmount, tokenId);
  }

  function _deployPoolsAndAddLiquidity() private {
    uscEthPair = IUniswapV2Pair(UNISWAP_V2_FACTORY.createPair(address(usc), WETH));
    chiEthPair = IUniswapV2Pair(UNISWAP_V2_FACTORY.createPair(address(chi), WETH));
    usc.approve(address(UNISWAP_V2_ROUTER), type(uint256).max);
    chi.approve(address(UNISWAP_V2_ROUTER), type(uint256).max);
    IERC20(WETH).approve(address(UNISWAP_V2_ROUTER), type(uint256).max);

    uint256 a;
    uint256 b;
    uint256 l;

    (a, b, l) = UNISWAP_V2_ROUTER.addLiquidity(
      address(usc),
      WETH,
      INITIAL_USC_ETH_PRICE * INITIAL_ETH_LIQUIDITY,
      INITIAL_ETH_LIQUIDITY,
      0,
      0,
      address(this),
      block.timestamp
    );

    (a, b, l) = UNISWAP_V2_ROUTER.addLiquidity(
      address(chi),
      WETH,
      10 * INITIAL_CHI_ETH_PRICE * INITIAL_ETH_LIQUIDITY,
      10 * INITIAL_ETH_LIQUIDITY,
      0,
      0,
      address(this),
      block.timestamp
    );
  }

  function _setupMockPriceFeedAggreagtor(
    uint256 wethPrice,
    uint256 uscPrice,
    uint256 chiPrice,
    uint256 stETHPrice
  ) internal {
    priceFeedAggregator = new MockPriceFeedAggregator();
    priceFeedAggregator.setMockPrice(WETH, wethPrice);
    priceFeedAggregator.setMockPrice(address(usc), uscPrice);
    priceFeedAggregator.setMockPrice(address(chi), chiPrice);
    priceFeedAggregator.setMockPrice(address(STETH), stETHPrice);
  }

  function _calculateUscSpotPrice(uint256 ethPrice) private view returns (uint256) {
    (uint256 reserveUSC, uint256 reserveWETH) = UniswapV2Library.getReserves(
      address(UNISWAP_V2_FACTORY),
      address(usc),
      WETH
    );
    uint256 uscFor1ETH = UniswapV2Library.quote(1 ether, reserveWETH, reserveUSC);
    return Math.mulDiv(ethPrice, 1 ether, uscFor1ETH);
  }

  function _calculateChiSpotPrice(uint256 ethPrice) private view returns (uint256) {
    (uint256 reserveCHI, uint256 reserveWETH) = UniswapV2Library.getReserves(
      address(UNISWAP_V2_FACTORY),
      address(chi),
      WETH
    );
    uint256 chiFor1ETH = UniswapV2Library.quote(1 ether, reserveWETH, reserveCHI);
    return Math.mulDiv(ethPrice, 1 ether, chiFor1ETH);
  }

  function _convertUsdValueToTokenAmount(uint256 usdValue, uint256 price) internal pure returns (uint256) {
    return Math.mulDiv(usdValue, 1e18, price);
  }

  function _convertTokenAmountToUsdValue(uint256 amount, uint256 price) internal pure returns (uint256) {
    return Math.mulDiv(amount, price, 1e18);
  }

  function _makePath(address t1, address t2) internal pure returns (address[] memory path) {
    path = new address[](2);
    path[0] = t1;
    path[1] = t2;
  }

  function _makePath(address t1, address t2, address t3) internal pure returns (address[] memory path) {
    path = new address[](3);
    path[0] = t1;
    path[1] = t2;
    path[2] = t3;
  }

  function _swap(address tokenIn, address tokenOut, uint256 amount) private returns (uint256) {
    address[] memory path;

    if (tokenIn != WETH && tokenOut != WETH) {
      path = _makePath(tokenIn, WETH, tokenOut);
    } else {
      path = _makePath(tokenIn, tokenOut);
    }

    IERC20(tokenIn).approve(address(UNISWAP_V2_ROUTER), amount);
    uint256[] memory amounts = UNISWAP_V2_ROUTER.swapExactTokensForTokens(
      amount,
      0,
      path,
      address(this),
      block.timestamp
    );

    uint256 amountReceived = amounts[path.length - 1];

    return amountReceived;
  }

  // bool deltaUSC - true if we are checking deltaUSC, false if we are checking deltaETH
  function _checkReservesAndDeltaValue(bool excessReserves, bool deltaBigger, bool deltaUSC) internal {
    (bool isExcessOfReserves, uint256 reserveDiff, ) = arbitrage._getReservesData();
    assertEq(isExcessOfReserves, excessReserves);

    uint256 ethPrice = priceFeedAggregator.peek(WETH);
    uint256 deltaValue;
    if (deltaUSC) {
      deltaValue = _convertTokenAmountToUsdValue(arbitrage._calculateDeltaUSC(ethPrice), BASE_PRICE);
    } else {
      deltaValue = _convertTokenAmountToUsdValue(arbitrage._calculateDeltaETH(ethPrice), ethPrice);
    }

    if (deltaBigger) {
      assert(deltaValue > reserveDiff);
    } else {
      assert(deltaValue < reserveDiff);
    }
  }

  function _checkUSCSpotPrice(uint256 targetPrice) internal {
    uint256 ethPrice = priceFeedAggregator.peek(WETH);
    uint256 uscSpotPrice = _calculateUscSpotPrice(ethPrice);
    assertApproxEqAbs(uscSpotPrice, targetPrice, USD_EPS);
  }

  function _runAndCheckArbitrage(uint256 expectedArbitrageNum) internal {
    (, uint256 reserveDiffBefore, ) = arbitrage._getReservesData();

    vm.expectEmit(false, true, false, false);
    emit ExecuteArbitrage(address(this), expectedArbitrageNum, 0, 0, 0, 0);
    arbitrage.executeArbitrage(0);

    _checkUSCSpotPrice(arbitrage.USC_TARGET_PRICE());

    (, uint256 reserveDiffAfter, ) = arbitrage._getReservesData();

    assertGe(reserveDiffBefore, reserveDiffAfter, "Reserve diff should decrease after arbitrage");
  }

  function _uscPriceDexMoveUp(uint256 uscPriceTarget) internal {
    uint256 ethPrice = priceFeedAggregator.peek(WETH);
    (uint256 reserveUSC, uint256 reserveWETH) = UniswapV2Library.getReserves(
      address(UNISWAP_V2_FACTORY),
      address(usc),
      address(WETH)
    );
    uint256 deltaETH = arbitrage._calculateDelta(reserveWETH, ethPrice, reserveUSC, uscPriceTarget);
    _swap(WETH, address(usc), deltaETH);
    _checkUSCSpotPrice(uscPriceTarget);
  }

  function _uscPriceDexMoveDown(uint256 uscPriceTarget) internal {
    uint256 ethPrice = priceFeedAggregator.peek(WETH);
    (uint256 reserveUSC, uint256 reserveWETH) = UniswapV2Library.getReserves(
      address(UNISWAP_V2_FACTORY),
      address(usc),
      address(WETH)
    );
    uint256 deltaUSC = arbitrage._calculateDelta(reserveUSC, uscPriceTarget, reserveWETH, ethPrice);
    _swap(address(usc), WETH, deltaUSC);
    _checkUSCSpotPrice(uscPriceTarget);
  }

  function _moveReserveDiffTo(int256 reserveDiff) internal {
    uint256 ethPrice = priceFeedAggregator.peek(WETH);
    uint256 uscValue = _convertTokenAmountToUsdValue(usc.totalSupply(), BASE_PRICE);
    uint256 ethAmount = _convertUsdValueToTokenAmount(uint256(int256(uscValue) + reserveDiff), ethPrice);

    deal(address(this), ethAmount);
    IWETH(WETH).deposit{value: ethAmount}();
    IERC20(WETH).transfer(address(reserveHolder), ethAmount);
  }
}

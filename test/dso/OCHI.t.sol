// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {Test} from "forge-std/Test.sol";
import {IUniswapV2Factory} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import {IUniswapV2Pair} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IOCHI} from "contracts/interfaces/IOCHI.sol";
import {IMintableBurnable} from "contracts/interfaces/IMintableBurnable.sol";
import {IPriceFeedAggregator} from "contracts/interfaces/IPriceFeedAggregator.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import {MockERC20} from "contracts/mock/MockERC20.sol";
import {OCHI} from "contracts/dso/OCHI.sol";
import {USC} from "contracts/tokens/USC.sol";
import {CHI} from "contracts/tokens/CHI.sol";
import {LPRewards} from "contracts/dso/LPRewards.sol";
import {ExternalContractAddresses} from "contracts/library/ExternalContractAddresses.sol";

contract oChiTest is ERC721Holder, Test {
  uint256 public constant ROUNDING_ERROR_PERCENTAGE_TOLERANCE = 0.0002 ether;
  uint256 public constant INITIAL_ETH_LIQUIDITY = 1000 ether;
  uint256 public constant INITIAL_SUPPLY = 1000000 ether;
  uint256 public constant ETH_PRICE = 2000 * 10 ** 8;
  uint256 public constant CHI_PRICE = 5 * (10 ** 8);
  uint256 public constant USC_PRICE = 10 ** 8;
  address public constant WETH = ExternalContractAddresses.WETH;
  IUniswapV2Factory public constant UNISWAP_V2_FACTORY =
    IUniswapV2Factory(ExternalContractAddresses.UNI_V2_POOL_FACTORY);
  IUniswapV2Router02 public constant UNISWAP_V2_ROUTER =
    IUniswapV2Router02(ExternalContractAddresses.UNI_V2_SWAP_ROUTER);

  address public priceFeedAggregator;
  uint256 public firstEpochTimestamp;

  MockERC20 public usc;
  MockERC20 public chi;
  IUniswapV2Pair public uscEthPair;
  IUniswapV2Pair public chiEthPair;
  OCHI public ochi;

  receive() external payable {}

  function setUp() public {
    string memory mainnetRpcUrl = vm.envString("MAINNET_RPC_URL");
    uint256 mainnetFork = vm.createFork(mainnetRpcUrl);
    vm.selectFork(mainnetFork);
    vm.deal(address(this), 1000000 ether);

    priceFeedAggregator = makeAddr("PriceFeedAggregator");
    usc = new MockERC20("USC", "USC", INITIAL_SUPPLY * 2);
    chi = new MockERC20("CHI", "CHI", INITIAL_SUPPLY * 3);
    _deployPoolsAndAddLiquidity();

    LPRewards uscEthLPRewards = new LPRewards(uscEthPair, IPriceFeedAggregator(priceFeedAggregator));
    LPRewards chiEthLPRewards = new LPRewards(chiEthPair, IPriceFeedAggregator(priceFeedAggregator));

    ochi = new OCHI();
    ochi.initialize(
      IERC20(address(usc)),
      IMintableBurnable(address(chi)),
      IPriceFeedAggregator(priceFeedAggregator),
      uscEthPair,
      chiEthPair,
      uscEthLPRewards,
      chiEthLPRewards,
      block.timestamp + 1 weeks
    );

    uscEthLPRewards.setOCHI(address(ochi));
    chiEthLPRewards.setOCHI(address(ochi));

    chi.transfer(address(ochi), INITIAL_SUPPLY);
    chi.approve(address(ochi), type(uint256).max);
    uscEthPair.approve(address(ochi), type(uint256).max);
    chiEthPair.approve(address(ochi), type(uint256).max);
  }

  function test_SetUp() public {
    assertEq(ochi.name(), "Option CHI");
    assertEq(ochi.symbol(), "oCHI");
    assertEq(ochi.owner(), address(this));
    assertEq(ochi.currentEpoch(), 1);
    assertEq(ochi.lpRewards(uscEthPair).currentEpoch(), 1);
    assertEq(ochi.lpRewards(chiEthPair).currentEpoch(), 1);
    assertEq(ochi.firstEpochTimestamp(), block.timestamp + 1 weeks);
    assertEq(address(ochi.usc()), address(usc));
    assertEq(address(ochi.chi()), address(chi));
    assertEq(address(ochi.priceFeedAggregator()), priceFeedAggregator);
    assertEq(address(ochi.uscEthPair()), address(uscEthPair));
    assertEq(address(ochi.chiEthPair()), address(chiEthPair));
    assertNotEq(address(ochi.lpRewards(uscEthPair)), address(0));
  }

  function testFork_Mint_BothLPTokensWithoutChi() public {
    _mockTokenPrices(ETH_PRICE, USC_PRICE, CHI_PRICE);
    uint256 uscEthAmountToDeposit = uscEthPair.balanceOf(address(this)) / 10;
    uint256 chiEthAmountToDeposit = chiEthPair.balanceOf(address(this)) / 10;
    ochi.mint(0, uscEthAmountToDeposit, chiEthAmountToDeposit, 26);

    assertEq(ochi.ownerOf(1), address(this));
    assertEq(ochi.mintedOCHI(), 1);
    assertEq(uscEthPair.balanceOf(address(ochi.lpRewards(uscEthPair))), uscEthAmountToDeposit);
    assertEq(chiEthPair.balanceOf(address(ochi.lpRewards(chiEthPair))), chiEthAmountToDeposit);

    (
      uint256 chiAmount,
      uint256 strikePrice,
      uint256 uscEthPairAmount,
      uint256 chiEthPairAmount,
      uint64 lockedUntil,
      uint64 validUntil
    ) = ochi.options(1);

    (uint256 uscEthPoolValue, uint256 chiEthPoolValue) = _getPoolsValues();
    uint256 correctChiAmount = ((((uscEthPoolValue / 10 + chiEthPoolValue / 10) * 1 ether) / CHI_PRICE) * 100) / 95;
    assertApproxEqRel(chiAmount, correctChiAmount, ROUNDING_ERROR_PERCENTAGE_TOLERANCE);
    assertEq(strikePrice, (CHI_PRICE * 95) / 100);
    assertEq(uscEthPairAmount, uscEthAmountToDeposit);
    assertEq(chiEthPairAmount, chiEthAmountToDeposit);
    assertEq(lockedUntil, 28);
    assertEq(validUntil, 54);
  }

  function testFork_Mint_WithoutLPTokensWithChi() public {
    _mockTokenPrices(ETH_PRICE, USC_PRICE, CHI_PRICE);
    uint256 chiAmountToDeposit = chi.totalSupply() / 5;
    ochi.mint(chiAmountToDeposit, 0, 0, 26);

    assertEq(ochi.ownerOf(1), address(this));
    assertEq(ochi.mintedOCHI(), 1);
    assertEq(uscEthPair.balanceOf(address(ochi.lpRewards(uscEthPair))), 0);
    assertEq(chiEthPair.balanceOf(address(ochi.lpRewards(chiEthPair))), 0);

    (
      uint256 chiAmount,
      uint256 strikePrice,
      uint256 uscEthPairAmount,
      uint256 chiEthPairAmount,
      uint64 lockedUntil,
      uint64 validUntil
    ) = ochi.options(1);

    uint256 correctChiAmount = (chiAmountToDeposit * 100) / 95;
    assertApproxEqRel(chiAmount, correctChiAmount, ROUNDING_ERROR_PERCENTAGE_TOLERANCE);
    assertEq(strikePrice, (CHI_PRICE * 95) / 100);
    assertEq(uscEthPairAmount, 0);
    assertEq(chiEthPairAmount, 0);
    assertEq(lockedUntil, 28);
    assertEq(validUntil, 54);
  }

  function testFork_Mint_BothLPTokensWithChi() public {
    _mockTokenPrices(ETH_PRICE, USC_PRICE, CHI_PRICE);
    uint256 uscEthAmountToDeposit = uscEthPair.balanceOf(address(this)) / 10;
    uint256 chiEthAmountToDeposit = chiEthPair.balanceOf(address(this)) / 10;
    uint256 chiAmountToDeposit = chi.totalSupply() / 10;
    ochi.mint(chiAmountToDeposit, uscEthAmountToDeposit, chiEthAmountToDeposit, 26);

    assertEq(ochi.ownerOf(1), address(this));
    assertEq(ochi.mintedOCHI(), 1);
    assertEq(uscEthPair.balanceOf(address(ochi.lpRewards(uscEthPair))), uscEthAmountToDeposit);
    assertEq(chiEthPair.balanceOf(address(ochi.lpRewards(chiEthPair))), chiEthAmountToDeposit);

    (
      uint256 chiAmount,
      uint256 strikePrice,
      uint256 uscEthPairAmount,
      uint256 chiEthPairAmount,
      uint64 lockedUntil,
      uint64 validUntil
    ) = ochi.options(1);

    (uint256 uscEthPoolValue, uint256 chiEthPoolValue) = _getPoolsValues();
    uint256 correctChiAmount = ((((uscEthPoolValue / 10 + chiEthPoolValue / 10) * 1 ether) /
      CHI_PRICE +
      chiAmountToDeposit) * 1000) / 925;
    assertApproxEqRel(chiAmount, correctChiAmount, ROUNDING_ERROR_PERCENTAGE_TOLERANCE);
    assertEq(strikePrice, (CHI_PRICE * 925) / 1000);
    assertEq(uscEthPairAmount, uscEthAmountToDeposit);
    assertEq(chiEthPairAmount, chiEthAmountToDeposit);
    assertEq(lockedUntil, 28);
    assertEq(validUntil, 54);
  }

  function testFork_Mint_DiscountCap() public {
    _mockTokenPrices(ETH_PRICE, USC_PRICE, CHI_PRICE);
    uint256 uscEthAmountToDeposit = (uscEthPair.balanceOf(address(this)) * 6) / 10;
    uint256 chiEthAmountToDeposit = (chiEthPair.balanceOf(address(this)) * 6) / 10;
    uint256 chiAmountToDeposit = chi.totalSupply() / 3;
    ochi.mint(chiAmountToDeposit, uscEthAmountToDeposit, chiEthAmountToDeposit, 52);

    assertEq(ochi.ownerOf(1), address(this));
    assertEq(ochi.mintedOCHI(), 1);
    assertEq(uscEthPair.balanceOf(address(ochi.lpRewards(uscEthPair))), uscEthAmountToDeposit);
    assertEq(chiEthPair.balanceOf(address(ochi.lpRewards(chiEthPair))), chiEthAmountToDeposit);

    (
      uint256 chiAmount,
      uint256 strikePrice,
      uint256 uscEthPairAmount,
      uint256 chiEthPairAmount,
      uint64 lockedUntil,
      uint64 validUntil
    ) = ochi.options(1);

    (uint256 uscEthPoolValue, uint256 chiEthPoolValue) = _getPoolsValues();
    uint256 correctChiAmount = ((((uscEthPoolValue * 6) / 10 + (chiEthPoolValue * 6) / 10) * 1 ether) /
      CHI_PRICE +
      chiAmountToDeposit) * 2;
    assertApproxEqRel(chiAmount, correctChiAmount, ROUNDING_ERROR_PERCENTAGE_TOLERANCE);
    assertEq(strikePrice, (CHI_PRICE * 5) / 10);
    assertEq(uscEthPairAmount, uscEthAmountToDeposit);
    assertEq(chiEthPairAmount, chiEthAmountToDeposit);
    assertEq(lockedUntil, 54);
    assertEq(validUntil, 106);
  }

  function testFork_Mint_Revert_InvalidLockPeriod() public {
    vm.expectRevert(abi.encodeWithSelector(IOCHI.InvalidLockPeriod.selector, 0));
    ochi.mint(1 ether, 1 ether, 1 ether, 0);

    vm.expectRevert(abi.encodeWithSelector(IOCHI.InvalidLockPeriod.selector, 53));
    ochi.mint(1 ether, 1 ether, 1 ether, 53);
  }

  function testFork_Mint_Revert_PolTargetRatioExceeded() public {
    uint256 totalSupply = uscEthPair.totalSupply();
    uint256 amount = (totalSupply * 81) / 100;

    vm.expectRevert(IOCHI.PolTargetRatioExceeded.selector);
    ochi.mint(1 ether, amount, 1 ether, 26);

    totalSupply = chiEthPair.totalSupply();
    amount = (totalSupply * 81) / 100;

    vm.expectRevert(IOCHI.PolTargetRatioExceeded.selector);
    ochi.mint(1 ether, 1 ether, amount, 26);
  }

  function testFork_Burn() public {
    _mockTokenPrices(ETH_PRICE, USC_PRICE, CHI_PRICE);
    ochi.mint(1 ether, 1 ether, 1 ether, 26);

    for (uint256 i = 0; i <= 26; i++) {
      vm.warp(block.timestamp + 1 weeks);
      ochi.updateEpoch();
    }

    uint256 senderChiBalanceBefore = chi.balanceOf(address(this));
    uint256 ochiChiBalanceBefore = chi.balanceOf(address(ochi));
    ochi.approve(address(ochi), 1);
    ochi.burn(1);
    uint256 senderChiBalanceAfter = chi.balanceOf(address(this));
    uint256 ochiChiBalanceAfter = chi.balanceOf(address(ochi));

    (uint256 amount, , , , , ) = ochi.options(1);
    assertEq(senderChiBalanceAfter, senderChiBalanceBefore + amount);
    assertEq(ochiChiBalanceAfter, ochiChiBalanceBefore - amount);
  }

  function testFork_Burn_Revert_NotApprovedOrOwner() public {
    _mockTokenPrices(ETH_PRICE, USC_PRICE, CHI_PRICE);
    ochi.mint(1 ether, 1 ether, 1 ether, 26);

    address caller = makeAddr("caller");
    vm.startPrank(caller);
    vm.expectRevert(abi.encodeWithSelector(IOCHI.NotAllowed.selector, 1));
    ochi.burn(1);
  }

  function testFork_Burn_Revert_OptionLocked() public {
    _mockTokenPrices(ETH_PRICE, USC_PRICE, CHI_PRICE);
    ochi.mint(1 ether, 1 ether, 1 ether, 26);

    for (uint256 i = 0; i < 26; i++) {
      vm.warp(block.timestamp + 1 weeks);
      ochi.updateEpoch();
    }

    vm.expectRevert(abi.encodeWithSelector(IOCHI.OptionLocked.selector, 1));
    ochi.burn(1);
  }

  function testFork_Burn_Revert_OptionExpired() public {
    _mockTokenPrices(ETH_PRICE, USC_PRICE, CHI_PRICE);
    ochi.mint(1 ether, 1 ether, 1 ether, 26);

    for (uint256 i = 0; i <= 53; i++) {
      vm.warp(block.timestamp + 1 weeks);
      ochi.updateEpoch();
    }

    vm.expectRevert(abi.encodeWithSelector(IOCHI.OptionExpired.selector, 1));
    ochi.burn(1);
  }

  function testFork_UpdateEpoch() public {
    vm.warp(block.timestamp + 1 weeks);
    _mockTokenPrices(ETH_PRICE, USC_PRICE, CHI_PRICE);
    ochi.updateEpoch();

    assertEq(ochi.currentEpoch(), 2);
    assertEq(ochi.lpRewards(uscEthPair).currentEpoch(), 2);
    assertEq(ochi.lpRewards(chiEthPair).currentEpoch(), 2);
  }

  function testFork_UpdateEpoch_Revert_EpochNotFinished() public {
    vm.expectRevert(IOCHI.EpochNotFinished.selector);
    _mockTokenPrices(ETH_PRICE, USC_PRICE, CHI_PRICE);
    ochi.updateEpoch();
  }

  function testFork_ClaimRewards_OnlyHisRewards() public {
    _mockTokenPrices(ETH_PRICE, USC_PRICE, CHI_PRICE);
    ochi.mint(1 ether, 1 ether, 1 ether, 26);
    ochi.mint(10 ether, 10 ether, 8 ether, 51);

    vm.warp(block.timestamp + 1 weeks);
    ochi.updateEpoch();
    vm.warp(block.timestamp + 1 weeks);
    ochi.updateEpoch();
    _mockTokenPrices(2 * ETH_PRICE, 2 * USC_PRICE, 2 * CHI_PRICE);

    (uint256 uscEthPairPrice, uint256 chiEthPairPrice) = _getLPPrices();
    int256 uscEthRewardsInUSD = ochi.lpRewards(uscEthPair).calculateUnclaimedReward(1);
    int256 chiEthRewardsInUSD = ochi.lpRewards(chiEthPair).calculateUnclaimedReward(1);
    uint256 uscEthPairRewardAmount = (uint256(uscEthRewardsInUSD) * 1 ether) / uscEthPairPrice;
    uint256 chiEthPairRewardAmount = (uint256(chiEthRewardsInUSD) * 1 ether) / chiEthPairPrice;

    uint256 uscEthPairTotalSupplyBefore = uscEthPair.totalSupply();
    uint256 chiEthPairTotalSupplyBefore = chiEthPair.totalSupply();
    uint256 callerUscBalanceBefore = usc.balanceOf(address(this));
    uint256 callerChiBalanceBefore = chi.balanceOf(address(this));
    uint256 callerEthBalanceBefore = address(this).balance;
    ochi.claimRewards(1);

    assertApproxEqRel(
      uscEthPair.totalSupply(),
      uscEthPairTotalSupplyBefore - uscEthPairRewardAmount,
      ROUNDING_ERROR_PERCENTAGE_TOLERANCE
    );
    assertApproxEqRel(
      chiEthPair.totalSupply(),
      chiEthPairTotalSupplyBefore - chiEthPairRewardAmount,
      ROUNDING_ERROR_PERCENTAGE_TOLERANCE
    );
    assertApproxEqRel(
      usc.balanceOf(address(this)),
      callerUscBalanceBefore + (uscEthPairRewardAmount * INITIAL_SUPPLY) / uscEthPair.totalSupply(),
      ROUNDING_ERROR_PERCENTAGE_TOLERANCE
    );
    assertApproxEqRel(
      chi.balanceOf(address(this)),
      callerChiBalanceBefore + (chiEthPairRewardAmount * INITIAL_SUPPLY) / chiEthPair.totalSupply(),
      ROUNDING_ERROR_PERCENTAGE_TOLERANCE
    );
    assertApproxEqRel(
      address(this).balance,
      callerEthBalanceBefore +
        (INITIAL_ETH_LIQUIDITY * uscEthPairRewardAmount) /
        uscEthPair.totalSupply() +
        (INITIAL_ETH_LIQUIDITY * chiEthPairRewardAmount) /
        chiEthPair.totalSupply(),
      ROUNDING_ERROR_PERCENTAGE_TOLERANCE
    );
  }

  function testFork_ClaimRewards_Revert_NotAllowed() public {
    _mockTokenPrices(ETH_PRICE, USC_PRICE, CHI_PRICE);
    ochi.mint(1 ether, 1 ether, 1 ether, 26);

    address caller = makeAddr("caller");
    vm.startPrank(caller);
    vm.expectRevert(abi.encodeWithSelector(IOCHI.NotAllowed.selector, 1));
    ochi.claimRewards(1);
  }

  function testFork_RecoverLPTokens() public {
    _mockTokenPrices(ETH_PRICE, USC_PRICE, CHI_PRICE);
    ochi.mint(1 ether, 1 ether, 1 ether, 26);
    ochi.mint(2 ether, 10 ether, 8 ether, 21);

    uint256 uscEthPairBalanceBefore = uscEthPair.balanceOf(address(this));
    uint256 chiEthPairBalanceBefore = chiEthPair.balanceOf(address(this));
    ochi.recoverLPTokens();

    assertEq(uscEthPair.balanceOf(address(ochi.lpRewards(uscEthPair))), 0);
    assertEq(chiEthPair.balanceOf(address(ochi.lpRewards(chiEthPair))), 0);
    assertEq(uscEthPair.balanceOf(address(this)), uscEthPairBalanceBefore + 11 ether);
    assertEq(chiEthPair.balanceOf(address(this)), chiEthPairBalanceBefore + 9 ether);
  }

  function testFork_GetUnclaimedRewardsValue() public {
    _mockTokenPrices(ETH_PRICE, USC_PRICE, CHI_PRICE);
    ochi.mint(1 ether, 1 ether, 1 ether, 26);
    ochi.mint(2 ether, 10 ether, 8 ether, 1);

    vm.warp(block.timestamp + 1 weeks);
    ochi.updateEpoch();
    vm.warp(block.timestamp + 1 weeks);
    ochi.updateEpoch();

    int256 uscEthReward = ochi.lpRewards(uscEthPair).calculateUnclaimedReward(1);
    int256 chiEthReward = ochi.lpRewards(chiEthPair).calculateUnclaimedReward(1);
    assertEq(ochi.getUnclaimedRewardsValue(1), uscEthReward + chiEthReward);

    uscEthReward = ochi.lpRewards(uscEthPair).calculateUnclaimedReward(2);
    chiEthReward = ochi.lpRewards(chiEthPair).calculateUnclaimedReward(2);
    assertEq(ochi.getUnclaimedRewardsValue(2), uscEthReward + chiEthReward);
  }

  function _deployPoolsAndAddLiquidity() private {
    uscEthPair = IUniswapV2Pair(UNISWAP_V2_FACTORY.createPair(address(usc), WETH));
    chiEthPair = IUniswapV2Pair(UNISWAP_V2_FACTORY.createPair(address(chi), WETH));
    usc.approve(address(UNISWAP_V2_ROUTER), type(uint256).max);
    chi.approve(address(UNISWAP_V2_ROUTER), type(uint256).max);

    UNISWAP_V2_ROUTER.addLiquidityETH{value: INITIAL_ETH_LIQUIDITY}(
      address(usc),
      INITIAL_SUPPLY,
      0,
      0,
      address(this),
      block.timestamp
    );
    UNISWAP_V2_ROUTER.addLiquidityETH{value: INITIAL_ETH_LIQUIDITY}(
      address(chi),
      INITIAL_SUPPLY,
      0,
      0,
      address(this),
      block.timestamp
    );
  }

  function _mockTokenPrices(uint256 ethPrice, uint256 uscPrice, uint256 chiPrice) private {
    vm.mockCall(
      address(priceFeedAggregator),
      abi.encodeWithSelector((IPriceFeedAggregator.peek.selector), WETH),
      abi.encode(ethPrice, 0)
    );
    vm.mockCall(
      address(priceFeedAggregator),
      abi.encodeWithSelector((IPriceFeedAggregator.peek.selector), address(usc)),
      abi.encode(uscPrice, 0)
    );
    vm.mockCall(
      address(priceFeedAggregator),
      abi.encodeWithSelector((IPriceFeedAggregator.peek.selector), address(chi)),
      abi.encode(chiPrice, 0)
    );
  }

  function _getPoolsValues() private view returns (uint256, uint256) {
    uint256 uscEthPoolValue = ((usc.balanceOf(address(uscEthPair)) * USC_PRICE) +
      (IERC20(WETH).balanceOf(address(uscEthPair)) * ETH_PRICE)) / 10 ** 18;
    uint256 chiEthPoolValue = ((chi.balanceOf(address(chiEthPair)) * CHI_PRICE) +
      (IERC20(WETH).balanceOf(address(chiEthPair)) * ETH_PRICE)) / 10 ** 18;
    return (uscEthPoolValue, chiEthPoolValue);
  }

  function _getLPPrices() private view returns (uint256, uint256) {
    uint256 ethPrice = IPriceFeedAggregator(priceFeedAggregator).peek(WETH);
    uint256 uscPrice = IPriceFeedAggregator(priceFeedAggregator).peek(address(usc));
    uint256 chiPrice = IPriceFeedAggregator(priceFeedAggregator).peek(address(chi));
    uint256 uscEthPairPrice = (ethPrice *
      IERC20(WETH).balanceOf(address(uscEthPair)) +
      uscPrice *
      usc.balanceOf(address(uscEthPair))) / uscEthPair.totalSupply();
    uint256 chiEthPairPrice = (ethPrice *
      IERC20(WETH).balanceOf(address(chiEthPair)) +
      chiPrice *
      chi.balanceOf(address(chiEthPair))) / chiEthPair.totalSupply();
    return (uscEthPairPrice, chiEthPairPrice);
  }
}

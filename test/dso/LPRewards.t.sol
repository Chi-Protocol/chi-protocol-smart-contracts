// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {Test} from "forge-std/Test.sol";
import {StdStorage, stdStorage} from "forge-std/StdStorage.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IUniswapV2Factory} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import {IUniswapV2Pair} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import {MockERC20} from "contracts/mock/MockERC20.sol";
import {IPriceFeedAggregator} from "contracts/interfaces/IPriceFeedAggregator.sol";
import {ILPRewards} from "contracts/interfaces/ILPRewards.sol";
import {LPRewards} from "contracts/dso/LPRewards.sol";
import {ExternalContractAddresses} from "contracts/library/ExternalContractAddresses.sol";

contract LPRewardsTest is Test {
  using stdStorage for StdStorage;

  uint256 public constant ROUNDING_ERROR_PERCENTAGE_TOLERANCE = 0.0002 ether;
  uint256 public constant INITIAL_SUPPLY = 1000000 ether;
  uint256 public constant INITIAL_ETH_LIQUIDITY = 1000 ether;
  uint256 public constant ETH_PRICE = 2000 * 10 ** 8;
  uint256 public constant USC_PRICE = 10 ** 8;
  address public constant WETH = ExternalContractAddresses.WETH;
  IUniswapV2Factory public constant UNISWAP_V2_FACTORY =
    IUniswapV2Factory(ExternalContractAddresses.UNI_V2_POOL_FACTORY);
  IUniswapV2Router02 public constant UNISWAP_V2_ROUTER =
    IUniswapV2Router02(ExternalContractAddresses.UNI_V2_SWAP_ROUTER);

  MockERC20 public usc;
  IUniswapV2Pair public token;
  LPRewards public lpRewards;
  address public priceFeedAggregator;

  function setUp() public {
    string memory mainnetRpcUrl = vm.envString("MAINNET_RPC_URL");
    uint256 mainnetFork = vm.createFork(mainnetRpcUrl);
    vm.selectFork(mainnetFork);
    vm.deal(address(this), 1000000 ether);

    usc = new MockERC20("USC", "USC", INITIAL_SUPPLY * 2);
    _deployPoolAndAddLiquidity();
    priceFeedAggregator = makeAddr("PriceFeedAggregator");
    lpRewards = new LPRewards(token, IPriceFeedAggregator(priceFeedAggregator));
    lpRewards.setOCHI(address(this));
  }

  receive() external payable {}

  function testFork_SetUp() public {
    assertEq(lpRewards.decimals(), uint8(18));
    assertEq(lpRewards.currentEpoch(), uint64(1));
    assertEq(lpRewards.totalAmountLocked(), int256(0));
    assertEq(lpRewards.owner(), address(this));
    assertEq(address(lpRewards.lpToken()), address(token));
    assertEq(address(lpRewards.priceFeedAggregator()), address(IPriceFeedAggregator(priceFeedAggregator)));
  }

  function testFuzzFork_SetOCHI(address ochi) public {
    lpRewards.setOCHI(ochi);
    assertEq(lpRewards.ochi(), ochi);
  }

  function testFork_SetOCHI_Revert_NotOwner() public {
    address caller = makeAddr("caller");
    vm.startPrank(caller);
    vm.expectRevert("Ownable: caller is not the owner");
    lpRewards.setOCHI(address(0));
  }

  function testFork_LockLP() public {
    lpRewards.lockLP(5, 1000 ether, 10);

    (uint256 amountLocked, uint64 lastClaimedEpoch, uint64 endingEpoch) = lpRewards.lockingTokenData(5);
    (int256 totalDeltaAmountLocked, int256 cumulativeProfit) = lpRewards.epochData(2);

    assertEq(amountLocked, 1000 ether);
    assertEq(lastClaimedEpoch, 1);
    assertEq(endingEpoch, 12);
    assertEq(totalDeltaAmountLocked, 1000 ether);
    assertEq(cumulativeProfit, 0);

    (totalDeltaAmountLocked, cumulativeProfit) = lpRewards.epochData(12);
    assertEq(totalDeltaAmountLocked, -1000 ether);
    assertEq(cumulativeProfit, 0);
  }

  function testFuzzFork_LockLP(uint256 tokenIn, int256 amount, uint64 epochDuration) public {
    vm.assume(amount > 0);
    epochDuration = uint64(bound(epochDuration, 1, type(uint64).max - 2));

    lpRewards.lockLP(tokenIn, uint256(amount), epochDuration);

    (uint256 amountLocked, uint64 lastClaimedEpoch, uint64 endingEpoch) = lpRewards.lockingTokenData(tokenIn);
    (int256 totalDeltaAmountLocked, int256 cumulativeProfit) = lpRewards.epochData(2);
    assertEq(amountLocked, uint256(amount));
    assertEq(lastClaimedEpoch, 1);
    assertEq(endingEpoch, epochDuration + 2);
    assertEq(totalDeltaAmountLocked, amount);
    assertEq(cumulativeProfit, 0);

    (totalDeltaAmountLocked, cumulativeProfit) = lpRewards.epochData(epochDuration + 2);
    assertEq(totalDeltaAmountLocked, -amount);
    assertEq(cumulativeProfit, 0);
  }

  function testFuzzFork_LockLP_Revert_TokenIdAlreadyUsed(
    uint256 tokenId,
    int256 value,
    uint256 amount,
    uint64 epochPeriod
  ) public {
    vm.assume(value != 0);
    vm.assume(amount != 0);
    stdstore.target(address(lpRewards)).sig("lockingTokenData(uint256)").with_key(tokenId).depth(0).checked_write_int(
      value
    );
    vm.expectRevert(abi.encodeWithSelector((ILPRewards.LockingTokenIdAlreadyUsed.selector), tokenId));
    lpRewards.lockLP(tokenId, amount, epochPeriod);
  }

  function testFork_LockLP_Revert_NotOCHI() public {
    address caller = makeAddr("caller");
    vm.startPrank(caller);
    vm.expectRevert(ILPRewards.NotOCHI.selector);
    lpRewards.lockLP(5, 1000 ether, 10);
  }

  function testFuzzFork_RecoverLPTokens(uint256 amount) public {
    uint256 ownerBalanceBefore = token.balanceOf(address(this));
    amount = bound(amount, 1, ownerBalanceBefore);
    token.transfer(address(lpRewards), amount);

    assertEq(token.balanceOf(address(lpRewards)), amount);
    assertEq(token.balanceOf(address(this)), ownerBalanceBefore - amount);
    lpRewards.recoverLPTokens(address(this));
    assertEq(token.balanceOf(address(lpRewards)), 0);
    assertEq(token.balanceOf(address(this)), ownerBalanceBefore);
  }

  function testFork_RecoverLPTokens_Revert_NotOCHI() public {
    address caller = makeAddr("caller");
    vm.startPrank(caller);
    vm.expectRevert(ILPRewards.NotOCHI.selector);
    lpRewards.recoverLPTokens(address(this));
  }

  function testFork_UpdateEpoch() public {
    _mockTokenPrices(ETH_PRICE, USC_PRICE);
    uint256 correctLpPrice = (ETH_PRICE * INITIAL_ETH_LIQUIDITY + USC_PRICE * INITIAL_SUPPLY) / token.totalSupply();
    _lockLP(1, 1000 ether, 10);
    _lockLP(2, 2000 ether, 1);
    lpRewards.updateEpoch();

    assertEq(lpRewards.currentEpoch(), 2);
    assertEq(lpRewards.totalAmountLocked(), 0);
    assertEq(lpRewards.currentLPValue(), correctLpPrice);
    assertEq(lpRewards.cumulativeProfit(), 0);
    assertEq(lpRewards.epochMinLPBalance(), 3000 ether);

    (int256 totalDeltaAmountLocked, int256 cumulativeProfit) = lpRewards.epochData(0);
    assertEq(totalDeltaAmountLocked, 0);
    assertEq(cumulativeProfit, 0);

    _swap();
    _lockLP(3, 3000 ether, 1);
    _lockLP(4, 4000 ether, 10);
    lpRewards.updateEpoch();

    uint256 newLpPrice = _getLPPrice();
    int256 correctCumulativeRewards = int256(newLpPrice) - int256(correctLpPrice);
    assertEq(lpRewards.currentEpoch(), 3);
    assertEq(lpRewards.totalAmountLocked(), 3000 ether);
    assertEq(lpRewards.currentLPValue(), newLpPrice);
    assertEq(lpRewards.cumulativeProfit(), correctCumulativeRewards);
    assertEq(lpRewards.epochMinLPBalance(), 10000 ether);

    _swap();
    _lockLP(5, 5000 ether, 1);
    _lockLP(6, 6000 ether, 10);
    lpRewards.updateEpoch();

    uint256 oldLpPrice = newLpPrice;
    newLpPrice = _getLPPrice();
    correctCumulativeRewards += ((int256(newLpPrice) - int256(oldLpPrice)) * 10) / 8;
    assertEq(lpRewards.currentEpoch(), 4);
    assertEq(lpRewards.totalAmountLocked(), 8000 ether);
    assertEq(lpRewards.currentLPValue(), newLpPrice);
    assertEq(lpRewards.cumulativeProfit(), correctCumulativeRewards);
    assertEq(lpRewards.epochMinLPBalance(), 21000 ether);
  }

  function test_CalculateUnclaimedRewards() public {
    _mockTokenPrices(ETH_PRICE, USC_PRICE);
    uint256 correctLpPrice = (ETH_PRICE * INITIAL_ETH_LIQUIDITY + USC_PRICE * INITIAL_SUPPLY) / token.totalSupply();
    _lockLP(1, 1000 ether, 10);
    _lockLP(2, 2000 ether, 1);
    lpRewards.updateEpoch();

    assertEq(lpRewards.calculateUnclaimedReward(1), 0);
    assertEq(lpRewards.calculateUnclaimedReward(2), 0);

    _mockTokenPrices(2 * ETH_PRICE, 2 * USC_PRICE);
    lpRewards.updateEpoch();

    assertApproxEqRel(
      lpRewards.calculateUnclaimedReward(1),
      int256(correctLpPrice) * 1000,
      ROUNDING_ERROR_PERCENTAGE_TOLERANCE
    );
    assertApproxEqRel(
      lpRewards.calculateUnclaimedReward(2),
      int256(correctLpPrice) * 2000,
      ROUNDING_ERROR_PERCENTAGE_TOLERANCE
    );

    _mockTokenPrices(3 * ETH_PRICE, 3 * USC_PRICE);
    lpRewards.updateEpoch();

    assertApproxEqRel(
      lpRewards.calculateUnclaimedReward(1),
      int256(correctLpPrice) * 1000 * 4,
      ROUNDING_ERROR_PERCENTAGE_TOLERANCE
    );
    assertApproxEqRel(
      lpRewards.calculateUnclaimedReward(2),
      int256(correctLpPrice) * 2000,
      ROUNDING_ERROR_PERCENTAGE_TOLERANCE
    );

    _lockLP(3, 3000 ether, 1);
    lpRewards.updateEpoch();

    assertApproxEqRel(
      lpRewards.calculateUnclaimedReward(1),
      int256(correctLpPrice) * 1000 * 4,
      ROUNDING_ERROR_PERCENTAGE_TOLERANCE
    );
    assertEq(lpRewards.calculateUnclaimedReward(3), 0);

    _mockTokenPrices(5 * ETH_PRICE, 5 * USC_PRICE);
    lpRewards.updateEpoch();

    assertApproxEqRel(
      lpRewards.calculateUnclaimedReward(1),
      int256(correctLpPrice) * 1000 * 4 + int256(correctLpPrice) * 3000,
      ROUNDING_ERROR_PERCENTAGE_TOLERANCE
    );
    assertApproxEqRel(
      lpRewards.calculateUnclaimedReward(3),
      int256(correctLpPrice) * 3000 * 2 + int256(correctLpPrice) * 3000,
      ROUNDING_ERROR_PERCENTAGE_TOLERANCE
    );
  }

  function test_ClaimRewards_OnlyHisRewards() public {
    _mockTokenPrices(ETH_PRICE, USC_PRICE);
    _lockLP(1, 1000 ether, 10);
    _lockLP(2, 2000 ether, 3);
    lpRewards.updateEpoch();

    _mockTokenPrices(2 * ETH_PRICE, 2 * USC_PRICE);
    lpRewards.updateEpoch();
    lpRewards.claimRewards(1, address(this));
    assertApproxEqRel(token.balanceOf(address(lpRewards)), 2500 ether, ROUNDING_ERROR_PERCENTAGE_TOLERANCE);
  }

  function test_ClaimRewards_RewardsFromExpired() public {
    _mockTokenPrices(ETH_PRICE, USC_PRICE);
    _lockLP(1, 1000 ether, 10);
    _lockLP(2, 2000 ether, 1);
    lpRewards.updateEpoch();

    _mockTokenPrices(2 * ETH_PRICE, 2 * USC_PRICE);
    lpRewards.updateEpoch();

    _mockTokenPrices(3 * ETH_PRICE, 3 * USC_PRICE);
    lpRewards.updateEpoch();
    lpRewards.claimRewards(1, address(this));
    assertApproxEqRel(token.balanceOf(address(lpRewards)), 1666.6666 ether, ROUNDING_ERROR_PERCENTAGE_TOLERANCE);
  }

  function _deployPoolAndAddLiquidity() private {
    token = IUniswapV2Pair(UNISWAP_V2_FACTORY.createPair(address(usc), WETH));
    usc.approve(address(UNISWAP_V2_ROUTER), type(uint256).max);

    UNISWAP_V2_ROUTER.addLiquidityETH{value: INITIAL_ETH_LIQUIDITY}(
      address(usc),
      INITIAL_SUPPLY,
      0,
      0,
      address(this),
      block.timestamp
    );
  }

  function _swap() private {
    uint256 uscBalance = 1000 ether;
    usc.approve(address(UNISWAP_V2_ROUTER), type(uint256).max);

    address[] memory path = new address[](2);
    path[0] = address(usc);
    path[1] = WETH;
    UNISWAP_V2_ROUTER.swapExactTokensForTokens(uscBalance, 0, path, address(this), block.timestamp);
  }

  function _lockLP(uint256 tokenId, uint256 amount, uint64 epochDuration) private {
    token.transfer(address(lpRewards), amount);
    lpRewards.lockLP(tokenId, amount, epochDuration);
  }

  function _getLPPrice() private view returns (uint256) {
    return
      (ETH_PRICE * IERC20(WETH).balanceOf(address(token)) + USC_PRICE * usc.balanceOf(address(token))) /
      token.totalSupply();
  }

  function _mockTokenPrices(uint256 ethPrice, uint256 uscPrice) private {
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
  }
}

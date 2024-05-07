// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {Test} from "forge-std/Test.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {IUniswapV2Factory} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import {IUniswapV2Pair} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import {IUniswapV2TwapOracle} from "contracts/interfaces/IUniswapV2TwapOracle.sol";
import {IWETH} from "contracts/interfaces/IWETH.sol";
import {UniswapV2TwapOracle} from "contracts/oracles/UniswapV2TwapOracle.sol";
import {UniswapV2OracleLibrary} from "contracts/uniswap/libraries/UniswapV2OracleLibrary.sol";
import {MockERC20} from "contracts/mock/MockERC20.sol";
import {ExternalContractAddresses} from "contracts/library/ExternalContractAddresses.sol";

contract UniswaV2TwapOracleTest is Test {
  uint32 public UPDATE_PERIOD = 1 hours;
  uint32 public MIN_PERIOD_FROM_LAST_SNAPSHOT = 1 hours / 2;
  uint256 public INITIAL_TOKEN_LIQUIDITY = 500 ether;
  uint256 public INITIAL_ETH_LIQUIDITY = 1000 ether;
  address public constant ETH_USD_CHAINLINK_FEED = ExternalContractAddresses.ETH_USD_CHAINLINK_FEED;
  address public constant WETH = ExternalContractAddresses.WETH;
  IUniswapV2Factory public constant UNISWAP_V2_FACTORY =
    IUniswapV2Factory(ExternalContractAddresses.UNI_V2_POOL_FACTORY);
  IUniswapV2Router02 public constant UNISWAP_V2_ROUTER =
    IUniswapV2Router02(ExternalContractAddresses.UNI_V2_SWAP_ROUTER);

  IUniswapV2Pair public pair;
  UniswapV2TwapOracle public oracle;
  MockERC20 public token;

  function setUp() public {
    string memory mainnetRpcUrl = vm.envString("MAINNET_RPC_URL");
    uint256 mainnetFork = vm.createFork(mainnetRpcUrl);
    vm.selectFork(mainnetFork);

    token = new MockERC20("Mock Token", "MTKN", 10000 ether);
    _deployPoolAndAddLiquidity();
    oracle = new UniswapV2TwapOracle(
      address(UNISWAP_V2_FACTORY),
      address(token),
      WETH,
      UPDATE_PERIOD,
      MIN_PERIOD_FROM_LAST_SNAPSHOT,
      AggregatorV3Interface(ETH_USD_CHAINLINK_FEED)
    );
  }

  function testFork_SetUp() public {
    (uint256 lastSnapshotPriceCumulative0, uint256 lastSnapshotPriceCumulative1, ) = oracle.lastSnapshot();
    (uint256 previousSnapshotPriceCumulative0, uint256 previousSnapshotPriceCumulative1, ) = oracle.previousSnapshot();
    assertEq(oracle.baseToken(), address(token));
    assertEq(oracle.baseAmount(), 10 ** uint256(token.decimals()));
    assertEq(oracle.updatePeriod(), UPDATE_PERIOD);
    assertEq(oracle.minPeriodFromLastSnapshot(), MIN_PERIOD_FROM_LAST_SNAPSHOT);
    assertEq(address(oracle.quoteTokenChainlinkFeed()), ETH_USD_CHAINLINK_FEED);
    assertEq(lastSnapshotPriceCumulative0, pair.price0CumulativeLast());
    assertEq(lastSnapshotPriceCumulative1, pair.price1CumulativeLast());
    assertEq(previousSnapshotPriceCumulative0, lastSnapshotPriceCumulative0);
    assertEq(previousSnapshotPriceCumulative1, lastSnapshotPriceCumulative1);
  }

  function testFork_Name() public {
    assertEq(oracle.name(), "UniV2 TWAP - MTKN");
  }

  function testFork_Decimals() public {
    assertEq(oracle.decimals(), 8);
  }

  function testFork_updateCumulativePricesSnapshot() public {
    vm.warp(block.timestamp + UPDATE_PERIOD);

    (uint256 lastSnapPriceCum0Before, uint256 lastSnapPriceCum1Before, uint32 lastSnapTimestampBefore) = oracle
      .lastSnapshot();
    oracle.updateCumulativePricesSnapshot();

    (uint256 lastSnapPriceCum0, uint256 lastSnapPriceCum1, uint32 lastSnapTimestamp) = oracle.lastSnapshot();
    (uint256 prevSnapPriceCum0, uint256 prevSnapPriceCum1, uint32 prevSnapTimestamp) = oracle.previousSnapshot();
    (uint256 price0Cum, uint256 price1Cum, ) = UniswapV2OracleLibrary.currentCumulativePrices(address(pair));

    assertEq(lastSnapPriceCum0, price0Cum);
    assertEq(lastSnapPriceCum1, price1Cum);
    assertEq(lastSnapTimestamp, uint32(block.timestamp));
    assertEq(prevSnapPriceCum0, lastSnapPriceCum0Before);
    assertEq(prevSnapPriceCum1, lastSnapPriceCum1Before);
    assertEq(prevSnapTimestamp, lastSnapTimestampBefore);
  }

  function testFork_updateCumulativePricesSnapshot_Revert_PeriodNotPassed() public {
    vm.warp(block.timestamp + UPDATE_PERIOD - 1 seconds);
    vm.expectRevert(IUniswapV2TwapOracle.PeriodNotPassed.selector);
    oracle.updateCumulativePricesSnapshot();
  }

  function testFork_getTwapQuote_MinPeriodNotPassed() public {
    vm.warp(block.timestamp + UPDATE_PERIOD);
    oracle.updateCumulativePricesSnapshot();
    _swap(address(token), WETH, 100 ether);
    vm.warp(block.timestamp + MIN_PERIOD_FROM_LAST_SNAPSHOT - 1);

    (uint256 prevSnapPriceCum0, uint256 prevSnapPriceCum1, uint32 prevSnapTimestamp) = oracle.previousSnapshot();
    (uint256 price0Cum, uint256 price1Cum, ) = UniswapV2OracleLibrary.currentCumulativePrices(address(pair));
    uint256 averageTokenPrice = (price0Cum - prevSnapPriceCum0) / (block.timestamp - prevSnapTimestamp);
    uint256 averageEthPrice = (price1Cum - prevSnapPriceCum1) / (block.timestamp - prevSnapTimestamp);
    uint256 tokenTwapPrice = (averageTokenPrice * 1 ether) >> 112;
    uint256 ethTwapPrice = (averageEthPrice * 1 ether) >> 112;

    uint256 tokenPrice = oracle.getTwapQuote(address(token), 1 ether);
    uint256 ethPrice = oracle.getTwapQuote(WETH, 1 ether);
    assertEq(tokenPrice, tokenTwapPrice);
    assertEq(ethPrice, ethTwapPrice);
  }

  function testFork_getTwapQuote_MinPeriodPassed() public {
    vm.warp(block.timestamp + UPDATE_PERIOD);
    oracle.updateCumulativePricesSnapshot();
    _swap(address(token), WETH, 100 ether);
    vm.warp(block.timestamp + MIN_PERIOD_FROM_LAST_SNAPSHOT);

    (uint256 currSnapPriceCum0, uint256 currSnapPriceCum1, uint32 currSnapTimestamp) = oracle.lastSnapshot();
    (uint256 price0Sum, uint256 price1Sum, ) = UniswapV2OracleLibrary.currentCumulativePrices(address(pair));
    uint256 averageTokenPrice = (price0Sum - currSnapPriceCum0) / (block.timestamp - currSnapTimestamp);
    uint256 averageEthPrice = (price1Sum - currSnapPriceCum1) / (block.timestamp - currSnapTimestamp);
    uint256 tokenTwapPrice = (averageTokenPrice * 1 ether) >> 112;
    uint256 ethTwapPrice = (averageEthPrice * 1 ether) >> 112;

    uint256 tokenPrice = oracle.getTwapQuote(address(token), 1 ether);
    uint256 ethPrice = oracle.getTwapQuote(WETH, 1 ether);
    assertEq(tokenPrice, tokenTwapPrice);
    assertEq(ethPrice, ethTwapPrice);
  }

  function testFork_Peek() public {
    vm.warp(block.timestamp + UPDATE_PERIOD);
    oracle.updateCumulativePricesSnapshot();

    (, int256 quoteTokenPriceInUSD, , , ) = AggregatorV3Interface(ETH_USD_CHAINLINK_FEED).latestRoundData();
    uint256 twapPrice = oracle.getTwapQuote(address(token), 1 ether);
    uint256 priceInUSD = oracle.peek();
    assertEq(priceInUSD, (uint256(quoteTokenPriceInUSD) * twapPrice) / 1 ether);
  }

  function _deployPoolAndAddLiquidity() private {
    pair = IUniswapV2Pair(UNISWAP_V2_FACTORY.createPair(address(token), WETH));
    token.approve(address(UNISWAP_V2_ROUTER), type(uint256).max);

    UNISWAP_V2_ROUTER.addLiquidityETH{value: INITIAL_ETH_LIQUIDITY}(
      address(token),
      INITIAL_TOKEN_LIQUIDITY,
      0,
      0,
      address(this),
      block.timestamp
    );
  }

  function _swap(address tokenIn, address tokenOut, uint256 amountIn) private {
    address[] memory path = new address[](2);
    path[0] = tokenIn;
    path[1] = tokenOut;
    UNISWAP_V2_ROUTER.swapExactTokensForTokens(amountIn, 0, path, address(this), block.timestamp);
  }
}

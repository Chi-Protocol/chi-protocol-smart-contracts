// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {Test} from "forge-std/Test.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {ChainlinkOracle} from "contracts/oracles/ChainlinkOracle.sol";
import {ExternalContractAddresses} from "contracts/library/ExternalContractAddresses.sol";

contract ChainlinkOracleTest is Test {
  address public constant WETH = ExternalContractAddresses.WETH;
  address public constant STETH = ExternalContractAddresses.stETH;
  AggregatorV3Interface public constant ethPriceFeed =
    AggregatorV3Interface(ExternalContractAddresses.ETH_USD_CHAINLINK_FEED);
  AggregatorV3Interface public constant stEthPriceFeed =
    AggregatorV3Interface(ExternalContractAddresses.STETH_USD_CHAINLINK_FEED);

  ChainlinkOracle public ethChainlinkOracle;
  ChainlinkOracle public stEthChainlinkOracle;

  function setUp() public {
    string memory mainnetRpcUrl = vm.envString("MAINNET_RPC_URL");
    uint256 mainnetFork = vm.createFork(mainnetRpcUrl);
    vm.selectFork(mainnetFork);

    ethChainlinkOracle = new ChainlinkOracle(WETH, address(ethPriceFeed));
    stEthChainlinkOracle = new ChainlinkOracle(STETH, address(stEthPriceFeed));
  }

  function testFork_SetUp() public {
    assertEq(ethChainlinkOracle.baseToken(), WETH);
    assertEq(address(ethChainlinkOracle.chainlinkFeed()), address(ethPriceFeed));
    assertEq(stEthChainlinkOracle.baseToken(), STETH);
    assertEq(address(stEthChainlinkOracle.chainlinkFeed()), address(stEthPriceFeed));
  }

  function testFork_Name() public {
    assertEq(ethChainlinkOracle.name(), "Chainlink Price - WETH");
    assertEq(stEthChainlinkOracle.name(), "Chainlink Price - stETH");
  }

  function testFork_Decimals() public {
    assertEq(ethChainlinkOracle.decimals(), ethPriceFeed.decimals());
    assertEq(stEthChainlinkOracle.decimals(), stEthPriceFeed.decimals());
  }

  function testFork_Peek() public {
    (, int256 ethPriceInUSD, , , ) = ethPriceFeed.latestRoundData();
    (, int256 stEthPriceInUSD, , , ) = stEthPriceFeed.latestRoundData();

    assertEq(ethChainlinkOracle.peek(), uint256(ethPriceInUSD));
    assertEq(stEthChainlinkOracle.peek(), uint256(stEthPriceInUSD));
  }

  function testFuzz_Peek(uint256 price) public {
    vm.assume(price > 0 && price < (1 << 255));
    vm.mockCall(
      address(ethPriceFeed),
      abi.encodeWithSelector(ethPriceFeed.latestRoundData.selector),
      abi.encode(0, price, 0, 0, 0)
    );
    assertEq(ethChainlinkOracle.peek(), price);
  }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {Test} from "forge-std/Test.sol";
import {IOracle} from "contracts/interfaces/IOracle.sol";
import {IPriceFeedAggregator} from "contracts/interfaces/IPriceFeedAggregator.sol";
import {PriceFeedAggregator} from "contracts/oracles/PriceFeedAggregator.sol";

contract PriceFeedAggregatorTest is Test {
  PriceFeedAggregator public priceFeedAggregator;

  function setUp() public {
    priceFeedAggregator = new PriceFeedAggregator();
  }

  function test_SetUp() public {
    assertEq(address(priceFeedAggregator.owner()), address(this));
  }

  function testFuzz_SetPriceFeed(address asset, address priceFeed) public {
    vm.assume(asset != address(0x0));
    vm.assume(priceFeed != address(0x0));

    priceFeedAggregator.setPriceFeed(asset, priceFeed);
    assertEq(address(priceFeedAggregator.priceFeeds(asset)), priceFeed);
  }

  function testFuzz_SetPriceFeed_RevertZeroAddress(address nonZeroAddress) public {
    vm.assume(nonZeroAddress != address(0x0));
    vm.expectRevert(IPriceFeedAggregator.ZeroAddress.selector);
    priceFeedAggregator.setPriceFeed(address(0x0), nonZeroAddress);

    vm.expectRevert(IPriceFeedAggregator.ZeroAddress.selector);
    priceFeedAggregator.setPriceFeed(nonZeroAddress, address(0x0));

    vm.expectRevert(IPriceFeedAggregator.ZeroAddress.selector);
    priceFeedAggregator.setPriceFeed(address(0x0), address(0x0));
  }

  function testFuzz_SetPriceFeed_Revert_NonOwner(address caller) public {
    vm.assume(caller != address(this));
    vm.expectRevert("Ownable: caller is not the owner");
    vm.startPrank(caller);
    priceFeedAggregator.setPriceFeed(address(0x0), address(0x0));
    vm.stopPrank();
  }

  function testFuzz_Peek(address asset, address priceFeed, uint256 price, uint8 decimals) public {
    vm.assume(asset != address(0x0));
    vm.assume(priceFeed != address(0x0));
    vm.assume(price > 0 && price < (1 << 255));
    priceFeedAggregator.setPriceFeed(asset, priceFeed);

    vm.mockCall(priceFeed, abi.encodeWithSelector(IOracle.peek.selector), abi.encode(price));
    vm.mockCall(priceFeed, abi.encodeWithSelector(IOracle.decimals.selector), abi.encode(decimals));
    uint256 retPrice = priceFeedAggregator.peek(asset);
    assertEq(retPrice, price);
  }

  function testFuzz_Peek_Revert_ZeroAddress() public {
    vm.expectRevert(IPriceFeedAggregator.ZeroAddress.selector);
    priceFeedAggregator.peek(address(0x0));
  }
}

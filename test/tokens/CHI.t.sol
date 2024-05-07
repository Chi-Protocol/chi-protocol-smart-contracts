// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {TokenTest} from "./Token.t.sol";
import {CHI} from "contracts/tokens/CHI.sol";
import {ICHI} from "contracts/interfaces/ICHI.sol";
import {IToken} from "contracts/interfaces/IToken.sol";
import {IMintable} from "contracts/interfaces/IMintable.sol";

contract USCTest is TokenTest {
  uint256 public constant INITIAL_SUPPLY = 1000000000000000000000000000;

  function setUp() public {
    token = IToken(address(new CHI(INITIAL_SUPPLY)));
  }

  function test_SetUp() public {
    assertEq(token.name(), "CHI");
    assertEq(token.symbol(), "CHI");
    assertEq(token.decimals(), 18);
    assertEq(token.totalSupply(), INITIAL_SUPPLY);
    assertEq(token.balanceOf(address(this)), INITIAL_SUPPLY);
  }

  function testFuzz_BurnFrom(address caller, address from, uint256 amount) public {
    vm.assume(caller != address(0));
    vm.assume(from != address(0) && from != address(this));
    uint256 totalSupplyBefore = token.totalSupply();
    amount = bound(amount, 0, type(uint256).max - totalSupplyBefore);
    token.updateMinter(caller, true);
    vm.startPrank(from);
    token.approve(caller, amount);
    vm.stopPrank();

    vm.startPrank(caller);
    token.mint(from, amount);
    ICHI(address(token)).burnFrom(from, amount);
    vm.stopPrank();

    assertEq(token.balanceOf(from), 0);
    assertEq(token.totalSupply(), totalSupplyBefore);
  }

  function testFuzz_BurnFrom_Revert_NotMinter(address caller, address from, uint256 amount) public {
    vm.assume(caller != address(0));
    vm.assume(from != address(0));
    vm.startPrank(caller);
    vm.expectRevert(abi.encodeWithSelector(IMintable.NotMinter.selector, caller));
    ICHI(address(token)).burnFrom(from, amount);
    vm.stopPrank();
  }
}

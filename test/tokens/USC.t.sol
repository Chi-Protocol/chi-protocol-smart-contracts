// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {TokenTest} from "./Token.t.sol";
import {USC} from "contracts/tokens/USC.sol";
import {IToken} from "contracts/interfaces/IToken.sol";

contract USCTest is TokenTest {
  function setUp() public {
    token = IToken(address(new USC()));
  }

  function test_SetUp() public {
    assertEq(token.name(), "USC");
    assertEq(token.symbol(), "USC");
    assertEq(token.decimals(), 18);
  }
}

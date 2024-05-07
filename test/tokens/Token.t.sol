// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IToken} from "contracts/interfaces/IToken.sol";
import {IMintable} from "contracts/interfaces/IMintable.sol";

abstract contract TokenTest is Test {
  IToken public token;

  event UpdateMinter(address indexed _account, bool indexed _status);

  function testFuzz_UpdateMinter(address minter, bool status) public {
    vm.assume(minter != address(0));
    vm.expectEmit(true, true, true, true);
    emit UpdateMinter(minter, status);
    token.updateMinter(minter, status);
    assertEq(token.isMinter(minter), status);
  }

  function testFuzz_UpdateMinter_Revert_ZeroAddress(bool status) public {
    vm.expectRevert(IMintable.ZeroAddress.selector);
    token.updateMinter(address(0), status);
  }

  function testFuzz_UpdateMinter_Revert_NotOwner(address caller, address minter, bool status) public {
    vm.assume(caller != address(this));
    vm.expectRevert("Ownable: caller is not the owner");
    vm.startPrank(caller);
    token.updateMinter(minter, status);
    vm.stopPrank();
  }

  function testFuzz_Mint(address receiver, uint256 amount) public {
    vm.assume(receiver != address(0));
    uint256 totalSupplyBefore = token.totalSupply();
    amount = bound(amount, 0, type(uint256).max - totalSupplyBefore);
    token.updateMinter(address(this), true);

    token.mint(receiver, amount);
    assertEq(token.balanceOf(receiver), amount);
    assertEq(token.totalSupply(), totalSupplyBefore + amount);
  }

  function testFuzz_Mint_Revert_NotMinter(address receiver, uint256 amount) public {
    vm.expectRevert(abi.encodeWithSelector(IMintable.NotMinter.selector, address(this)));
    token.mint(receiver, amount);
  }

  function testFuzz_Burn(address caller, uint256 amount) public {
    vm.assume(caller != address(0));
    uint256 totalSupplyBefore = token.balanceOf(address(this));
    amount = bound(amount, 0, type(uint256).max - totalSupplyBefore);
    token.updateMinter(caller, true);

    vm.startPrank(caller);
    token.mint(caller, amount);
    token.burn(amount);
    vm.stopPrank();

    assertEq(token.balanceOf(address(this)), totalSupplyBefore);
    assertEq(token.totalSupply(), totalSupplyBefore);
  }

  function testFuzz_Burn_Revert_NotMinter(address caller, uint256 amount) public {
    vm.startPrank(caller);
    vm.expectRevert(abi.encodeWithSelector(IMintable.NotMinter.selector, caller));
    token.burn(amount);
    vm.stopPrank();
  }
}

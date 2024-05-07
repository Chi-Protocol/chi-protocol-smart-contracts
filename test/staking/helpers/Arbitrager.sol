// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IRewardController} from "contracts/interfaces/IRewardController.sol";

contract Arbitrager {
  IERC20 public usc;
  IRewardController public rewardController;

  constructor(IERC20 _usc, IRewardController _rewardController) {
    usc = _usc;
    rewardController = _rewardController;
  }

  function rewardUSC(uint256 amount) public {
    usc.approve(address(rewardController), amount);
    rewardController.rewardUSC(amount);
  }
}

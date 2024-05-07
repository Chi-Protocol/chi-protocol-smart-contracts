// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {USCStaking} from "contracts/staking/USCStaking.sol";
import {ChiStaking} from "contracts/staking/ChiStaking.sol";

contract Staker {
  IERC20 public usc;
  IERC20 public chi;
  USCStaking public uscStaking;
  ChiStaking public chiStaking;

  constructor(IERC20 _usc, IERC20 _chi, address _uscStaking, address _chiStaking) {
    usc = _usc;
    chi = _chi;
    uscStaking = USCStaking(_uscStaking);
    chiStaking = ChiStaking(_chiStaking);
  }

  function stake(uint256 amount) external {
    usc.approve(address(uscStaking), amount);
    uscStaking.stake(amount);
  }

  function stakeChi(uint256 amount) external {
    chi.approve(address(chiStaking), amount);
    chiStaking.stake(amount);
  }

  function unstake(uint256 amount) external {
    uscStaking.unstake(amount);
  }

  function unstakeChi(uint256 amount) external {
    chiStaking.unstake(amount);
  }

  function lockChi(uint256 amount, uint256 duration, bool useStakedTokens) external {
    chi.approve(address(chiStaking), amount);
    chiStaking.lock(amount, duration, useStakedTokens);
  }

  function claimUSCRewards() external {
    uscStaking.claimUSCRewards();
  }
}

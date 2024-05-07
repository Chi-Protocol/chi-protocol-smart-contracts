// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IStakingWithEpochs} from "./IStakingWithEpochs.sol";
import {IStaking} from "./IStaking.sol";

interface ILPStaking is IStakingWithEpochs, IStaking {
  event UpdateEpoch(uint256 indexed epoch, uint256 chiEmissions);
  event LockChi(address indexed account, uint256 amount, uint256 duration);
  event ClaimStETH(address indexed account, uint256 amount);

  error InvalidDuration(uint256 duration);

  function updateEpoch(uint256, uint256) external;

  function lockChi(uint256) external;
}

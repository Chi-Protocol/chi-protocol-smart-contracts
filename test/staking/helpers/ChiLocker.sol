// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {IChiLocking} from "contracts/interfaces/IChiLocking.sol";

contract ChiLocker {
  IChiLocking public chiLocking;

  constructor(IChiLocking _chiLocking) {
    chiLocking = _chiLocking;
  }

  function lockChi(uint256 amount, uint256 duration) public {
    chiLocking.lockChi(address(this), amount, duration);
  }
}

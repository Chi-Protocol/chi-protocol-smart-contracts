// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IOracle} from "../interfaces/IOracle.sol";

contract MockOracle is IOracle {
  uint256 public price;

  function name() external pure override returns (string memory) {
    return "MockOracle";
  }

  function decimals() external pure override returns (uint8) {
    return 8;
  }

  function setPrice(uint256 _price) external {
    price = _price;
  }

  function peek() external view override returns (uint256) {
    return price;
  }
}

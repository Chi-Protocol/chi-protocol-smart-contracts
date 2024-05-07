// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// library copied from uniswap/v2-core/contracts/libraries/SafeMath.sol
// the only change is in pragma solidity version.
// this contract was the reason of incompatible solidity version error

// a library for performing overflow-safe math, courtesy of DappHub (https://github.com/dapphub/ds-math)

library SafeMath {
  function add(uint x, uint y) internal pure returns (uint z) {
    require((z = x + y) >= x, "ds-math-add-overflow");
  }

  function sub(uint x, uint y) internal pure returns (uint z) {
    require((z = x - y) <= x, "ds-math-sub-underflow");
  }

  function mul(uint x, uint y) internal pure returns (uint z) {
    require(y == 0 || (z = x * y) / y == x, "ds-math-mul-overflow");
  }
}

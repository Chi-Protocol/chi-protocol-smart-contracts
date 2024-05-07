// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IToken.sol";

interface ICHI is IToken {
  /// @notice Burns given amount from given account
  /// @param account Account to burn CHI from
  /// @param amount Amount of CHI to burn
  /// @custom:usage This function should be called from OCHI contract in purpose of burning CHI to boost option discount
  function burnFrom(address account, uint256 amount) external;
}

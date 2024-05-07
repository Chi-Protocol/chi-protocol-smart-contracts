// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IMintable} from "./IMintable.sol";

interface IToken is IMintable, IERC20 {
  /// @notice Returns name of token
  /// @return name Name of token
  function name() external view returns (string memory name);

  /// @notice Returns symbol of token
  /// @return symbol Symbol of token
  function symbol() external view returns (string memory symbol);

  /// @notice Returns decimals of token
  /// @return decimals Decimals of token
  function decimals() external view returns (uint8 decimals);

  /// @notice Mints given amount of token to given account
  /// @param account Account to mint token to
  /// @param amount Amount of token to mint
  /// @custom:usage This function should be called from Arbitrage contract in purpose of minting token
  function mint(address account, uint256 amount) external;

  /// @notice Burns given amount from caller
  /// @param amount Amount of token to burn
  /// @custom:usage This function should be called from Arbitrage contract in purpose of burning token
  function burn(uint256 amount) external;
}

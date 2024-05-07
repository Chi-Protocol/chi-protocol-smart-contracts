// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IArbitrage} from "./IArbitrage.sol";

interface IArbitrageV2 is IArbitrage {
  event UpdateArbitrager(address indexed account, bool status);

  error NotArbitrager(address account);
  error PriceIsNotPegged();

  /// @notice Update arbitrager status
  /// @dev This function can be called only by owner of contract
  /// @param account Arbitrager account
  /// @param status Arbitrager status
  function updateArbitrager(address account, bool status) external;

  /// @notice Claim rewards from arbitrages
  /// @dev This function can be called only by owner of contract
  /// @param tokens Tokens to claim rewards for
  function claimRewards(IERC20[] memory tokens) external;
}

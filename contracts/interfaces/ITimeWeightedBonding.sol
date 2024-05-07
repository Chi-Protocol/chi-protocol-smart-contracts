// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ITimeWeightedBonding {
  event SetCliffTimestampEnd(uint256 indexed cliffTimestampEnd);
  event RecoverChi(address indexed account, uint256 amount);
  event Buy(address indexed account, uint256 amount, uint256 ethCost);
  event Vest(address indexed account, uint256 amount);

  error EtherSendFailed(address to, uint256 value);

  /// @notice Sets timestamp when cliff period ends in ChiVesting contract
  /// @dev This can be replaced by getting cliff period from ChiVesting contract
  /// @dev It is kept this way so owner can dictate discount by changing this parameter
  /// @param _cliffTimestampEnd Timestamp when cliff period ends
  function setCliffTimestampEnd(uint256 _cliffTimestampEnd) external;

  /// @notice Vests given amount of CHI tokens for given user
  /// @param user Address of user to vest tokens for
  /// @param amount Amount of CHI tokens to vest
  /// @custom:usage This function should be called from owner in purpose of vesting CHI tokens for initial team
  function vest(address user, uint256 amount) external;

  /// @notice Buys CHI tokens for discounted price for caller, sends ETH to treasury
  /// @param amount Amount of CHI tokens to buy
  function buy(uint256 amount) external payable;

  /// @notice Recovers CHI tokens from contract
  /// @param amount Amount of CHI tokens to recover
  /// @custom:usage This function should be called from owner in purpose of recovering CHI tokens that are not sold
  function recoverChi(uint256 amount) external;
}

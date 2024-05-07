// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IIDO {
  error IDONotRunning();
  error IDOAlreadyStarted();
  error MinValueNotReached();
  error MaxValueReached();
  error SoftCapReached();
  error SoftCapNotReached();
  error IDONotFinished();
  error ClaimingNotEnabled();
  error AlreadyClaimed();
  error AmountLargerThenBought(uint256 amount, uint256 ethAmount);
  error EtherSendFailed(address to, uint256 amount);

  event Buy(address indexed account, uint256 amount, uint256 totalEthAmount);
  event Withdraw(address indexed account, uint256 amount, uint256 ethAmountLeft);
  event Claim(address indexed account, uint256 ethAmount, uint256 chiAmount);

  /// @notice Buys CHI token on IDO for the listed price by sending ETH
  function buy() external payable;

  /// @notice Withdraws deposited ETH if soft cap is not reached
  function withdraw() external;

  /// @notice Claims bought CHI once the IDO is finished
  /// @notice Bought CHI is vested
  function claim() external;

  /// @notice Returns how much CHI would user get at this moment for deposited ETH amount
  /// @param account account for which to return amount
  /// @param ethDeposit deposited ETH amount
  /// @return chiAmount resulting CHI amount
  function calculateChiAmountForAccount(address account, uint256 ethDeposit) external view returns (uint256 chiAmount);
}

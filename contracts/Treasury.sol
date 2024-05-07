// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "contracts/interfaces/ITreasury.sol";

/// @title Treasury
/// @notice This contract is responsible for keeping the tokens and distributing to other contracts for further rewards distribution
contract Treasury is ITreasury, Ownable {
  using SafeERC20 for IERC20;

  constructor() Ownable() {}

  /// @inheritdoc ITreasury
  function transfer(address token, address destination, uint256 amount) external onlyOwner {
    if (token == address(0)) {
      _nativeTransfer(destination, amount);
    } else {
      _erc20Transfer(token, destination, amount);
    }
  }

  function _nativeTransfer(address destination, uint256 amount) internal {
    (bool success, ) = destination.call{value: amount}(new bytes(0));
    if (!success) {
      revert EtherSendFailed(msg.sender, amount);
    }
  }

  function _erc20Transfer(address token, address destination, uint256 amount) internal {
    IERC20(token).safeTransfer(destination, amount);
  }

  fallback() external payable {}

  receive() external payable {}
}

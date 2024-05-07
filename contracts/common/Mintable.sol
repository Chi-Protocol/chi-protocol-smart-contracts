// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/IMintable.sol";

/// @title Mintable
/// @notice CHI and USC tokens should inherit from this contract
contract Mintable is IMintable, Ownable {
  mapping(address account => bool status) public isMinter;

  modifier onlyMinter() {
    if (!isMinter[msg.sender]) {
      revert NotMinter(msg.sender);
    }
    _;
  }

  /// @inheritdoc IMintable
  function updateMinter(address account, bool status) external onlyOwner {
    if (account == address(0)) {
      revert ZeroAddress();
    }
    isMinter[account] = status;
    emit UpdateMinter(account, status);
  }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IMintable {
  error ZeroAddress();
  error NotMinter(address _caller);

  event UpdateMinter(address indexed _account, bool indexed _status);

  /// @notice Checks if account is minter
  /// @param account Address to check
  /// @return status Status of minter, true if minter, false if not
  function isMinter(address account) external view returns (bool status);

  /// @notice Grants/revokes minter role
  /// @param account Address to grant/revoke minter role
  /// @param status True to grant, false to revoke
  function updateMinter(address account, bool status) external;
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../interfaces/IChiLocking.sol";
import "../interfaces/IChiVesting.sol";

/// @title Voting Escrow CHI token contract
/// @notice This contract is used by governance to determine voting power for users
/// @notice Users get voting power by locking chi tokens
contract veCHI is ERC20 {
  error NonTransferable();

  IChiLocking public immutable chiLocking;
  IChiVesting public immutable chiVesting;

  constructor(IChiLocking _chiLocking, IChiVesting _chiVesting) ERC20("Voting Escrow CHI", "veCHI") {
    chiLocking = _chiLocking;
    chiVesting = _chiVesting;
  }

  /// @notice Returns balance/voting power of given account
  /// @param account Account to get balance/voting power for
  function balanceOf(address account) public view virtual override returns (uint256) {
    return chiLocking.getVotingPower(account) + chiVesting.getVotingPower(account);
  }

  /// @notice Returns total voting power in the protocol
  function totalSupply() public view virtual override returns (uint256) {
    return chiLocking.getTotalVotingPower() + chiVesting.getTotalVotingPower();
  }

  /// @notice veCHI is not transferable/mintable/burnable
  function _beforeTokenTransfer(address, address, uint256) internal pure override {
    revert NonTransferable();
  }
}

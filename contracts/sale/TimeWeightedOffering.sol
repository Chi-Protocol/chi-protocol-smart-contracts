// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/ITimeWeightedBonding.sol";
import "../interfaces/IPriceFeedAggregator.sol";
import "../interfaces/IChiVesting.sol";
import "../library/ExternalContractAddresses.sol";

contract TimeWeightedOffering is Ownable {
  using SafeERC20 for IERC20;

  IERC20 public immutable chi;
  IChiVesting public immutable chiVesting;

  event Vest(address indexed user, uint256 amount);

  constructor(IERC20 _chi, IChiVesting _chiVesting) Ownable() {
    chi = _chi;
    chiVesting = _chiVesting;
  }

  function vest(address user, uint256 amount) external onlyOwner {
    chi.safeTransferFrom(msg.sender, address(chiVesting), amount);
    chiVesting.addVesting(user, amount);
    emit Vest(user, amount);
  }
}

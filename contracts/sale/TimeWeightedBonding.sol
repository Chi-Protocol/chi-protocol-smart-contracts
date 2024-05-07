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

/// @title Contract handles buying CHI tokens for investor using time weighted bonding mechanism
/// @notice This contract holds CHI tokens that are for sale
/// @notice This contract sells tokens for discounted price and vests them through ChiVesting contract
contract TimeWeightedBonding is ITimeWeightedBonding, Ownable {
  using SafeERC20 for IERC20;

  uint256 public constant BASE_PRICE = 10 ** 8;
  uint256 public constant MAX_LOCK_PERIOD = 208; // 208 epochs = 208 weeks = 4 years
  uint256 public constant EPOCH_DURATION = 1 weeks;
  address public constant WETH = ExternalContractAddresses.WETH;

  address public immutable treasury;
  IERC20 public immutable chi;
  IChiVesting public immutable chiVesting;
  IPriceFeedAggregator public immutable priceFeedAggregator;

  uint256 public cliffTimestampEnd;

  constructor(
    IERC20 _chi,
    IPriceFeedAggregator _priceFeedAggregator,
    IChiVesting _chiVesting,
    uint256 _cliffTimestampEnd,
    address _treasury
  ) Ownable() {
    chi = _chi;
    priceFeedAggregator = _priceFeedAggregator;
    chiVesting = _chiVesting;
    cliffTimestampEnd = _cliffTimestampEnd;
    treasury = _treasury;
  }

  /// @inheritdoc ITimeWeightedBonding
  function setCliffTimestampEnd(uint256 _cliffTimestampEnd) external onlyOwner {
    cliffTimestampEnd = _cliffTimestampEnd;
    emit SetCliffTimestampEnd(_cliffTimestampEnd);
  }

  /// @inheritdoc ITimeWeightedBonding
  function recoverChi(uint256 amount) external onlyOwner {
    chi.safeTransfer(msg.sender, amount);
    emit RecoverChi(msg.sender, amount);
  }

  /// @inheritdoc ITimeWeightedBonding
  function vest(address user, uint256 amount) external onlyOwner {
    chi.safeTransferFrom(msg.sender, address(chiVesting), amount);
    chiVesting.addVesting(user, amount);
    emit Vest(user, amount);
  }

  /// @inheritdoc ITimeWeightedBonding
  function buy(uint256 amount) external payable {
    uint256 ethPrice = _peek(WETH);
    uint256 chiPrice = _getDiscountedChiPrice();
    uint256 ethCost = Math.mulDiv(amount, chiPrice, ethPrice);

    chi.safeTransfer(address(chiVesting), amount);
    chiVesting.addVesting(msg.sender, amount);

    _safeTransferETH(treasury, ethCost);
    _safeTransferETH(msg.sender, msg.value - ethCost);

    emit Buy(msg.sender, amount, ethCost);
  }

  function _getDiscountedChiPrice() private view returns (uint256) {
    uint256 cliffDuration = (cliffTimestampEnd - block.timestamp) / EPOCH_DURATION;
    uint256 discount = Math.mulDiv(cliffDuration, BASE_PRICE, MAX_LOCK_PERIOD);
    return Math.mulDiv(_peek(address(chi)), BASE_PRICE - discount, BASE_PRICE);
  }

  function _peek(address asset) private view returns (uint256) {
    uint256 price = priceFeedAggregator.peek(asset);
    return price;
  }

  function _safeTransferETH(address to, uint256 value) private {
    if (value != 0) {
      (bool success, ) = to.call{value: value}(new bytes(0));
      if (!success) {
        revert EtherSendFailed(to, value);
      }
    }
  }
}

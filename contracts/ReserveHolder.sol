// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "./interfaces/IReserveHolder.sol";
import "./interfaces/IPriceFeedAggregator.sol";
import "./interfaces/ISTETH.sol";
import "./interfaces/IWETH.sol";
import "./interfaces/ICurvePool.sol";
import "./library/ExternalContractAddresses.sol";

/// @title Contract for holding stETH reserves
/// @notice This contract holds stETH reserves and rebalances them
/// @notice Part of reserves are is WETH so arbitrage can take them and perform aribtrage without swapping stETH for WETH
/// @dev This contract is upgradeable
contract ReserveHolder is IReserveHolder, OwnableUpgradeable {
  using SafeERC20 for ISTETH;
  using SafeERC20 for IWETH;

  uint256 public constant BASE_PRICE = 1e8;
  uint256 public constant MAX_PERCENTAGE = 100_00;
  IWETH public constant WETH = IWETH(ExternalContractAddresses.WETH);
  ISTETH public constant stETH = ISTETH(ExternalContractAddresses.stETH);
  ICurvePool public constant curvePool = ICurvePool(ExternalContractAddresses.CURVE_ETH_STETH_POOL);

  IPriceFeedAggregator public priceFeedAggregator;
  address public claimer;
  uint256 public totalClaimed;
  uint256 public swapEthTolerance;
  uint256 public ethThreshold;
  uint256 public totalStEthDeposited;
  uint256 public curveStEthSafeGuardPercentage;

  mapping(address account => bool status) public isArbitrager;

  modifier onlyArbitrager() {
    if (isArbitrager[msg.sender] != true) {
      revert NotArbitrager(msg.sender);
    }
    _;
  }

  modifier onlyClaimer() {
    if (msg.sender != claimer) {
      revert NotClaimer(msg.sender);
    }
    _;
  }

  receive() external payable {
    emit Receive(msg.sender, msg.value);
  }

  function initialize(
    IPriceFeedAggregator _priceFeedAggregator,
    address _claimer,
    uint256 _ethThreshold,
    uint256 _curveStEthSafeGuardPercentage
  ) external initializer {
    if (_ethThreshold > MAX_PERCENTAGE) {
      revert ThresholdTooHigh(_ethThreshold);
    }
    __Ownable_init();
    claimer = _claimer;
    priceFeedAggregator = _priceFeedAggregator;
    ethThreshold = _ethThreshold;
    curveStEthSafeGuardPercentage = _curveStEthSafeGuardPercentage;
    swapEthTolerance = 0.1 ether;
  }

  /// @inheritdoc IReserveHolder
  function setArbitrager(address arbitrager, bool status) external onlyOwner {
    isArbitrager[arbitrager] = status;
    emit SetArbitrager(arbitrager, status);
  }

  /// @inheritdoc IReserveHolder
  function setClaimer(address _claimer) external onlyOwner {
    claimer = _claimer;
    emit SetClaimer(_claimer);
  }

  /// @inheritdoc IReserveHolder
  function setEthThreshold(uint256 _ethThreshold) external onlyOwner {
    if (_ethThreshold > MAX_PERCENTAGE) {
      revert ThresholdTooHigh(_ethThreshold);
    }
    ethThreshold = _ethThreshold;
    emit SetEthThreshold(_ethThreshold);
  }

  /// @inheritdoc IReserveHolder
  function setSwapEthTolerance(uint256 _swapEthTolerance) external onlyOwner {
    swapEthTolerance = _swapEthTolerance;
    emit SetSwapEthTolerance(_swapEthTolerance);
  }

  /// @inheritdoc IReserveHolder
  function setCurveStEthSafeGuardPercentage(uint256 _curveStEthSafeGuardPercentage) external onlyOwner {
    if (_curveStEthSafeGuardPercentage > MAX_PERCENTAGE) {
      revert SafeGuardTooHigh(_curveStEthSafeGuardPercentage);
    }
    curveStEthSafeGuardPercentage = _curveStEthSafeGuardPercentage;
    emit SetCurveStEthSafeGuardPercentage(_curveStEthSafeGuardPercentage);
  }

  /// @inheritdoc IReserveHolder
  function getReserveValue() external view returns (uint256) {
    uint256 stEthPrice = priceFeedAggregator.peek(address(stETH));
    uint256 ethPrice = priceFeedAggregator.peek(address(WETH));
    uint256 ethBalance = address(this).balance + WETH.balanceOf(address(this));
    return Math.mulDiv(totalStEthDeposited, stEthPrice, 1e18) + Math.mulDiv(ethBalance, ethPrice, 1e18);
  }

  /// @inheritdoc IReserveHolder
  function getCurrentRewards() external view returns (uint256) {
    return stETH.balanceOf(address(this)) - totalStEthDeposited;
  }

  /// @inheritdoc IReserveHolder
  function getCumulativeRewards() external view returns (uint256) {
    return stETH.balanceOf(address(this)) - totalStEthDeposited + totalClaimed;
  }

  /// @inheritdoc IReserveHolder
  function deposit(uint256 amount) external {
    uint256 balanceBefore = stETH.balanceOf(address(this));
    stETH.safeTransferFrom(msg.sender, address(this), amount);
    totalStEthDeposited += stETH.balanceOf(address(this)) - balanceBefore;

    emit Deposit(msg.sender, amount);
  }

  /// @inheritdoc IReserveHolder
  function rebalance() external {
    uint256 ethPrice = _peek(address(WETH));
    uint256 stEthPrice = _peek(address(stETH));
    uint256 ethValue = Math.mulDiv(WETH.balanceOf(address(this)), ethPrice, BASE_PRICE);
    uint256 stEthValue = Math.mulDiv(stETH.balanceOf(address(this)), stEthPrice, BASE_PRICE);
    uint256 ethThresholdValue = Math.mulDiv((ethValue + stEthValue), ethThreshold, MAX_PERCENTAGE);

    if (ethThresholdValue > ethValue) {
      uint256 stEthAmountToSwap = Math.mulDiv((ethThresholdValue - ethValue), BASE_PRICE, stEthPrice);
      uint256 stEthBalanceBefore = stETH.balanceOf(address(this));
      _swap(stEthAmountToSwap);
      uint256 stEthBalanceAfter = stETH.balanceOf(address(this));
      totalStEthDeposited -= stEthBalanceBefore - stEthBalanceAfter;

      emit Rebalance(0, stEthAmountToSwap);
    } else if (ethThresholdValue < ethValue) {
      uint256 stEthBalanceBefore = stETH.balanceOf(address(this));
      uint256 ethAmountToSwap = Math.mulDiv((ethValue - ethThresholdValue), BASE_PRICE, ethPrice);

      WETH.withdraw(ethAmountToSwap);
      stETH.submit{value: ethAmountToSwap}(address(this));

      uint256 stEthBalanceAfter = stETH.balanceOf(address(this));
      totalStEthDeposited += stEthBalanceAfter - stEthBalanceBefore;

      emit Rebalance(ethAmountToSwap, 0);
    }
  }

  /// @inheritdoc IReserveHolder
  function redeem(uint256 amount) external onlyArbitrager returns (uint256) {
    uint256 ethBalance = WETH.balanceOf(address(this));
    if (amount > ethBalance) {
      uint256 stEthBalanceBefore = stETH.balanceOf(address(this));
      uint256 stEthAmountToSwap = amount - ethBalance;
      uint256 safeStEthAmountToSwap = stEthAmountToSwap +
        Math.mulDiv(stEthAmountToSwap, curveStEthSafeGuardPercentage, MAX_PERCENTAGE);
      _swap(safeStEthAmountToSwap);
      uint256 stEthBalanceAfter = stETH.balanceOf(address(this));
      totalStEthDeposited -= stEthBalanceBefore - stEthBalanceAfter;

      emit RedeemSwap(amount - ethBalance, safeStEthAmountToSwap);
    }
    WETH.safeTransfer(msg.sender, amount);

    emit Redeem(msg.sender, amount);
    return amount;
  }

  /// @inheritdoc IReserveHolder
  function claimRewards(address account, uint256 amount) external onlyClaimer {
    totalClaimed += amount;
    stETH.safeTransfer(account, amount);
    emit ClaimRewards(account, amount);
  }

  /// @inheritdoc IReserveHolder
  function wrapETH() external {
    WETH.deposit{value: address(this).balance}();
  }

  function _swap(uint256 amountIn) private {
    stETH.approve(address(curvePool), amountIn);
    uint256 ethReceived = curvePool.exchange(1, 0, amountIn, 0);
    WETH.deposit{value: ethReceived}();
  }

  function _peek(address asset) private view returns (uint256) {
    uint256 price = priceFeedAggregator.peek(asset);
    return price;
  }

  function _safeTransferETH(address to, uint256 value) private {
    (bool success, ) = to.call{value: value}(new bytes(0));
    if (!success) {
      revert EtherSendFailed(to, value);
    }
  }
}

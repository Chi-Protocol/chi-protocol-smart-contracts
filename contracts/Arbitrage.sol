// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "contracts/interfaces/IWETH.sol";
import "contracts/interfaces/IPriceFeedAggregator.sol";
import "contracts/interfaces/IReserveHolder.sol";
import "contracts/interfaces/IArbitrageERC20.sol";
import "contracts/interfaces/IRewardController.sol";
import "contracts/library/ExternalContractAddresses.sol";
import "contracts/uniswap/libraries/UniswapV2Library.sol";
import "contracts/interfaces/IArbitrage.sol";

/// @title Contract for performing arbitrage
/// @notice This contract is responsible for buying USC tokens and for keeping price of USC token pegged to target price
/// @dev This contract does not hold any assets
contract Arbitrage is IArbitrage, ReentrancyGuard, Ownable {
  using SafeERC20 for IERC20;
  using SafeERC20 for IArbitrageERC20;

  uint256 public constant BASE_PRICE = 1e8;
  uint256 public constant USC_TARGET_PRICE = 1e8;
  uint256 public constant EQ_PRICE_DELTA = 1000 wei;
  uint256 public constant POOL_FEE = 30;
  uint256 public constant MAX_FEE = 100_00;
  // F = (1 - pool_fee) on 18 decimals
  uint256 public constant F = ((MAX_FEE - POOL_FEE) * 1e18) / MAX_FEE;
  uint16 public constant MAX_PRICE_TOLERANCE = 100_00;
  address public constant WETH = ExternalContractAddresses.WETH;
  address public constant STETH = ExternalContractAddresses.stETH;
  IUniswapV2Router02 public constant swapRouter = IUniswapV2Router02(ExternalContractAddresses.UNI_V2_SWAP_ROUTER);
  IUniswapV2Factory public constant poolFactory = IUniswapV2Factory(ExternalContractAddresses.UNI_V2_POOL_FACTORY);

  IArbitrageERC20 public immutable USC;
  IArbitrageERC20 public immutable CHI;
  IRewardController public immutable rewardController;
  IPriceFeedAggregator public immutable priceFeedAggregator;
  IReserveHolder public immutable reserveHolder;

  uint256 public maxMintPriceDiff;
  uint16 public priceTolerance;

  constructor(
    IArbitrageERC20 _USC,
    IArbitrageERC20 _CHI,
    IRewardController _rewardController,
    IPriceFeedAggregator _priceFeedAggregator,
    IReserveHolder _reserveHolder
  ) Ownable() {
    USC = _USC;
    CHI = _CHI;
    rewardController = _rewardController;
    priceFeedAggregator = _priceFeedAggregator;
    reserveHolder = _reserveHolder;

    IERC20(USC).approve(address(rewardController), type(uint256).max);
    IERC20(STETH).approve(address(reserveHolder), type(uint256).max);
  }

  /// @inheritdoc IArbitrage
  function setPriceTolerance(uint16 _priceTolerance) external onlyOwner {
    if (_priceTolerance > MAX_PRICE_TOLERANCE) {
      revert ToleranceTooBig(_priceTolerance);
    }
    priceTolerance = _priceTolerance;
    emit SetPriceTolerance(_priceTolerance);
  }

  /// @inheritdoc IArbitrage
  function setMaxMintPriceDiff(uint256 _maxMintPriceDiff) external onlyOwner {
    maxMintPriceDiff = _maxMintPriceDiff;
    emit SetMaxMintPriceDiff(_maxMintPriceDiff);
  }

  /// @inheritdoc IArbitrage
  function mint() external payable nonReentrant returns (uint256) {
    uint256 ethAmount = msg.value;
    IWETH(WETH).deposit{value: ethAmount}();
    IERC20(WETH).safeTransfer(address(reserveHolder), ethAmount);
    return _mint(ethAmount, WETH);
  }

  /// @inheritdoc IArbitrage
  function mintWithWETH(uint256 wethAmount) external nonReentrant returns (uint256) {
    IERC20(WETH).safeTransferFrom(msg.sender, address(reserveHolder), wethAmount);
    return _mint(wethAmount, WETH);
  }

  /// @inheritdoc IArbitrage
  function mintWithStETH(uint256 stETHAmount) external nonReentrant returns (uint256) {
    IERC20(STETH).safeTransferFrom(msg.sender, address(this), stETHAmount);
    reserveHolder.deposit(IERC20(STETH).balanceOf(address(this)));
    return _mint(stETHAmount, STETH);
  }

  /// @inheritdoc IArbitrage
  function executeArbitrage() public override nonReentrant returns (uint256) {
    return _executeArbitrage();
  }

  /// @inheritdoc IArbitrage
  function getArbitrageData()
    public
    view
    returns (bool isPriceAboveTarget, bool isExcessOfReserves, uint256 reserveDiff, uint256 discount)
  {
    uint256 ethPrice = priceFeedAggregator.peek(WETH);
    uint256 uscPrice = _getAndValidateUscPrice(ethPrice);

    uint256 reserveValue;
    (isExcessOfReserves, reserveDiff, reserveValue) = _getReservesData();
    isPriceAboveTarget = uscPrice >= USC_TARGET_PRICE;

    //If prices are equal delta does not need to be calculated
    if (_almostEqualAbs(uscPrice, USC_TARGET_PRICE, EQ_PRICE_DELTA)) {
      discount = Math.mulDiv(reserveDiff, BASE_PRICE, reserveValue);
    }
  }

  function _executeArbitrage() internal returns (uint256) {
    (bool isPriceAboveTarget, bool isExcessOfReserves, uint256 reserveDiff, uint256 discount) = getArbitrageData();

    uint256 ethPrice = priceFeedAggregator.peek(WETH);

    if (discount != 0) {
      if (isExcessOfReserves) {
        return _arbitrageAtPegExcessOfReserves(reserveDiff, discount, ethPrice);
      } else {
        return _arbitrageAtPegDeficitOfReserves(reserveDiff, discount, ethPrice);
      }
    } else if (isPriceAboveTarget) {
      if (isExcessOfReserves) {
        return _arbitrageAbovePegExcessOfReserves(reserveDiff, ethPrice);
      } else {
        return _arbitrageAbovePegDeficitOfReserves(reserveDiff, ethPrice);
      }
    } else {
      if (isExcessOfReserves) {
        return _arbitrageBellowPegExcessOfReserves(reserveDiff, ethPrice);
      } else {
        return _arbitrageBellowPegDeficitOfReserves(reserveDiff, ethPrice);
      }
    }
  }

  function _mint(uint256 amount, address token) private returns (uint256) {
    uint256 ethPrice = priceFeedAggregator.peek(WETH);

    uint256 uscSpotPrice = _calculateUscSpotPrice(ethPrice);
    if (!_almostEqualAbs(uscSpotPrice, USC_TARGET_PRICE, maxMintPriceDiff)) {
      _executeArbitrage();
    }

    uint256 usdValue;
    if (token == WETH) {
      usdValue = _convertTokenAmountToUsdValue(amount, ethPrice);
    } else {
      uint256 tokenPrice = priceFeedAggregator.peek(token);
      usdValue = _convertTokenAmountToUsdValue(amount, tokenPrice);
    }

    uint256 uscAmountToMint = _convertUsdValueToTokenAmount(usdValue, USC_TARGET_PRICE);
    USC.mint(msg.sender, uscAmountToMint);
    emit Mint(msg.sender, token, amount, uscAmountToMint);
    return uscAmountToMint;
  }

  function _arbitrageAbovePegExcessOfReserves(uint256 reserveDiff, uint256 ethPrice) private returns (uint256) {
    uint256 deltaUSC = _calculateDeltaUSC(ethPrice);

    USC.mint(address(this), deltaUSC);
    uint256 ethAmountReceived = _swap(address(USC), WETH, deltaUSC);

    uint256 deltaUsd = _convertTokenAmountToUsdValue(deltaUSC, USC_TARGET_PRICE);
    uint256 deltaInETH = _convertUsdValueToTokenAmount(deltaUsd, ethPrice);

    if (deltaInETH > ethAmountReceived) {
      revert DeltaBiggerThanAmountReceivedETH(deltaInETH, ethAmountReceived);
    }

    uint256 ethAmountToSwap;
    uint256 ethAmountForReserves;

    if (deltaUsd > reserveDiff) {
      ethAmountToSwap = _convertUsdValueToTokenAmount(reserveDiff, ethPrice);
      ethAmountForReserves = _convertUsdValueToTokenAmount(deltaUsd, ethPrice) - ethAmountToSwap;
      IERC20(WETH).safeTransfer(address(reserveHolder), ethAmountForReserves);
    } else {
      ethAmountToSwap = _convertUsdValueToTokenAmount(deltaUsd, ethPrice);
    }

    uint256 chiAmountReceived = _swap(WETH, address(CHI), ethAmountToSwap);
    CHI.burn(chiAmountReceived);

    uint256 rewardAmount = ethAmountReceived - ethAmountToSwap - ethAmountForReserves;

    IERC20(WETH).safeTransfer(msg.sender, rewardAmount);
    uint256 rewardValue = _convertTokenAmountToUsdValue(rewardAmount, ethPrice);
    emit ExecuteArbitrage(msg.sender, 1, deltaUsd, reserveDiff, ethPrice, rewardValue);
    return rewardValue;
  }

  function _arbitrageAbovePegDeficitOfReserves(uint256 reserveDiff, uint256 ethPrice) private returns (uint256) {
    uint256 deltaUSC = _calculateDeltaUSC(ethPrice);

    USC.mint(address(this), deltaUSC);
    uint256 ethAmountReceived = _swap(address(USC), WETH, deltaUSC);

    uint256 deltaUsd = _convertTokenAmountToUsdValue(deltaUSC, USC_TARGET_PRICE);
    uint256 deltaInETH = _convertUsdValueToTokenAmount(deltaUsd, ethPrice);

    if (deltaInETH > ethAmountReceived) {
      revert DeltaBiggerThanAmountReceivedETH(deltaInETH, ethAmountReceived);
    }

    IERC20(WETH).safeTransfer(address(reserveHolder), deltaInETH);

    uint256 rewardAmount = ethAmountReceived - deltaInETH;

    IERC20(WETH).safeTransfer(msg.sender, rewardAmount);
    uint256 rewardValue = _convertTokenAmountToUsdValue(rewardAmount, ethPrice);
    emit ExecuteArbitrage(msg.sender, 2, deltaUsd, reserveDiff, ethPrice, rewardValue);
    return rewardValue;
  }

  function _arbitrageBellowPegExcessOfReserves(uint256 reserveDiff, uint256 ethPrice) private returns (uint256) {
    uint256 uscAmountToFreeze;
    uint256 uscAmountToBurn;
    uint256 ethAmountToRedeem;
    uint256 ethAmountFromChi;

    uint256 deltaETH = _calculateDeltaETH(ethPrice);
    uint256 deltaUsd = _convertTokenAmountToUsdValue(deltaETH, ethPrice);

    if (deltaUsd > reserveDiff) {
      ethAmountToRedeem = _convertUsdValueToTokenAmount(reserveDiff, ethPrice);
      uscAmountToFreeze = _convertUsdValueToTokenAmount(reserveDiff, USC_TARGET_PRICE);
      uscAmountToBurn = _convertUsdValueToTokenAmount(deltaUsd - reserveDiff, USC_TARGET_PRICE);

      uint256 chiAmountToMint = _getAmountInForAmountOut(address(CHI), WETH, deltaETH - ethAmountToRedeem);
      CHI.mint(address(this), chiAmountToMint);
      ethAmountFromChi = _swap(address(CHI), WETH, chiAmountToMint);
    } else {
      ethAmountToRedeem = deltaETH;
      uscAmountToFreeze = _convertUsdValueToTokenAmount(deltaUsd, USC_TARGET_PRICE);
    }

    reserveHolder.redeem(ethAmountToRedeem);
    uint256 uscAmountReceived = _swap(WETH, address(USC), ethAmountToRedeem + ethAmountFromChi);

    if (uscAmountReceived < uscAmountToFreeze) {
      uscAmountToFreeze = uscAmountReceived;
    }

    rewardController.rewardUSC(uscAmountToFreeze);

    if (uscAmountToBurn > 0) {
      USC.burn(uscAmountToBurn);
    }

    uint256 rewardAmount = uscAmountReceived - uscAmountToFreeze - uscAmountToBurn;
    USC.safeTransfer(msg.sender, rewardAmount);
    uint256 rewardValue = _convertTokenAmountToUsdValue(rewardAmount, USC_TARGET_PRICE);
    emit ExecuteArbitrage(msg.sender, 3, deltaUsd, reserveDiff, ethPrice, rewardValue);
    return rewardValue;
  }

  function _arbitrageBellowPegDeficitOfReserves(uint256 reserveDiff, uint256 ethPrice) private returns (uint256) {
    uint256 uscAmountToBurn;
    uint256 uscAmountToFreeze;
    uint256 ethAmountToRedeem;
    uint256 ethAmountFromChi;

    uint256 deltaETH = _calculateDeltaETH(ethPrice);
    uint256 deltaUsd = _convertTokenAmountToUsdValue(deltaETH, ethPrice);

    if (deltaUsd > reserveDiff) {
      ethAmountFromChi = _convertUsdValueToTokenAmount(reserveDiff, ethPrice);
      uscAmountToBurn = _convertUsdValueToTokenAmount(reserveDiff, USC_TARGET_PRICE);
      uscAmountToFreeze = _convertUsdValueToTokenAmount(deltaUsd - reserveDiff, USC_TARGET_PRICE);
      ethAmountToRedeem = deltaETH - ethAmountFromChi;
      reserveHolder.redeem(ethAmountToRedeem);
    } else {
      ethAmountFromChi = deltaETH;
      uscAmountToBurn = _convertUsdValueToTokenAmount(deltaUsd, USC_TARGET_PRICE);
    }

    uint256 uscAmountReceived;
    {
      if (ethAmountFromChi > 0) {
        uint256 chiAmountToMint = _getAmountInForAmountOut(address(CHI), WETH, ethAmountFromChi);
        CHI.mint(address(this), chiAmountToMint);
        _swap(address(CHI), WETH, chiAmountToMint);
      }

      uscAmountReceived = _swap(WETH, address(USC), ethAmountFromChi + ethAmountToRedeem);
    }

    if (uscAmountToFreeze > 0) {
      rewardController.rewardUSC(uscAmountToFreeze);
    }

    if (uscAmountToBurn > 0) {
      USC.burn(uscAmountToBurn);
    }

    {
      uint256 rewardAmount = uscAmountReceived - uscAmountToFreeze - uscAmountToBurn;
      USC.safeTransfer(msg.sender, rewardAmount);
      uint256 rewardValue = _convertTokenAmountToUsdValue(rewardAmount, USC_TARGET_PRICE);
      emit ExecuteArbitrage(msg.sender, 4, deltaUsd, reserveDiff, ethPrice, rewardValue);
      return rewardValue;
    }
  }

  function _arbitrageAtPegExcessOfReserves(
    uint256 reserveDiff,
    uint256 discount,
    uint256 ethPrice
  ) private returns (uint256) {
    uint256 ethToRedeem = _convertUsdValueToTokenAmount(reserveDiff, ethPrice);

    reserveHolder.redeem(ethToRedeem);

    uint256 chiReceived = _swap(WETH, address(CHI), ethToRedeem);
    uint256 chiArbitrageReward = Math.mulDiv(chiReceived, discount, BASE_PRICE);

    CHI.burn(chiReceived - chiArbitrageReward);

    IERC20(CHI).safeTransfer(msg.sender, chiArbitrageReward);

    uint256 chiPrice = priceFeedAggregator.peek(address(CHI));
    uint256 rewardValue = _convertTokenAmountToUsdValue(chiArbitrageReward, chiPrice);
    emit ExecuteArbitrage(msg.sender, 5, 0, reserveDiff, ethPrice, rewardValue);
    return rewardValue;
  }

  function _arbitrageAtPegDeficitOfReserves(
    uint256 reserveDiff,
    uint256 discount,
    uint256 ethPrice
  ) private returns (uint256) {
    uint256 ethToGet = _convertUsdValueToTokenAmount(reserveDiff, ethPrice);

    uint256 chiToCoverEth = _getAmountInForAmountOut(address(CHI), WETH, ethToGet);
    uint256 chiArbitrageReward = Math.mulDiv(chiToCoverEth, discount, BASE_PRICE);

    CHI.mint(address(this), chiToCoverEth + chiArbitrageReward);

    uint256 ethReceived = _swap(address(CHI), WETH, chiToCoverEth);
    IERC20(WETH).safeTransfer(address(reserveHolder), ethReceived);

    IERC20(CHI).safeTransfer(msg.sender, chiArbitrageReward);

    uint256 chiPrice = priceFeedAggregator.peek(address(CHI));
    uint256 rewardValue = _convertTokenAmountToUsdValue(chiArbitrageReward, chiPrice);
    emit ExecuteArbitrage(msg.sender, 6, 0, reserveDiff, ethPrice, rewardValue);
    return rewardValue;
  }

  function _getReservesData() public view returns (bool isExcessOfReserves, uint256 reserveDiff, uint256 reserveValue) {
    reserveValue = reserveHolder.getReserveValue();
    uint256 uscTotalSupplyValue = _convertTokenAmountToUsdValue(USC.totalSupply(), USC_TARGET_PRICE);

    if (reserveValue > uscTotalSupplyValue) {
      isExcessOfReserves = true;
      reserveDiff = (reserveValue - uscTotalSupplyValue);
    } else {
      isExcessOfReserves = false;
      reserveDiff = (uscTotalSupplyValue - reserveValue);
    }
  }

  function _getAndValidateUscPrice(uint256 ethPrice) private view returns (uint256) {
    uint256 uscPrice = priceFeedAggregator.peek(address(USC));
    uint256 uscSpotPrice = _calculateUscSpotPrice(ethPrice);
    uint256 priceDiff = _absDiff(uscSpotPrice, uscPrice);
    uint256 maxPriceDiff = Math.mulDiv(uscPrice, priceTolerance, MAX_PRICE_TOLERANCE);

    if (priceDiff > maxPriceDiff) {
      revert PriceSlippageTooBig();
    }

    return uscSpotPrice;
  }

  // input ethPrice has 8 decimals
  // returns result with 8 decimals
  function _calculateUscSpotPrice(uint256 ethPrice) private view returns (uint256) {
    (uint256 reserveUSC, uint256 reserveWETH) = UniswapV2Library.getReserves(
      address(poolFactory),
      address(USC),
      address(WETH)
    );
    uint256 uscFor1ETH = UniswapV2Library.quote(1 ether, reserveWETH, reserveUSC);
    return Math.mulDiv(ethPrice, 1 ether, uscFor1ETH);
  }

  // what amount of In tokens to put in pool to make price:   1 tokenOut = (priceOut / priceIn) tokenIn
  // assuming reserves are on 18 decimals, prices are on 8 decimals
  function _calculateDelta(
    uint256 reserveIn,
    uint256 priceIn,
    uint256 reserveOut,
    uint256 priceOut
  ) public pure returns (uint256) {
    // F = (1 - pool_fee) = 0.997 on 18 decimals,   in square root formula  a = F

    // parameter `b` in square root formula,  b = rIn * (1+f) ,  on 18 decimals
    uint256 b = Math.mulDiv(reserveIn, 1e18 + F, 1e18);
    uint256 b_sqr = Math.mulDiv(b, b, 1e18);

    // parameter `c` in square root formula,  c = rIn^2 - (rIn * rOut * priceOut) / priceIn
    uint256 c_1 = Math.mulDiv(reserveIn, reserveIn, 1e18);
    uint256 c_2 = Math.mulDiv(Math.mulDiv(reserveIn, reserveOut, 1e18), priceOut, priceIn);

    uint256 c;
    uint256 root;
    if (c_1 > c_2) {
      c = c_1 - c_2;
      // d = 4ac
      uint256 d = Math.mulDiv(4 * F, c, 1e18);

      // root = sqrt(b^2 - 4ac)
      // multiplying by 10^9 to get back to 18 decimals
      root = Math.sqrt(b_sqr - d) * 1e9;
    } else {
      c = c_2 - c_1;
      // d = 4ac
      uint256 d = Math.mulDiv(4 * F, c, 1e18);

      // root = sqrt(b^2 - 4ac)    -> in this case `c` is negative, so we add `d` to `b^2`
      // multiplying by 10^9 to get back to 18 decimals
      root = Math.sqrt(b_sqr + d) * 1e9;
    }
    // delta = (-b + root) / 2*f
    uint256 delta = Math.mulDiv(1e18, root - b, 2 * F);

    return delta;
  }

  // given ethPrice is on 8 decimals
  // how many USC to put in pool to make price:   1 ETH = ethPrice * USC
  function _calculateDeltaUSC(uint256 ethPrice) public view returns (uint256) {
    (uint256 reserveUSC, uint256 reserveWETH) = UniswapV2Library.getReserves(
      address(poolFactory),
      address(USC),
      address(WETH)
    );
    return _calculateDelta(reserveUSC, USC_TARGET_PRICE, reserveWETH, ethPrice);
  }

  // how many ETH to put in pool to make price:   1 ETH = ethPrice * USC
  function _calculateDeltaETH(uint256 ethPrice) public view returns (uint256) {
    (uint256 reserveUSC, uint256 reserveWETH) = UniswapV2Library.getReserves(
      address(poolFactory),
      address(USC),
      address(WETH)
    );
    return _calculateDelta(reserveWETH, ethPrice, reserveUSC, USC_TARGET_PRICE);
  }

  function _makePath(address t1, address t2) internal pure returns (address[] memory path) {
    path = new address[](2);
    path[0] = t1;
    path[1] = t2;
  }

  function _makePath(address t1, address t2, address t3) internal pure returns (address[] memory path) {
    path = new address[](3);
    path[0] = t1;
    path[1] = t2;
    path[2] = t3;
  }

  function _swap(address tokenIn, address tokenOut, uint256 amount) private returns (uint256) {
    address[] memory path;

    if (tokenIn != WETH && tokenOut != WETH) {
      path = _makePath(tokenIn, WETH, tokenOut);
    } else {
      path = _makePath(tokenIn, tokenOut);
    }

    IERC20(tokenIn).approve(address(swapRouter), amount);
    uint256[] memory amounts = swapRouter.swapExactTokensForTokens(amount, 0, path, address(this), block.timestamp);

    uint256 amountReceived = amounts[path.length - 1];

    return amountReceived;
  }

  function _getAmountInForAmountOut(address tIn, address tOut, uint256 amountOut) internal view returns (uint256) {
    (uint256 rIn, uint256 rOut) = UniswapV2Library.getReserves(address(poolFactory), tIn, tOut);
    return UniswapV2Library.getAmountIn(amountOut, rIn, rOut);
  }

  function _convertUsdValueToTokenAmount(uint256 usdValue, uint256 price) internal pure returns (uint256) {
    return Math.mulDiv(usdValue, 1e18, price);
  }

  function _convertTokenAmountToUsdValue(uint256 amount, uint256 price) internal pure returns (uint256) {
    return Math.mulDiv(amount, price, 1e18);
  }

  function _absDiff(uint256 a, uint256 b) internal pure returns (uint256) {
    return (a > b) ? a - b : b - a;
  }

  function _almostEqualAbs(uint256 price1, uint256 price2, uint256 delta) internal pure returns (bool) {
    return _absDiff(price1, price2) <= delta;
  }

  receive() external payable {}
}

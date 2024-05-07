// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "../library/ExternalContractAddresses.sol";
import "../interfaces/ISTETH.sol";

/// @title Testpage Helper
/// @notice Helper for the dashboard used to test protocol on the testnet
contract TestpageHelper {
  error EthValueIsZero();

  address public constant WETH = ExternalContractAddresses.WETH;
  ISTETH public constant stETH = ISTETH(ExternalContractAddresses.stETH);
  IUniswapV2Router02 public constant swapRouter = IUniswapV2Router02(ExternalContractAddresses.UNI_V2_SWAP_ROUTER);

  function addStETHRewards(address reserveHolder) external payable {
    if (msg.value == 0) revert EthValueIsZero();
    stETH.submit{value: msg.value}(address(this));
    IERC20(stETH).transfer(reserveHolder, msg.value);
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

  function exchange(address tokenIn, address tokenOut, uint256 amount) public returns (uint256) {
    IERC20(tokenIn).transferFrom(msg.sender, address(this), amount);
    uint256 amountOut = _exchange(tokenIn, tokenOut, amount);
    IERC20(tokenOut).transfer(msg.sender, amountOut);
    return amountOut;
  }

  function exchangeManyTimes(
    address token0,
    address token1,
    uint256 startAmount,
    uint256 times
  ) external returns (uint256) {
    IERC20(token0).transferFrom(msg.sender, address(this), startAmount);
    uint256 amount = startAmount;
    for (uint256 i = 0; i < times; i++) {
      if (i % 2 == 0) {
        amount = _exchange(token0, token1, amount);
      } else {
        amount = _exchange(token1, token0, amount);
      }
    }
    IERC20(times % 2 == 0 ? token0 : token1).transfer(msg.sender, amount);
    return amount;
  }

  function _exchange(address tokenIn, address tokenOut, uint256 amount) public returns (uint256) {
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

  function addLiquidity(address tokenA, address tokenB, uint256 amountA, uint256 amountB) external {
    IERC20(tokenA).transferFrom(msg.sender, address(this), amountA);
    IERC20(tokenB).transferFrom(msg.sender, address(this), amountB);
    IERC20(tokenA).approve(address(swapRouter), amountA);
    IERC20(tokenB).approve(address(swapRouter), amountB);
    swapRouter.addLiquidity(tokenA, tokenB, amountA, amountB, 0, 0, msg.sender, block.timestamp);
  }

  function addLiquidityETH(address token, uint256 amountToken) external payable {
    IERC20(token).transferFrom(msg.sender, address(this), amountToken);
    IERC20(token).approve(address(swapRouter), amountToken);
    swapRouter.addLiquidityETH{value: msg.value}(token, amountToken, 0, 0, msg.sender, block.timestamp);
  }
}

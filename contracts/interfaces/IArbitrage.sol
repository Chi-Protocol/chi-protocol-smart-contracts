// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IArbitrage {
  event SetPriceTolerance(uint16 priceTolerance);
  event SetMaxMintPriceDiff(uint256 maxMintPriceDiff);
  event Mint(address indexed account, address token, uint256 amount, uint256 uscAmount);
  event ExecuteArbitrage(
    address indexed account,
    uint256 indexed arbNum,
    uint256 deltaUsd,
    uint256 reserveDiff,
    uint256 ethPrice,
    uint256 rewardValue
  );

  error DeltaBiggerThanAmountReceivedETH(uint256 deltaETH, uint256 receivedETH);
  error ToleranceTooBig(uint16 _tolerance);
  error PriceSlippageTooBig();

  /// @notice Sets spot price tolerance from TWAP price
  /// @dev 100% = 10000
  /// @param _priceTolerance Price tolerance in percents
  /// @custom:usage This function should be called from owner in purpose of setting price tolerance
  function setPriceTolerance(uint16 _priceTolerance) external;

  /// @notice Sets max mint price diff
  /// @param _maxMintPriceDiff Max mint price diff
  /// @custom:usage This function should be called from owner in purpose of setting max mint price diff
  function setMaxMintPriceDiff(uint256 _maxMintPriceDiff) external;

  /// @notice Mint USC tokens for ETH
  /// @dev If USC price is different from target price for less then max mint price diff, then minting is allowed without performing arbitrage
  /// @return uscAmount Amount of USC tokens minted
  function mint() external payable returns (uint256 uscAmount);

  /// @notice Mint USC tokens for WETH
  /// @dev If USC price is different from target price for less then max mint price diff, then minting is allowed without performing arbitrage
  /// @param wethAmount Amount of WETH to mint with
  /// @return uscAmount Amount of USC tokens minted
  function mintWithWETH(uint256 wethAmount) external returns (uint256 uscAmount);

  /// @notice Mint USC tokens for stETH
  /// @dev If USC price is different from target price for less then max mint price diff, then minting is allowed without performing arbitrage
  /// @param stETHAmount Amount of stETH to mint with
  /// @return uscAmount Amount of USC tokens minted
  function mintWithStETH(uint256 stETHAmount) external returns (uint256 uscAmount);

  /// @notice Executes arbitrage, profit sent to caller
  /// @notice Returns reward value in USD
  /// @return rewardValue Reward value in USD
  /// @custom:usage This function should be called from external keeper in purpose of pegging USC price and getting reward
  /// @custom:usage This function has no restrictions, anyone can be arbitrager
  function executeArbitrage() external returns (uint256 rewardValue);

  /// @notice Gets information for perfoming arbitrage such as price diff, reserve diff, discount
  /// @return isPriceAboveTarget True if USC price is above target price
  /// @return isExcessOfReserves True if there is excess of reserves
  /// @return reserveDiff Reserve diff, excess or deficit of reserves
  /// @return discount Discount in percents, only if price is equal to target price
  function getArbitrageData()
    external
    view
    returns (bool isPriceAboveTarget, bool isExcessOfReserves, uint256 reserveDiff, uint256 discount);
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IArbitrageV3 {
  error DeltaBiggerThanAmountReceivedETH(uint256 deltaETH, uint256 receivedETH);
  error ToleranceTooBig(uint16 _tolerance);
  error PriceSlippageTooBig();
  error NotArbitrager(address account);
  error PriceIsNotPegged();
  error ReserveDiffTooBig();
  error ChiPriceNotPegged(uint256 spotPrice, uint256 twapPrice);
  error FeeTooBig(uint256 fee);
  error ChiSpotPriceTooBig();
  error ContractIsPaused();

  event SetPriceTolerance(uint16 priceTolerance);
  event Mint(address indexed account, address token, uint256 amount, uint256 uscAmount);
  event ExecuteArbitrage(
    address indexed account,
    uint256 indexed arbNum,
    uint256 deltaUsd,
    uint256 reserveDiff,
    uint256 ethPrice,
    uint256 rewardValue
  );
  event UpdateArbitrager(address indexed account, bool status);
  event SetMaxMintBurnPriceDiff(uint256 maxMintBurnPriceDiff);
  event SetChiPriceTolerance(uint16 chiPriceTolerance);
  event SetMaxMintBurnReserveTolerance(uint16 maxBurnReserveTolerance);
  event SetMintBurnFee(uint256 mintFee);
  event UpdatePrivileged(address indexed privileged, bool isPrivileged);
  event Burn(address account, uint256 amount, uint256 ethAmount);

  /// @notice Sets absolute peg price tolerance
  /// @param _priceTolerance Absolute value of price tolerance
  /// @custom:usage This function should be called from owner in purpose of setting price tolerance
  function setPegPriceToleranceAbs(uint256 _priceTolerance) external;

  /// @notice Sets spot price tolerance from TWAP price
  /// @dev 100% = 10000
  /// @param _priceTolerance Price tolerance in percents
  /// @custom:usage This function should be called from owner in purpose of setting price tolerance
  function setPriceTolerance(uint16 _priceTolerance) external;

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
  /// @param maxChiSpotPrice maximum spot price of CHI, if 0 TWAP check will be done
  /// @return rewardValue Reward value in USD
  /// @custom:usage This function should be called from external keeper in purpose of pegging USC price and getting reward
  /// @custom:usage This function has no restrictions, anyone can be arbitrager
  function executeArbitrage(uint256 maxChiSpotPrice) external returns (uint256 rewardValue);

  /// @notice Gets information for perfoming arbitrage such as price diff, reserve diff, discount
  /// @return isPriceAboveTarget True if USC price is above target price
  /// @return isExcessOfReserves True if there is excess of reserves
  /// @return reserveDiff Reserve diff, excess or deficit of reserves
  /// @return discount Discount in percents, only if price is equal to target price
  function getArbitrageData()
    external
    view
    returns (bool isPriceAboveTarget, bool isExcessOfReserves, uint256 reserveDiff, uint256 discount);

  /// @notice Update arbitrager status
  /// @dev This function can be called only by owner of contract
  /// @param account Arbitrager account
  /// @param status Arbitrager status
  function updateArbitrager(address account, bool status) external;

  /// @notice Claim rewards from arbitrages
  /// @dev This function can be called only by owner of contract
  /// @param tokens Tokens to claim rewards for
  function claimRewards(IERC20[] memory tokens) external;

  /// @notice Sets maximum mint and burn price difference
  /// @dev This function can be called only by owner of contract, value is absolute
  /// @param _maxMintBurnPriceDiff Maximum mint and burn price difference
  function setMaxMintBurnPriceDiff(uint256 _maxMintBurnPriceDiff) external;

  /// @notice Sets CHI price tolerance percentage when checking TWAP
  /// @dev This function can be called only by owner of contract, value is relative
  /// @param _chiPriceTolerance CHI price tolerance percentage
  function setChiPriceTolerance(uint16 _chiPriceTolerance) external;

  /// @notice Sets maximum mint and burn price difference
  /// @dev This function can be called only by owner of contract, value is relative
  /// @param _maxMintBurnReserveTolerance Maximum mint and burn reserve tolerance
  function setMaxMintBurnReserveTolerance(uint16 _maxMintBurnReserveTolerance) external;

  /// @notice Sets mint and burn fee
  /// @dev This function can be called only by owner of contract
  /// @param _mintBurnFee Mint and burn fee
  function setMintBurnFee(uint16 _mintBurnFee) external;

  /// @notice Update privilege status, only privileged accounts can call arbitrage and pass CHI TWAP check
  /// @dev This function can be called only by owner of contract
  /// @param account Arbitrager account
  /// @param status Privilege status
  function updatePrivileged(address account, bool status) external;

  /// @notice Burns USC tokens from msg.sender and sends him WETH from reserves
  /// @param amount Amount of USC tokens to burn
  /// @return ethAmount Amount of WETH received
  function burn(uint256 amount) external returns (uint256 ethAmount);

  /// @notice Sets mint pause
  /// @param isPaused true of false
  function setMintPause(bool isPaused) external;

  /// @notice Sets burn pause
  /// @param isPaused true of false
  function setBurnPause(bool isPaused) external;
}

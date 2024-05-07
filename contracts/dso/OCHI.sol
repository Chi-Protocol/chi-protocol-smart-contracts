// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "../interfaces/IOCHI.sol";
import "../interfaces/IPriceFeedAggregator.sol";
import "../interfaces/IMintableBurnable.sol";
import "../interfaces/ILPRewards.sol";
import "../library/ExternalContractAddresses.sol";
import "./PoolHelper.sol";

/// @title Contract for creating and executing options
/// @notice Each LP token has its own LPRewards contract
/// @dev This contract is upgradeable
/// @dev This contract handles creation and execution of options but does not hold LP tokens
contract OCHI is IOCHI, ERC721EnumerableUpgradeable, OwnableUpgradeable {
  using SafeERC20 for IERC20;
  using SafeERC20 for IMintableBurnable;
  using SafeERC20 for IUniswapV2Pair;

  uint256 public constant MAX_LOCK_PERIOD_EPOCHS = 52;
  uint256 public constant EPOCH_DURATION = 1 weeks;
  uint256 public constant BASE_PRICE = 1e8;
  uint256 public constant MULTIPLIER = 1e18;
  uint256 public constant TARGET_RATIO = 80_00;
  uint256 public constant DENOMINATOR = 100_00;
  address public constant WETH = ExternalContractAddresses.WETH;

  IERC20 public usc;
  IMintableBurnable public chi;
  IUniswapV2Pair public uscEthPair;
  IUniswapV2Pair public chiEthPair;
  IPriceFeedAggregator public priceFeedAggregator;

  uint64 public currentEpoch;
  uint256 public firstEpochTimestamp;
  uint256 public mintedOCHI;
  uint256 public totalOCHIlocked;

  mapping(IUniswapV2Pair token => ILPRewards) public lpRewards;
  mapping(uint256 id => ChiOption) public options;

  function initialize(
    IERC20 _usc,
    IMintableBurnable _chi,
    IPriceFeedAggregator _priceFeedAggregator,
    IUniswapV2Pair _uscEthPair,
    IUniswapV2Pair _chiEthPair,
    ILPRewards _uscEthPairRewards,
    ILPRewards _chiEthPairRewards,
    uint256 _firstEpochTimestamp
  ) external initializer {
    __ERC721_init("Option CHI", "oCHI");
    __Ownable_init();
    usc = _usc;
    chi = _chi;
    priceFeedAggregator = _priceFeedAggregator;
    uscEthPair = _uscEthPair;
    chiEthPair = _chiEthPair;

    lpRewards[_uscEthPair] = _uscEthPairRewards;
    lpRewards[_chiEthPair] = _chiEthPairRewards;

    currentEpoch = 1;
    firstEpochTimestamp = _firstEpochTimestamp;
  }

  /// @inheritdoc IOCHI
  function mint(
    uint256 chiAmount,
    uint256 uscEthPairAmount,
    uint256 chiEthPairAmount,
    uint64 lockPeriodInEpochs
  ) external {
    if (lockPeriodInEpochs > MAX_LOCK_PERIOD_EPOCHS || lockPeriodInEpochs == 0) {
      revert InvalidLockPeriod(lockPeriodInEpochs);
    }

    (uint256 strikePrice, uint256 oChiAmount) = calculateOptionData(
      chiAmount,
      uscEthPairAmount,
      chiEthPairAmount,
      lockPeriodInEpochs
    );

    uint64 nextEpoch = currentEpoch + 1;
    uint256 tokenId = ++mintedOCHI;
    options[tokenId] = ChiOption({
      amount: oChiAmount,
      strikePrice: strikePrice,
      uscEthPairAmount: uscEthPairAmount,
      chiEthPairAmount: chiEthPairAmount,
      lockedUntil: nextEpoch + lockPeriodInEpochs,
      validUntil: nextEpoch + 2 * lockPeriodInEpochs
    });

    totalOCHIlocked += oChiAmount;

    ILPRewards uscEthLPRewards = lpRewards[uscEthPair];
    ILPRewards chiEthLPRewards = lpRewards[chiEthPair];

    if (chiAmount > 0) {
      chi.burnFrom(msg.sender, chiAmount);
    }
    IERC20(address(uscEthPair)).safeTransferFrom(msg.sender, address(uscEthLPRewards), uscEthPairAmount);
    IERC20(address(chiEthPair)).safeTransferFrom(msg.sender, address(chiEthLPRewards), chiEthPairAmount);

    uscEthLPRewards.lockLP(tokenId, uscEthPairAmount, uint64(lockPeriodInEpochs));
    chiEthLPRewards.lockLP(tokenId, chiEthPairAmount, uint64(lockPeriodInEpochs));

    _safeMint(msg.sender, tokenId);

    emit Mint(tokenId, chiAmount, uscEthPairAmount, chiEthPairAmount, lockPeriodInEpochs, strikePrice, oChiAmount);
  }

  /// @inheritdoc IOCHI
  function burn(uint256 tokenId) external {
    if (!_isApprovedOrOwner(msg.sender, tokenId)) {
      revert NotAllowed(tokenId);
    }

    ChiOption storage option = options[tokenId];

    if (currentEpoch < option.lockedUntil) {
      revert OptionLocked(tokenId);
    }
    if (currentEpoch > option.validUntil) {
      revert OptionExpired(tokenId);
    }

    lpRewards[uscEthPair].claimRewards(tokenId, msg.sender);
    lpRewards[chiEthPair].claimRewards(tokenId, msg.sender);

    uint256 chiAmount = option.amount;
    uint256 chiBalance = chi.balanceOf(address(this));
    uint256 amountToTransfer = Math.min(chiAmount, chiBalance);
    uint256 amountToMint = chiAmount - amountToTransfer;

    if (amountToMint > 0) {
      chi.mint(msg.sender, amountToMint);
    }
    if (amountToTransfer > 0) {
      chi.transfer(msg.sender, amountToTransfer);
    }

    _burn(tokenId);

    totalOCHIlocked -= options[tokenId].amount;

    emit Burn(msg.sender, tokenId, chiAmount);
  }

  /// @inheritdoc IOCHI
  function updateEpoch() public {
    if (block.timestamp < firstEpochTimestamp + (currentEpoch - 1) * EPOCH_DURATION) {
      revert EpochNotFinished();
    }

    lpRewards[uscEthPair].updateEpoch();
    lpRewards[chiEthPair].updateEpoch();

    currentEpoch++;
    emit UpdateEpoch(currentEpoch - 1, block.timestamp);
  }

  /// @inheritdoc IOCHI
  function claimRewards(uint256 tokenId) public {
    if (!_isApprovedOrOwner(msg.sender, tokenId)) {
      revert NotAllowed(tokenId);
    }

    lpRewards[uscEthPair].claimRewards(tokenId, msg.sender);
    lpRewards[chiEthPair].claimRewards(tokenId, msg.sender);

    emit ClaimRewardsOCHI(tokenId);
  }

  /// @notice Claims rewards for all users tokens
  function claimAllRewards() public {
    uint256 balance = balanceOf(msg.sender);
    for (uint256 i = 0; i < balance; i++) {
      claimRewards(tokenOfOwnerByIndex(msg.sender, i));
    }
  }

  /// @inheritdoc IOCHI
  function recoverLPTokens() external onlyOwner {
    lpRewards[uscEthPair].recoverLPTokens(msg.sender);
    lpRewards[chiEthPair].recoverLPTokens(msg.sender);

    emit RecoverLPTokens();
  }

  /// @inheritdoc IOCHI
  function getUnclaimedRewardsValue(uint256 tokenId) external view returns (int256) {
    return
      lpRewards[uscEthPair].calculateUnclaimedReward(tokenId) + lpRewards[chiEthPair].calculateUnclaimedReward(tokenId);
  }

  /// @notice Calulates strike price and ochi amount for supplied asets
  /// @param chiAmount amount of chi token to supply
  /// @param uscEthPairAmount amount of USC/ETH LP token to supply
  /// @param chiEthPairAmount amount of CHI/ETH LP token to supply
  /// @param lockPeriodInEpochs locking duration
  /// @return strikePrice strike price given for supplied assets
  /// @return oChiAmount ochi amount given for supplied assets
  function calculateOptionData(
    uint256 chiAmount,
    uint256 uscEthPairAmount,
    uint256 chiEthPairAmount,
    uint256 lockPeriodInEpochs
  ) public view returns (uint256 strikePrice, uint256 oChiAmount) {
    uint256 timeMultiplier = Math.mulDiv(lockPeriodInEpochs, MULTIPLIER, 4 * MAX_LOCK_PERIOD_EPOCHS);
    uint256 chiMultiplier = Math.mulDiv(chiAmount, MULTIPLIER, chi.totalSupply());
    (uint256 poolMultiplier, uint256 positionsValue) = getAndValidatePositionsData(uscEthPairAmount, chiEthPairAmount);

    uint256 discount = timeMultiplier + Math.min(poolMultiplier + chiMultiplier, MULTIPLIER / 4);
    uint256 chiPrice = _peek(address(chi));
    strikePrice = Math.mulDiv(chiPrice, MULTIPLIER - discount, MULTIPLIER);

    uint256 chiValue = Math.mulDiv(chiAmount, chiPrice, MULTIPLIER);
    oChiAmount = Math.mulDiv(positionsValue + chiValue, MULTIPLIER, strikePrice);
  }

  /// @notice Calculates multiplier for supplied LP assets
  /// @param uscEthPairAmount amount of USC/ETH LP token to supply
  /// @param chiEthPairAmount amount of CHI/ETH LP token to supply
  /// @return multiplier multiplier used for caluclating discount
  /// @param value parameter used for calculating ochi amount
  function getAndValidatePositionsData(
    uint256 uscEthPairAmount,
    uint256 chiEthPairAmount
  ) public view returns (uint256 multiplier, uint256 value) {
    uint256 uscEthPairTotalSupply = uscEthPair.totalSupply();
    uint256 chiEthPairTotalSupply = chiEthPair.totalSupply();

    if (
      uscEthPair.balanceOf(address(this)) + uscEthPairAmount >
      Math.mulDiv(uscEthPairTotalSupply, TARGET_RATIO, DENOMINATOR) ||
      chiEthPair.balanceOf(address(this)) + chiEthPairAmount >
      Math.mulDiv(chiEthPairTotalSupply, TARGET_RATIO, DENOMINATOR)
    ) {
      revert PolTargetRatioExceeded();
    }

    multiplier =
      Math.mulDiv(uscEthPairAmount, MULTIPLIER, uscEthPairTotalSupply) +
      Math.mulDiv(chiEthPairAmount, MULTIPLIER, chiEthPairTotalSupply);

    value = (PoolHelper.getUSDValueForLP(uscEthPairAmount, uscEthPair, priceFeedAggregator) +
      PoolHelper.getUSDValueForLP(chiEthPairAmount, chiEthPair, priceFeedAggregator));
  }

  /// @notice Calculates the total LP reward for the last epoch
  /// @return totalReward total reward in usd value
  function getLastEpochTotalReward() external view returns (int256 totalReward) {
    if (currentEpoch < 2) return 0;
    return lpRewards[uscEthPair].getLastEpochProfit() + lpRewards[chiEthPair].getLastEpochProfit();
  }

  function _peek(address asset) internal view returns (uint256 price) {
    price = priceFeedAggregator.peek(asset);
  }
}

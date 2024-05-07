// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../interfaces/IIDO.sol";
import "../interfaces/ICHI.sol";
import "../interfaces/IChiVesting.sol";

/// @title IDO
/// @notice Contract handles IDO for CHI tokens
contract IDO is IIDO, Ownable, ReentrancyGuard {
  ICHI public chi;
  IChiVesting public chiVesting;
  uint256 public startTimestamp;
  uint256 public endTimestamp;
  uint256 public minValue;
  uint256 public maxValue;
  uint256 public softCap;
  uint256 public hardCap;
  uint256 public totalSale;
  uint256 public price;
  address public treasury;
  bool public claimingEnabled;
  mapping(address account => uint256 amount) public ethAmount;
  mapping(address account => bool claimed) public claimed;
  mapping(address account => uint256 amount) public boughtChiAmount;
  mapping(address account => bool whitelisted) public whitelisted;

  uint256 public constant MAX_TAX_PERCENT = 100_00000000;
  uint256 public startTaxPercent;
  uint256 public taxPercentFallPerSec;

  constructor(
    ICHI _chi,
    IChiVesting _chiVesting,
    uint256 _startTimestamp,
    uint256 _endTimestamp,
    uint256 _minValue,
    uint256 _maxValue,
    uint256 _softCap,
    uint256 _hardCap,
    uint256 _price,
    address _treasury,
    uint256 _startTaxPercent,
    uint256 _taxPercentFallPerSec
  ) Ownable() {
    chi = _chi;
    chiVesting = _chiVesting;
    startTimestamp = _startTimestamp;
    endTimestamp = _endTimestamp;
    minValue = _minValue;
    maxValue = _maxValue;
    softCap = _softCap;
    hardCap = _hardCap;
    price = _price;
    treasury = _treasury;
    startTaxPercent = _startTaxPercent;
    taxPercentFallPerSec = _taxPercentFallPerSec;
    totalSale = 0;
    claimingEnabled = false;
  }

  function changeTime(uint256 _startTimestamp, uint256 _endTimestamp) external onlyOwner {
    startTimestamp = _startTimestamp;
    endTimestamp = _endTimestamp;
  }

  function changeValueRange(uint256 _minValue, uint256 _maxValue) external onlyOwner {
    minValue = _minValue;
    maxValue = _maxValue;
  }

  function changeTax(uint256 _startTaxPercent, uint256 _taxPercentFallPerSec) external onlyOwner {
    startTaxPercent = _startTaxPercent;
    taxPercentFallPerSec = _taxPercentFallPerSec;
  }

  function changeClaimingEnabled(bool _claimingEnabled) external onlyOwner {
    claimingEnabled = _claimingEnabled;
  }

  function changePrice(uint256 _price) external onlyOwner {
    if (block.timestamp > startTimestamp) {
      revert IDOAlreadyStarted();
    }
    price = _price;
  }

  function whitelist(address[] calldata accounts, bool[] calldata toWhitelist) external onlyOwner {
    for (uint256 i = 0; i < accounts.length; i++) {
      whitelisted[accounts[i]] = toWhitelist[i];
    }
  }

  function withdrawSale() external onlyOwner {
    if (totalSale < softCap) {
      revert SoftCapNotReached();
    }

    _sendBack(treasury, address(this).balance);
  }

  function rescueTokens(IERC20 token, uint256 amount, address to) external onlyOwner {
    token.transfer(to, amount);
  }

  function currentTax() public view returns (uint256) {
    if (block.timestamp < startTimestamp) {
      return startTaxPercent;
    }

    uint256 timePassed = block.timestamp - startTimestamp;
    uint256 totalFall = timePassed * taxPercentFallPerSec;

    if (totalFall < startTaxPercent) {
      return startTaxPercent - totalFall;
    } else {
      return 0;
    }
  }

  function calculateTaxedChiAmount(uint256 ethDeposit, uint256 tax) public view returns (uint256) {
    uint256 chiAmount = Math.mulDiv(ethDeposit, price, 1e18);
    if (tax > 0) {
      chiAmount -= Math.mulDiv(chiAmount, tax, 100_00000000);
    }
    return chiAmount;
  }

  function calculateChiAmountForAccount(address account, uint256 ethDeposit) public view returns (uint256) {
    if (whitelisted[account]) {
      return calculateTaxedChiAmount(ethDeposit, 0);
    } else {
      return calculateTaxedChiAmount(ethDeposit, currentTax());
    }
  }

  function buy() external payable {
    if (block.timestamp < startTimestamp || block.timestamp > endTimestamp || totalSale == hardCap) {
      revert IDONotRunning();
    }

    uint256 currAmount = ethAmount[msg.sender];
    uint256 amountToBuy = Math.min(msg.value, Math.min(hardCap - totalSale, maxValue - currAmount));

    if (amountToBuy == 0) {
      revert MaxValueReached();
    }
    if (currAmount + amountToBuy < minValue) {
      revert MinValueNotReached();
    }

    ethAmount[msg.sender] += amountToBuy;
    totalSale += amountToBuy;
    boughtChiAmount[msg.sender] += calculateChiAmountForAccount(msg.sender, amountToBuy);

    uint256 toReturn = msg.value - amountToBuy;
    _sendBack(msg.sender, toReturn);

    emit Buy(msg.sender, amountToBuy, ethAmount[msg.sender]);
  }

  function withdraw() external nonReentrant {
    if (totalSale >= softCap) {
      revert SoftCapReached();
    }

    uint256 amount = ethAmount[msg.sender];
    ethAmount[msg.sender] -= amount;
    totalSale -= amount;
    boughtChiAmount[msg.sender] = 0;

    _sendBack(msg.sender, amount);

    emit Withdraw(msg.sender, amount, ethAmount[msg.sender]);
  }

  function claim() external nonReentrant {
    if (block.timestamp < endTimestamp) {
      revert IDONotFinished();
    }
    if (!claimingEnabled) {
      revert ClaimingNotEnabled();
    }
    if (claimed[msg.sender]) {
      revert AlreadyClaimed();
    }

    claimed[msg.sender] = true;
    uint256 chiAmount = boughtChiAmount[msg.sender];
    chi.transfer(msg.sender, chiAmount);

    emit Claim(msg.sender, ethAmount[msg.sender], chiAmount);
  }

  function _sendBack(address to, uint256 amount) internal {
    if (amount != 0) {
      (bool success, ) = to.call{value: amount}(new bytes(0));
      if (!success) {
        revert EtherSendFailed(msg.sender, amount);
      }
    }
  }
}

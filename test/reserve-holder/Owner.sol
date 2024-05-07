// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "contracts/interfaces/IPriceFeedAggregator.sol";
import "contracts/ReserveHolder.sol";

contract Owner {
  ReserveHolder public reserveHolder;

  function deployReserveHolder(
    address priceFeedAggregator,
    address claimer,
    uint256 ethThreshold,
    uint256 curveStEthSafeGuardPercentage
  ) external returns (address) {
    reserveHolder = new ReserveHolder();
    reserveHolder.initialize(
      IPriceFeedAggregator(priceFeedAggregator),
      claimer,
      ethThreshold,
      curveStEthSafeGuardPercentage
    );
    return address(reserveHolder);
  }

  function setArbitrager(address arbitrager, bool status) external {
    reserveHolder.setArbitrager(arbitrager, status);
  }

  function setClaimer(address newClaimer) external {
    reserveHolder.setClaimer(newClaimer);
  }

  function setEthThreshold(uint256 newEthThreshold) external {
    reserveHolder.setEthThreshold(newEthThreshold);
  }

  function setSwapEthTolerance(uint256 newSwapEthTolerance) external {
    reserveHolder.setSwapEthTolerance(newSwapEthTolerance);
  }

  function rebalance() external {
    reserveHolder.rebalance();
  }
}

import { ethers } from "hardhat";
import {
  getContractAddressFromJsonDb,
  registerContractInJsonDb,
} from "../helpers/deploy-helpers";
import { MAX_MINT_PRICE_DIFF, USC_PRICE_TOLERANCE } from "../helpers/constants";

export async function deployArbitrage(
  uscAddress: string,
  chiAddress: string,
  rewardControllerAddress: string,
  priceFeedAggregatorAddress: string,
  reserveHolderAddress: string,
) {
  let arbitrageAddress = await getContractAddressFromJsonDb("Arbitrage");

  if (!arbitrageAddress) {
    const Arbitrage = await ethers.getContractFactory("Arbitrage");
    const arbitrage = await Arbitrage.deploy(
      uscAddress,
      chiAddress,
      rewardControllerAddress,
      priceFeedAggregatorAddress,
      reserveHolderAddress,
    );
    await arbitrage.deployed();
    await registerContractInJsonDb("Arbitrage", arbitrage.address);
    arbitrageAddress = arbitrage.address;

    const setPriceToleranceTx =
      await arbitrage.setPriceTolerance(USC_PRICE_TOLERANCE);
    await setPriceToleranceTx.wait();

    const setMaxMintPriceDiffTx =
      await arbitrage.setMaxMintPriceDiff(MAX_MINT_PRICE_DIFF);
    await setMaxMintPriceDiffTx.wait();

    const rewardController = await ethers.getContractAt(
      "RewardController",
      rewardControllerAddress,
    );
    const setArbitragerTx = await rewardController.setArbitrager(
      arbitrage.address,
    );
    await setArbitragerTx.wait();
  }

  return arbitrageAddress;
}

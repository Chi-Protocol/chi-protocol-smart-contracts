import { ethers } from "hardhat";
import { TREASURY_ADDRESS } from "../helpers/constants";
import {
  getContractAddressFromJsonDb,
  registerContractInJsonDb,
} from "../helpers/deploy-helpers";

export async function deployTimeWeightedBoding(
  chiAddress: string,
  priceFeedAggregatorAddress: string,
  chiVestingAddress: string,
) {
  const currBlockNum = await ethers.provider.getBlockNumber();
  const currBlock = await ethers.provider.getBlock(currBlockNum);
  const cliffTimestampEnd = currBlock.timestamp + 6 * 30 * 24 * 60 * 60;

  const timeWeitherBondingAddress = await getContractAddressFromJsonDb(
    "TimeWeightedBonding",
  );

  if (!timeWeitherBondingAddress) {
    const TimeWeightedBonding = await ethers.getContractFactory(
      "TimeWeightedBonding",
    );
    const timeWeightedBonding = await TimeWeightedBonding.deploy(
      chiAddress,
      priceFeedAggregatorAddress,
      chiVestingAddress,
      cliffTimestampEnd,
      TREASURY_ADDRESS,
    );
    await timeWeightedBonding.deployed();
    await registerContractInJsonDb(
      "TimeWeightedBonding",
      timeWeightedBonding.address,
    );

    const chiVesting = await ethers.getContractAt(
      "ChiVesting",
      chiVestingAddress,
    );
    const setChiVesterTx = await chiVesting.setChiVester(
      timeWeightedBonding.address,
      true,
    );
    await setChiVesterTx.wait();
  }
}

import { ethers, upgrades } from "hardhat";
import { UNI_V2_POOL_FACTORY, WETH } from "../helpers/constants";
import {
  getContractAddressFromJsonDb,
  registerContractInJsonDb,
} from "../helpers/deploy-helpers";

export async function deployDSO(
  uscAddress: string,
  chiAddress: string,
  priceFeedAggregatorAddress: string,
) {
  const uniswapFactory = await ethers.getContractAt(
    "IUniswapV2Factory",
    UNI_V2_POOL_FACTORY,
  );
  const uscEthPairAddress = await uniswapFactory.getPair(uscAddress, WETH);
  const chiEthPairAddress = await uniswapFactory.getPair(chiAddress, WETH);

  let uscEthLpRewardsAddress =
    await getContractAddressFromJsonDb("USC_ETH_LP_rewards");

  if (!uscEthLpRewardsAddress) {
    const LPRewards = await ethers.getContractFactory("LPRewards");
    const uscEthLpRewards = await LPRewards.deploy(
      uscEthPairAddress,
      priceFeedAggregatorAddress,
    );
    await registerContractInJsonDb(
      "USC_ETH_LP_rewards",
      uscEthLpRewards.address,
    );
    uscEthLpRewardsAddress = uscEthLpRewards.address;
  }

  let chiEthLpRewardsAddress =
    await getContractAddressFromJsonDb("CHI_ETH_LP_rewards");

  if (!chiEthLpRewardsAddress) {
    const LPRewards = await ethers.getContractFactory("LPRewards");
    const chiEthLpRewards = await LPRewards.deploy(
      chiEthPairAddress,
      priceFeedAggregatorAddress,
    );
    await registerContractInJsonDb(
      "CHI_ETH_LP_rewards",
      chiEthLpRewards.address,
    );
    chiEthLpRewardsAddress = chiEthLpRewards.address;
  }

  let ochiAddress = await getContractAddressFromJsonDb("OCHI");

  if (!ochiAddress) {
    const blockTimestamp = (await ethers.provider.getBlock("latest")).timestamp;
    const OCHI = await ethers.getContractFactory("OCHI");
    const oCHI = await upgrades.deployProxy(OCHI, [
      uscAddress,
      chiAddress,
      priceFeedAggregatorAddress,
      uscEthPairAddress,
      chiEthPairAddress,
      uscEthLpRewardsAddress,
      chiEthLpRewardsAddress,
      blockTimestamp,
    ]);
    await oCHI.deployed();
    await registerContractInJsonDb("OCHI", oCHI.address);
    ochiAddress = oCHI.address;

    const uscEthLpRewards = await ethers.getContractAt(
      "LPRewards",
      uscEthLpRewardsAddress,
    );
    let setOCHITx = await uscEthLpRewards.setOCHI(oCHI.address);
    await setOCHITx.wait();

    const chiEthLpRewards = await ethers.getContractAt(
      "LPRewards",
      chiEthLpRewardsAddress,
    );
    setOCHITx = await chiEthLpRewards.setOCHI(oCHI.address);
    await setOCHITx.wait();

    const chi = await ethers.getContractAt("CHI", chiAddress);
    const updateMinterRole = await chi.updateMinter(oCHI.address, true);
    await updateMinterRole.wait();
  }

  return ochiAddress;
}

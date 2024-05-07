import { ethers } from "hardhat";
import { CHI_INITIAL_SUPPLY } from "./helpers/constants";
import {
  getContractAddressFromJsonDb,
  registerContractInJsonDb,
} from "./helpers/deploy-helpers";
import {
  deployLiquidityPools,
  provideLiquidity,
} from "./sub-deploys/liquidity-pools";
import { deployOracles } from "./sub-deploys/oracles";
import { deployStakingAndReserveHolder } from "./sub-deploys/staking-reserve-holder";
import { deployTimeWeightedBoding } from "./sub-deploys/time-weighted-bonding";
import { deployArbitrage } from "./sub-deploys/arbitrage";
import { deployVotingEscrowChi } from "./sub-deploys/governance";
import { deployDSO } from "./sub-deploys/dso";
import { deployIDO } from "./sub-deploys/ido";

async function deployUSC() {
  const uscAddress = await getContractAddressFromJsonDb("USC");
  if (uscAddress) {
    return await ethers.getContractAt("USC", uscAddress);
  } else {
    const USC = await ethers.getContractFactory("USC");
    const usc = await USC.deploy();
    await usc.deployed();
    await registerContractInJsonDb("USC", usc.address);

    return usc;
  }
}

async function deployCHI() {
  const chiAddress = await getContractAddressFromJsonDb("CHI");
  if (chiAddress) {
    return await ethers.getContractAt("CHI", chiAddress);
  } else {
    const CHI = await ethers.getContractFactory("CHI");
    const chi = await CHI.deploy(
      ethers.utils.parseEther(CHI_INITIAL_SUPPLY.toString()),
    );
    await chi.deployed();
    await registerContractInJsonDb("CHI", chi.address);

    return chi;
  }
}

async function main() {
  console.log("Deploying contracts...");

  const usc = await deployUSC();
  const chi = await deployCHI();

  await deployLiquidityPools(usc.address, chi.address);
  await provideLiquidity(usc, chi);

  const priceFeedAggregatorAddress = await deployOracles(
    usc.address,
    chi.address,
  );
  console.log("Oracles deployed");

  const [
    rewardControllerAddress,
    ,
    ,
    chiLockingAddress,
    chiVestingAddress,
    reserveHolderAddress,
  ] = await deployStakingAndReserveHolder(
    usc.address,
    chi.address,
    priceFeedAggregatorAddress,
  );
  console.log("Staking and reserve holder deployed");

  const oCHI = await deployDSO(
    usc.address,
    chi.address,
    priceFeedAggregatorAddress,
  );
  console.log("DSO deployed");

  let updateMinterTx = await chi.updateMinter(oCHI, true);
  await updateMinterTx.wait();

  await deployTimeWeightedBoding(
    chi.address,
    priceFeedAggregatorAddress,
    chiVestingAddress,
  );

  await deployIDO();
  console.log("IDO deployed");

  const arbitrage = await deployArbitrage(
    usc.address,
    chi.address,
    rewardControllerAddress,
    priceFeedAggregatorAddress,
    reserveHolderAddress,
  );

  const reserveHolder = await ethers.getContractAt(
    "ReserveHolder",
    reserveHolderAddress,
  );
  const setArbitragerTx = await reserveHolder.setArbitrager(arbitrage, true);
  await setArbitragerTx.wait();

  console.log("Arbitrage contract given arbitrager role inside reserve holder");

  updateMinterTx = await chi.updateMinter(arbitrage, true);
  await updateMinterTx.wait();
  updateMinterTx = await usc.updateMinter(arbitrage, true);
  await updateMinterTx.wait();
  console.log("Minter role given to arbitrage contract");

  await deployVotingEscrowChi(chiLockingAddress, chiVestingAddress);

  const DataProvider = await ethers.getContractFactory("DataProvider");
  const dataProvider = await DataProvider.deploy();
  await dataProvider.deployed();

  registerContractInJsonDb("DataProvider", dataProvider.address);

  const TestpageHelper = await ethers.getContractFactory("TestpageHelper");
  const testpageHelper = await TestpageHelper.deploy();
  await testpageHelper.deployed();

  registerContractInJsonDb("TestpageHelper", testpageHelper.address);

  const Treasury = await ethers.getContractFactory("Treasury");
  const treasury = await Treasury.deploy();
  await treasury.deployed();

  registerContractInJsonDb("Treasury", treasury.address);

  let deployerSigner = (await ethers.getSigners())[0];
  let deployer = deployerSigner.address;

  await chi.updateMinter(deployer, true);

  let mintToTreasuryTx = await chi.mint(treasury.address, ethers.utils.parseEther("1000000"));
  await mintToTreasuryTx.wait();  

  let mintToOchiTx = await chi.mint(oCHI, ethers.utils.parseEther("1000000"));
  await mintToOchiTx.wait();

  let mintToRCTx = await chi.mint(
    rewardControllerAddress,
    ethers.utils.parseEther("1000000"),
  );
  await mintToRCTx.wait();

  console.log("Contracts deployed!");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

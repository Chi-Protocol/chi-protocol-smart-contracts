import { ethers, upgrades } from "hardhat";
import { CHI, CHI__factory } from "../../typechain-types";
import { MULTISIG_ADDRESS } from "../helpers/constants";
import {
  getContractAddressFromJsonDb,
  registerContractInJsonDb,
} from "../helpers/deploy-helpers";

export async function deployIDO() {
  const chiAddress = await getContractAddressFromJsonDb("CHI");
  const chiVestingAddress = await getContractAddressFromJsonDb("ChiVesting");

  const IDOFactory = await ethers.getContractFactory("IDO");

  const blockTimestamp = (await ethers.provider.getBlock("latest")).timestamp;
  const day = 60*60*24;
  const startTimestamp = blockTimestamp + 2*day;
  const duration = 2*day;
  const endTimestamp = startTimestamp + duration;
  
  const minValue = ethers.utils.parseEther("0.1");
  const maxValue = ethers.utils.parseEther("10");

  const softCap = ethers.utils.parseEther("80");
  const hardCap = ethers.utils.parseEther("200");

  const price = ethers.utils.parseEther("15000");

  const startTaxPercent = ethers.BigNumber.from(70_00000000);
  // falling 10% in 5 minutes
  const taxPercentFallPerSec = ethers.BigNumber.from(10_00000000).div(5*60);

  const ido = await IDOFactory.deploy(
    chiAddress,
    chiVestingAddress,
    startTimestamp,
    endTimestamp,
    minValue,
    maxValue,
    softCap,
    hardCap,
    price,
    MULTISIG_ADDRESS,
    startTaxPercent,
    taxPercentFallPerSec
  );

  await registerContractInJsonDb(
    "IDO",
    ido.address,
  );

  const CHI = await ethers.getContractAt("CHI", await getContractAddressFromJsonDb("CHI")) as CHI;
  const totalChi = hardCap.mul(price).div(ethers.utils.parseEther("1"));
  CHI.mint(ido.address, totalChi);

  return ido.address;
}
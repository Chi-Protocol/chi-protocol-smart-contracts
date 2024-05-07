import { ethers } from "hardhat";
import { registerContractInJsonDb } from "../helpers/deploy-helpers";

export async function deployVotingEscrowChi(
  chiLockingAddress: string,
  chiVestingAddress: string,
) {
  const VeCHI = await ethers.getContractFactory("veCHI");
  const veCHI = await VeCHI.deploy(chiLockingAddress, chiVestingAddress);
  await veCHI.deployed();
  await registerContractInJsonDb("veCHI", veCHI.address);
}

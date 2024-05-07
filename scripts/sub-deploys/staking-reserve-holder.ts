import { ethers, upgrades } from "hardhat";
import {
  CHI_VESTING_CLIFF_DURATION,
  CHI_VESTING_DURATION,
  CURVE_SAFE_GUARD_PERCENTAGE,
  RESERVE_HOLDER_ETH_THRESHOLD,
} from "../helpers/constants";
import {
  getContractAddressFromJsonDb,
  registerContractInJsonDb,
} from "../helpers/deploy-helpers";

export async function deployReserveHolder(
  priceFeedAggregatorAddress: string,
  rewardController: string,
) {
  const ReserveHolder = await ethers.getContractFactory("ReserveHolder");
  const reserveHolder = await upgrades.deployProxy(ReserveHolder, [
    priceFeedAggregatorAddress,
    rewardController,
    RESERVE_HOLDER_ETH_THRESHOLD,
    CURVE_SAFE_GUARD_PERCENTAGE,
  ]);
  await reserveHolder.deployed();
  await registerContractInJsonDb("ReserveHolder", reserveHolder.address);

  return reserveHolder.address;
}

export async function deployStakingAndReserveHolder(
  uscAddress: string,
  chiAddress: string,
  priceFeedAggregatorAddress: string,
) {
  let chiStakingAddress = await getContractAddressFromJsonDb("ChiStaking");

  if (!chiStakingAddress) {
    const ChiStaking = await ethers.getContractFactory("ChiStaking");
    const chiStaking = await upgrades.deployProxy(ChiStaking, [chiAddress]);
    await chiStaking.deployed();
    await registerContractInJsonDb("ChiStaking", chiStaking.address);
    chiStakingAddress = chiStaking.address;
  }

  let chiLockingAddress = await getContractAddressFromJsonDb("ChiLocking");

  if (!chiLockingAddress) {
    const ChiLocking = await ethers.getContractFactory("ChiLocking");
    const chiLocking = await upgrades.deployProxy(ChiLocking, [
      chiAddress,
      chiStakingAddress,
    ]);
    await chiLocking.deployed();
    await registerContractInJsonDb("ChiLocking", chiLocking.address);
    chiLockingAddress = chiLocking.address;

    const setChiLockerTx = await chiLocking.setChiLocker(
      chiStakingAddress,
      true,
    );
    await setChiLockerTx.wait();

    const chiStaking = await ethers.getContractAt(
      "ChiStaking",
      chiStakingAddress,
    );
    const setChiLockingTx = await chiStaking.setChiLocking(chiLocking.address);
    await setChiLockingTx.wait();
  }

  let uscEthLPStakingAddress =
    await getContractAddressFromJsonDb("USC_ETH_LP_Staking");
  if (!uscEthLPStakingAddress) {
    const uscEthLPAddress = await getContractAddressFromJsonDb("USC_ETH_LP");
    const LPStaking = await ethers.getContractFactory("LPStaking");
    const uscEthLPStaking = await upgrades.deployProxy(LPStaking, [
      chiAddress,
      chiLockingAddress,
      uscEthLPAddress,
      "Staked USC-ETH LP",
      "Staked USC-ETH LP",
    ]);
    await uscEthLPStaking.deployed();

    await registerContractInJsonDb(
      "USC_ETH_LP_Staking",
      uscEthLPStaking.address,
    );
    uscEthLPStakingAddress = uscEthLPStaking.address;
  }

  let chiEthLPStakingAddress =
    await getContractAddressFromJsonDb("CHI_ETH_LP_Staking");
  if (!chiEthLPStakingAddress) {
    const chiEthLPAddress = await getContractAddressFromJsonDb("CHI_ETH_LP");
    const LPStaking = await ethers.getContractFactory("LPStaking");
    const chiEthLPStaking = await upgrades.deployProxy(LPStaking, [
      chiAddress,
      chiLockingAddress,
      chiEthLPAddress,
      "Staked CHI-ETH LP",
      "Staked CHI-ETH LP",
    ]);
    await chiEthLPStaking.deployed();

    await registerContractInJsonDb(
      "CHI_ETH_LP_Staking",
      chiEthLPStaking.address,
    );
    chiEthLPStakingAddress = chiEthLPStaking.address;
  }

  let chiVestingAddress = await getContractAddressFromJsonDb("ChiVesting");

  if (!chiVestingAddress) {
    const ChiVesting = await ethers.getContractFactory("ChiVesting");
    const chiVesting = await upgrades.deployProxy(ChiVesting, [
      chiAddress,
      CHI_VESTING_CLIFF_DURATION,
      CHI_VESTING_DURATION,
    ]);
    await chiVesting.deployed();
    await registerContractInJsonDb("ChiVesting", chiVesting.address);
    chiVestingAddress = chiVesting.address;
  }

  let uscStakingAddress = await getContractAddressFromJsonDb("USCStaking");

  if (!uscStakingAddress) {
    const USCStaking = await ethers.getContractFactory("USCStaking");
    const uscStaking = await upgrades.deployProxy(USCStaking, [
      uscAddress,
      chiAddress,
      chiLockingAddress,
    ]);
    await uscStaking.deployed();
    await registerContractInJsonDb("USCStaking", uscStaking.address);
    uscStakingAddress = uscStaking.address;

    const chiLocking = await ethers.getContractAt(
      "ChiLocking",
      chiLockingAddress,
    );
    const setUscStakingTx = await chiLocking.setUscStaking(uscStaking.address);
    await setUscStakingTx.wait();
  }

  let reserveHolderAddress =
    await getContractAddressFromJsonDb("ReserveHolder");

  if (!reserveHolderAddress) {
    reserveHolderAddress = await deployReserveHolder(
      priceFeedAggregatorAddress,
      uscStakingAddress,
    );
    await registerContractInJsonDb("ReserveHolder", reserveHolderAddress);
  }

  let rewardControllerAddress =
    await getContractAddressFromJsonDb("RewardController");

  if (!rewardControllerAddress) {
    const blockTimestamp = (await ethers.provider.getBlock("latest")).timestamp;
    const RewardController =
      await ethers.getContractFactory("RewardController");
    const rewardController = await upgrades.deployProxy(RewardController, [
      chiAddress,
      uscAddress,
      reserveHolderAddress,
      uscStakingAddress,
      chiStakingAddress,
      chiLockingAddress,
      chiVestingAddress,
      uscEthLPStakingAddress,
      chiEthLPStakingAddress,
      blockTimestamp,
    ]);

    await rewardController.deployed();
    await registerContractInJsonDb(
      "RewardController",
      rewardController.address,
    );
    rewardControllerAddress = rewardController.address;

    const uscStaking = await ethers.getContractAt(
      "USCStaking",
      uscStakingAddress,
    );
    const chiStaking = await ethers.getContractAt(
      "ChiStaking",
      chiStakingAddress,
    );
    const chiLocking = await ethers.getContractAt(
      "ChiLocking",
      chiLockingAddress,
    );
    const chiVesting = await ethers.getContractAt(
      "ChiVesting",
      chiVestingAddress,
    );
    const uscEthLPStaking = await ethers.getContractAt(
      "LPStaking",
      uscEthLPStakingAddress,
    );
    const chiEthLPStaking = await ethers.getContractAt(
      "LPStaking",
      chiEthLPStakingAddress,
    );

    let tx;
    tx = await uscStaking.setRewardController(rewardControllerAddress);
    await tx.wait();
    tx = await chiStaking.setRewardController(rewardControllerAddress);
    await tx.wait();
    tx = await chiLocking.setRewardController(rewardControllerAddress);
    await tx.wait();
    tx = await chiVesting.setRewardController(rewardControllerAddress);
    await tx.wait();
    tx = await uscEthLPStaking.setRewardController(rewardControllerAddress);
    await tx.wait();
    tx = await chiEthLPStaking.setRewardController(rewardControllerAddress);
    await tx.wait();

    console.log("Reward controller address configured in all contracts");

    tx = await rewardController.setChiIncentivesForUscStaking(
      ethers.utils.parseEther("20000"),
    );
    await tx.wait();

    tx = await rewardController.setChiIncentivesForChiLocking(
      ethers.utils.parseEther("30000"),
    );
    await tx.wait();

    tx = await rewardController.setChiIncentivesForUscEthLPStaking(
      ethers.utils.parseEther("10000"),
    );
    await tx.wait();

    tx = await rewardController.setChiIncentivesForChiEthLPStaking(
      ethers.utils.parseEther("15000"),
    );
    await tx.wait();

    console.log("Chi locking, USC and LP staking incentives configured");
  }

  const reserveHolder = await ethers.getContractAt(
    "ReserveHolder",
    reserveHolderAddress,
  );
  const tx = await reserveHolder.setClaimer(rewardControllerAddress);
  await tx.wait();

  console.log("Claimer configured");

  return [
    rewardControllerAddress,
    uscStakingAddress,
    chiStakingAddress,
    chiLockingAddress,
    chiVestingAddress,
    reserveHolderAddress,
  ];
}

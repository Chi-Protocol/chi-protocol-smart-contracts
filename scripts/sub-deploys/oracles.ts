import { ethers } from "hardhat";
import {
  ETH_USD_PRICE_FEED,
  STETH_USD_PRICE_FEED,
  TWAP_ORACLE_MIN_PERIOD_FROM_SNAPSHOT,
  TWAP_ORACLE_UPDATE_PERIOD,
  UNI_V2_POOL_FACTORY,
  WETH,
  stETH,
} from "../helpers/constants";
import {
  getContractAddressFromJsonDb,
  registerContractInJsonDb,
} from "../helpers/deploy-helpers";

export async function deployOracles(uscAddress: string, chiAddress: string) {
  let ethUsdOracleAddress =
    await getContractAddressFromJsonDb("ETH_USD_oracle");
  if (!ethUsdOracleAddress) {
    const ChainlinkOracle = await ethers.getContractFactory("ChainlinkOracle");
    const ethUsdOracle = await ChainlinkOracle.deploy(WETH, ETH_USD_PRICE_FEED);
    await registerContractInJsonDb("ETH_USD_oracle", ethUsdOracle.address);
    ethUsdOracleAddress = ethUsdOracle.address;
  }

  let stEthUsdOracleAddress =
    await getContractAddressFromJsonDb("stETH_USD_oracle");
  if (!stEthUsdOracleAddress) {
    const ChainlinkOracle = await ethers.getContractFactory("ChainlinkOracle");
    const stEthUsdOracle = await ChainlinkOracle.deploy(
      stETH,
      STETH_USD_PRICE_FEED,
    );
    await registerContractInJsonDb("stETH_USD_oracle", stEthUsdOracle.address);
    stEthUsdOracleAddress = stEthUsdOracle.address;
  }

  let uscUsdOracleAddress =
    await getContractAddressFromJsonDb("USC_USD_oracle");
  if (!uscUsdOracleAddress) {
    const UniswapV2TwapOracle = await ethers.getContractFactory(
      "UniswapV2TwapOracle",
    );
    const uscUsdOracle = await UniswapV2TwapOracle.deploy(
      UNI_V2_POOL_FACTORY,
      uscAddress,
      WETH,
      TWAP_ORACLE_UPDATE_PERIOD,
      TWAP_ORACLE_MIN_PERIOD_FROM_SNAPSHOT,
      ETH_USD_PRICE_FEED,
    );
    await registerContractInJsonDb("USC_USD_oracle", uscUsdOracle.address);
    uscUsdOracleAddress = uscUsdOracle.address;
  }

  let chiUsdOracleAddress =
    await getContractAddressFromJsonDb("CHI_USD_oracle");
  if (!chiUsdOracleAddress) {
    const UniswapV2TwapOracle = await ethers.getContractFactory(
      "UniswapV2TwapOracle",
    );
    const chiUsdOracle = await UniswapV2TwapOracle.deploy(
      UNI_V2_POOL_FACTORY,
      chiAddress,
      WETH,
      TWAP_ORACLE_UPDATE_PERIOD,
      TWAP_ORACLE_MIN_PERIOD_FROM_SNAPSHOT,
      ETH_USD_PRICE_FEED,
    );
    await registerContractInJsonDb("CHI_USD_oracle", chiUsdOracle.address);
    chiUsdOracleAddress = chiUsdOracle.address;
  }

  let priceFeedAggregatorAddress = await getContractAddressFromJsonDb(
    "PriceFeedAggregator",
  );
  if (!priceFeedAggregatorAddress) {
    const PriceFeedAggregator = await ethers.getContractFactory(
      "PriceFeedAggregator",
    );
    const priceFeedAggregator = await PriceFeedAggregator.deploy();
    await registerContractInJsonDb(
      "PriceFeedAggregator",
      priceFeedAggregator.address,
    );
    priceFeedAggregatorAddress = priceFeedAggregator.address;

    let tx;
    tx = await priceFeedAggregator.setPriceFeed(WETH, ethUsdOracleAddress);
    await tx.wait();
    tx = await priceFeedAggregator.setPriceFeed(stETH, stEthUsdOracleAddress);
    await tx.wait();
    tx = await priceFeedAggregator.setPriceFeed(
      uscAddress,
      uscUsdOracleAddress,
    );
    await tx.wait();
    tx = await priceFeedAggregator.setPriceFeed(
      chiAddress,
      chiUsdOracleAddress,
    );
    await tx.wait();
  }

  return priceFeedAggregatorAddress;
}

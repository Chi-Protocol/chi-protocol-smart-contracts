import { ethers } from "hardhat";
import {
  CHI_INITIAL_LIQUIDITY,
  CHI_POOL_ETH_INITIAL_LIQUIDITY,
  DEADLINE,
  UNI_V2_POOL_FACTORY,
  UNI_V2_SWAP_ROUTER,
  USC_INITIAL_LIQUIDITY,
  USC_POOL_ETH_INITIAL_LIQUIDITY,
  WETH,
} from "../helpers/constants";
import {
  getContractAddressFromJsonDb,
  registerContractInJsonDb,
} from "../helpers/deploy-helpers";
import { CHI, USC } from "../../typechain-types";

export async function deployLiquidityPools(
  uscAddress: string,
  chiAddress: string,
) {
  const uniswapV2Factory = await ethers.getContractAt(
    "IUniswapV2Factory",
    UNI_V2_POOL_FACTORY,
  );

  const uscEthPoolAddress = await getContractAddressFromJsonDb("USC_ETH_LP");
  if (!uscEthPoolAddress) {
    const uscEthPoolCreationTx = await uniswapV2Factory.createPair(
      uscAddress,
      WETH,
    );
    await uscEthPoolCreationTx.wait();
    const uscEthPairAddress = await uniswapV2Factory.getPair(uscAddress, WETH);

    await registerContractInJsonDb("USC_ETH_LP", uscEthPairAddress);
  }

  const chiEthPoolAddress = await getContractAddressFromJsonDb("CHI_ETH_LP");
  if (!chiEthPoolAddress) {
    const chiEthPoolCreationTx = await uniswapV2Factory.createPair(
      chiAddress,
      WETH,
    );
    await chiEthPoolCreationTx.wait();
    const chiEthPairAddress = await uniswapV2Factory.getPair(chiAddress, WETH);

    await registerContractInJsonDb("CHI_ETH_LP", chiEthPairAddress);
  }
}

export async function provideLiquidity(usc: USC, chi: CHI) {
  const [deployer] = await ethers.getSigners();

  const updateMinterTx = await usc.updateMinter(deployer.address, true);
  await updateMinterTx.wait();

  const mintTx = await usc.mint(
    deployer.address,
    ethers.utils.parseEther(USC_INITIAL_LIQUIDITY),
  );
  await mintTx.wait();

  const removeMinterTx = await usc.updateMinter(deployer.address, false);
  await removeMinterTx.wait();

  const swapRouter = await ethers.getContractAt(
    "IUniswapV2Router02",
    UNI_V2_SWAP_ROUTER,
  );

  const uscApproveTx = await usc.approve(
    swapRouter.address,
    ethers.utils.parseEther(USC_INITIAL_LIQUIDITY),
  );
  await uscApproveTx.wait();

  const uscEthAddLiquidityTx = await swapRouter.addLiquidityETH(
    usc.address,
    ethers.utils.parseEther(USC_INITIAL_LIQUIDITY),
    0,
    0,
    deployer.address,
    DEADLINE,
    {
      value: ethers.utils.parseEther(USC_POOL_ETH_INITIAL_LIQUIDITY),
    },
  );
  await uscEthAddLiquidityTx.wait();

  const chiApproveTx = await chi.approve(
    swapRouter.address,
    ethers.utils.parseEther(CHI_INITIAL_LIQUIDITY),
  );
  await chiApproveTx.wait();

  const chiEthAddLiquidityTx = await swapRouter.addLiquidityETH(
    chi.address,
    ethers.utils.parseEther(CHI_INITIAL_LIQUIDITY),
    0,
    0,
    deployer.address,
    DEADLINE,
    {
      value: ethers.utils.parseEther(CHI_POOL_ETH_INITIAL_LIQUIDITY),
    },
  );
  await chiEthAddLiquidityTx.wait();
}

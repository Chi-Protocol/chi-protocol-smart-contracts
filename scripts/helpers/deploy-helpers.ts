import hre from "hardhat";
import { existsSync, readFileSync, writeFileSync } from "fs";

export const getContractAddressFromJsonDb = (contractId: string) => {
  const network = hre.network.name;

  const deployedContractsJson = existsSync("deployed-contracts.json")
    ? JSON.parse(readFileSync("deployed-contracts.json", "utf8"))
    : {};

  return deployedContractsJson[network]?.[contractId];
};

export const registerContractInJsonDb = async (
  contractId: string,
  contractAddress: string,
) => {
  const network = hre.network.name;

  const deployedContractsJson = existsSync("deployed-contracts.json")
    ? JSON.parse(readFileSync("deployed-contracts.json", "utf8"))
    : {};

  deployedContractsJson[network] = {
    ...deployedContractsJson[network],
    [contractId]: contractAddress,
  };

  writeFileSync(
    "deployed-contracts.json",
    JSON.stringify(deployedContractsJson, null, 2),
    { flag: "w", encoding: "utf8" },
  );

  console.log(
    `Contract ${contractId} was registered at ${contractAddress} on network ${network}`,
  );
};

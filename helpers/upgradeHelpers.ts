import { ethers, upgrades } from "hardhat";
import { AfETH } from "../typechain-types";

export const initialUpgradeableDeploy = async function () {
  const afETHDeployment = await ethers.getContractFactory("afETH");
  const afEth = (await afETHDeployment.deploy(
    "Asymmetry Finance ETH",
    "afETH"
  )) as AfETH;

  const AfStrategy = await ethers.getContractFactory("AfStrategy");
  const afStrategy = await upgrades.deployProxy(AfStrategy, [afEth.address]);
  await afStrategy.deployed();
  return afStrategy;
};

export const getLatestContract = async function (
  proxyAddress: string,
  latestContractName: string
) {
  const afStrategyLatest = await upgrades.forceImport(
    proxyAddress,
    await ethers.getContractFactory(latestContractName)
  );
  return afStrategyLatest;
};

export const upgrade = async function (
  proxyAddress: string,
  contractName: string
) {
  const NewContractFactory = await ethers.getContractFactory(contractName);
  const newContract = await upgrades.upgradeProxy(
    proxyAddress,
    NewContractFactory
  );
  return newContract;
};

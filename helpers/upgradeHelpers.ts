import { ethers, upgrades } from "hardhat";
import { AfETH } from "../typechain-types";

export const initialUpgradeableDeploy = async function () {
  const afETHFactory = await ethers.getContractFactory("afETH");
  const afEth = (await afETHFactory.deploy(
    "Asymmetry Finance ETH",
    "afETH"
  )) as AfETH;

  const AfStrategy = await ethers.getContractFactory("AfStrategy");
  const afStrategy = await upgrades.deployProxy(AfStrategy, [afEth.address]);
  await afStrategy.deployed();

  // deploy derivatives and add to strategy

  const derivativeFactory0 = await ethers.getContractFactory("Reth");
  const derivative0 = await derivativeFactory0.deploy();
  await derivative0.transferOwnership(afStrategy.address);
  await afStrategy.addDerivative(derivative0.address, "1000000000000000000");

  const derivativeFactory1 = await ethers.getContractFactory("SfrxEth");
  const derivative1 = await derivativeFactory1.deploy();
  await derivative1.transferOwnership(afStrategy.address);
  await afStrategy.addDerivative(derivative1.address, "1000000000000000000");

  const derivativeFactory2 = await ethers.getContractFactory("WstEth");
  const derivative2 = await derivativeFactory2.deploy();
  await derivative2.transferOwnership(afStrategy.address);
  await afStrategy.addDerivative(derivative2.address, "1000000000000000000");

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

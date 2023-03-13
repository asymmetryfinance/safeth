import { ethers, upgrades } from "hardhat";

export const initialUpgradeableDeploy = async function () {
  const AfStrategy = await ethers.getContractFactory("AfStrategy");
  const afStrategy = await upgrades.deployProxy(AfStrategy, [
    "Asymmetry Finance ETH",
    "safETH",
  ]);
  await afStrategy.deployed();

  // deploy derivatives and add to strategy

  const derivativeFactory0 = await ethers.getContractFactory("Reth");
  const derivative0 = await upgrades.deployProxy(derivativeFactory0, [
    afStrategy.address,
  ]);
  await derivative0.deployed();
  await afStrategy.addDerivative(derivative0.address, "1000000000000000000");

  const derivativeFactory1 = await ethers.getContractFactory("SfrxEth");
  const derivative1 = await upgrades.deployProxy(derivativeFactory1, [
    afStrategy.address,
  ]);
  await derivative1.deployed();
  await afStrategy.addDerivative(derivative1.address, "1000000000000000000");

  const derivativeFactory2 = await ethers.getContractFactory("WstEth");
  const derivative2 = await upgrades.deployProxy(derivativeFactory2, [
    afStrategy.address,
  ]);
  await derivative2.deployed();
  await afStrategy.addDerivative(derivative2.address, "1000000000000000000");

  const derivativeFactory3 = await ethers.getContractFactory("StakeWise");
  const derivative3 = await upgrades.deployProxy(derivativeFactory3, [
    afStrategy.address,
  ]);
  await derivative3.deployed();
  await afStrategy.addDerivative(derivative3.address, "1000000000000000000");
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

// scripts/create-box.js
import { ethers, upgrades } from "hardhat";
import { AfETH } from "../typechain-types";

export const deployV1 = async function () {
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

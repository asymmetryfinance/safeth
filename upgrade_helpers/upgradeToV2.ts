import { ethers, upgrades } from "hardhat";
export const upgradeToV2 = async function (proxyAddress: string) {
  const AfStrategyV2 = await ethers.getContractFactory("AfStrategyV2");
  const afStrategyV2 = await upgrades.upgradeProxy(proxyAddress, AfStrategyV2);
  return afStrategyV2;
};

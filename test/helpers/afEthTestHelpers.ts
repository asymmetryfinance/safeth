import { ethers, upgrades } from "hardhat";
import { deploySafEth } from "../helpers/upgradeHelpers";
import {
  AfEth,
  ExtraRewardsStream,
  SafEth,
  CvxStrategy,
} from "../../typechain-types";

export const deployStrategyContract = async () => {
  const safEth = (await deploySafEth()) as SafEth;

  const AfEthFactory = await ethers.getContractFactory("AfEth");
  const afEth = (await AfEthFactory.deploy(
    "Asymmetry Finance ETH",
    "afETh"
  )) as AfEth;
  await afEth.deployed();

  const ExtraRewardsStreamFactory = await ethers.getContractFactory(
    "ExtraRewardsStream"
  );
  const extraRewardsStream =
    (await ExtraRewardsStreamFactory.deploy()) as ExtraRewardsStream;
  await afEth.deployed();

  const CvxStrategy = await ethers.getContractFactory("CvxStrategy");
  const cvxStrategy = (await upgrades.deployProxy(CvxStrategy, [
    safEth.address,
    afEth.address,
    extraRewardsStream.address,
  ])) as CvxStrategy;
  await cvxStrategy.deployed();

  const accounts = await ethers.getSigners();
  await accounts[0].sendTransaction({
    to: extraRewardsStream.address,
    value: ethers.utils.parseEther("10.0"),
  });
  const tx = await extraRewardsStream.reset(
    60 * 60 * 24 * 7 * 16,
    cvxStrategy.address
  );
  await tx.wait();

  await afEth.setMinter(cvxStrategy.address);

  return { afEth, safEth, cvxStrategy, extraRewardsStream };
};

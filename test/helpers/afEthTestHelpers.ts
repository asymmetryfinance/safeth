import { ethers, upgrades } from "hardhat";
import { deploySafEth } from "../helpers/upgradeHelpers";
import {
  AfEth,
  ExtraRewardsStream,
  SafEth,
  CvxStrategy,
} from "../../typechain-types";

export const deployStrategyContract = async () => {
  console.log("deploying strategy contract");
  const safEth = (await deploySafEth()) as SafEth;

  await safEth.deployed();

  const RethFeedFactory = await ethers.getContractFactory(
    "ChainLinkRethFeedMock"
  );
  const WstFeedFactory = await ethers.getContractFactory(
    "ChainLinkWstFeedMock"
  );
  const rethFeed = await RethFeedFactory.deploy();
  await rethFeed.deployed();
  const wstFeed = await WstFeedFactory.deploy();
  await wstFeed.deployed();

  let t = await safEth.setChainlinkFeed(0, rethFeed.address);
  await t.wait();
  t = await safEth.setChainlinkFeed(2, wstFeed.address);
  await t.wait();

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
    60 * 60 * 24 * 7 * 16 * 16, // 16 lock periods (256 weeks) plenty of time to streaming rewards during all tests
    cvxStrategy.address
  );
  await tx.wait();

  await afEth.setMinter(cvxStrategy.address);

  return { afEth, safEth, cvxStrategy, extraRewardsStream };
};

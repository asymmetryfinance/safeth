/* eslint-disable new-cap */
import { upgrades, ethers } from "hardhat";
import { SafEth } from "../typechain-types";

import { deployDerivatives } from "./helpers/upgradeHelpers";

describe("SafEth", function () {
  let safEth: SafEth;
   const supportedDerivatives = [
    ["Reth", ""],
    "SfrxEth",
    "WstEth",
    "Ankr",
    "Stafi",
    "Swell",
  ];
  before(async () => {
    const SafEth = await ethers.getContractFactory("SafEth");
    safEth = (await upgrades.deployProxy(SafEth, [
      "Asymmetry Finance ETH",
      "safETH",
    ])) as SafEth;
    await safEth.deployed();
    const derivatives = await deployDerivatives(safEth.address);
    for (let i = 0; i < derivatives.length; i++)
      await safEth.addDerivative(derivatives[i].address, "1000000000000000000");
    await safEth.setPauseStaking(false);
  });

  describe("Slippage", function () {
    it("Should set slippage derivatives for each derivatives contract", async function () {});
  });
});

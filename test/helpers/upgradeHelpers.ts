import { ethers, network, upgrades } from "hardhat";
import { MULTI_SIG } from "./constants";

export const supportedDerivatives = [
  "Reth",
  "SfrxEth",
  "WstEth",
  "Ankr",
  "Stafi",
  "Swell",
];

export const deployDerivatives = async function (owner: string) {
  const derivatives = [];
  for (let i = 0; i < supportedDerivatives.length; i++) {
    const factory = await ethers.getContractFactory(supportedDerivatives[i]);
    const derivative = await upgrades.deployProxy(factory, [owner]);
    await derivative.deployed();
    derivatives.push(derivative);
    await derivative.initializeV2();

    if (supportedDerivatives[i] === "SfrxEth") {
      await network.provider.request({
        method: "hardhat_impersonateAccount",
        params: [MULTI_SIG],
      });
      const signers = await ethers.getSigners();
      await signers[9].sendTransaction({
        to: MULTI_SIG,
        value: "100000000000000000000",
      });
      const multiSigSigner = await ethers.getSigner(MULTI_SIG);
      const multiSig = derivative.connect(multiSigSigner);
      await multiSig.setDepegSlippage("4000000000000000");
    }
  }
  return derivatives;
};

export const deploySafEth = async function () {
  const SafEth = await ethers.getContractFactory("SafEth");
  const safEth = await upgrades.deployProxy(SafEth, [
    "Asymmetry Finance ETH",
    "safETH",
  ]);
  await safEth.deployed();
  const derivatives = await deployDerivatives(safEth.address);
  for (let i = 0; i < derivatives.length; i++)
    await safEth.addDerivative(derivatives[i].address, "1000000000000000000");
  await safEth.setPauseStaking(false);
  return safEth;
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

import { ethers, getNamedAccounts, network } from "hardhat";
import { expect } from "chai";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { BigNumber, Contract, Signer } from "ethers";

import ERC20 from "@openzeppelin/contracts/build/contracts/ERC20.json";
import {
  RETH_WHALE,
  SFRAXETH_ADDRESS,
  SFRAXETH_WHALE,
  WSTETH_ADRESS,
  WSTETH_WHALE,
} from "./constants";
import { AfETH, AfStrategy } from "../typechain-types";
import { deployV1 } from "../upgrade_helpers/deployV1";
import { afEthAbi } from "./abi/afEthAbi";
import { upgradeToV2 } from "../upgrade_helpers/upgradeToV2";
import { getLatestContract } from "../upgrade_helpers/getLatestContract";

describe.only("Af Strategy", function () {
  let accounts: SignerWithAddress[];
  let afEth: AfETH;
  let strategyProxy: AfStrategy;
  let aliceSigner: Signer;
  let wstEth: Contract;
  let rEth: Contract;
  let sfrxeth: Contract;

  beforeEach(async () => {
    const { admin, alice } = await getNamedAccounts();
    accounts = await ethers.getSigners();

    strategyProxy = (await deployV1()) as AfStrategy;

    const rethAddress = await strategyProxy.rethAddress();
    const afEthAddress = await strategyProxy.afETH();
    afEth = new ethers.Contract(afEthAddress, afEthAbi, accounts[0]) as AfETH;
    await afEth.setMinter(strategyProxy.address);

    // initialize derivative contracts
    wstEth = new ethers.Contract(WSTETH_ADRESS, ERC20.abi, accounts[0]);
    rEth = new ethers.Contract(rethAddress, ERC20.abi, accounts[0]);
    sfrxeth = new ethers.Contract(SFRAXETH_ADDRESS, ERC20.abi, accounts[0]);

    // signing defaults to admin, use this to sign for other wallets
    // you can add and name wallets in hardhat.config.ts
    aliceSigner = accounts.find(
      (account) => account.address === alice
    ) as Signer;

    // Send wstETH derivative to admin
    await network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [WSTETH_WHALE],
    });
    let transferAmount = ethers.utils.parseEther("50");
    let whaleSigner = await ethers.getSigner(WSTETH_WHALE);
    const wstEthWhale = wstEth.connect(whaleSigner);
    await wstEthWhale.transfer(admin, transferAmount);
    const wstEthBalance = await wstEth.balanceOf(admin);
    expect(BigNumber.from(wstEthBalance)).gte(transferAmount);

    // Send rETH derivative to admin
    await network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [RETH_WHALE],
    });
    transferAmount = ethers.utils.parseEther("50");
    whaleSigner = await ethers.getSigner(RETH_WHALE);
    const rEthWhale = rEth.connect(whaleSigner);
    await rEthWhale.transfer(admin, transferAmount);
    const rEthBalance = await rEth.balanceOf(admin);
    expect(BigNumber.from(rEthBalance)).gte(transferAmount);

    // Send sfrxeth derivative to admin
    await network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [SFRAXETH_WHALE],
    });
    transferAmount = ethers.utils.parseEther("50");
    whaleSigner = await ethers.getSigner(SFRAXETH_WHALE);
    const sfrxethWhale = sfrxeth.connect(whaleSigner);
    await sfrxethWhale.transfer(admin, transferAmount);
  });

  describe("Deposit/Withdraw", function () {
    it("Should deposit without changing the underlying price by a significant amount", async () => {
      const aliceStrategySigner = strategyProxy.connect(aliceSigner as Signer);

      const depositAmount = ethers.utils.parseEther("1");

      const price0 = await aliceStrategySigner.price();

      await aliceStrategySigner.stake({ value: depositAmount });
      const price1 = await aliceStrategySigner.price();
      expect(approxEqual(price0, price1)).eq(true);

      await aliceStrategySigner.stake({ value: depositAmount });
      const price2 = await aliceStrategySigner.price();
      expect(approxEqual(price1, price2)).eq(true);

      await aliceStrategySigner.stake({ value: depositAmount });
      const price3 = await aliceStrategySigner.price();
      expect(approxEqual(price2, price3)).eq(true);
    });
    it("Should withdraw without changing the underlying price by a significant amount", async () => {
      const { alice } = await getNamedAccounts();

      const aliceStrategySigner = strategyProxy.connect(aliceSigner as Signer);
      const depositAmount = ethers.utils.parseEther("1");

      await aliceStrategySigner.stake({ value: depositAmount });

      const unstakeAmountPerTx = (await afEth.balanceOf(alice)).div(4);

      const price0 = await aliceStrategySigner.price();

      await aliceStrategySigner.unstake(unstakeAmountPerTx);
      const price1 = await aliceStrategySigner.price();
      expect(approxEqual(price0, price1)).eq(true);

      await aliceStrategySigner.unstake(unstakeAmountPerTx);
      const price2 = await aliceStrategySigner.price();
      expect(approxEqual(price1, price2)).eq(true);

      await aliceStrategySigner.unstake(unstakeAmountPerTx);
      const price3 = await aliceStrategySigner.price();
      expect(approxEqual(price2, price3)).eq(true);

      await aliceStrategySigner.unstake(await afEth.balanceOf(alice));
      const price4 = await aliceStrategySigner.price();
      expect(approxEqual(price3, price4)).eq(true);
    });
  });

  describe("Prices", async () => {
    it("Should get rethPrice which is higher than eth price", async () => {
      const oneReth = BigNumber.from("1000000000000000000"); // 10^18 wei
      const oneEth = BigNumber.from("1000000000000000000"); // 10^18 wei
      const rethPrice = await strategyProxy.ethPerRethAmount(oneReth);
      expect(rethPrice.gt(oneEth)).eq(true);
    });

    it("Should get sfrxEthPrice which is higher than eth price", async () => {
      const oneSfrxEth = BigNumber.from("1000000000000000000"); // 10^18 wei
      const oneEth = BigNumber.from("1000000000000000000"); // 10^18 wei
      const sfrxPrice = await strategyProxy.ethPerSfrxAmount(oneSfrxEth);
      expect(sfrxPrice.gt(oneEth)).eq(true);
    });
    // TODO add price test for wsteth
  });

  describe("Upgrades", async () => {
    it("Should have the same proxy address before and after upgrading", async () => {
      const addressBefore = strategyProxy.address;
      const strategy2 = await upgradeToV2(strategyProxy.address);
      const addressAfter = strategy2.address;
      expect(addressBefore).eq(addressAfter);
    });
    it("Should have roughly the same price after upgrading", async () => {
      const priceBefore = await strategyProxy.price();
      const strategy2 = await upgradeToV2(strategyProxy.address);
      const priceAfter = await strategy2.price();
      expect(approxEqual(priceBefore, priceAfter)).eq(true);
    });
    it("Should allow v2 functionality to be used after upgrading", async () => {
      const strategy2 = await upgradeToV2(strategyProxy.address);
      expect(await strategy2.newFunctionCalled()).eq(false);
      await strategy2.newFunction();
      expect(await strategy2.newFunctionCalled()).eq(true);
    });
    it("Should get latest version of an already upgraded contract and use new functionality", async () => {
      await upgradeToV2(strategyProxy.address);
      const latestContract = await getLatestContract(
        strategyProxy.address,
        "AfStrategyV2"
      );
      expect(await latestContract.newFunctionCalled()).eq(false);
      await latestContract.newFunction();
      expect(await latestContract.newFunctionCalled()).eq(true);
    });
  });

  // Verify that 2 numbers are within 0.000001% of each other
  const approxEqual = (amount1: BigNumber, amount2: BigNumber) => {
    if (amount1.eq(amount2)) return true;
    const difference = amount1.gt(amount2)
      ? amount1.sub(amount2)
      : amount2.sub(amount1);
    const differenceRatio = amount1.div(difference);
    return differenceRatio.gt("1000000");
  };
});

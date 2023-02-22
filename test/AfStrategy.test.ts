import { ethers, getNamedAccounts } from "hardhat";
import { expect } from "chai";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { BigNumber, Signer } from "ethers";
import { AfETH, AfStrategy } from "../typechain-types";
import { deployV1 } from "../upgrade_helpers/deployV1";
import { afEthAbi } from "./abi/afEthAbi";
import { upgrade } from "../upgrade_helpers/upgrade";
import { getLatestContract } from "../upgrade_helpers/getLatestContract";
import { takeSnapshot } from "@nomicfoundation/hardhat-network-helpers";

describe.only("Af Strategy", function () {
  let accounts: SignerWithAddress[];
  let afEth: AfETH;
  let strategyProxy: AfStrategy;
  let aliceSigner: Signer;

  let snapshot: any;

  before(async () => {
    strategyProxy = (await deployV1()) as AfStrategy;
  });

  beforeEach(async () => {
    const { alice } = await getNamedAccounts();
    accounts = await ethers.getSigners();
    const afEthAddress = await strategyProxy.afETH();
    afEth = new ethers.Contract(afEthAddress, afEthAbi, accounts[0]) as AfETH;
    await afEth.setMinter(strategyProxy.address);
    // signing defaults to admin, use this to sign for other wallets
    // you can add and name wallets in hardhat.config.ts
    aliceSigner = accounts.find(
      (account) => account.address === alice
    ) as Signer;
    snapshot = await takeSnapshot();
  });

  afterEach(async () => {
    await snapshot.restore();
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
    it("Should get wstEthPrice which is higher than eth price", async () => {
      const oneWstEth = BigNumber.from("1000000000000000000"); // 10^18 wei
      const oneEth = BigNumber.from("1000000000000000000"); // 10^18 wei
      const wstPrice = await strategyProxy.ethPerWstAmount(oneWstEth);
      expect(wstPrice.gt(oneEth)).eq(true);
    });
    // TODO add price test for wsteth
  });

  describe("Upgrades", async () => {
    it("Should have the same proxy address before and after upgrading", async () => {
      const addressBefore = strategyProxy.address;
      const strategy2 = await upgrade(
        strategyProxy.address,
        "AfStrategyV2Mock"
      );
      const addressAfter = strategy2.address;
      expect(addressBefore).eq(addressAfter);
    });
    it("Should have roughly the same price after upgrading", async () => {
      const priceBefore = await strategyProxy.price();
      const strategy2 = await upgrade(
        strategyProxy.address,
        "AfStrategyV2Mock"
      );
      const priceAfter = await strategy2.price();
      expect(approxEqual(priceBefore, priceAfter)).eq(true);
    });
    it("Should allow v2 functionality to be used after upgrading", async () => {
      const strategy2 = await upgrade(
        strategyProxy.address,
        "AfStrategyV2Mock"
      );
      expect(await strategy2.newFunctionCalled()).eq(false);
      await strategy2.newFunction();
      expect(await strategy2.newFunctionCalled()).eq(true);
    });
    it("Should get latest version of an already upgraded contract and use new functionality", async () => {
      await upgrade(strategyProxy.address, "AfStrategyV2Mock");
      const latestContract = await getLatestContract(
        strategyProxy.address,
        "AfStrategyV2Mock"
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

import { ethers, getNamedAccounts } from "hardhat";
import { expect } from "chai";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { BigNumber, Signer } from "ethers";
import { AfETH, AfStrategy } from "../typechain-types";
import { afEthAbi } from "./abi/afEthAbi";
import {
  initialUpgradeableDeploy,
  upgrade,
  getLatestContract,
} from "../helpers/upgradeHelpers";
import { takeSnapshot } from "@nomicfoundation/hardhat-network-helpers";

describe.only("Af Strategy", function () {
  let accounts: SignerWithAddress[];
  let afEth: AfETH;
  let strategyProxy: AfStrategy;
  let aliceSigner: Signer;

  let snapshot: any;

  before(async () => {
    strategyProxy = (await initialUpgradeableDeploy()) as AfStrategy;
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

  describe("Derivatives", async () => {
    const derivatives = [] as any;
    before(async () => {
      const factory0 = await ethers.getContractFactory("Reth");
      const factory1 = await ethers.getContractFactory("SfrxEth");
      const factory2 = await ethers.getContractFactory("WstEth");
      derivatives.push(await factory0.deploy());
      derivatives.push(await factory1.deploy());
      derivatives.push(await factory2.deploy());
    });

    it("Should test each function on all derivative contracts", async () => {
      for (let i = 0; i < derivatives.length; i++) {
        // no balance before deposit
        const preStakeBalance = await derivatives[i].balance();
        expect(preStakeBalance.eq(0)).eq(true);

        // no value before deposit
        const preStakeValue = await derivatives[i].totalEthValue();
        expect(preStakeValue.eq(0)).eq(true);

        // price expected to be > eth price (always going up )
        const ethPerDerivative = await derivatives[i].ethPerDerivative(
          ethers.utils.parseEther("1")
        );
        expect(ethPerDerivative.gt(ethers.utils.parseEther("1"))).eq(true);

        await derivatives[i].deposit({ value: ethers.utils.parseEther("1") });

        // slippage should be less than 2% when staking (rocketpool sucks)
        const postStakeValue = await derivatives[i].totalEthValue();
        const valueDifference = ethers.utils
          .parseEther("1")
          .sub(postStakeValue)
          .abs();
        expect(valueDifference).lt(ethers.utils.parseEther("0.02"));

        // has balance after deposit
        const postStakeBalance = await derivatives[i].balance();
        expect(postStakeBalance.gt(0)).eq(true);

        await derivatives[i].withdraw(await derivatives[i].balance());

        // no balance after withdrawing all
        const postWithdrawBalance = await derivatives[i].balance();
        expect(postWithdrawBalance.eq(0)).eq(true);

        // no balance after withdrawing all
        const postWithdrawValue = await derivatives[i].totalEthValue();
        expect(postWithdrawValue.eq(0)).eq(true);
      }
    });
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

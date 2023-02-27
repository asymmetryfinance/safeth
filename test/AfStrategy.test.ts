/* eslint-disable new-cap */
import { ethers } from "hardhat";
import { expect } from "chai";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { BigNumber } from "ethers";
import { AfETH, AfStrategy } from "../typechain-types";
import { afEthAbi } from "./abi/afEthAbi";

import {
  initialUpgradeableDeploy,
  upgrade,
  getLatestContract,
} from "../helpers/upgradeHelpers";
import {
  SnapshotRestorer,
  takeSnapshot,
  time,
} from "@nomicfoundation/hardhat-network-helpers";
import bigDecimal from "js-big-decimal";

describe.only("Af Strategy", function () {
  let adminAccount: SignerWithAddress;
  let afEth: AfETH;
  let strategyProxy: AfStrategy;
  let snapshot: SnapshotRestorer;

  before(async () => {
    strategyProxy = (await initialUpgradeableDeploy()) as AfStrategy;
    const accounts = await ethers.getSigners();
    adminAccount = accounts[0];
    const afEthAddress = await strategyProxy.afETH();
    afEth = new ethers.Contract(afEthAddress, afEthAbi, accounts[0]) as AfETH;
    await afEth.setMinter(strategyProxy.address);
  });

  beforeEach(async () => {
    snapshot = await takeSnapshot();
  });

  afterEach(async () => {
    await snapshot.restore();
  });

  describe("Deposit/Withdraw", function () {
    it("Should deposit without changing the underlying valueBySupply by a significant amount", async () => {
      const depositAmount = ethers.utils.parseEther("1");

      const price0 = await strategyProxy.valueBySupply();

      // set all derivatives to the same weight and stake
      // if there are 3 derivatives this is 33/33/33
      const derivativeCount = (
        await strategyProxy.derivativeCount()
      ).toNumber();
      const initialWeight = BigNumber.from("1000000000000000000");

      for (let i = 0; i < derivativeCount; i++) {
        await strategyProxy.adjustWeight(i, initialWeight);
        await time.increase(1);
      }

      await strategyProxy.stake({ value: depositAmount });
      await time.increase(1);
      const price1 = await strategyProxy.valueBySupply();
      expect(approxEqual(price0, price1)).eq(true);

      await strategyProxy.stake({ value: depositAmount });
      await time.increase(1);
      const price2 = await strategyProxy.valueBySupply();
      expect(approxEqual(price1, price2)).eq(true);

      await strategyProxy.stake({ value: depositAmount });
      await time.increase(1);
      const price3 = await strategyProxy.valueBySupply();
      expect(approxEqual(price2, price3)).eq(true);
    });
    it("Should withdraw without changing the underlying valueBySupply by a significant amount", async () => {
      const depositAmount = ethers.utils.parseEther("1");
      // set all derivatives to the same weight and stake
      // if there are 3 derivatives this is 33/33/33
      const derivativeCount = (
        await strategyProxy.derivativeCount()
      ).toNumber();
      const initialWeight = BigNumber.from("1000000000000000000");

      for (let i = 0; i < derivativeCount; i++) {
        await strategyProxy.adjustWeight(i, initialWeight);
        await time.increase(1);
      }

      await strategyProxy.stake({ value: depositAmount });

      const unstakeAmountPerTx = (
        await afEth.balanceOf(adminAccount.address)
      ).div(4);

      const price0 = await strategyProxy.valueBySupply();

      await strategyProxy.unstake(unstakeAmountPerTx);
      await time.increase(1);
      const price1 = await strategyProxy.valueBySupply();
      expect(approxEqual(price0, price1)).eq(true);

      await strategyProxy.unstake(unstakeAmountPerTx);
      await time.increase(1);
      const price2 = await strategyProxy.valueBySupply();
      expect(approxEqual(price1, price2)).eq(true);

      await strategyProxy.unstake(unstakeAmountPerTx);
      await time.increase(1);
      const price3 = await strategyProxy.valueBySupply();
      expect(approxEqual(price2, price3)).eq(true);

      await strategyProxy.unstake(await afEth.balanceOf(adminAccount.address));
      await time.increase(1);
      const price4 = await strategyProxy.valueBySupply();
      expect(approxEqual(price3, price4)).eq(true);
    });
  });

  describe("Derivatives", async () => {
    const derivatives = [] as any;
    before(async () => {
      const factory0 = await ethers.getContractFactory("Reth");
      const factory1 = await ethers.getContractFactory("SfrxEth");
      const factory2 = await ethers.getContractFactory("WstEth");
      const factory3 = await ethers.getContractFactory("StakeWise");
      derivatives.push(await factory0.deploy());
      derivatives.push(await factory1.deploy());
      derivatives.push(await factory2.deploy());
      derivatives.push(await factory3.deploy());
    });

    it("Should test each function on all derivative contracts", async () => {
      for (let i = 0; i < derivatives.length; i++) {
        // no balance before deposit
        const preStakeBalance = await derivatives[i].balance();
        expect(preStakeBalance.eq(0)).eq(true);

        // no value before deposit
        const preStakeValue = await derivatives[i].totalEthValue();
        expect(preStakeValue.eq(0)).eq(true);

        await derivatives[i].deposit({ value: ethers.utils.parseEther("1") });
        await time.increase(1);
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
        await time.increase(1);
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
      await time.increase(1);
      const addressAfter = strategy2.address;
      expect(addressBefore).eq(addressAfter);
    });
    it("Should have roughly the same valueBySupply after upgrading", async () => {
      const priceBefore = await strategyProxy.valueBySupply();
      const strategy2 = await upgrade(
        strategyProxy.address,
        "AfStrategyV2Mock"
      );
      await time.increase(1);
      const priceAfter = await strategy2.valueBySupply();
      expect(approxEqual(priceBefore, priceAfter)).eq(true);
    });
    it("Should allow v2 functionality to be used after upgrading", async () => {
      const strategy2 = await upgrade(
        strategyProxy.address,
        "AfStrategyV2Mock"
      );
      await time.increase(1);
      expect(await strategy2.newFunctionCalled()).eq(false);
      await strategy2.newFunction();
      await time.increase(1);
      expect(await strategy2.newFunctionCalled()).eq(true);
    });

    it("Should get latest version of an already upgraded contract and use new functionality", async () => {
      await upgrade(strategyProxy.address, "AfStrategyV2Mock");
      const latestContract = await getLatestContract(
        strategyProxy.address,
        "AfStrategyV2Mock"
      );
      await time.increase(1);
      expect(await latestContract.newFunctionCalled()).eq(false);
      await latestContract.newFunction();
      await time.increase(1);
      expect(await latestContract.newFunctionCalled()).eq(true);
    });
  });

  describe("Weights & Rebalance", async () => {
    it("Should rebalance the underlying values to current weights", async () => {
      const derivativeCount = (
        await strategyProxy.derivativeCount()
      ).toNumber();

      const initialWeight = BigNumber.from("1000000000000000000"); // 10^18
      const initialDeposit = ethers.utils.parseEther("1");

      // set all derivatives to the same weight and stake
      // if there are 3 derivatives this is 33/33/33
      for (let i = 0; i < derivativeCount; i++) {
        await strategyProxy.adjustWeight(i, initialWeight);
        await time.increase(1);
      }
      await strategyProxy.stake({ value: initialDeposit });
      await time.increase(1);

      const underlyingValueBefore = await strategyProxy.underlyingValue();
      const priceBefore = await strategyProxy.valueBySupply();

      // set weight of derivative0 as equal to the sum of the other weights and rebalance
      // this is like 33/33/33 -> 50/25/25 (3 derivatives) or 25/25/25/25 -> 50/16.66/16.66/16.66 (4 derivatives)
      strategyProxy.adjustWeight(0, initialWeight.mul(derivativeCount - 1));
      await strategyProxy.rebalanceToWeights();
      await time.increase(1);

      const underlyingValueAfter = await strategyProxy.underlyingValue();
      const priceAfter = await strategyProxy.valueBySupply();

      // less than 2% difference before and after (because slippage)
      expect(
        decimalApproxEqual(
          new bigDecimal(underlyingValueAfter.toString()),
          new bigDecimal(underlyingValueBefore.toString()),
          new bigDecimal(0.02)
        )
      ).eq(true);

      const pricePercentChange = new bigDecimal(priceBefore.toString()).divide(
        new bigDecimal(priceAfter.toString()),
        18
      );

      const valuePercentChange = new bigDecimal(
        underlyingValueBefore.toString()
      ).divide(new bigDecimal(underlyingValueAfter.toString()), 18);

      // valueBySupply expected change by almost exactly the same % as value
      expect(
        decimalApproxEqual(
          pricePercentChange,
          valuePercentChange,
          new bigDecimal("0.000000001")
        )
      ).eq(true);

      // value of all derivatives excluding the first
      let remainingDerivativeValue = new bigDecimal();
      for (let i = 1; i < derivativeCount; i++) {
        remainingDerivativeValue = remainingDerivativeValue.add(
          new bigDecimal((await strategyProxy.derivativeValue(i)).toString())
        );
      }

      // value of first derivative should approx equal to the sum of the others (2% tolerance for slippage)
      expect(
        decimalApproxEqual(
          remainingDerivativeValue,
          new bigDecimal((await strategyProxy.derivativeValue(0)).toString()),
          new bigDecimal(0.02)
        )
      ).eq(true);
    });

    it("Should stake, unstake & rebalance when one of the weights is set to 0", async () => {
      const derivativeCount = (
        await strategyProxy.derivativeCount()
      ).toNumber();

      const initialWeight = BigNumber.from("1000000000000000000");
      const initialDeposit = ethers.utils.parseEther("1");

      // set all derivatives to the same weight and stake
      // if there are 3 derivatives this is 33/33/33
      for (let i = 0; i < derivativeCount; i++) {
        await strategyProxy.adjustWeight(i, initialWeight);
      }
      await strategyProxy.stake({ value: initialDeposit });
      await time.increase(1);

      const underlyingValueBefore = await strategyProxy.underlyingValue();

      // set derivative 0 to 0, rebalance and stake
      // This is like 33/33/33 -> 0/50/50
      await strategyProxy.adjustWeight(0, 0);
      await time.increase(1);
      await strategyProxy.rebalanceToWeights();
      await time.increase(1);

      const derivative0ValueAfter = await strategyProxy.derivativeValue(0);
      // derivative0 should now have 0 value
      expect(derivative0ValueAfter.toString() === "0").eq(true);

      const underlyingValueAfter = await strategyProxy.underlyingValue();

      // Underlying value is approx the same
      // 2% tolerance because slippage
      expect(
        decimalApproxEqual(
          new bigDecimal(underlyingValueBefore.toString()),
          new bigDecimal(underlyingValueAfter.toString()),
          new bigDecimal(0.02)
        )
      ).eq(true);

      await strategyProxy.unstake(await afEth.balanceOf(adminAccount.address));

      const finalUnderlyingValue = await strategyProxy.underlyingValue();
      // successfully withdrew with a 0 weight
      expect(finalUnderlyingValue.toString()).eq("0");
    });
  });

  // verify that 2 bigDecimals are within a given % of each other
  const decimalApproxEqual = (
    amount1: bigDecimal,
    amount2: bigDecimal,
    maxDifferencePercent: bigDecimal
  ) => {
    if (amount1.compareTo(amount2) === -1) {
      const differencePercent = new bigDecimal(1).subtract(
        amount1.divide(amount2, 18)
      );
      return (
        maxDifferencePercent.compareTo(differencePercent) === 1 ||
        maxDifferencePercent.compareTo(differencePercent) === 0
      );
    } else {
      const differencePercent = new bigDecimal(1).subtract(
        amount2.divide(amount1, 18)
      );
      return (
        maxDifferencePercent.compareTo(differencePercent) === 1 ||
        maxDifferencePercent.compareTo(differencePercent) === 0
      );
    }
  };

  // Verify that 2 ethers BigNumbers are within 0.000001% of each other
  const approxEqual = (amount1: BigNumber, amount2: BigNumber) => {
    if (amount1.eq(amount2)) return true;
    const difference = amount1.gt(amount2)
      ? amount1.sub(amount2)
      : amount2.sub(amount1);
    const differenceRatio = amount1.div(difference);
    return differenceRatio.gt("1000000");
  };
});

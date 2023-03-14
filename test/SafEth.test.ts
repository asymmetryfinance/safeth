/* eslint-disable new-cap */
import { network, upgrades, ethers } from "hardhat";
import { expect } from "chai";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { BigNumber } from "ethers";
import { SafEth } from "../typechain-types";

import {
  initialUpgradeableDeploy,
  upgrade,
  getLatestContract,
} from "./helpers/upgradeHelpers";
import {
  SnapshotRestorer,
  takeSnapshot,
} from "@nomicfoundation/hardhat-network-helpers";
import { rEthDepositPoolAbi } from "./abi/rEthDepositPoolAbi";
import { RETH_MAX } from "./helpers/constants";
import { derivativeAbi } from "./abi/derivativeAbi";

describe("Af Strategy", function () {
  let adminAccount: SignerWithAddress;
  let strategyProxy: SafEth;
  let snapshot: SnapshotRestorer;
  let initialHardhatBlock: number; // incase we need to reset to where we started

  const resetToBlock = async (blockNumber: number) => {
    await network.provider.request({
      method: "hardhat_reset",
      params: [
        {
          forking: {
            jsonRpcUrl: process.env.MAINNET_URL,
            blockNumber,
          },
        },
      ],
    });

    strategyProxy = (await initialUpgradeableDeploy()) as SafEth;
    const accounts = await ethers.getSigners();
    adminAccount = accounts[0];
  };

  before(async () => {
    const latestBlock = await ethers.provider.getBlock("latest");
    initialHardhatBlock = latestBlock.number;
    await resetToBlock(initialHardhatBlock);
  });

  describe("Large Amounts", function () {
    it("Should deposit and withdraw a large amount", async function () {
      const startingBalance = await adminAccount.getBalance();
      const depositAmount = ethers.utils.parseEther("1000");
      const tx1 = await strategyProxy.stake({ value: depositAmount });
      const mined1 = await tx1.wait();
      const networkFee1 = mined1.gasUsed.mul(mined1.effectiveGasPrice);

      const tx2 = await strategyProxy.unstake(
        await strategyProxy.balanceOf(adminAccount.address)
      );
      const mined2 = await tx2.wait();
      const networkFee2 = mined2.gasUsed.mul(mined2.effectiveGasPrice);
      const finalBalance = await adminAccount.getBalance();

      expect(
        within1Percent(
          finalBalance.add(networkFee1).add(networkFee2),
          startingBalance
        )
      ).eq(true);
    });
  });

  describe("Slippage", function () {
    it("Should set slippage derivatives via the strategy contract", async function () {
      const depositAmount = ethers.utils.parseEther("1");
      const derivativeCount = (
        await strategyProxy.derivativeCount()
      ).toNumber();

      // set slippages to a value we expect to fail
      for (let i = 0; i < derivativeCount; i++) {
        await strategyProxy.setMaxSlippage(i, 0); // 0% slippage we expect to fail
      }
      await expect(
        strategyProxy.stake({ value: depositAmount })
      ).to.be.revertedWith("Too little received");

      // set slippages back to good values
      for (let i = 0; i < derivativeCount; i++) {
        await strategyProxy.setMaxSlippage(i, ethers.utils.parseEther("0.05")); // 5%
      }
      await strategyProxy.stake({ value: depositAmount });
    });
  });

  describe("Owner functions", function () {
    it("Should pause staking / unstaking", async function () {
      snapshot = await takeSnapshot();
      const tx1 = await strategyProxy.setPauseStaking(true);
      await tx1.wait();
      const depositAmount = ethers.utils.parseEther("1");

      const derivativeCount = (
        await strategyProxy.derivativeCount()
      ).toNumber();
      const initialWeight = BigNumber.from("1000000000000000000");

      for (let i = 0; i < derivativeCount; i++) {
        const tx2 = await strategyProxy.adjustWeight(i, initialWeight);
        await tx2.wait();
      }
      await expect(
        strategyProxy.stake({ value: depositAmount })
      ).to.be.revertedWith("staking is paused");

      const tx3 = await strategyProxy.setPauseUnstaking(true);
      await tx3.wait();

      await expect(strategyProxy.unstake(1000)).to.be.revertedWith(
        "unstaking is paused"
      );

      // dont stay paused
      await snapshot.restore();
    });
    it("Should only allow owner to call pausing functions", async function () {
      const accounts = await ethers.getSigners();
      const nonOwnerSigner = strategyProxy.connect(accounts[2]);
      await expect(nonOwnerSigner.setPauseStaking(true)).to.be.revertedWith(
        "Ownable: caller is not the owner"
      );
      await expect(nonOwnerSigner.setPauseUnstaking(true)).to.be.revertedWith(
        "Ownable: caller is not the owner"
      );
    });
    it("Should be able to change min/max", async function () {
      snapshot = await takeSnapshot();
      await strategyProxy.setMinAmount(100);
      const minAmount = await strategyProxy.minAmount();
      expect(minAmount).eq(100);

      await strategyProxy.setMaxAmount(999);
      const maxAmount = await strategyProxy.maxAmount();
      expect(maxAmount).eq(999);

      await snapshot.restore();
    });
    it("Should only allow owner to call min/max functions", async function () {
      const accounts = await ethers.getSigners();
      const nonOwnerSigner = strategyProxy.connect(accounts[2]);
      await expect(nonOwnerSigner.setMinAmount(100000000)).to.be.revertedWith(
        "Ownable: caller is not the owner"
      );
      await expect(nonOwnerSigner.setMinAmount(900000000)).to.be.revertedWith(
        "Ownable: caller is not the owner"
      );
    });
  });

  describe("Derivatives", async () => {
    let derivatives = [] as any;
    beforeEach(async () => {
      await resetToBlock(16637130);
      derivatives = [];
      const factory0 = await ethers.getContractFactory("Reth");
      const factory1 = await ethers.getContractFactory("SfrxEth");
      const factory2 = await ethers.getContractFactory("WstEth");

      const derivative0 = await upgrades.deployProxy(factory0, [
        adminAccount.address,
      ]);
      await derivative0.deployed();
      derivatives.push(derivative0);

      const derivative1 = await upgrades.deployProxy(factory1, [
        adminAccount.address,
      ]);
      await derivative1.deployed();
      derivatives.push(derivative1);

      const derivative2 = await upgrades.deployProxy(factory2, [
        adminAccount.address,
      ]);
      await derivative2.deployed();
      derivatives.push(derivative2);
    });

    // Special case for testing rEth specific code path
    it("Should use reth deposit contract", async () => {
      await resetToBlock(15430855); // Deposit contract not full here
      const factory = await ethers.getContractFactory("Reth");
      const rEthDerivative = await upgrades.deployProxy(factory, [
        adminAccount.address,
      ]);
      await rEthDerivative.deployed();

      const depositPoolAddress = "0x2cac916b2A963Bf162f076C0a8a4a8200BCFBfb4";
      const depositPool = new ethers.Contract(
        depositPoolAddress,
        rEthDepositPoolAbi,
        adminAccount
      );
      const balance = await depositPool.getBalance();
      expect(balance).lt(RETH_MAX);

      const preStakeBalance = await rEthDerivative.balance();
      expect(preStakeBalance.eq(0)).eq(true);

      const ethDepositAmount = "1";

      const ethPerDerivative = await rEthDerivative.ethPerDerivative(
        ethDepositAmount
      );
      const derivativePerEth = BigNumber.from(
        "1000000000000000000000000000000000000"
      ).div(ethPerDerivative);

      const derivativeBalanceEstimate =
        BigNumber.from(ethDepositAmount).mul(derivativePerEth);

      const tx1 = await rEthDerivative.deposit({
        value: ethers.utils.parseEther(ethDepositAmount),
      });
      await tx1.wait();

      const postStakeBalance = await rEthDerivative.balance();

      expect(within2Percent(postStakeBalance, derivativeBalanceEstimate)).eq(
        true
      );
    });

    it("Should test deposit & withdraw on each derivative contract", async () => {
      const depositAmount = ethers.utils.parseEther("1");

      for (let i = 0; i < derivatives.length; i++) {
        // no balance before deposit
        const preStakeBalance = await derivatives[i].balance();
        expect(preStakeBalance.eq(0)).eq(true);

        const ethDepositAmount = "1";

        const ethPerDerivative = await derivatives[i].ethPerDerivative(
          ethDepositAmount
        );
        const derivativePerEth = BigNumber.from(
          "1000000000000000000000000000000000000"
        ).div(ethPerDerivative);
        const derivativeBalanceEstimate =
          BigNumber.from(ethDepositAmount).mul(derivativePerEth);
        const tx1 = await derivatives[i].deposit({ value: depositAmount });
        await tx1.wait();
        const postStakeBalance = await derivatives[i].balance();
        // roughly expected balance after deposit
        expect(within1Percent(postStakeBalance, derivativeBalanceEstimate)).eq(
          true
        );

        const tx2 = await derivatives[i].withdraw(
          await derivatives[i].balance()
        );
        await tx2.wait();

        // no balance after withdrawing all
        const postWithdrawBalance = await derivatives[i].balance();
        expect(postWithdrawBalance.eq(0)).eq(true);
      }
    });

    it("Should upgrade a derivative contract, stake and unstake with the new functionality", async () => {
      const derivativeToUpgrade = derivatives[0];

      const upgradedDerivative = await upgrade(
        derivativeToUpgrade.address,
        "DerivativeMock"
      );
      await upgradedDerivative.deployed();

      const depositAmount = ethers.utils.parseEther("1");

      const tx1 = await upgradedDerivative.deposit({ value: depositAmount });
      const mined1 = await tx1.wait();
      const networkFee1 = mined1.gasUsed.mul(mined1.effectiveGasPrice);

      const balanceBeforeWithdraw = await adminAccount.getBalance();

      // new functionality
      const tx2 = await upgradedDerivative.withdrawAll();
      const mined2 = await tx2.wait();
      const networkFee2 = mined2.gasUsed.mul(mined2.effectiveGasPrice);

      const balanceAfterWithdraw = await adminAccount.getBalance();
      const withdrawAmount = balanceAfterWithdraw.sub(balanceBeforeWithdraw);

      // Value in and out approx same
      // 2% tolerance because slippage
      expect(
        within1Percent(
          depositAmount,
          withdrawAmount.add(networkFee1).add(networkFee2)
        )
      ).eq(true);
    });
  });

  describe("Upgrades", async () => {
    beforeEach(async () => {
      snapshot = await takeSnapshot();
    });
    afterEach(async () => {
      await snapshot.restore();
    });

    it("Should have the same proxy address before and after upgrading", async () => {
      const addressBefore = strategyProxy.address;
      const strategy2 = await upgrade(strategyProxy.address, "SafEthV2Mock");
      await strategy2.deployed();
      const addressAfter = strategy2.address;
      expect(addressBefore).eq(addressAfter);
    });
    it("Should allow v2 functionality to be used after upgrading", async () => {
      const strategy2 = await upgrade(strategyProxy.address, "SafEthV2Mock");
      await strategy2.deployed();
      expect(await strategy2.newFunctionCalled()).eq(false);
      const tx = await strategy2.newFunction();
      await tx.wait();
      expect(await strategy2.newFunctionCalled()).eq(true);
    });

    it("Should get latest version of an already upgraded contract and use new functionality", async () => {
      await upgrade(strategyProxy.address, "SafEthV2Mock");
      const latestContract = await getLatestContract(
        strategyProxy.address,
        "SafEthV2Mock"
      );
      await latestContract.deployed();
      expect(await latestContract.newFunctionCalled()).eq(false);
      const tx = await latestContract.newFunction();
      await tx.wait();
      expect(await latestContract.newFunctionCalled()).eq(true);
    });

    it("Should be able to upgrade both the strategy contract and its derivatives and still function correctly", async () => {
      const strategy2 = await upgrade(strategyProxy.address, "SafEthV2Mock");

      const derivativeAddressToUpgrade = await strategy2.derivatives(1);

      const upgradedDerivative = await upgrade(
        derivativeAddressToUpgrade,
        "DerivativeMock"
      );
      await upgradedDerivative.deployed();

      const depositAmount = ethers.utils.parseEther("1");
      const tx1 = await strategy2.stake({ value: depositAmount });
      const mined1 = await tx1.wait();
      const networkFee1 = mined1.gasUsed.mul(mined1.effectiveGasPrice);

      const balanceBeforeWithdraw = await adminAccount.getBalance();

      const tx2 = await strategy2.unstake(
        await strategyProxy.balanceOf(adminAccount.address)
      );
      const mined2 = await tx2.wait();
      const networkFee2 = mined2.gasUsed.mul(mined1.effectiveGasPrice);
      const balanceAfterWithdraw = await adminAccount.getBalance();

      const withdrawAmount = balanceAfterWithdraw.sub(balanceBeforeWithdraw);

      // Value in and out approx same
      // 2% tolerance because slippage
      expect(
        within1Percent(
          depositAmount,
          withdrawAmount.add(networkFee1).add(networkFee2)
        )
      ).eq(true);
    });
  });

  describe("Weights & Rebalance", async () => {
    beforeEach(async () => {
      snapshot = await takeSnapshot();
    });
    afterEach(async () => {
      await snapshot.restore();
    });

    it("Should rebalance the underlying values to current weights", async () => {
      const derivativeCount = (
        await strategyProxy.derivativeCount()
      ).toNumber();

      const initialWeight = BigNumber.from("1000000000000000000"); // 10^18
      const initialDeposit = ethers.utils.parseEther("1");

      // set all derivatives to the same weight and stake
      // if there are 3 derivatives this is 33/33/33
      for (let i = 0; i < derivativeCount; i++) {
        const tx1 = await strategyProxy.adjustWeight(i, initialWeight);
        await tx1.wait();
      }
      const tx2 = await strategyProxy.stake({ value: initialDeposit });
      await tx2.wait();

      // set weight of derivative0 as equal to the sum of the other weights and rebalance
      // this is like 33/33/33 -> 50/25/25 (3 derivatives)
      strategyProxy.adjustWeight(0, initialWeight.mul(derivativeCount - 1));
      const tx3 = await strategyProxy.rebalanceToWeights();
      await tx3.wait();

      const ethBalances = await estimatedDerivativeValues();

      // TODO make this test work for any number of derivatives
      expect(within1Percent(ethBalances[0], ethBalances[1].mul(2))).eq(true);
      expect(within1Percent(ethBalances[0], ethBalances[2].mul(2))).eq(true);
    });

    it("Should stake with a weight set to 0", async () => {
      const derivativeCount = (
        await strategyProxy.derivativeCount()
      ).toNumber();

      const initialWeight = BigNumber.from("1000000000000000000");
      const initialDeposit = ethers.utils.parseEther("1");

      // set all derivatives to the same weight and stake
      // if there are 3 derivatives this is 33/33/33
      for (let i = 0; i < derivativeCount; i++) {
        const tx1 = await strategyProxy.adjustWeight(i, initialWeight);
        await tx1.wait();
      }

      const tx2 = await strategyProxy.adjustWeight(0, 0);
      await tx2.wait();
      const tx3 = await strategyProxy.stake({ value: initialDeposit });
      await tx3.wait();

      const ethBalances = await estimatedDerivativeValues();

      // TODO make this test work for any number of derivatives
      expect(ethBalances[0]).eq(BigNumber.from(0));
      expect(
        within1Percent(initialDeposit, ethBalances[1].add(ethBalances[1]))
      ).eq(true);
    });

    it("Should stake, set a weight to 0, rebalance, & unstake", async () => {
      const derivativeCount = (
        await strategyProxy.derivativeCount()
      ).toNumber();

      const initialWeight = BigNumber.from("1000000000000000000");
      const initialDeposit = ethers.utils.parseEther("1");

      const balanceBefore = await adminAccount.getBalance();

      let totalNetworkFee = BigNumber.from(0);
      // set all derivatives to the same weight and stake
      // if there are 3 derivatives this is 33/33/33
      for (let i = 0; i < derivativeCount; i++) {
        const tx1 = await strategyProxy.adjustWeight(i, initialWeight);
        const mined1 = await tx1.wait();
        const networkFee1 = mined1.gasUsed.mul(mined1.effectiveGasPrice);
        totalNetworkFee = totalNetworkFee.add(networkFee1);
      }
      const tx2 = await strategyProxy.stake({ value: initialDeposit });
      const mined2 = await tx2.wait();
      const networkFee2 = mined2.gasUsed.mul(mined2.effectiveGasPrice);
      totalNetworkFee = totalNetworkFee.add(networkFee2);

      // set derivative 0 to 0, rebalance and stake
      // This is like 33/33/33 -> 0/50/50
      const tx3 = await strategyProxy.adjustWeight(0, 0);
      const mined3 = await tx3.wait();
      const networkFee3 = mined3.gasUsed.mul(mined3.effectiveGasPrice);
      totalNetworkFee = totalNetworkFee.add(networkFee3);
      const tx4 = await strategyProxy.rebalanceToWeights();
      const mined4 = await tx4.wait();
      const networkFee4 = mined4.gasUsed.mul(mined4.effectiveGasPrice);
      totalNetworkFee = totalNetworkFee.add(networkFee4);

      const tx5 = await strategyProxy.unstake(
        await strategyProxy.balanceOf(adminAccount.address)
      );
      const mined5 = await tx5.wait();
      const networkFee5 = mined5.gasUsed.mul(mined5.effectiveGasPrice);
      totalNetworkFee = totalNetworkFee.add(networkFee5);

      const balanceAfter = await adminAccount.getBalance();

      expect(
        within1Percent(balanceBefore, balanceAfter.add(totalNetworkFee))
      ).eq(true);
    });
  });

  // get estimated total eth value of each derivative
  const estimatedDerivativeValues = async () => {
    const derivativeCount = (await strategyProxy.derivativeCount()).toNumber();

    const ethBalances: BigNumber[] = [];
    for (let i = 0; i < derivativeCount; i++) {
      const derivativeAddress = await strategyProxy.derivatives(i);

      const derivative = new ethers.Contract(
        derivativeAddress,
        derivativeAbi,
        adminAccount
      );

      const db = await derivative.balance();

      const ethPerDerivative = await derivative.ethPerDerivative(db);

      const ethBalanceEstimate = (await derivative.balance())
        .mul(ethPerDerivative)
        .div("1000000000000000000");
      ethBalances.push(ethBalanceEstimate);
    }
    return ethBalances;
  };

  // Verify that 2 ethers BigNumbers are within 2 percent of each other
  const within2Percent = (amount1: BigNumber, amount2: BigNumber) => {
    if (amount1.eq(amount2)) return true;
    const difference = amount1.gt(amount2)
      ? amount1.sub(amount2)
      : amount2.sub(amount1);
    const differenceRatio = amount1.div(difference);
    return differenceRatio.gt("50");
  };

  // Verify that 2 ethers BigNumbers are within 1 percent of each other
  const within1Percent = (amount1: BigNumber, amount2: BigNumber) => {
    if (amount1.eq(amount2)) return true;
    const difference = amount1.gt(amount2)
      ? amount1.sub(amount2)
      : amount2.sub(amount1);
    const differenceRatio = amount1.div(difference);
    return differenceRatio.gt("100");
  };
});

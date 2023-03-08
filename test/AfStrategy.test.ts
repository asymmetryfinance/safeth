/* eslint-disable new-cap */
import { network, upgrades, ethers } from "hardhat";
import { expect } from "chai";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { BigNumber } from "ethers";
import { AfStrategy, SafETH } from "../typechain-types";
import { afEthAbi } from "./abi/afEthAbi";
import ERC20 from "@openzeppelin/contracts/build/contracts/ERC20.json";

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
import { rEthDepositPoolAbi } from "./abi/rEthDepositPoolAbi";
import { RETH_MAX } from "./constants";

describe("Af Strategy", function () {
  let adminAccount: SignerWithAddress;
  let afEth: SafETH;
  let strategyProxy: AfStrategy;
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

    strategyProxy = (await initialUpgradeableDeploy()) as AfStrategy;
    const accounts = await ethers.getSigners();
    adminAccount = accounts[0];
    const afEthAddress = await strategyProxy.safETH();
    afEth = new ethers.Contract(afEthAddress, afEthAbi, accounts[0]) as SafETH;
    await afEth.setMinter(strategyProxy.address);
  };

  before(async () => {
    const latestBlock = await ethers.provider.getBlock("latest");
    initialHardhatBlock = latestBlock.number;
    await resetToBlock(initialHardhatBlock);
  });

  describe("Slippage", function () {
    it("Set slippage derivatives via the strategy contract", async function () {
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

  describe("Pause", function () {
    it("Should pause staking / unstaking", async function () {
      snapshot = await takeSnapshot();
      await strategyProxy.setPauseStaking(true);
      await time.increase(1);
      const depositAmount = ethers.utils.parseEther("1");

      const derivativeCount = (
        await strategyProxy.derivativeCount()
      ).toNumber();
      const initialWeight = BigNumber.from("1000000000000000000");

      for (let i = 0; i < derivativeCount; i++) {
        await strategyProxy.adjustWeight(i, initialWeight);
        await time.increase(1);
      }
      await expect(
        strategyProxy.stake({ value: depositAmount })
      ).to.be.revertedWith("staking is paused");

      await strategyProxy.setPauseUnstaking(true);

      await expect(strategyProxy.unstake(1000)).to.be.revertedWith(
        "unstaking is paused"
      );

      // dont stay paused
      await snapshot.restore();
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
      const factory3 = await ethers.getContractFactory("StakeWise");

      const derivative0 = await upgrades.deployProxy(factory0);
      await derivative0.deployed();
      derivatives.push(derivative0);

      const derivative1 = await upgrades.deployProxy(factory1);
      await derivative1.deployed();
      derivatives.push(derivative1);

      const derivative2 = await upgrades.deployProxy(factory2);
      await derivative2.deployed();
      derivatives.push(derivative2);

      const derivative3 = await upgrades.deployProxy(factory3);
      await derivative3.deployed();
      derivatives.push(derivative3);
    });

    it("Should use reth deposit contract", async () => {
      await resetToBlock(15430855); // Deposit contract not full here
      const factory = await ethers.getContractFactory("Reth");
      const rEthDerivative = await upgrades.deployProxy(factory);
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

      const value = ethers.utils.parseEther("1");
      const postStakeEthEstimation = await rEthDerivative.derivativePerEth(
        value
      );

      await rEthDerivative.deposit({ value });
      await time.increase(1);

      const postStakeBalance = await rEthDerivative.balance();
      expect(within2Percent(postStakeBalance, postStakeEthEstimation)).eq(true);
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

    it("Should test Stakewise withdraw when an rEth2 balance has accumulated", async () => {
      const stakewise = derivatives[3];

      const rEth2WhaleAddress = "0x7BdDb2C97AF91f97E73F07dEB976fdFC2d2Ee93c";

      const rEth2Address = "0x20bc832ca081b91433ff6c17f85701b6e92486c5";
      const rEth2 = new ethers.Contract(rEth2Address, ERC20.abi, adminAccount);

      await network.provider.request({
        method: "hardhat_impersonateAccount",
        params: [rEth2WhaleAddress],
      });

      const transferAmount = ethers.utils.parseEther("0.1");
      const whaleSigner = await ethers.getSigner(rEth2WhaleAddress);
      const rEth2Whale = rEth2.connect(whaleSigner);

      await stakewise.deposit({ value: ethers.utils.parseEther("0.1") });

      // simulate rEth2 reward accumulation
      await rEth2Whale.transfer(stakewise.address, transferAmount);

      // balance is in sEth2 which stable to eth
      const derivativeBalanceBeforeWithdraw = await stakewise.balance();

      const ethBalanceBeforeWithdraw = await adminAccount.getBalance();
      await stakewise.withdraw(await stakewise.balance());
      const ethBalanceAfterWithdraw = await adminAccount.getBalance();

      const balanceWithdrawn = ethBalanceAfterWithdraw.sub(
        ethBalanceBeforeWithdraw
      );

      // expect the derivative balance (which is in sEth) to approx equal the total amount withdrawn
      // 2% tolerance from slippage
      expect(
        within2Percent(balanceWithdrawn, derivativeBalanceBeforeWithdraw)
      ).eq(true);
    });

    it("Should withdraw the full balance from stakewise if more than the balance is passed in", async () => {
      const stakewise = derivatives[3];

      await stakewise.deposit({ value: ethers.utils.parseEther("0.1") });

      const derivativeBalanceBeforeWithdraw = await stakewise.balance();

      const ethBalanceBeforeWithdraw = await adminAccount.getBalance();
      await stakewise.withdraw((await stakewise.balance()).mul(2));
      const ethBalanceAfterWithdraw = await adminAccount.getBalance();

      const balanceWithdrawn = ethBalanceAfterWithdraw.sub(
        ethBalanceBeforeWithdraw
      );

      // expect the derivative balance (which is in sEth) to approx equal the total amount withdrawn
      // 2% tolerance from slippage
      expect(
        within2Percent(balanceWithdrawn, derivativeBalanceBeforeWithdraw)
      ).eq(true);
    });

    it("Should not deposit if more than the minActivatingDeposit on Stakewise", async () => {
      await resetToBlock(13637030); // 32 eth min at this block
      const factory = await ethers.getContractFactory("StakeWise");

      const stakewise = await upgrades.deployProxy(factory);
      await stakewise.deployed();

      const balanceBeforeDeposit = await stakewise.balance();

      const depositResult = await stakewise.deposit({
        value: ethers.utils.parseEther("33"),
      });
      await depositResult.wait();

      const balanceAfterDeposit = await stakewise.balance();

      // deposit doesnt happen because exceeded minActivatingDeposit at this block
      expect(balanceBeforeDeposit.toString()).eq(
        balanceAfterDeposit.toString()
      );
    });

    it("Should upgrade a derivative contract and have same values before and after upgrade", async () => {
      const derivativeToUpgrade = derivatives[1];

      const addressBefore = derivativeToUpgrade.address;
      const priceBefore = await derivativeToUpgrade.ethPerDerivative(
        "1000000000000000000"
      );

      const upgradedDerivative = await upgrade(addressBefore, "DerivativeMock");
      await upgradedDerivative.deployed();

      const addressAfter = upgradedDerivative.address;
      const priceAfter = await derivativeToUpgrade.ethPerDerivative(
        "1000000000000000000"
      );

      // value same before and after
      expect(addressBefore).eq(addressAfter);
      // price shouldnt have changed - maybe a tiny bit because block time
      expect(approxEqual(priceBefore, priceAfter)).eq(true);
    });

    it("Should upgrade a derivative contract, stake and unstake with the new functionality", async () => {
      const derivativeToUpgrade = derivatives[0];

      const upgradedDerivative = await upgrade(
        derivativeToUpgrade.address,
        "DerivativeMock"
      );
      await upgradedDerivative.deployed();

      const depositAmount = ethers.utils.parseEther("1");

      await upgradedDerivative.deposit({ value: ethers.utils.parseEther("1") });
      await time.increase(1);

      const balanceBeforeWithdraw = await adminAccount.getBalance();

      // new functionality
      await upgradedDerivative.withdrawAll();

      const balanceAfterWithdraw = await adminAccount.getBalance();
      const withdrawAmount = balanceAfterWithdraw.sub(balanceBeforeWithdraw);

      // Value in and out approx same
      // 2% tolerance because slippage
      expect(within2Percent(depositAmount, withdrawAmount)).eq(true);
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
      const strategy2 = await upgrade(
        strategyProxy.address,
        "AfStrategyV2Mock"
      );
      await time.increase(1);
      const addressAfter = strategy2.address;
      expect(addressBefore).eq(addressAfter);
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

    it("Should be able to upgrade both the strategy contract and its derivatives and still function correctly", async () => {
      const strategy2 = await upgrade(
        strategyProxy.address,
        "AfStrategyV2Mock"
      );

      const derivativeAddressToUpgrade = await strategy2.derivatives(1);

      const upgradedDerivative = await upgrade(
        derivativeAddressToUpgrade,
        "DerivativeMock"
      );
      await upgradedDerivative.deployed();

      const depositAmount = ethers.utils.parseEther("1");
      await strategy2.stake({ value: depositAmount });
      await time.increase(1);

      const balanceBeforeWithdraw = await adminAccount.getBalance();
      await strategy2.unstake(await afEth.balanceOf(adminAccount.address));
      const balanceAfterWithdraw = await adminAccount.getBalance();

      const withdrawAmount = balanceAfterWithdraw.sub(balanceBeforeWithdraw);

      // Value in and out approx same
      // 2% tolerance because slippage
      expect(within2Percent(depositAmount, withdrawAmount)).eq(true);
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
        await strategyProxy.adjustWeight(i, initialWeight);
        await time.increase(1);
      }
      await strategyProxy.stake({ value: initialDeposit });
      await time.increase(1);

      // set weight of derivative0 as equal to the sum of the other weights and rebalance
      // this is like 33/33/33 -> 50/25/25 (3 derivatives) or 25/25/25/25 -> 50/16.66/16.66/16.66 (4 derivatives)
      strategyProxy.adjustWeight(0, initialWeight.mul(derivativeCount - 1));
      await strategyProxy.rebalanceToWeights();
      await time.increase(1);

      // value of all derivatives excluding the first
      let remainingDerivativeValue = BigNumber.from(0);
      for (let i = 1; i < derivativeCount; i++) {
        remainingDerivativeValue = remainingDerivativeValue.add(
          await strategyProxy.derivativeValue(i)
        );
      }

      // value of first derivative should approx equal to the sum of the others (2% tolerance for slippage)
      expect(
        within2Percent(
          remainingDerivativeValue,
          await strategyProxy.derivativeValue(0)
        )
      ).eq(true);
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
        await strategyProxy.adjustWeight(i, initialWeight);
      }

      await strategyProxy.adjustWeight(0, 0);

      await strategyProxy.stake({ value: initialDeposit });
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

      // set derivative 0 to 0, rebalance and stake
      // This is like 33/33/33 -> 0/50/50
      await strategyProxy.adjustWeight(0, 0);
      await time.increase(1);
      await strategyProxy.rebalanceToWeights();
      await time.increase(1);

      const derivative0ValueAfter = await strategyProxy.derivativeValue(0);
      // derivative0 should now have 0 value
      expect(derivative0ValueAfter.toString() === "0").eq(true);

      await strategyProxy.unstake(await afEth.balanceOf(adminAccount.address));
    });
  });

  // Verify that 2 ethers BigNumbers are within 0.000001% of each other
  const approxEqual = (amount1: BigNumber, amount2: BigNumber) => {
    if (amount1.eq(amount2)) return true;
    const difference = amount1.gt(amount2)
      ? amount1.sub(amount2)
      : amount2.sub(amount1);
    const differenceRatio = amount1.div(difference);
    return differenceRatio.gt("1000000");
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
});

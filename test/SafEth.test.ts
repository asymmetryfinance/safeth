/* eslint-disable new-cap */
import { network, upgrades, ethers } from "hardhat";
import { expect } from "chai";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { BigNumber } from "ethers";
import { SafEth, SafEthReentrancyTest } from "../typechain-types";

import {
  deploySafEth,
  upgrade,
  getLatestContract,
} from "./helpers/upgradeHelpers";
import {
  SnapshotRestorer,
  takeSnapshot,
  time,
} from "@nomicfoundation/hardhat-network-helpers";
import { WSTETH_ADDRESS, WSTETH_WHALE } from "./helpers/constants";
import { derivativeAbi } from "./abi/derivativeAbi";
import { getDifferenceRatio } from "./SafEth-Integration.test";
import ERC20 from "@openzeppelin/contracts/build/contracts/ERC20.json";

describe("SafEth", function () {
  let adminAccount: SignerWithAddress;
  let safEthProxy: SafEth;
  let safEthReentrancyTest: SafEthReentrancyTest;
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

    safEthProxy = (await deploySafEth()) as SafEth;

    const SafEthReentrancyTestFactory = await ethers.getContractFactory(
      "SafEthReentrancyTest"
    );
    safEthReentrancyTest = (await SafEthReentrancyTestFactory.deploy(
      safEthProxy.address
    )) as SafEthReentrancyTest;
    await safEthReentrancyTest.deployed();

    const accounts = await ethers.getSigners();
    adminAccount = accounts[0];
  };

  before(async () => {
    const latestBlock = await ethers.provider.getBlock("latest");
    initialHardhatBlock = latestBlock.number;
    await resetToBlock(initialHardhatBlock);
  });

  describe("Large Amounts", function () {
    it("Should deposit and withdraw a large amount with minimal loss from slippage", async function () {
      const startingBalance = await adminAccount.getBalance();
      const depositAmount = ethers.utils.parseEther("200");
      const tx1 = await safEthProxy.stake(0, { value: depositAmount });
      const mined1 = await tx1.wait();
      const networkFee1 = mined1.gasUsed.mul(mined1.effectiveGasPrice);
      const tx2 = await safEthProxy.unstake(
        await safEthProxy.balanceOf(adminAccount.address),
        0
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
    it("Should fail unstake on zero safEthAmount", async function () {
      await expect(safEthProxy.unstake(0, 0)).revertedWith("amount too low");
    });
    it("Should fail unstake on invalid safEthAmount", async function () {
      await expect(safEthProxy.unstake(10, 0)).revertedWith(
        "insufficient balance"
      );
    });
    it("Should fail with wrong min/max", async function () {
      let depositAmount = ethers.utils.parseEther(".2");
      await expect(
        safEthProxy.stake(0, { value: depositAmount })
      ).to.be.revertedWith("amount too low");

      depositAmount = ethers.utils.parseEther("2050");
      await expect(
        safEthProxy.stake(0, { value: depositAmount })
      ).to.be.revertedWith("amount too high");
    });
  });

  describe("Slippage", function () {
    it("Should set slippage derivatives via the strategy contract", async function () {
      const depositAmount = ethers.utils.parseEther("1");
      const derivativeCount = (await safEthProxy.derivativeCount()).toNumber();

      for (let i = 0; i < derivativeCount; i++) {
        await safEthProxy.setMaxSlippage(i, ethers.utils.parseEther("0.01")); // 1%
      }
      await safEthProxy.stake(0, { value: depositAmount });

      for (let i = 0; i < derivativeCount; i++) {
        await safEthProxy.setMaxSlippage(i, ethers.utils.parseEther("0.02")); // 2%
      }
      await safEthProxy.stake(0, { value: depositAmount });
    });
  });
  describe("Receive Eth", function () {
    it("Should revert if sent eth by a user", async function () {
      await expect(
        adminAccount.sendTransaction({
          to: safEthProxy.address,
          value: ethers.utils.parseEther("1.0"),
        })
      ).to.be.revertedWith("Not a derivative contract");
    });
  });
  describe("Re-entrancy", function () {
    it("Should revert if re-entering unstake", async function () {
      console.log("about to send eth");
      const tx0 = await adminAccount.sendTransaction({
        to: safEthReentrancyTest.address,
        value: ethers.utils.parseEther("10.0"),
      });
      await tx0.wait();
      console.log("about to unstake");
      safEthReentrancyTest.testUnstake();

      await expect(safEthReentrancyTest.testUnstake()).to.be.revertedWith(
        "Failed to send Ether"
      );
    });
  });
  describe("Min Out", function () {
    it("Should fail staking with minOut higher than expected safEth output", async function () {
      const depositAmount = ethers.utils.parseEther("1");
      const minOut = ethers.utils.parseEther("2");
      await expect(
        safEthProxy.stake(minOut, { value: depositAmount })
      ).to.be.revertedWith("mint amount less than minOut");
    });
  });
  describe("Owner functions", function () {
    it("Should pause staking / unstaking", async function () {
      snapshot = await takeSnapshot();
      const tx1 = await safEthProxy.setPauseStaking(true);
      await tx1.wait();
      const depositAmount = ethers.utils.parseEther("1");

      const derivativeCount = (await safEthProxy.derivativeCount()).toNumber();
      const initialWeight = BigNumber.from("1000000000000000000");

      for (let i = 0; i < derivativeCount; i++) {
        const tx2 = await safEthProxy.adjustWeight(i, initialWeight);
        await tx2.wait();
      }
      await expect(
        safEthProxy.stake(0, { value: depositAmount })
      ).to.be.revertedWith("staking is paused");

      const tx3 = await safEthProxy.setPauseUnstaking(true);
      await tx3.wait();

      await expect(safEthProxy.unstake(1000, 0)).to.be.revertedWith(
        "unstaking is paused"
      );

      // dont stay paused
      await snapshot.restore();
    });
    it("Should fail with adding non erc 165 compliant derivative", async function () {
      await expect(
        safEthProxy.addDerivative(WSTETH_ADDRESS, "1000000000000000000")
      ).to.be.revertedWith("invalid contract");
    });
    it("Should fail with adding invalid erc165 derivative", async function () {
      const derivativeFactory0 = await ethers.getContractFactory(
        "InvalidErc165Derivative"
      );
      const derivative0 = await upgrades.deployProxy(derivativeFactory0, [
        safEthProxy.address,
      ]);
      await derivative0.deployed();
      await expect(
        safEthProxy.addDerivative(derivative0.address, "1000000000000000000")
      ).to.be.revertedWith("invalid derivative");
    });
    it("Should only allow owner to call pausing functions", async function () {
      const accounts = await ethers.getSigners();
      const nonOwnerSigner = safEthProxy.connect(accounts[2]);
      await expect(nonOwnerSigner.setPauseStaking(true)).to.be.revertedWith(
        "Ownable: caller is not the owner"
      );
      await expect(nonOwnerSigner.setPauseUnstaking(true)).to.be.revertedWith(
        "Ownable: caller is not the owner"
      );
    });
    it("Should be able to change min/max", async function () {
      snapshot = await takeSnapshot();
      await safEthProxy.setMinAmount(100);
      const minAmount = await safEthProxy.minAmount();
      expect(minAmount).eq(100);

      await safEthProxy.setMaxAmount(999);
      const maxAmount = await safEthProxy.maxAmount();
      expect(maxAmount).eq(999);

      await snapshot.restore();
    });
    it("Should only allow owner to call min/max functions", async function () {
      const accounts = await ethers.getSigners();
      const nonOwnerSigner = safEthProxy.connect(accounts[2]);
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
      await resetToBlock(initialHardhatBlock);
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
    it("Should withdraw reth on amm if deposit contract empty", async () => {
      // await resetToBlock(15430855); // Deposit contract not full here
      const factory = await ethers.getContractFactory("Reth");
      const rEthDerivative = await upgrades.deployProxy(factory, [
        adminAccount.address,
      ]);
      await rEthDerivative.deployed();

      const ethDepositAmount = "6000";
      const weiDepositAmount = ethers.utils.parseEther(ethDepositAmount);

      const tx1 = await rEthDerivative.deposit({ value: weiDepositAmount });
      await tx1.wait();

      const ethBalancePre = await ethers.provider.getBalance(
        rEthDerivative.address
      );
      expect(ethBalancePre).eq(0);

      const balance = await rEthDerivative.balance();
      expect(balance).gt(0);

      const tx2 = await rEthDerivative.withdraw(balance);
      await tx2.wait();

      const balanceAfter = await rEthDerivative.balance();
      expect(balanceAfter).eq(0);

      const ethBalancePost = await ethers.provider.getBalance(
        rEthDerivative.address
      );
      expect(ethBalancePost).eq(0);
    });
    it("Should test deposit & withdraw on each derivative contract", async () => {
      const ethDepositAmount = "200";

      const weiDepositAmount = ethers.utils.parseEther(ethDepositAmount);

      for (let i = 0; i < derivatives.length; i++) {
        // no balance before deposit
        const preStakeBalance = await derivatives[i].balance();
        expect(preStakeBalance.eq(0)).eq(true);

        const ethPerDerivative = await derivatives[i].ethPerDerivative();
        const derivativePerEth = BigNumber.from(
          "1000000000000000000000000000000000000"
        ).div(ethPerDerivative);
        const derivativeBalanceEstimate =
          BigNumber.from(ethDepositAmount).mul(derivativePerEth);
        const tx1 = await derivatives[i].deposit({ value: weiDepositAmount });
        await tx1.wait();
        const postStakeBalance = await derivatives[i].balance();

        // roughly expected derivative balance after deposit
        expect(within1Percent(postStakeBalance, derivativeBalanceEstimate)).eq(
          true
        );

        const preWithdrawEthBalance = await adminAccount.getBalance();
        const tx2 = await derivatives[i].withdraw(
          await derivatives[i].balance()
        );
        const mined2 = await tx2.wait();
        const networkFee2 = mined2.gasUsed.mul(mined2.effectiveGasPrice);
        const postWithdrawEthBalance = await adminAccount.getBalance();

        const ethReceived = postWithdrawEthBalance
          .sub(preWithdrawEthBalance)
          .add(networkFee2);

        // roughly same amount of eth received as originally deposited
        expect(within1Percent(ethReceived, weiDepositAmount)).eq(true);

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
      const addressBefore = safEthProxy.address;
      const strategy2 = await upgrade(safEthProxy.address, "SafEthV2Mock");
      await strategy2.deployed();
      const addressAfter = strategy2.address;
      expect(addressBefore).eq(addressAfter);
    });
    it("Should allow v2 functionality to be used after upgrading", async () => {
      const strategy2 = await upgrade(safEthProxy.address, "SafEthV2Mock");
      await strategy2.deployed();
      expect(await strategy2.newFunctionCalled()).eq(false);
      const tx = await strategy2.newFunction();
      await tx.wait();
      expect(await strategy2.newFunctionCalled()).eq(true);
    });

    it("Should get latest version of an already upgraded contract and use new functionality", async () => {
      await upgrade(safEthProxy.address, "SafEthV2Mock");
      const latestContract = await getLatestContract(
        safEthProxy.address,
        "SafEthV2Mock"
      );
      await latestContract.deployed();
      expect(await latestContract.newFunctionCalled()).eq(false);
      const tx = await latestContract.newFunction();
      await tx.wait();
      expect(await latestContract.newFunctionCalled()).eq(true);
    });

    it("Should be able to upgrade both the strategy contract and its derivatives and still function correctly", async () => {
      const strategy2 = await upgrade(safEthProxy.address, "SafEthV2Mock");

      const derivativeAddressToUpgrade = await strategy2.derivatives(1);

      const upgradedDerivative = await upgrade(
        derivativeAddressToUpgrade,
        "DerivativeMock"
      );
      await upgradedDerivative.deployed();

      const depositAmount = ethers.utils.parseEther("1");
      const tx1 = await strategy2.stake(0, { value: depositAmount });
      const mined1 = await tx1.wait();
      const networkFee1 = mined1.gasUsed.mul(mined1.effectiveGasPrice);

      const balanceBeforeWithdraw = await adminAccount.getBalance();

      const tx2 = await strategy2.unstake(
        await safEthProxy.balanceOf(adminAccount.address),
        0
      );
      const mined2 = await tx2.wait();
      const networkFee2 = mined2.gasUsed.mul(mined1.effectiveGasPrice);
      const balanceAfterWithdraw = await adminAccount.getBalance();

      const withdrawAmount = balanceAfterWithdraw.sub(balanceBeforeWithdraw);

      // Value in and out approx same
      expect(
        within1Percent(
          depositAmount,
          withdrawAmount.add(networkFee1).add(networkFee2)
        )
      ).eq(true);
    });

    it("Should allow owner to use admin features on upgraded contracts", async () => {
      const safEth2 = await upgrade(safEthProxy.address, "SafEthV2Mock");
      await safEth2.deployed();
      const depositAmount = ethers.utils.parseEther("1");
      const tx1 = await safEth2.stake(0, { value: depositAmount });
      await tx1.wait();

      const derivativeCount = await safEth2.derivativeCount();

      for (let i = 0; i < derivativeCount; i++) {
        const derivativeAddress = await safEth2.derivatives(i);

        const derivative = new ethers.Contract(
          derivativeAddress,
          derivativeAbi,
          adminAccount
        );
        const ethBalanceBeforeWithdraw = await adminAccount.getBalance();

        // admin withdraw from the derivatives in case of emergency
        const tx2 = await safEth2.adminWithdrawDerivative(
          i,
          derivative.balance()
        );
        const mined2 = await tx2.wait();
        const networkFee2 = mined2.gasUsed.mul(mined2.effectiveGasPrice);
        const ethBalanceAfterWithdraw = await adminAccount.getBalance();

        const amountWithdrawn = ethBalanceAfterWithdraw
          .sub(ethBalanceBeforeWithdraw)
          .add(networkFee2);

        expect(within1Percent(depositAmount, amountWithdrawn));
      }

      // accidentally send the contract some erc20
      await network.provider.request({
        method: "hardhat_impersonateAccount",
        params: [WSTETH_WHALE],
      });

      const whaleSigner = await ethers.getSigner(WSTETH_WHALE);
      const erc20 = new ethers.Contract(
        WSTETH_ADDRESS,
        ERC20.abi,
        adminAccount
      );
      const erc20Whale = erc20.connect(whaleSigner);
      const erc20Amount = ethers.utils.parseEther("1000");
      await erc20Whale.transfer(safEth2.address, erc20Amount);

      const erc20BalanceBefore = await erc20.balanceOf(adminAccount.address);

      // recover accidentally deposited erc20 with new admin functionality
      const tx4 = await safEth2.adminWithdrawErc20(
        WSTETH_ADDRESS,
        await erc20.balanceOf(safEth2.address)
      );
      await tx4.wait();
      const erc20BalanceAfter = await erc20.balanceOf(adminAccount.address);

      const erc20Received = erc20BalanceAfter.sub(erc20BalanceBefore);

      expect(erc20Received).eq(erc20Amount);
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
      const derivativeCount = (await safEthProxy.derivativeCount()).toNumber();

      const initialWeight = BigNumber.from("1000000000000000000"); // 10^18
      const initialDeposit = ethers.utils.parseEther("1");

      // set all derivatives to the same weight and stake
      // if there are 3 derivatives this is 33/33/33
      for (let i = 0; i < derivativeCount; i++) {
        const tx1 = await safEthProxy.adjustWeight(i, initialWeight);
        await tx1.wait();
      }
      const tx2 = await safEthProxy.stake(0, { value: initialDeposit });
      await tx2.wait();

      // set weight of derivative0 as equal to the sum of the other weights and rebalance
      // this is like 33/33/33 -> 50/25/25 (3 derivatives)
      safEthProxy.adjustWeight(0, initialWeight.mul(derivativeCount - 1));
      const tx3 = await safEthProxy.rebalanceToWeights();
      await tx3.wait();

      const ethBalances = await estimatedDerivativeValues();
      // TODO make this test work for any number of derivatives
      expect(within1Percent(ethBalances[0], ethBalances[1].mul(2))).eq(true);
      expect(within1Percent(ethBalances[0], ethBalances[2].mul(2))).eq(true);
    });

    it("Should stake with a weight set to 0", async () => {
      const derivativeCount = (await safEthProxy.derivativeCount()).toNumber();

      const initialWeight = BigNumber.from("1000000000000000000");
      const initialDeposit = ethers.utils.parseEther("1");

      // set all derivatives to the same weight and stake
      // if there are 3 derivatives this is 33/33/33
      for (let i = 0; i < derivativeCount; i++) {
        const tx1 = await safEthProxy.adjustWeight(i, initialWeight);
        await tx1.wait();
      }

      const tx2 = await safEthProxy.adjustWeight(0, 0);
      await tx2.wait();
      const tx3 = await safEthProxy.stake(0, { value: initialDeposit });
      await tx3.wait();

      const ethBalances = await estimatedDerivativeValues();

      // TODO make this test work for any number of derivatives
      expect(ethBalances[0]).eq(BigNumber.from(0));
      expect(
        within1Percent(initialDeposit, ethBalances[1].add(ethBalances[1]))
      ).eq(true);
    });

    it("Should stake, set a weight to 0, rebalance, & unstake", async () => {
      const derivativeCount = (await safEthProxy.derivativeCount()).toNumber();

      const initialWeight = BigNumber.from("1000000000000000000");
      const initialDeposit = ethers.utils.parseEther("1");

      const balanceBefore = await adminAccount.getBalance();

      let totalNetworkFee = BigNumber.from(0);
      // set all derivatives to the same weight and stake
      // if there are 3 derivatives this is 33/33/33
      for (let i = 0; i < derivativeCount; i++) {
        const tx1 = await safEthProxy.adjustWeight(i, initialWeight);
        const mined1 = await tx1.wait();
        const networkFee1 = mined1.gasUsed.mul(mined1.effectiveGasPrice);
        totalNetworkFee = totalNetworkFee.add(networkFee1);
      }
      const tx2 = await safEthProxy.stake(0, { value: initialDeposit });
      const mined2 = await tx2.wait();
      const networkFee2 = mined2.gasUsed.mul(mined2.effectiveGasPrice);
      totalNetworkFee = totalNetworkFee.add(networkFee2);

      // set derivative 0 to 0, rebalance and stake
      // This is like 33/33/33 -> 0/50/50
      const tx3 = await safEthProxy.adjustWeight(0, 0);
      const mined3 = await tx3.wait();
      const networkFee3 = mined3.gasUsed.mul(mined3.effectiveGasPrice);
      totalNetworkFee = totalNetworkFee.add(networkFee3);
      const tx4 = await safEthProxy.rebalanceToWeights();
      const mined4 = await tx4.wait();
      const networkFee4 = mined4.gasUsed.mul(mined4.effectiveGasPrice);
      totalNetworkFee = totalNetworkFee.add(networkFee4);

      const tx5 = await safEthProxy.unstake(
        await safEthProxy.balanceOf(adminAccount.address),
        0
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

  describe("Price", function () {
    it("Should correctly get approxPrice()", async function () {
      const depositAmount = ethers.utils.parseEther("1");
      await safEthProxy.stake(0, { value: depositAmount });

      const price1 = await safEthProxy.approxPrice();
      // starting price = 1 Eth
      expect(price1).eq("1000000000000000000");

      await time.increase(10000);
      const price2 = await safEthProxy.approxPrice();

      // price has increased after some time
      expect(price2).gt(price1);
    });
  });

  // get estimated total eth value of each derivative
  const estimatedDerivativeValues = async () => {
    const derivativeCount = (await safEthProxy.derivativeCount()).toNumber();

    const ethBalances: BigNumber[] = [];
    for (let i = 0; i < derivativeCount; i++) {
      const derivativeAddress = await safEthProxy.derivatives(i);
      const derivative = new ethers.Contract(
        derivativeAddress,
        derivativeAbi,
        adminAccount
      );
      const ethPerDerivative = await derivative.ethPerDerivative();

      const ethBalanceEstimate = (await derivative.balance())
        .mul(ethPerDerivative)
        .div("1000000000000000000");

      ethBalances.push(ethBalanceEstimate);
    }
    return ethBalances;
  };

  const within1Percent = (amount1: BigNumber, amount2: BigNumber) => {
    if (amount1.eq(amount2)) return true;
    return getDifferenceRatio(amount1, amount2).gt("100");
  };
});

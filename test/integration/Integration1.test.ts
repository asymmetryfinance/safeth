import { AfStrategy, SafETH } from "../../typechain-types";
import { ethers, upgrades } from "hardhat";
import { expect } from "chai";
import {
  getAdminAccount,
  getUserAccounts,
  randomEthAmount,
  randomStakeUnstake,
  stakeLargeAmount,
  stakeMaximum,
  stakeMinimum,
  totalUserBalances,
} from "./integrationHelpers";
import { getLatestContract } from "../../helpers/upgradeHelpers";
import { afEthAbi } from "../abi/afEthAbi";
import { BigNumber } from "ethers";
import { time } from "@nomicfoundation/hardhat-network-helpers";

// These tests are intended to run in-order.
// Together they form a single integration test simulating real-world usage
describe.only("Integration Test 1", function () {
  let safEthContractAddress: string;
  let strategyContractAddress: string;

  it("Should deploy safEth token", async function () {
    const safETHFactory = await ethers.getContractFactory("safETH");
    const safEth = (await safETHFactory.deploy(
      "Asymmetry Finance safETH",
      "safETH"
    )) as SafETH;
    await safEth.deployed();

    const owner = await safEth.owner();
    const totalSupply = await safEth.totalSupply();

    safEthContractAddress = safEth.address;

    expect(owner).eq((await getAdminAccount()).address);
    expect(totalSupply).eq("0");
  });

  it("Should deploy the strategy contract and set it as the afEth minter", async function () {
    const afStrategyFactory = await ethers.getContractFactory("AfStrategy");
    const strategy = (await upgrades.deployProxy(afStrategyFactory, [
      safEthContractAddress,
    ])) as AfStrategy;
    await strategy.deployed();

    strategyContractAddress = strategy.address;

    const safEth = new ethers.Contract(
      safEthContractAddress,
      afEthAbi,
      await getAdminAccount()
    ) as SafETH;

    await safEth.setMinter(strategyContractAddress);
    await time.increase(1);

    const owner = await strategy.owner();
    const derivativeCount = await strategy.derivativeCount();
    const underlyingValue = await strategy.underlyingValue();
    const safEthMinter = await safEth.minter();

    expect(owner).eq((await getAdminAccount()).address);
    expect(derivativeCount).eq("0");
    expect(underlyingValue).eq("0");
    expect(safEthMinter).eq(strategyContractAddress);
  });

  it("Should deploy derivative contracts and add them to the strategy contract with equal weights", async function () {
    const supportedDerivatives = ["Reth", "SfrxEth", "WstEth", "StakeWise"];
    const strategy = await getLatestContract(
      strategyContractAddress,
      "AfStrategy"
    );

    for (let i = 0; i < supportedDerivatives.length; i++) {
      const derivativeFactory = await ethers.getContractFactory(
        supportedDerivatives[i]
      );
      const derivative = await upgrades.deployProxy(derivativeFactory);
      await derivative.deployed();
      await derivative.transferOwnership(strategyContractAddress);
      await time.increase(1);
      await strategy.addDerivative(derivative.address, "1000000000000000000");
      await time.increase(1);
    }

    const derivativeCount = await strategy.derivativeCount();

    expect(derivativeCount).eq(supportedDerivatives.length);
  });

  it("Should stake a small amount", async function () {
    const strategy = await getLatestContract(
      strategyContractAddress,
      "AfStrategy"
    );

    const userAccounts = await getUserAccounts();

    let totalDeposited = BigNumber.from(0);

    const depositAmount = ethers.utils.parseEther(
      randomEthAmount(stakeMinimum, stakeMaximum)
    );
    totalDeposited = totalDeposited.add(depositAmount);
    const userStrategySigner = strategy.connect(userAccounts[0]);
    await userStrategySigner.stake({ value: depositAmount });
    await time.increase(1);

    const underlyingValue = await strategy.underlyingValue();

    expect(within2Percent(underlyingValue, totalDeposited)).eq(true);
  });

  it("Should stake a large amount", async function () {
    const strategy = await getLatestContract(
      strategyContractAddress,
      "AfStrategy"
    );

    const userAccounts = await getUserAccounts();

    let totalDeposited = BigNumber.from(0);

    const depositAmount = ethers.utils.parseEther(stakeLargeAmount.toString());
    totalDeposited = totalDeposited.add(depositAmount);
    const userStrategySigner = strategy.connect(userAccounts[0]);

    const underlyingValueBefore = await strategy.underlyingValue();

    await userStrategySigner.stake({ value: depositAmount });
    await time.increase(1);

    const underlyingValueAfter = await strategy.underlyingValue();

    const underlyingValueChange = underlyingValueBefore
      .sub(underlyingValueAfter)
      .abs();

    expect(within2Percent(underlyingValueChange, totalDeposited)).eq(true);
  });

  it("Should stake a random amount for each user", async function () {
    const strategy = await getLatestContract(
      strategyContractAddress,
      "AfStrategy"
    );

    const userAccounts = await getUserAccounts();

    let totalDeposited = BigNumber.from(0);

    const underlyingValueBefore = await strategy.underlyingValue();

    for (let i = 0; i < userAccounts.length; i++) {
      const depositAmount = ethers.utils.parseEther(
        randomEthAmount(stakeMinimum, stakeMaximum)
      );
      totalDeposited = totalDeposited.add(depositAmount);
      const userStrategySigner = strategy.connect(userAccounts[i]);
      await userStrategySigner.stake({ value: depositAmount });
      await time.increase(1);
    }

    const underlyingValueAfter = await strategy.underlyingValue();

    const underlyingValueChange = underlyingValueBefore
      .sub(underlyingValueAfter)
      .abs();

    expect(within2Percent(underlyingValueChange, totalDeposited)).eq(true);
  });

  it("Should change weights and rebalance (1)", async function () {
    const strategy = await getLatestContract(
      strategyContractAddress,
      "AfStrategy"
    );

    // set weight of derivative0 to 0 and derivative1 to 2 * 10^18
    // this is like going from 25/25/25/25 -> 0/50/25/25
    await strategy.adjustWeight(0, 0);
    await time.increase(1);
    await strategy.adjustWeight(1, "2000000000000000000");
    await time.increase(1);
    await strategy.rebalanceToWeights();
    await time.increase(1);

    const derivative0Value = await strategy.derivativeValue(0);
    const derivative1Value = await strategy.derivativeValue(1);
    const derivative2Value = await strategy.derivativeValue(2);
    const derivative3Value = await strategy.derivativeValue(3);

    expect(derivative0Value).eq(BigNumber.from(0));
    expect(
      within2Percent(derivative1Value, derivative2Value.add(derivative3Value))
    ).eq(true);
    expect(within2Percent(derivative2Value, derivative3Value)).eq(true);
  });

  it("Should do random stakes & unstakes for all users (1)", async function () {
    const strategy = await getLatestContract(
      strategyContractAddress,
      "AfStrategy"
    );

    const underlyingValueBefore = await strategy.underlyingValue();

    const totalUserBalanceBefore = await totalUserBalances();

    const networkFee = await randomStakeUnstake(
      strategyContractAddress,
      safEthContractAddress
    );

    const totalUserBalanceAfter = await totalUserBalances();

    const totalUserEthSentReceived = totalUserBalanceAfter
      .add(networkFee)
      .sub(totalUserBalanceBefore)
      .abs();

    const underlyingValueAfter = await strategy.underlyingValue();

    const underlyingValueChange = underlyingValueBefore
      .sub(underlyingValueAfter)
      .abs();

    expect(within2Percent(totalUserEthSentReceived, underlyingValueChange)).eq(
      true
    );
  });

  it("Should change weights and rebalance again (2)", async function () {
    const strategy = await getLatestContract(
      strategyContractAddress,
      "AfStrategy"
    );

    // set weight of derivative0 to 2 * 10^18
    // this is like going from 0/50/25/25 -> 33/33/16/16
    await strategy.adjustWeight(0, "2000000000000000000");
    await time.increase(1);
    await strategy.rebalanceToWeights();
    await time.increase(1);

    const derivative0Value = await strategy.derivativeValue(0);
    const derivative1Value = await strategy.derivativeValue(1);
    const derivative2Value = await strategy.derivativeValue(2);
    const derivative3Value = await strategy.derivativeValue(3);

    // derivative0 ~= derivative1
    // 33.33% = 33.33%
    expect(within2Percent(derivative0Value, derivative1Value)).eq(true);

    // derivative2 ~= derivative3
    // 16.66% ~= 16.66%
    expect(within2Percent(derivative2Value, derivative3Value)).eq(true);

    // derivative0 ~= derivative2+derivative3
    // 33.33% ~= 16.66% + 16.66%
    expect(
      within2Percent(derivative0Value, derivative2Value.add(derivative3Value))
    ).eq(true);

    // derivative1 ~= derivative2+derivative3
    // 33% ~= 16.66% + 16.66%
    expect(
      within2Percent(derivative1Value, derivative2Value.add(derivative3Value))
    ).eq(true);
  });

  it("Should do random stakes & unstakes for all users (2)", async function () {
    const strategy = await getLatestContract(
      strategyContractAddress,
      "AfStrategy"
    );

    const underlyingValueBefore = await strategy.underlyingValue();

    const totalUserBalanceBefore = await totalUserBalances();

    const networkFee = await randomStakeUnstake(
      strategyContractAddress,
      safEthContractAddress
    );

    const totalUserBalanceAfter = await totalUserBalances();

    const totalUserEthSentReceived = totalUserBalanceAfter
      .add(networkFee)
      .sub(totalUserBalanceBefore)
      .abs();

    const underlyingValueAfter = await strategy.underlyingValue();

    const underlyingValueChange = underlyingValueBefore
      .sub(underlyingValueAfter)
      .abs();

    expect(within2Percent(totalUserEthSentReceived, underlyingValueChange)).eq(
      true
    );
  });

  it("Should unstake everything for all users", async function () {
    const strategy = await getLatestContract(
      strategyContractAddress,
      "AfStrategy"
    );
    const safEth = new ethers.Contract(
      safEthContractAddress,
      afEthAbi,
      await getAdminAccount()
    ) as SafETH;

    const underlyingValueBefore = await strategy.underlyingValue();

    const totalUserBalanceBefore = await totalUserBalances();

    const userAccounts = await getUserAccounts();

    let networkFee = BigNumber.from(0);
    for (let i = 0; i < userAccounts.length; i++) {
      const withdrawAmount = await safEth.balanceOf(userAccounts[i].address);
      if (withdrawAmount.eq(0)) continue;
      const userStrategySigner = strategy.connect(userAccounts[i]);
      const unstakeResult = await userStrategySigner.unstake(withdrawAmount);
      const mined = await unstakeResult.wait();
      networkFee = networkFee.add(mined.gasUsed.mul(mined.effectiveGasPrice));
      await time.increase(1);
    }

    const underlyingValueAfter = await strategy.underlyingValue();

    const totalUserBalanceAfter = await totalUserBalances();

    const totalUserEthSentReceived = totalUserBalanceAfter
      .add(networkFee)
      .sub(totalUserBalanceBefore)
      .abs();

    const underlyingValueChange = underlyingValueBefore
      .sub(underlyingValueAfter)
      .abs();

    expect(within2Percent(underlyingValueChange, totalUserEthSentReceived)).eq(
      true
    );
  });
});

const within2Percent = (amount1: BigNumber, amount2: BigNumber) => {
  if (amount1.eq(amount2)) return true;
  return getDifferenceRatio(amount1, amount2).gt("50");
};

// Get ratio between 2 amounts such that % diff = 1/ratio
// Example: 200 = 0.5%, 100 = 1%, 50 = 2%, 25 = 4%, etc
// Useful for comparing %s with ethers bignumbers that dont support floating point numbers
const getDifferenceRatio = (amount1: BigNumber, amount2: BigNumber) => {
  if (amount1.lt(0) || amount2.lt(0)) throw new Error("Positive values only");
  const difference = amount1.gt(amount2)
    ? amount1.sub(amount2)
    : amount2.sub(amount1);
  return amount1.div(difference);
};

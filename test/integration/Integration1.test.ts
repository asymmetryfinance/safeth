import { AfStrategy, SafETH } from "../../typechain-types";
import { ethers, upgrades } from "hardhat";
import { expect } from "chai";
import {
  getAdminAccount,
  getUserAccounts,
  randomEthAmount,
  randomStakeUnstake,
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

  it("Should stake a random amount for each user", async function () {
    const strategy = await getLatestContract(
      strategyContractAddress,
      "AfStrategy"
    );

    const userAccounts = await getUserAccounts();

    let totalDeposited = BigNumber.from(0);

    for (let i = 0; i < userAccounts.length; i++) {
      const depositAmount = ethers.utils.parseEther(randomEthAmount(0.1, 5));
      totalDeposited = totalDeposited.add(depositAmount);
      const userStrategySigner = strategy.connect(userAccounts[i]);
      await userStrategySigner.stake({ value: depositAmount });
      await time.increase(1);
    }

    const underlyingValue = await strategy.underlyingValue();

    expect(within1Percent(underlyingValue, totalDeposited)).eq(true);
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

    const totalUserEthSentReceived = totalUserBalanceBefore
      .sub(totalUserBalanceAfter)
      .sub(networkFee);

    const underlyingValueAfter = await strategy.underlyingValue();

    const underlyingValueChange = underlyingValueAfter.sub(
      underlyingValueBefore
    );

    // higher tolerance because there are 3 trades per user in this test (more potential slippage)
    expect(within3Percent(totalUserEthSentReceived, underlyingValueChange)).eq(
      true
    );
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
      within1Percent(derivative1Value, derivative2Value.add(derivative3Value))
    ).eq(true);
    expect(within1Percent(derivative2Value, derivative3Value)).eq(true);
  });

  it("Should do random staking & unstakings for all users (2)", async function () {
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

    const totalUserEthSentReceived = totalUserBalanceBefore
      .sub(totalUserBalanceAfter)
      .sub(networkFee);

    const underlyingValueAfter = await strategy.underlyingValue();

    const underlyingValueChange = underlyingValueAfter.sub(
      underlyingValueBefore
    );

    // higher tolerance because there are 3 trades per user in this test (more potential slippage)
    expect(within3Percent(totalUserEthSentReceived, underlyingValueChange)).eq(
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

    expect(within1Percent(derivative0Value, derivative1Value)).eq(true);
    expect(within1Percent(derivative2Value, derivative3Value)).eq(true);

    expect(
      within1Percent(derivative0Value, derivative2Value.add(derivative3Value))
    ).eq(true);

    expect(
      within1Percent(derivative1Value, derivative2Value.add(derivative3Value))
    ).eq(true);
  });

  it("Should unstake everything for all users and check balances", async function () {
    // TODO finish this test and figure out why the others sometimes fail

    // const strategy = await getLatestContract(
    //   strategyContractAddress,
    //   "AfStrategy"
    // );

    // const safEth = new ethers.Contract(
    //   safEthContractAddress,
    //   afEthAbi,
    //   await getAdminAccount()
    // ) as SafETH;

    // const userAccounts = await getUserAccounts();

    // for (let i = 0; i < userAccounts.length; i++) {
    //   const withdrawAmount = await safEth.balanceOf(userAccounts[i].address);
    //   const userStrategySigner = strategy.connect(userAccounts[i]);
    //   const unstakeResult = await userStrategySigner.unstake(withdrawAmount);
    //   const mined = await unstakeResult.wait();
    // }

    // const underlyingValue = await strategy.underlyingValue();

    // console.log('underlyingValue', underlyingValue);

  });
});

const within1Percent = (amount1: BigNumber, amount2: BigNumber) => {
  if (amount1.eq(amount2)) return true;
  const difference = amount1.gt(amount2)
    ? amount1.sub(amount2)
    : amount2.sub(amount1);
  const differenceRatio = amount1.div(difference);
  return differenceRatio.gt("100");
};

const within2Percent = (amount1: BigNumber, amount2: BigNumber) => {
  if (amount1.eq(amount2)) return true;
  const difference = amount1.gt(amount2)
    ? amount1.sub(amount2)
    : amount2.sub(amount1);
  const differenceRatio = amount1.div(difference);
  return differenceRatio.gt("50");
};

const within3Percent = (amount1: BigNumber, amount2: BigNumber) => {
  if (amount1.eq(amount2)) return true;
  const difference = amount1.gt(amount2)
    ? amount1.sub(amount2)
    : amount2.sub(amount1);
  const differenceRatio = amount1.div(difference);
  return differenceRatio.gt("33");
};

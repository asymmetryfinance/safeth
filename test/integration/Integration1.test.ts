import { AfStrategy } from "../../typechain-types";
import { ethers, upgrades } from "hardhat";
import { expect } from "chai";
import {
  getAdminAccount,
  getUserAccounts,
  getUserBalances,
  randomStakes,
  randomUnstakes,
} from "./integrationHelpers";
import { getLatestContract } from "../helpers/upgradeHelpers";
import { BigNumber } from "ethers";

// These tests are intended to run in-order.
// Together they form a single integration test simulating real-world usage
describe("Integration Test 1", function () {
  let safEthContractAddress: string;
  let strategyContractAddress: string;

  let startingBalances: BigNumber[];

  // total gas fees per user account for all tests
  // To calculate slippage per account after tests are complete without fees effecting things
  let networkFeesPerAccount: BigNumber[];

  // How much was staked per account for all tests
  // To check slippage per account after tests are complete
  let totalStakedPerAccount: BigNumber[];

  before(async () => {
    startingBalances = await getUserBalances();
    networkFeesPerAccount = startingBalances.map(() => BigNumber.from(0));
    totalStakedPerAccount = startingBalances.map(() => BigNumber.from(0));
  });

  it("Should deploy the strategy contract", async function () {
    const afStrategyFactory = await ethers.getContractFactory("AfStrategy");
    const strategy = (await upgrades.deployProxy(afStrategyFactory, [
      "Asymmetry Finance ETH",
      "safETH",
    ])) as AfStrategy;
    await strategy.deployed();

    strategyContractAddress = strategy.address;

    const owner = await strategy.owner();
    const derivativeCount = await strategy.derivativeCount();
    const underlyingValue = await strategyUnderlyingValue();

    expect(owner).eq((await getAdminAccount()).address);
    expect(derivativeCount).eq("0");
    expect(underlyingValue).eq("0");
  });

  it("Should deploy derivative contracts and add them to the strategy contract with equal weights", async function () {
    const supportedDerivatives = ["Reth", "SfrxEth", "WstEth"];
    const strategy = await getLatestContract(
      strategyContractAddress,
      "AfStrategy"
    );

    for (let i = 0; i < supportedDerivatives.length; i++) {
      const derivativeFactory = await ethers.getContractFactory(
        supportedDerivatives[i]
      );
      const derivative = await upgrades.deployProxy(derivativeFactory, [
        strategyContractAddress,
      ]);
      await derivative.deployed();

      const tx1 = await strategy.addDerivative(
        derivative.address,
        "1000000000000000000"
      );
      await tx1.wait();
    }

    const derivativeCount = await strategy.derivativeCount();

    expect(derivativeCount).eq(supportedDerivatives.length);
  });

  it("Should stake a random amount 3 times for each user", async function () {
    await testRandomStakes();
  });

  it("Should unstake a random amount 3 times for each user", async function () {
    await testRandomUnstakes();
  });

  it("Should change weights and rebalance", async function () {
    const strategy = await getLatestContract(
      strategyContractAddress,
      "AfStrategy"
    );

    // set weight of derivative0 to 0 and derivative1 to 2 * 10^18
    // this is like going from 33/33/33 -> 0/66/33
    const tx1 = await strategy.adjustWeight(0, 0);
    await tx1.wait();
    const tx2 = await strategy.adjustWeight(1, "2000000000000000000");
    await tx2.wait();
    const tx3 = await strategy.rebalanceToWeights();
    await tx3.wait();

    const derivative0Value = await strategy.derivativeValue(0);
    const derivative1Value = await strategy.derivativeValue(1);
    const derivative2Value = await strategy.derivativeValue(2);

    expect(derivative0Value).eq(BigNumber.from(0));

    expect(within1Percent(derivative1Value, derivative2Value.mul(2))).eq(true);
  });

  it("Should stake a random amount 3 times for each user", async function () {
    await testRandomStakes();
  });

  it("Should unstake a random amount 3 times for each user", async function () {
    await testRandomUnstakes();
  });

  it("Should change weights and rebalance", async function () {
    const strategy = await getLatestContract(
      strategyContractAddress,
      "AfStrategy"
    );

    // set weight of derivative0 to 2 * 10^18
    // this is like going from 0/50/25/25 -> 33/33/16/16
    const tx1 = await strategy.adjustWeight(0, "2000000000000000000");
    await tx1.wait();
    const tx2 = await strategy.rebalanceToWeights();
    await tx2.wait();

    const derivative0Value = await strategy.derivativeValue(0);
    const derivative1Value = await strategy.derivativeValue(1);
    const derivative2Value = await strategy.derivativeValue(2);

    expect(within1Percent(derivative0Value, derivative1Value)).eq(true);
    expect(within1Percent(derivative0Value, derivative2Value.mul(2))).eq(true);
    expect(within1Percent(derivative1Value, derivative2Value.mul(2))).eq(true);
  });

  it("Should stake a random amount 3 times for each user", async function () {
    await testRandomStakes();
  });

  it("Should unstake a random amount 3 times for each user", async function () {
    await testRandomUnstakes();
  });

  it("Should unstake everything for all users", async function () {
    const strategy = await getLatestContract(
      strategyContractAddress,
      "AfStrategy"
    );
    const underlyingValueBefore = await strategyUnderlyingValue();
    const userAccounts = await getUserAccounts();
    let totalUnstaked = BigNumber.from(0);

    for (let i = 0; i < userAccounts.length; i++) {
      const withdrawAmount = await strategy.balanceOf(userAccounts[i].address);
      if (withdrawAmount.eq(0)) continue;
      const userStrategySigner = strategy.connect(userAccounts[i]);
      const balanceBefore = await userAccounts[i].getBalance();
      const unstakeResult = await userStrategySigner.unstake(withdrawAmount);
      const mined = await unstakeResult.wait();
      const networkFee = mined.gasUsed.mul(mined.effectiveGasPrice);
      const balanceAfter = await userAccounts[i].getBalance();
      const amountUnstaked = balanceAfter.sub(balanceBefore).add(networkFee);
      totalUnstaked = totalUnstaked.add(amountUnstaked);
    }

    const underlyingValueAfter = await strategyUnderlyingValue();

    const underlyingValueChange = underlyingValueBefore
      .sub(underlyingValueAfter)
      .abs();

    expect(within1Percent(underlyingValueChange, totalUnstaked)).eq(true);
  });

  it("Should verify slippage experienced by each user after all tests is < 1%", async () => {
    const endingBalances = await getUserBalances();

    // add fees back into the ending balances
    // So we can check slippage per user account slippage without fees having an effect
    const endingBalancesAndFees = endingBalances.map((endingBalance, i) =>
      endingBalance.add(networkFeesPerAccount[i])
    );

    const totalSlippagePerAccount = startingBalances.map((startingBalance, i) =>
      startingBalance.sub(endingBalancesAndFees[i])
    );

    for (let i = 0; i < totalStakedPerAccount.length; i++) {
      const stakedMinusSlippage = totalStakedPerAccount[i].sub(
        totalSlippagePerAccount[i]
      );
      const staked = totalStakedPerAccount[i];
      expect(within1Percent(staked, stakedMinusSlippage)).eq(true);
    }
  });

  const testRandomStakes = async () => {
    const underlyingValueBefore = await strategyUnderlyingValue();

    const totalStaked = await randomStakes(
      strategyContractAddress,
      networkFeesPerAccount,
      totalStakedPerAccount
    );

    const underlyingValueAfter = await strategyUnderlyingValue();

    const underlyingValueChange = underlyingValueAfter.sub(
      underlyingValueBefore
    );
    expect(within1Percent(underlyingValueChange, totalStaked)).eq(true);
  };

  const testRandomUnstakes = async () => {
    const underlyingValueBefore = await strategyUnderlyingValue();
    const totalUnstaked = await randomUnstakes(
      strategyContractAddress,
      safEthContractAddress,
      networkFeesPerAccount
    );
    const underlyingValueAfter = await strategyUnderlyingValue();
    const underlyingValueChange = underlyingValueAfter.sub(
      underlyingValueBefore
    );
    expect(within1Percent(underlyingValueChange.mul(-1), totalUnstaked)).eq(
      true
    );
  };

  // Underlying value of all derivatives in the strategy contract
  const strategyUnderlyingValue = async () => {
    const strategy = await getLatestContract(
      strategyContractAddress,
      "AfStrategy"
    );

    const derivativeCount = await strategy.derivativeCount();

    let derivativeValue = BigNumber.from(0);

    for (let i = 0; i < derivativeCount; i++) {
      derivativeValue = derivativeValue.add(await strategy.derivativeValue(i));
    }

    return derivativeValue;
  };
});

const within1Percent = (amount1: BigNumber, amount2: BigNumber) => {
  if (amount1.eq(amount2)) return true;
  return getDifferenceRatio(amount1, amount2).gt("100");
};

// Get ratio between 2 amounts such that % diff = 1/ratio
// Example: 200 = 0.5%, 100 = 1%, 50 = 2%, 25 = 4%, etc
// Useful for comparing ethers bignumbers that dont support floating point numbers
const getDifferenceRatio = (amount1: BigNumber, amount2: BigNumber) => {
  if (amount1.lt(0) || amount2.lt(0)) throw new Error("Positive values only");
  const difference = amount1.gt(amount2)
    ? amount1.sub(amount2)
    : amount2.sub(amount1);
  return amount1.div(difference);
};

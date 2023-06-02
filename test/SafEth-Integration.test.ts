import { SafEth } from "../typechain-types";
import { ethers, network, upgrades } from "hardhat";
import { expect } from "chai";
import {
  getAdminAccount,
  getUserAccounts,
  getUserBalances,
  randomStakes,
  randomUnstakes,
} from "./helpers/integrationHelpers";
import {
  getLatestContract,
  supportedDerivatives,
} from "./helpers/upgradeHelpers";
import { BigNumber } from "ethers";
import { within1Percent } from "./helpers/functions";
import { derivativeAbi } from "./abi/derivativeAbi";

// These tests are intended to run in-order.
// Together they form a single integration test simulating real-world usage
describe("SafEth Integration Test", function () {
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
    await network.provider.request({
      method: "hardhat_reset",
      params: [
        {
          forking: {
            jsonRpcUrl: process.env.MAINNET_URL,
            blockNumber: Number(process.env.BLOCK_NUMBER),
          },
        },
      ],
    });
  });

  it("Should deploy the strategy contract", async function () {
    const safEthFactory = await ethers.getContractFactory("SafEth");
    const strategy = (await upgrades.deployProxy(safEthFactory, [
      "Asymmetry Finance ETH",
      "safETH",
    ])) as SafEth;
    await strategy.deployed();

    strategyContractAddress = strategy.address;

    const owner = await strategy.owner();
    const derivativeCount = await strategy.derivativeCount();

    expect(owner).eq((await getAdminAccount()).address);
    expect(derivativeCount).eq("0");
  });

  it("Should deploy derivative contracts and add them to the strategy contract with equal weights", async function () {
    const strategy = await getLatestContract(strategyContractAddress, "SafEth");

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
    await strategy.setPauseStaking(false);

    // ankr slippage tolerance needs to be set high for the integration test
    // withdraws are affecting the pool but price is oraclePrice that doesnt change
    // so with enough tests slippage becomes high because there is no arb happening
    const t = await strategy.setMaxSlippage(3, "30000000000000000"); // 3% slippage
    await t.wait();

    expect(derivativeCount).eq(supportedDerivatives.length);
  });

  it("Should stake a random amount 3 times for each user", async function () {
    await randomStakes(
      strategyContractAddress,
      networkFeesPerAccount,
      totalStakedPerAccount
    );
  });

  it("Should unstake a random amount 3 times for each user", async function () {
    await randomUnstakes(
      strategyContractAddress,
      safEthContractAddress,
      networkFeesPerAccount
    );
  });

  it("Should change weights and rebalance", async function () {
    const strategy = await getLatestContract(strategyContractAddress, "SafEth");

    // set weight of derivative0 to 0 and derivative1 to 2 * 10^18
    // this is like going from 33/33/33 -> 0/66/33
    const tx1 = await strategy.adjustWeight(0, 0);
    await tx1.wait();
    const tx2 = await strategy.adjustWeight(1, "2000000000000000000");
    await tx2.wait();
    await rebalanceToWeights(strategy as SafEth);
  });

  it("Should stake a random amount 3 times for each user", async function () {
    await randomStakes(
      strategyContractAddress,
      networkFeesPerAccount,
      totalStakedPerAccount
    );
  });

  it("Should unstake a random amount 3 times for each user", async function () {
    await randomUnstakes(
      strategyContractAddress,
      safEthContractAddress,
      networkFeesPerAccount
    );
  });

  it("Should change weights and rebalance", async function () {
    const strategy = await getLatestContract(strategyContractAddress, "SafEth");

    // set weight of derivative0 to 2 * 10^18
    // this is like going from 0/66/33 -> 40/40/20
    const tx1 = await strategy.adjustWeight(0, "2000000000000000000");
    await tx1.wait();
    await rebalanceToWeights(strategy as SafEth);
  });

  it("Should stake a random amount 3 times for each user", async function () {
    await randomStakes(
      strategyContractAddress,
      networkFeesPerAccount,
      totalStakedPerAccount
    );
  });

  it("Should unstake a random amount 3 times for each user", async function () {
    await randomUnstakes(
      strategyContractAddress,
      safEthContractAddress,
      networkFeesPerAccount
    );
  });

  it("Should unstake everything for all users", async function () {
    const strategy = await getLatestContract(strategyContractAddress, "SafEth");
    const userAccounts = await getUserAccounts();

    for (let i = 0; i < userAccounts.length; i++) {
      const withdrawAmount = await strategy.balanceOf(userAccounts[i].address);
      if (withdrawAmount.eq(0)) continue;
      const userStrategySigner = strategy.connect(userAccounts[i]);
      const unstakeResult = await userStrategySigner.unstake(withdrawAmount, 0);
      const mined = await unstakeResult.wait();
      const networkFee = mined.gasUsed.mul(mined.effectiveGasPrice);
      networkFeesPerAccount[i] = networkFeesPerAccount[i].add(networkFee);
    }
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

  // function to show safEth.derivativeRebalance() can do everything safEth.rebalanceToWeights() does
  const rebalanceToWeights = async (safEthProxy: SafEth) => {
    const adminAccount = await getAdminAccount();

    const derivativeCount = (await safEthProxy.derivativeCount()).toNumber();
    // first sell them all into derivative0
    for (let i = 1; i < derivativeCount; i++) {
      const derivativeAddress = (await safEthProxy.derivatives(i)).derivative;
      const derivative = new ethers.Contract(
        derivativeAddress,
        derivativeAbi,
        adminAccount
      );
      const derivativeBalance = await derivative.balance();
      await safEthProxy.derivativeRebalance(i, 0, derivativeBalance);
    }

    const derivative0Address = (await safEthProxy.derivatives(0)).derivative;
    const derivative0 = new ethers.Contract(
      derivative0Address,
      derivativeAbi,
      adminAccount
    );
    const derivative0StartingBalance = await derivative0.balance();
    const totalWeight = await safEthProxy.totalWeight();
    // then rebalance to weights
    for (let i = 1; i < derivativeCount; i++) {
      const derivativeInfo = await safEthProxy.derivatives(i);
      const weight = derivativeInfo.weight;
      const derivative0SellAmount = derivative0StartingBalance
        .mul(weight)
        .div(totalWeight);
      await safEthProxy.derivativeRebalance(0, i, derivative0SellAmount);
    }
  };
});

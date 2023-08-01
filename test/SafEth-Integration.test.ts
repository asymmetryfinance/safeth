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
import { withinHalfPercent } from "./helpers/functions";
import { derivativeAbi } from "./abi/derivativeAbi";
import { MULTI_SIG } from "./helpers/constants";

// These tests are intended to run in-order.
// Together they form a single integration test simulating real-world usage
describe.skip("SafEth Integration Test", function () {
  let safEthAddress: string;
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

  it("Should deploy the safEth contract", async function () {
    const safEthFactory = await ethers.getContractFactory("SafEth");
    const safEth = (await upgrades.deployProxy(safEthFactory, [
      "Asymmetry Finance ETH",
      "safETH",
    ])) as SafEth;
    await safEth.deployed();

    safEthAddress = safEth.address;

    const owner = await safEth.owner();
    const derivativeCount = await safEth.derivativeCount();

    expect(owner).eq((await getAdminAccount()).address);
    expect(derivativeCount).eq("0");
  });

  it("Should deploy derivative contracts and add them to the safEth contract with equal weights", async function () {
    const safEth = await getLatestContract(safEthAddress, "SafEth");

    for (let i = 0; i < supportedDerivatives.length; i++) {
      const derivativeFactory = await ethers.getContractFactory(
        supportedDerivatives[i]
      );
      const derivative = await upgrades.deployProxy(derivativeFactory, [
        safEthAddress,
      ]);
      await derivative.deployed();

      const tx1 = await safEth.addDerivative(
        derivative.address,
        "1000000000000000000"
      );
      await tx1.wait();
    }

    const derivativeCount = await safEth.derivativeCount();
    await safEth.setPauseStaking(false);

    // ankr slippage tolerance needs to be set high for the integration test
    // withdraws are affecting the pool but price is oraclePrice that doesnt change
    // so with enough tests slippage becomes high because there is no arb happening
    const ankrDerivativeIndex = supportedDerivatives.indexOf("Ankr");
    const ankrDerivativeAddress = (
      await safEth.derivatives(ankrDerivativeIndex)
    ).derivative;
    const ankrDerivative = await getLatestContract(
      ankrDerivativeAddress,
      "Ankr"
    );
    await ankrDerivative.initializeV2();
    const signers = await ethers.getSigners();
    await signers[0].sendTransaction({
      to: MULTI_SIG,
      value: "1000000000000000000000",
    });
    await network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [MULTI_SIG],
    });

    const multiSigSigner = await ethers.getSigner(MULTI_SIG);
    const ankrMultiSig = ankrDerivative.connect(multiSigSigner);

    const t = await ankrMultiSig.setMaxSlippage("30000000000000000"); // 2% slippage
    await t.wait();
    expect(derivativeCount).eq(supportedDerivatives.length);
  });

  it("Should stake a random amount 3 times for each user", async function () {
    await randomStakes(
      safEthAddress,
      networkFeesPerAccount,
      totalStakedPerAccount
    );
  });

  it("Should unstake a random amount 3 times for each user", async function () {
    await randomUnstakes(safEthAddress, networkFeesPerAccount);
  });

  it("Should change weights and rebalance", async function () {
    const safEth = await getLatestContract(safEthAddress, "SafEth");

    // set weight of derivative0 to 0 and derivative1 to 2
    const tx1 = await safEth.adjustWeight(0, 0);
    await tx1.wait();
    const tx2 = await safEth.adjustWeight(1, "2000000000000000000");
    await tx2.wait();
    await rebalanceToWeights(safEth as SafEth);
  });

  it("Should stake a random amount 3 times for each user", async function () {
    await randomStakes(
      safEthAddress,
      networkFeesPerAccount,
      totalStakedPerAccount
    );
  });

  it("Should unstake a random amount 3 times for each user", async function () {
    await randomUnstakes(safEthAddress, networkFeesPerAccount);
  });

  it("Should change weights and rebalance", async function () {
    const safEth = await getLatestContract(safEthAddress, "SafEth");

    // set weight of derivative0 to 2
    const tx1 = await safEth.adjustWeight(0, "2000000000000000000");
    await tx1.wait();
    await rebalanceToWeights(safEth as SafEth);
  });

  it("Should stake a random amount 3 times for each user", async function () {
    await randomStakes(
      safEthAddress,
      networkFeesPerAccount,
      totalStakedPerAccount
    );
  });

  it("Should unstake a random amount 3 times for each user", async function () {
    await randomUnstakes(safEthAddress, networkFeesPerAccount);
  });

  it("Should unstake everything for all users", async function () {
    const safEth = await getLatestContract(safEthAddress, "SafEth");
    const userAccounts = await getUserAccounts();

    for (let i = 0; i < userAccounts.length; i++) {
      const withdrawAmount = await safEth.balanceOf(userAccounts[i].address);
      if (withdrawAmount.eq(0)) continue;
      const userSafEthSigner = safEth.connect(userAccounts[i]);
      const unstakeResult = await userSafEthSigner.unstake(withdrawAmount, 0);
      const mined = await unstakeResult.wait();
      const networkFee = mined.gasUsed.mul(mined.effectiveGasPrice);
      networkFeesPerAccount[i] = networkFeesPerAccount[i].add(networkFee);
    }
  });

  it("Should verify slippage experienced by each user after all tests is < 0.5%", async () => {
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

      expect(withinHalfPercent(staked, stakedMinusSlippage)).eq(true);
    }
  });

  // function to show safEth.derivativeRebalance() can do everything safEth.rebalanceToWeights() does
  const rebalanceToWeights = async (safEth: SafEth) => {
    const adminAccount = await getAdminAccount();

    const derivativeCount = (await safEth.derivativeCount()).toNumber();
    // first sell them all into derivative0
    for (let i = 1; i < derivativeCount; i++) {
      const derivativeAddress = (await safEth.derivatives(i)).derivative;
      const derivative = new ethers.Contract(
        derivativeAddress,
        derivativeAbi,
        adminAccount
      );
      const derivativeBalance = await derivative.balance();
      await safEth.derivativeRebalance(i, 0, derivativeBalance);
    }

    const derivative0Address = (await safEth.derivatives(0)).derivative;
    const derivative0 = new ethers.Contract(
      derivative0Address,
      derivativeAbi,
      adminAccount
    );
    const derivative0StartingBalance = await derivative0.balance();
    const totalWeight = await safEth.totalWeight();
    // then rebalance to weights
    for (let i = 1; i < derivativeCount; i++) {
      const derivativeInfo = await safEth.derivatives(i);
      const weight = derivativeInfo.weight;
      const derivative0SellAmount = derivative0StartingBalance
        .mul(weight)
        .div(totalWeight);
      await safEth.derivativeRebalance(0, i, derivative0SellAmount);
    }
  };
});

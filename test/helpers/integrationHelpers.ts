import { BigNumber } from "ethers";
import { ethers } from "hardhat";
import { getLatestContract } from "./upgradeHelpers";
import { expect } from "chai";

let randomSeed = 2;
export const stakeMinimum = 0.5;
export const stakeMaximum = 5;

export const getAdminAccount = async () => {
  const accounts = await ethers.getSigners();
  return accounts[0];
};
export const getUserAccounts = async () => {
  const accounts = await ethers.getSigners();
  return accounts.slice(1, accounts.length);
};

export const randomEthAmount = (min: number, max: number) => {
  return (min + deterministicRandom() * (max - min)).toFixed(18);
};

// For deterministic (seeded) random values in tests
const deterministicRandom = () => {
  const x = Math.sin(randomSeed++) * 10000;
  return x - Math.floor(x);
};

export const getUserBalances = async () => {
  const accounts = await getUserAccounts();
  const balances = [];
  for (let i = 0; i < accounts.length; i++) {
    balances.push(await accounts[i].getBalance());
  }
  return balances;
};

export const totalUserBalances = async () => {
  const userAccounts = await getUserAccounts();
  let total = BigNumber.from(0);
  for (let i = 0; i < userAccounts.length; i++) {
    total = total.add(BigNumber.from(await userAccounts[i].getBalance()));
  }
  return total;
};

// randomly stake random amount for all users
export const randomStakes = async (
  safEthAddress: string,
  networkFeesPerAccount: BigNumber[],
  totalStakedPerAccount: BigNumber[]
) => {
  const safEth = await getLatestContract(safEthAddress, "SafEth");

  const userAccounts = await getUserAccounts();

  let totalStaked = BigNumber.from(0);

  for (let i = 0; i < userAccounts.length; i++) {
    const userSafEthSigner = safEth.connect(userAccounts[i]);
    for (let j = 0; j < 3; j++) {
      const ethAmount = randomEthAmount(stakeMinimum, stakeMaximum);
      const depositAmount = ethers.utils.parseEther(ethAmount);
      totalStaked = totalStaked.add(depositAmount);
      // console.log("staking ", userAccounts[i].address, depositAmount);
      const stakeResult = await userSafEthSigner.stake(0, {
        value: depositAmount,
      });
      const mined = await stakeResult.wait();
      const networkFee = mined.gasUsed.mul(mined.effectiveGasPrice);
      networkFeesPerAccount[i] = networkFeesPerAccount[i].add(networkFee);
      totalStakedPerAccount[i] = totalStakedPerAccount[i].add(depositAmount);
    }
  }
  const contractEthBalance = await ethers.provider.getBalance(safEthAddress);
  expect(contractEthBalance).eq(0);
  return totalStaked;
};

// randomly unstake random amount for all users
export const randomUnstakes = async (
  safEthAddress: string,
  networkFeesPerAccount: BigNumber[]
) => {
  const safth = await getLatestContract(safEthAddress, "SafEth");

  const userAccounts = await getUserAccounts();

  let totalUnstaked = BigNumber.from(0);

  for (let i = 0; i < userAccounts.length; i++) {
    const userSafEthSigner = safth.connect(userAccounts[i]);
    for (let j = 0; j < 3; j++) {
      const safEthBalanceWei = await safth.balanceOf(userAccounts[i].address);
      const safEthBalance = ethers.utils.formatEther(safEthBalanceWei);
      // withdraw a random portion of their balance
      const withdrawAmount = ethers.utils.parseEther(
        randomEthAmount(0, parseFloat(safEthBalance))
      );
      const balanceBefore = await userAccounts[i].getBalance();
      const unstakeResult = await userSafEthSigner.unstake(withdrawAmount, 0);
      const mined = await unstakeResult.wait();
      const networkFee = mined.gasUsed.mul(mined.effectiveGasPrice);
      networkFeesPerAccount[i] = networkFeesPerAccount[i].add(networkFee);
      const balanceAfter = await userAccounts[i].getBalance();
      const amountUnstaked = balanceAfter.sub(balanceBefore).add(networkFee);
      totalUnstaked = totalUnstaked.add(amountUnstaked);
      // console.log("unstaked ", userAccounts[i].address, amountUnstaked);
    }
  }
  const contractEthBalance = await ethers.provider.getBalance(safEthAddress);
  expect(contractEthBalance).eq(0);
  return totalUnstaked;
};

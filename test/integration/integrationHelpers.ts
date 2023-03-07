import { BigNumber } from "ethers";
import { ethers } from "hardhat";
import { getLatestContract } from "../../helpers/upgradeHelpers";
import { SafETH } from "../../typechain-types";
import { afEthAbi } from "../abi/afEthAbi";

export const stakeMinimum = 0.1;
export const stakeMaximum = 3;

export const stakeLargeAmount = 5;

export const getAdminAccount = async () => {
  const accounts = await ethers.getSigners();
  return accounts[0];
};
export const getUserAccounts = async () => {
  const accounts = await ethers.getSigners();
  return accounts.slice(1, accounts.length);
};

export const randomEthAmount = (min: number, max: number) => {
  return (min + Math.random() * (max - min)).toString();
};

export const randomBnInRange = (min: BigNumber, max: BigNumber) => {
  return ethers.BigNumber.from(min).add(
    ethers.BigNumber.from(ethers.utils.randomBytes(32)).mod(max.sub(min))
  );
};

export const getUserBalances = async () => {
  const accounts = await getUserAccounts();
  const balances = [];
  for (let i = 0; i < accounts.length; i++) {
    balances.push(await accounts[i].getBalance());
  }
};

export const totalUserBalances = async () => {
  const userAccounts = await getUserAccounts();
  let total = BigNumber.from(0);
  for (let i = 0; i < userAccounts.length; i++) {
    total = total.add(BigNumber.from(await userAccounts[i].getBalance()));
  }
  return total;
};

// randomly either stakes a random amount or unstake half their balance
// assumes user has some staked balance already for unstakes to work
export const randomStakeUnstake = async (
  strategyContractAddress: string,
  safEthContractAddress: string
) => {
  const strategy = await getLatestContract(
    strategyContractAddress,
    "AfStrategy"
  );

  const safEth = new ethers.Contract(
    safEthContractAddress,
    afEthAbi,
    await getAdminAccount()
  ) as SafETH;

  const userAccounts = await getUserAccounts();

  let totalNetworkFee = BigNumber.from(0);
  for (let i = 0; i < userAccounts.length; i++) {
    const userStrategySigner = strategy.connect(userAccounts[i]);
    for (let j = 0; j < 3; j++) {
      const doStake = Math.random() > 0.5;
      if (doStake) {
        const ethAmount = randomEthAmount(stakeMinimum, stakeMaximum);
        const depositAmount = ethers.utils.parseEther(ethAmount);
        console.log("depositing ", userAccounts[i].address, depositAmount);
        const stakeResult = await userStrategySigner.stake({
          value: depositAmount,
        });
        const mined = await stakeResult.wait();
        totalNetworkFee = totalNetworkFee.add(
          mined.gasUsed.mul(mined.effectiveGasPrice)
        );
      } else {
        const safEthBalance = await safEth.balanceOf(userAccounts[i].address);
        const withdrawAmount = safEthBalance.div(4);
        console.log("withdrawing ", userAccounts[i].address, withdrawAmount);
        const unstakeResult = await userStrategySigner.unstake(withdrawAmount);
        const mined = await unstakeResult.wait();
        totalNetworkFee = totalNetworkFee.add(
          mined.gasUsed.mul(mined.effectiveGasPrice)
        );
      }
    }
  }
  return totalNetworkFee;
};

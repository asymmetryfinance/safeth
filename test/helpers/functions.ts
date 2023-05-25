import { BigNumber } from "ethers";
import { SafEth } from "../../typechain-types";
import { ethers } from "hardhat";
import { derivativeAbi } from "../abi/derivativeAbi";

export const within1Percent = (amount1: BigNumber, amount2: BigNumber) => {
  if (amount1.eq(amount2)) return true;
  return getDifferenceRatio(amount1, amount2).gt("100");
};

// Get ratio between 2 amounts such that % diff = 1/ratio
// Example: 200 = 0.5%, 100 = 1%, 50 = 2%, 25 = 4%, etc
// Useful for comparing ethers bignumbers that dont support floating point numbers
export const getDifferenceRatio = (amount1: BigNumber, amount2: BigNumber) => {
  if (amount1.lt(0) || amount2.lt(0)) throw new Error("Positive values only");
  const difference = amount1.gt(amount2)
    ? amount1.sub(amount2)
    : amount2.sub(amount1);
  return amount1.div(difference);
};

export const rebalanceToWeights = async (safEth: SafEth) => {
  const accounts = await ethers.getSigners();
  const derivativeCount = await safEth.derivativeCount();
  const adminAccount = accounts[0];
  for (let i = 0; i < derivativeCount.toNumber(); i++) {
    const derivativeAddress = (await safEth.derivatives(i)).derivative;
    const derivative = new ethers.Contract(
      derivativeAddress,
      derivativeAbi,
      adminAccount
    );
      const balance = await derivative.balance();
      if (balance > 0) await safEth.derivativeWithdraw(i, balance);
  }

  const ethAmountToRebalance = address(this).balance;
  require(ethAmountToRebalance > 0, "no eth to rebalance");

  for (uint256 i = 0; i < count; i++) {
      if (derivatives[i].weight == 0 || !derivatives[i].enabled) continue;
      uint256 ethAmount = (ethAmountToRebalance * derivatives[i].weight) /
          totalWeight;
      // Price will change due to slippage
      derivatives[i].derivative.deposit{value: ethAmount}();
  }
  emit Rebalanced();
};
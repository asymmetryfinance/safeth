import { BigNumber, Contract } from "ethers";
import { ethers, network } from "hardhat";
import { MULTI_SIG } from "./constants";

export const within1Percent = (amount1: BigNumber, amount2: BigNumber) => {
  if (amount1.eq(amount2)) return true;
  return getDifferenceRatio(amount1, amount2).gt("100");
};
export const withinHalfPercent = (amount1: BigNumber, amount2: BigNumber) => {
  if (amount1.eq(amount2)) return true;
  return getDifferenceRatio(amount1, amount2).gt("200");
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

export const setMaxSlippage = async (
  derivative: Contract,
  amount: BigNumber
) => {
  await network.provider.request({
    method: "hardhat_impersonateAccount",
    params: [MULTI_SIG],
  });

  const multiSigSigner = await ethers.getSigner(MULTI_SIG);
  const multiSig = derivative.connect(multiSigSigner);

  const t = await multiSig.setMaxSlippage(amount);
  t.wait();
};

export const within1Pip = (amount1: BigNumber, amount2: BigNumber) => {
  if (amount1.eq(amount2)) return true;
  return getDifferenceRatio(amount1, amount2).gt("10000");
};

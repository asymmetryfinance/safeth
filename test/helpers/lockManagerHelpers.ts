import { ethers } from "hardhat";
import { VL_CVX } from "./constants";
import { vlCvxAbi } from "../abi/vlCvxAbi";
import { BigNumber } from "ethers";

export const getCurrentEpoch = async () => {
  const accounts = await ethers.getSigners();
  const vlCvxContract = new ethers.Contract(VL_CVX, vlCvxAbi, accounts[0]);
  return vlCvxContract.findEpochId(await getCurrentBlockTime());
};

export const getCurrentEpochStartTime = async () => {
  const currentEpoch = await getCurrentEpoch();
  const accounts = await ethers.getSigners();
  const vlCvxContract = new ethers.Contract(VL_CVX, vlCvxAbi, accounts[0]);
  return BigNumber.from((await vlCvxContract.epochs(currentEpoch)).date);
};

export const getCurrentEpochEndTime = async () => {
  const currentEpoch = await getCurrentEpoch();
  const accounts = await ethers.getSigners();
  const vlCvxContract = new ethers.Contract(VL_CVX, vlCvxAbi, accounts[0]);
  return BigNumber.from((await vlCvxContract.epochs(currentEpoch)).date).add(
    epochDuration
  );
};

export const getCurrentBlockTime = async () => {
  const currentBlock = await ethers.provider.getBlock("latest");
  return currentBlock.timestamp;
};

export const epochDuration = 60 * 60 * 24 * 7;

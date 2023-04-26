import { ethers } from "hardhat";
import { VL_CVX } from "./constants";
import { vlCvxAbi } from "../abi/vlCvxAbi";

export const getCurrentEpoch = async () => {
  const accounts = await ethers.getSigners();
  const vlCvxContract = new ethers.Contract(VL_CVX, vlCvxAbi, accounts[0]);
  const currentBlock = await ethers.provider.getBlock("latest");
  const currentBlockTime = currentBlock.timestamp;
  return vlCvxContract.findEpochId(currentBlockTime);
};

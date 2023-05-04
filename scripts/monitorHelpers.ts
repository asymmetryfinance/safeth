import { WebhookClient } from "discord.js";
import { BigNumber } from "ethers";
import hre, { ethers } from "hardhat";
import { chainlinkFeedAbi } from "../test/abi/chainlinkFeedAbi";
import { wstEthAbi } from "../test/abi/WstEthAbi";

const webhookClient = new WebhookClient({
  id: process.env.MONITOR_WEBHOOK_ID ?? "",
  token: process.env.MONITOR_WEBHOOK_TOKEN ?? "",
});

const previousPriceData: Record<string, BigNumber> = {};

let previousTotalSupply = BigNumber.from(0);

export const notifyOnStakeUnstake = async () => {
  const safEth = await ethers.getContractAt(
    "SafEth",
    "0xC57319e15d5D78Ba73c08C4E09d320705Bd4478D"
  );
  await safEth.deployed();

  const newTotalSupply = await safEth.totalSupply();

  console.log("newTotalSupply is", newTotalSupply);
  console.log("previousTotalSupply is", previousTotalSupply);
  if (!previousTotalSupply.eq(newTotalSupply)) {
    if (newTotalSupply.gt(previousTotalSupply)) {
      const events = await safEth.queryFilter("Staked", 0, "latest");
      const latestEvent = events[events.length - 1];
      notify(`Stake Event`);
      notify(`https://etherscan.io/tx/${latestEvent.transactionHash}`);
    } else if (newTotalSupply.lt(previousTotalSupply)) {
      const events = await safEth.queryFilter("Unstaked", 0, "latest");
      const latestEvent = events[events.length - 1];
      notify(`Unstake Event`);
      notify(`https://etherscan.io/tx/${latestEvent.transactionHash}`);
    }
    notify(`Total Supply: ${ethers.utils.formatEther(newTotalSupply)} safETH`);
  }
  previousTotalSupply = newTotalSupply;
};

export const notifyOnPriceDrop = async (
  priceData: Record<string, BigNumber>
) => {
  const keys = Object.keys(priceData);
  for (let i = 0; i < keys.length; i++) {
    const key = keys[i];
    const value = priceData[key];
    const previousValue = previousPriceData
      ? previousPriceData[key]
      : undefined;
    if (previousValue?.gt(value)) {
      notify(
        `${key} dropped from ${previousValue} to ${value} @ block ${await hre.ethers.provider.getBlockNumber()}`
      );
    }
    previousPriceData[key] = value;
  }
};

export const getContracts = async () => {
  const safEth = await ethers.getContractAt(
    "SafEth",
    "0xC57319e15d5D78Ba73c08C4E09d320705Bd4478D"
  );
  const wstEthDerivative = await ethers.getContractAt(
    "WstEth",
    "0x1533eDbe274AA1B9fB5dB2652D6d143e939B306f"
  );
  const rethDerivative = await ethers.getContractAt(
    "Reth",
    "0x8D5dD29592bf3bD5DC98Eb6c0E895fEa4Bd890D0"
  );
  const sfrxEthDerivative = await ethers.getContractAt(
    "SfrxEth",
    "0x1eD84a676f3ba626389cB131e7c1bc32935bbA37"
  );

  const chainLinkStEthEthFeed = new ethers.Contract(
    "0x86392dC19c0b719886221c78AB11eb8Cf5c52812",
    chainlinkFeedAbi,
    ethers.provider
  );

  const wstEth = new ethers.Contract(
    "0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0",
    wstEthAbi,
    ethers.provider
  );

  return {
    safEth,
    wstEthDerivative,
    rethDerivative,
    sfrxEthDerivative,
    chainLinkStEthEthFeed,
    wstEth,
  };
};

const notify = async (message: string) => {
  console.log(message);
  webhookClient.send(message);
};

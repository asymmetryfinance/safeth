import { WebhookClient } from "discord.js";
import { BigNumber } from "ethers";
import hre, { ethers } from "hardhat";
import { chainlinkFeedAbi } from "../test/abi/chainlinkFeedAbi";
import { wstEthAbi } from "../test/abi/WstEthAbi";

const webhookClientPrice = new WebhookClient({
  id: process.env.MONITOR_WEBHOOK_ID ?? "",
  token: process.env.MONITOR_WEBHOOK_TOKEN ?? "",
});

const webhookClientEvent = new WebhookClient({
  id: process.env.MONITOR_WEBHOOK_ID_EVENT ?? "",
  token: process.env.MONITOR_WEBHOOK_TOKEN_EVENT ?? "",
});

const previousPriceData: Record<string, BigNumber> = {};

let previousTotalSupply = BigNumber.from(0);
const failedTransactions: string[] = [];

export const notifyOnStakeUnstake = async () => {
  const safEth = await ethers.getContractAt(
    "SafEth",
    "0x6732Efaf6f39926346BeF8b821a04B6361C4F3e5"
  );
  await safEth.deployed();

  const newTotalSupply = await safEth.totalSupply();

  if (!previousTotalSupply.eq(newTotalSupply) && previousTotalSupply.gt(0)) {
    console.log("newTotalSupply is", newTotalSupply);
    console.log("previousTotalSupply is", previousTotalSupply);
    if (newTotalSupply.gt(previousTotalSupply)) {
      const events = await safEth.queryFilter("Staked", 0, "latest");
      const latestEvent = events[events.length - 1];
      notifyEventChannel(`**Stake Event**  :chart:`);
      notifyEventChannel(`${latestEvent.args.recipient}`);
      notifyEventChannel(
        `${ethers.utils.formatEther(
          newTotalSupply.sub(previousTotalSupply)
        )} safETH`
      );
    } else if (newTotalSupply.lt(previousTotalSupply)) {
      const events = await safEth.queryFilter("Unstaked", 0, "latest");
      const latestEvent = events[events.length - 1];
      notifyEventChannel(`**Unstake Event**  :chart_with_downwards_trend:`);
      notifyEventChannel(`${latestEvent.args.recipient}`);
      notifyEventChannel(
        `${ethers.utils.formatEther(
          newTotalSupply.sub(previousTotalSupply)
        )} safETH`
      );
    }
    notifyEventChannel(
      `${ethers.utils.formatEther(newTotalSupply)} safETH (New Total Supply)`
    );
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
      notifyPriceChannel(
        `**${key}** dropped from **${previousValue}** to **${value}** @ block ${await hre.ethers.provider.getBlockNumber()}`
      );
    }
    previousPriceData[key] = value;
  }
};

export const notfiyOnFailedTx = async (
  lastBlockCheckedForFailedTx: number
): Promise<number> => {
  const { safEth } = await getContracts();
  const etherscanProvider = new ethers.providers.EtherscanProvider(
    "homestead",
    process.env.ETHERSCAN_API_KEY
  );
  const currentBlock = await etherscanProvider.getBlockNumber();
  return etherscanProvider
    .getHistory(safEth.address, lastBlockCheckedForFailedTx, currentBlock)
    .then(async (history) => {
      history.forEach(async (tx) => {
        try {
          const receipt = await etherscanProvider.getTransactionReceipt(
            tx.hash
          );
          if (receipt.status === 0) {
            if (!failedTransactions.includes(tx.hash)) {
              failedTransactions.push(tx.hash);
              notifyEventChannel(`**Failed Transaction Detected** :warning:`);
              notifyEventChannel(tx.hash);
              notifyEventChannel("@here");
            }
          }
        } catch (error) {
          console.log("Failed to get receipt data: ", error);
          return lastBlockCheckedForFailedTx;
        }
      });
      return currentBlock;
    });
};

export const getContracts = async () => {
  const safEth = await ethers.getContractAt(
    "SafEth",
    "0x6732Efaf6f39926346BeF8b821a04B6361C4F3e5"
  );
  const wstEthDerivative = await ethers.getContractAt(
    "WstEth",
    "0x972A53e3A9114f61b98921Fb5B86C517e8F23Fad"
  );
  const rethDerivative = await ethers.getContractAt(
    "Reth",
    "0x7B6633c0cD81dC338688A528c0A3f346561F5cA3"
  );
  const sfrxEthDerivative = await ethers.getContractAt(
    "SfrxEth",
    "0x36Ce17a5c81E74dC111547f5DFFbf40b8BF6B20A"
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

const notifyPriceChannel = async (message: string) => {
  console.log(message);
  webhookClientPrice.send(message);
};

const notifyEventChannel = async (message: string) => {
  console.log(message);
  webhookClientEvent.send(message);
};

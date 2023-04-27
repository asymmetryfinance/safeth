import { WebhookClient } from "discord.js";
import { BigNumber } from "ethers";
import { ethers } from "hardhat";
import { chainlinkFeedAbi } from "../test/abi/chainlinkFeedAbi";
import { wstEthAbi } from "../test/abi/WstEthAbi";

const webhookClient = new WebhookClient({
  id: "1100096574140448858",
  token: "iA4trJu9OlcNyn3SslgUmHH0mVrd9xjozqXUDlMkhJKXHeE-uA0Nmq2Ej_j__UWtXfdA",
});

const previousPriceData: Record<string, BigNumber> = {};

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
      const message = `${key} dropped from ${previousValue} to ${value}`;
      console.log(message);
      webhookClient.send(message);
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

import { WebhookClient } from "discord.js";
import { BigNumber } from "ethers";
import { ethers } from "hardhat";
import { chainlinkFeedAbi } from "../test/abi/chainlinkFeedAbi";

async function main() {
  const webhookClient = new WebhookClient({
    id: "1100096574140448858",
    token:
      "iA4trJu9OlcNyn3SslgUmHH0mVrd9xjozqXUDlMkhJKXHeE-uA0Nmq2Ej_j__UWtXfdA",
  });

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
  const chainLinkStEthEthFeed = await ethers.getContractAt(
    "asdfdf",
    "0x86392dC19c0b719886221c78AB11eb8Cf5c52812"
  );

  console.log("Monitoring For Changes");

  let previousData: Record<string, string>;

  const notifyChange = (message: string) => {
    console.log(message);
//    webhookClient.send(message);
  };

  const checkForPriceDrop = async (data: Record<string, string>) => {
    console.log(
      "checkForChange",
      data,
      previousData,
      await ethers.provider.getBlockNumber()
    );
    const keys = Object.keys(data);
    for (let i = 0; i < keys.length; i++) {
      const key = keys[i];
      const value = data[key];
      const previousValue = previousData ? previousData[key] : undefined;
      if (BigNumber.from(previousValue).gt(value))
        notifyChange(`${key} changed from ${previousValue} to ${value}`);
    }
    previousData = { ...data };
  };

  while (true) {
    const safEthPrice = await safEth.approxPrice();
    const wstEthPrice = await wstEthDerivative.ethPerDerivative();
    const rethPrice = await rethDerivative.ethPerDerivative();
    const sfrxEthPrice = await sfrxEthDerivative.ethPerDerivative();
    const stEthEthPrice = await chainLinkStEthEthFeed.latestRoundData();

    console.log('stEthEthPrice', stEthEthPrice.toString());
    checkForPriceDrop({
      safEthPrice: safEthPrice.toString(),
      wstEthPrice: wstEthPrice.toString(),
      rethPrice: rethPrice.toString(),
      sfrxEthPrice: sfrxEthPrice.toString(),
    });

    await new Promise((resolve) => setTimeout(resolve, 10000));
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

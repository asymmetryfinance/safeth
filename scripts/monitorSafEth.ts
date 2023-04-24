import { WebhookClient } from "discord.js";
import { BigNumber } from "ethers";
import hre, { ethers } from "hardhat";

async function main() {
  const webhookClient = new WebhookClient({
    id: "1100096574140448858",
    token:
      "iA4trJu9OlcNyn3SslgUmHH0mVrd9xjozqXUDlMkhJKXHeE-uA0Nmq2Ej_j__UWtXfdA",
  });

  const SAFETH_ADDRESS = "0xC57319e15d5D78Ba73c08C4E09d320705Bd4478D";
  const RETH_ADDRESS = "0x8D5dD29592bf3bD5DC98Eb6c0E895fEa4Bd890D0";
  const WSTETH_ADDRESS = "0x1533eDbe274AA1B9fB5dB2652D6d143e939B306f";
  const STFRXETH_ADDRESS = "0x1eD84a676f3ba626389cB131e7c1bc32935bbA37";
  const safEth = await ethers.getContractAt("SafEth", SAFETH_ADDRESS);
  const wstEth = await ethers.getContractAt("WstEth", WSTETH_ADDRESS);
  const reth = await ethers.getContractAt("Reth", RETH_ADDRESS);
  const sfrxEth = await ethers.getContractAt("SfrxEth", STFRXETH_ADDRESS);

  let safEthPrice = await safEth.approxPrice();
  let wstEthPrice = await wstEth.ethPerDerivative();
  let rethPrice = await reth.ethPerDerivative();
  let sfrxEthPrice = await sfrxEth.ethPerDerivative();
  while (true) {
    const newSafEthPrice = await safEth.approxPrice();
    const newWstEthPrice = await wstEth.ethPerDerivative();
    const newRethPrice = await reth.ethPerDerivative();
    const newSfrxEthPrice = await sfrxEth.ethPerDerivative();
    webhookClient.send("Webhook test");
    if (BigNumber.from(newSafEthPrice).lt(safEthPrice)) {
      console.log("newSafEthPrice", newSafEthPrice.toString());
      console.log("oldSafEthPrice", safEthPrice.toString());
      console.log("block number", await hre.ethers.provider.getBlockNumber());
      console.error("SafEth price decreased");
      webhookClient.send("SafEth price decreased");
      webhookClient.send(
        "Block number: " + (await hre.ethers.provider.getBlockNumber())
      );
      webhookClient.send("newSafEthPrice: " + newSafEthPrice.toString());
      webhookClient.send("oldSafEthPrice: " + safEthPrice.toString());
    }
    if (BigNumber.from(newWstEthPrice).lt(wstEthPrice)) {
      console.log("newWstEthPrice", newWstEthPrice.toString());
      console.log("oldWstEthPrice", wstEthPrice.toString());
      console.error("WstEth price decreased");
      webhookClient.send("WstEth price decreased");
      webhookClient.send("newWstEthPrice: " + newWstEthPrice.toString());
      webhookClient.send("oldWstEthPrice: " + wstEthPrice.toString());
    }
    if (BigNumber.from(newRethPrice).lt(rethPrice)) {
      console.log("newRethPrice", newRethPrice.toString());
      console.log("oldRethPrice", rethPrice.toString());
      console.error("Reth price decreased");
      webhookClient.send("Reth price decreased");
      webhookClient.send("newRethPrice: " + newRethPrice.toString());
      webhookClient.send("oldRethPrice: " + rethPrice.toString());
    }
    if (BigNumber.from(newSfrxEthPrice).lt(sfrxEthPrice)) {
      console.log("newSfrxEthPrice", newSfrxEthPrice.toString());
      console.log("oldSfrxEthPrice", sfrxEthPrice.toString());
      console.error("SfrxEth price decreased");
      webhookClient.send("SfrxEth price decreased");
      webhookClient.send("newSfrxEthPrice: " + newSfrxEthPrice.toString());
      webhookClient.send("oldSfrxEthPrice: " + sfrxEthPrice.toString());
    }

    safEthPrice = newSafEthPrice;
    wstEthPrice = newWstEthPrice;
    rethPrice = newRethPrice;
    sfrxEthPrice = newSfrxEthPrice;
    await new Promise((resolve) => setTimeout(resolve, 10000));
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

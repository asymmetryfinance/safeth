import { ethers } from "ethers";
import {
  notifyOnPriceDrop,
  getContracts,
  notifyOnStakeUnstake,
  notfiyOnFailedTx,
} from "./monitorHelpers";

async function main() {
  console.log("Monitoring SafEth Health");
  let lastBlockCheckedForFailedTx = await ethers
    .getDefaultProvider()
    .getBlockNumber();

  const {
    safEth,
    wstEthDerivative,
    rethDerivative,
    sfrxEthDerivative,
    chainLinkStEthEthFeed,
    wstEth,
  } = await getContracts();

  while (true) {
    try {
      notifyOnStakeUnstake();
      const priceData = {
        safEthPrice: await safEth.approxPrice(),
        wstEthPrice: await wstEthDerivative.ethPerDerivative(),
        rethPrice: await rethDerivative.ethPerDerivative(),
        sfrxEthPrice: await sfrxEthDerivative.ethPerDerivative(),
        stEthEthPrice: (await chainLinkStEthEthFeed.latestRoundData())[1],
        stPerWst: await wstEth.getStETHByWstETH("1000000000000000000"),
      };

      notifyOnPriceDrop(priceData);
      lastBlockCheckedForFailedTx = await notfiyOnFailedTx(
        lastBlockCheckedForFailedTx
      );
    } catch (error) {
      console.error("Error: ", error);
    }

    await new Promise((resolve) => setTimeout(resolve, 10000));
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

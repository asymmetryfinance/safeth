import { notifyOnPriceDrop, getContracts } from "./monitorHelpers";

async function main() {
  console.log("Monitoring SafEth Health");

  const {
    safEth,
    wstEthDerivative,
    rethDerivative,
    sfrxEthDerivative,
    chainLinkStEthEthFeed,
    wstEth,
  } = await getContracts();

  while (true) {
    const priceData = {
      safEthPrice: await safEth.approxPrice(),
      wstEthPrice: await wstEthDerivative.ethPerDerivative(),
      rethPrice: await rethDerivative.ethPerDerivative(),
      sfrxEthPrice: await sfrxEthDerivative.ethPerDerivative(),
      stEthEthPrice: (await chainLinkStEthEthFeed.latestRoundData())[1],
      stPerWst: await wstEth.getStETHByWstETH("1000000000000000000"),
    };

    notifyOnPriceDrop(priceData);

    await new Promise((resolve) => setTimeout(resolve, 10000));
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

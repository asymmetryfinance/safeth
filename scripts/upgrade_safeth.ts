import { upgrades, ethers } from "hardhat";

async function main() {
  const SafEthDeployment = await ethers.getContractFactory("SafEth");
  console.log("Upgrading SafEth...");
  await upgrades.upgradeProxy(
    "0x6732Efaf6f39926346BeF8b821a04B6361C4F3e5",
    SafEthDeployment
  );

  console.log("SafEth Upgraded");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

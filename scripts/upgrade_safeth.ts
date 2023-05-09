import { upgrades, ethers } from "hardhat";

async function main() {
  const SafEthDeployment = await ethers.getContractFactory("SafEth");
  console.log("Upgrading SafEth...");
  await upgrades.upgradeProxy(
    "0xC57319e15d5D78Ba73c08C4E09d320705Bd4478D",
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

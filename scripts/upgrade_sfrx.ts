import { upgrades, ethers } from "hardhat";

async function main() {
  const SfrxEthDeployment = await ethers.getContractFactory("SfrxEth");
  console.log("Upgrading SfrxEth...");
  await upgrades.upgradeProxy(
    "0x36Ce17a5c81E74dC111547f5DFFbf40b8BF6B20A",
    SfrxEthDeployment
  );

  console.log("SfrxEth Upgraded");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

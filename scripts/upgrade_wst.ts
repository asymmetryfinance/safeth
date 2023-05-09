import { upgrades, ethers } from "hardhat";

async function main() {
  const WstEthDeployment = await ethers.getContractFactory("WstEth");
  console.log("Upgrading WstEth...");
  await upgrades.upgradeProxy(
    "0x1533eDbe274AA1B9fB5dB2652D6d143e939B306f",
    WstEthDeployment
  );

  console.log("WstEth Upgraded");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

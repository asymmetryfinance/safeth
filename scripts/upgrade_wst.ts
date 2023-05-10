import { upgrades, ethers } from "hardhat";

async function main() {
  const WstEthDeployment = await ethers.getContractFactory("WstEth");
  console.log("Upgrading WstEth...");
  await upgrades.upgradeProxy(
    "0x972A53e3A9114f61b98921Fb5B86C517e8F23Fad",
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

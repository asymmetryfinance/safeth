import { upgrades, ethers } from "hardhat";

async function main() {
  const RethDeployment = await ethers.getContractFactory("Reth");
  console.log("Upgrading Reth...");
  await upgrades.upgradeProxy(
    "0x8D5dD29592bf3bD5DC98Eb6c0E895fEa4Bd890D0",
    RethDeployment
  );

  console.log("Reth Upgraded");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

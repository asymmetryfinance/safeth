import { upgrades, ethers } from "hardhat";

async function main() {
  const RethDeployment = await ethers.getContractFactory("Reth");
  console.log("Upgrading Reth...");
  await upgrades.upgradeProxy(
    "0x7B6633c0cD81dC338688A528c0A3f346561F5cA3",
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

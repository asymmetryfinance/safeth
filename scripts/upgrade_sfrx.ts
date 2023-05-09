import { upgrades, ethers } from "hardhat";

async function main() {
  const SfrxEthDeployment = await ethers.getContractFactory("SfrxEth");
  console.log("Upgrading SfrxEth...");
  await upgrades.upgradeProxy(
    "0x1eD84a676f3ba626389cB131e7c1bc32935bbA37",
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

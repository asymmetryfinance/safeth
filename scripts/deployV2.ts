import { upgrades, ethers } from "hardhat";

async function main() {
  // Deploy new derivatives
  const AnkrDeployment = await ethers.getContractFactory("Ankr");
  const ankr = await upgrades.deployProxy(AnkrDeployment, [
    "0x6732Efaf6f39926346BeF8b821a04B6361C4F3e5",
  ]);
  await ankr.deployed();
  console.log("ankr deployed to:", ankr.address);

  const StafiDeployment = await ethers.getContractFactory("Stafi");
  const stafi = await upgrades.deployProxy(StafiDeployment, [
    "0x6732Efaf6f39926346BeF8b821a04B6361C4F3e5",
  ]);
  await stafi.deployed();
  console.log("stafi deployed to:", stafi.address);

  const SwellDeployment = await ethers.getContractFactory("Swell");
  const swell = await upgrades.deployProxy(SwellDeployment, [
    "0x6732Efaf6f39926346BeF8b821a04B6361C4F3e5",
  ]);
  await swell.deployed();
  console.log("swell deployed to:", swell.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

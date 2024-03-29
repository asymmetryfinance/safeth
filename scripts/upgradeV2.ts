import { ethers, defender, upgrades } from "hardhat";

async function main() {
  const SafEthDeployment = await ethers.getContractFactory("SafEth");
  const safEth = await ethers.getContractAt(
    "SafEth",
    "0x6732Efaf6f39926346BeF8b821a04B6361C4F3e5"
  );

  const safEthProposal = await defender.proposeUpgrade(
    "0x6732Efaf6f39926346BeF8b821a04B6361C4F3e5",
    SafEthDeployment
  );
  console.log("SafEth proposal at: ", safEthProposal.url);

  // Deploy derivatives
  const RethDeployment = await ethers.getContractFactory("Reth");
  const rEthProposal = await defender.proposeUpgrade(
    "0x7B6633c0cD81dC338688A528c0A3f346561F5cA3",
    RethDeployment
  );
  console.log("Reth proposal at: ", rEthProposal.url);

  const SfrxDeployment = await ethers.getContractFactory("SfrxEth");
  const sfrx = await upgrades.deployProxy(SfrxDeployment, [safEth.address]);
  await sfrx.deployed();

  console.log("sfrxEth deployed to:", sfrx.address);

  const WstDeployment = await ethers.getContractFactory("WstEth");
  const wstProposal = await defender.proposeUpgrade(
    "0x972A53e3A9114f61b98921Fb5B86C517e8F23Fad",
    WstDeployment
  );

  console.log("Wst proposal at: ", wstProposal.url);

  await safEth.initializeV2();
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

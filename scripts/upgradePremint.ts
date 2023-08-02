import { ethers, defender } from "hardhat";

async function main() {
  const SafEthDeployment = await ethers.getContractFactory("SafEth");

  const safEthProposal = await defender.proposeUpgrade(
    "0x6732Efaf6f39926346BeF8b821a04B6361C4F3e5",
    SafEthDeployment
  );

  console.log("SafEth proposal at: ", safEthProposal.url);
}

import { upgrades, ethers } from "hardhat";

async function main() {
  const VotiumMockFactory = await ethers.getContractFactory("VotiumPosition");
  const votiumMock = await upgrades.deployProxy(VotiumMockFactory, []);

  await votiumMock.deployed();

  console.log("Votium Mock deployed to:", votiumMock.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

import { upgrades, ethers } from "hardhat";
import { upgrade } from "../test/helpers/upgradeHelpers";

async function main() {
  const VotiumMockFactory = await ethers.getContractFactory("VotiumPosition");
  const votiumMock = await upgrades.deployProxy(VotiumMockFactory, []);

  await votiumMock.deployed();

  console.log("Votium Mock deployed to:", votiumMock.address);
}

async function main2() {
  const upgraded = await upgrade(
    "0xbbba116ef0525cd5ea9f4a9c1f628c3bfc343261",
    "VotiumPositionV2"
  );
  await upgraded.deployed();
}

main2()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

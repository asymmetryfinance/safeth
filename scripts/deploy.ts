import hre, { upgrades, ethers } from "hardhat";

async function main() {
  const SafTokenDeployment = await ethers.getContractFactory("SafETH");
  const safETH = await SafTokenDeployment.deploy(
    "Asymmetry Finance ETH",
    "safETH"
  );
  await safETH.deployed();

  await hre.ethernal.push({
    name: "safETH",
    address: safETH.address,
  });

  console.log("safETH deployed to:", safETH.address);

  const AfStrategyDeployment = await ethers.getContractFactory("AfStrategy");
  const afStrategy = await upgrades.deployProxy(AfStrategyDeployment, [
    safETH.address,
  ]);

  await afStrategy.deployed();

  console.log("AF Strategy deployed to:", afStrategy.address);

  await hre.ethernal.push({
    name: "AfStrategy",
    address: afStrategy.address,
  });

  await safETH.setMinter(afStrategy.address);

  // Deploy derivatives
  const rethDeployment = await ethers.getContractFactory("Reth");
  const reth = await upgrades.deployProxy(rethDeployment, [afStrategy.address]);
  await reth.deployed();
  await afStrategy.addDerivative(reth.address, "1000000000000000000");
  console.log("RETH deployed to:", reth.address);

  await hre.ethernal.push({
    name: "Reth",
    address: reth.address,
  });

  const SfrxDeployment = await ethers.getContractFactory("SfrxEth");
  const sfrx = await upgrades.deployProxy(SfrxDeployment, [afStrategy.address]);
  await sfrx.deployed();

  await afStrategy.addDerivative(sfrx.address, "1000000000000000000");
  console.log("sfrx deployed to:", sfrx.address);
  await hre.ethernal.push({
    name: "SfrxEth",
    address: sfrx.address,
  });

  const WstDeployment = await ethers.getContractFactory("WstEth");
  const wst = await upgrades.deployProxy(WstDeployment, [afStrategy.address]);
  await wst.deployed();

  await afStrategy.addDerivative(wst.address, "1000000000000000000");
  console.log("wst deployed to:", wst.address);
  await hre.ethernal.push({
    name: "WstEth",
    address: wst.address,
  });
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

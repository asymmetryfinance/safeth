import hre, { upgrades, ethers } from "hardhat";

async function main() {
  const SafTokenDeployment = await ethers.getContractFactory("afETH");
  const safETH = await SafTokenDeployment.deploy(
    "Asymmetry Finance ETH",
    "safETH"
  );
  await safETH.deployed();

  await hre.ethernal.push({
    name: "afETH",
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

  // Deploy derivatives
  const rethDeployment = await ethers.getContractFactory("Reth");
  const reth = await rethDeployment.deploy();
  await reth.deployed();
  console.log("RETH deployed to:", reth.address);
  await hre.ethernal.push({
    name: "Reth",
    address: reth.address,
  });

  //   const SfrxDeployment = await ethers.getContractFactory("SfrxEth");
  //   const sfrx = await SfrxDeployment.deploy();
  //   await sfrx.deployed();
  //   console.log("sfrx deployed to:", sfrx.address);
  //   await hre.ethernal.push({
  //     name: "SfrxEth",
  //     address: sfrx.address,
  //   });

  const WstDeployment = await ethers.getContractFactory("WstEth");
  const wst = await WstDeployment.deploy();
  await wst.deployed();
  console.log("wst deployed to:", wst.address);
  await hre.ethernal.push({
    name: "WstEth",
    address: wst.address,
  });

  await reth.transferOwnership(afStrategy.address);
  await afStrategy.addDerivative(reth.address, "1000000000000000000");

  //   await sfrx.transferOwnership(afStrategy.address);
  //   await afStrategy.addDerivative(sfrx.address, "1000000000000000000");

  await wst.transferOwnership(afStrategy.address);
  await afStrategy.addDerivative(wst.address, "1000000000000000000");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

import hre, { upgrades, ethers } from "hardhat";

async function main() {
  const SafTokenDeployment = await ethers.getContractFactory("safETH");
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
  const reth = await upgrades.deployProxy(rethDeployment, []);
  await reth.deployed();
  await reth.transferOwnership(afStrategy.address);
  await afStrategy.addDerivative(reth.address, "1000000000000000000");
  console.log("RETH deployed to:", reth.address);

  await hre.ethernal.push({
    name: "Reth",
    address: reth.address,
  });

  const SfrxDeployment = await ethers.getContractFactory("SfrxEth");
  const sfrx = await upgrades.deployProxy(SfrxDeployment, []);
  await sfrx.deployed();

  await sfrx.transferOwnership(afStrategy.address);
  await afStrategy.addDerivative(sfrx.address, "1000000000000000000");
  console.log("sfrx deployed to:", sfrx.address);
  await hre.ethernal.push({
    name: "SfrxEth",
    address: sfrx.address,
  });

  const WstDeployment = await ethers.getContractFactory("WstEth");
  const wst = await upgrades.deployProxy(WstDeployment, []);
  await wst.deployed();

  await wst.transferOwnership(afStrategy.address);
  await afStrategy.addDerivative(wst.address, "1000000000000000000");
  console.log("wst deployed to:", wst.address);
  await hre.ethernal.push({
    name: "WstEth",
    address: wst.address,
  });

  const StakeWiseDeployment = await ethers.getContractFactory("StakeWise");
  const stakeWise = await upgrades.deployProxy(StakeWiseDeployment, []);
  await stakeWise.deployed();

  await stakeWise.transferOwnership(afStrategy.address);
  await afStrategy.addDerivative(stakeWise.address, "1000000000000000000");
  console.log("stakewise deployed to:", stakeWise.address);
  await hre.ethernal.push({
    name: "StakeWise",
    address: stakeWise.address,
  });
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

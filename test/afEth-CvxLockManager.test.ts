import { ethers, upgrades } from "hardhat";
import {
  CRV_POOL_FACTORY,
  CVX_ADDRESS,
  VL_CVX,
  WETH_ADDRESS,
} from "./helpers/constants";
import ERC20 from "@openzeppelin/contracts/build/contracts/ERC20.json";
import { time } from "@nomicfoundation/hardhat-network-helpers";
import { AfCVX1155, AfEth } from "../typechain-types";
import { BigNumber } from "ethers";
import { crvPoolFactoryAbi } from "./abi/crvPoolFactoryAbi";
import { expect } from "chai";
import { vlCvxAbi } from "./abi/vlCvxAbi";

describe.only("AfEth (CvxLockManager)", async function () {
  let afEth: AfEth;
  let afCvx1155: AfCVX1155;

  const deployContracts = async () => {
    const AfCVX1155 = await ethers.getContractFactory("AfCVX1155");
    afCvx1155 = await AfCVX1155.deploy();
    await afCvx1155.deployed();

    const SafEth = await ethers.getContractFactory("SafEth");
    const safEth = await upgrades.deployProxy(SafEth, [
      "Asymmetry Finance ETH",
      "safETH",
    ]);
    await safEth.deployed();

    const AfEth = await ethers.getContractFactory("AfEth");
    const address = ethers.constants.AddressZero;
    afEth = (await upgrades.deployProxy(AfEth, [
      afCvx1155.address,
      address,
      safEth.address,
      "Asymmetry Finance ETH",
      "afETh",
    ])) as AfEth;
    await afEth.deployed();

    await afCvx1155.initialize(afEth.address);
  };

  beforeEach(async () => {
    const accounts = await ethers.getSigners();
    const crvPoolFactory = new ethers.Contract(
      CRV_POOL_FACTORY,
      crvPoolFactoryAbi,
      accounts[0]
    );

    await deployContracts();

    const deployCrv = await crvPoolFactory.deploy_pool(
      "Asymmetry Finance ETH",
      "afETH",
      [afEth.address, WETH_ADDRESS],
      BigNumber.from("400000"),
      BigNumber.from("145000000000000"),
      BigNumber.from("26000000"),
      BigNumber.from("45000000"),
      BigNumber.from("2000000000000"),
      BigNumber.from("230000000000000"),
      BigNumber.from("146000000000000"),
      BigNumber.from("5000000000"),
      BigNumber.from("600"),
      BigNumber.from("1000000000000000000")
    );
    const crvPoolReceipt = await deployCrv.wait();
    const crvToken = await crvPoolReceipt?.events?.[0]?.address;
    const crvAddress = new ethers.Contract(
      crvToken,
      ["function minter() external view returns (address)"],
      accounts[0]
    );
    const afEthCrvPoolAddress = await crvAddress.minter();
    await afEth.updateCrvPool(afEthCrvPoolAddress);
  });

  it("Should fail to withdraw cvx from an open position", async function () {
    const depositAmount = ethers.utils.parseEther("5");

    const tx = await afEth.stake({ value: depositAmount });
    await tx.wait();

    await expect(afEth.withdrawCvx(1)).to.be.revertedWith("Not closed");
  });

  it("Should fail to withdraw cvx from a position that has closed but not yet unlocked", async function () {
    let tx;
    const depositAmount = ethers.utils.parseEther("5");
    tx = await afEth.stake({ value: depositAmount });
    await tx.wait();

    tx = await afEth.unstake(1);
    await tx.wait();

    await expect(afEth.withdrawCvx(1)).to.be.revertedWith("Cvx still locked");
    await tx.wait();
  });

  it("Should fail to close a position with the wrong owner", async function () {
    const accounts = await ethers.getSigners();
    const depositAmount = ethers.utils.parseEther("5");

    const afEth0 = afEth.connect(accounts[0]);
    const afEth1 = afEth.connect(accounts[1]);

    const tx = await afEth0.stake({ value: depositAmount });
    await tx.wait();

    await expect(afEth1.unstake(1)).to.be.revertedWith("Not owner");
  });

  it("Should fail to close an already closed position", async function () {
    let tx;
    const depositAmount = ethers.utils.parseEther("5");

    tx = await afEth.stake({ value: depositAmount });
    await tx.wait();

    tx = await afEth.unstake(1);
    await tx.wait();

    await expect(afEth.unstake(1)).to.be.revertedWith("Not open");
  });

  it("Should fail to withdraw from a position twice", async function () {
    const accounts = await ethers.getSigners();
    let tx;
    const depositAmount = ethers.utils.parseEther("5");

    tx = await afEth.stake({ value: depositAmount });
    await tx.wait();

    tx = await afEth.unstake(1);
    await tx.wait();

    await time.increase(60 * 60 * 24 * 7 * 17);
    const vlCvxContract = new ethers.Contract(VL_CVX, vlCvxAbi, accounts[0]);

    // this is necessary every time we have increased time past a new epoch
    tx = await vlCvxContract.checkpointEpoch();
    await tx.wait();

    tx = await afEth.relockCvx();
    await tx.wait();

    tx = await afEth.withdrawCvx(1);
    await tx.wait();
    await expect(afEth.withdrawCvx(1)).to.be.revertedWith("No cvx to withdraw");
  });
  it("Should fail to withdraw from a non-existent positionId", async function () {
    const accounts = await ethers.getSigners();
    let tx;
    const depositAmount = ethers.utils.parseEther("5");

    tx = await afEth.stake({ value: depositAmount });
    await tx.wait();

    tx = await afEth.unstake(1);
    await tx.wait();

    await time.increase(60 * 60 * 24 * 7 * 17);
    const vlCvxContract = new ethers.Contract(VL_CVX, vlCvxAbi, accounts[0]);

    // this is necessary every time we have increased time past a new epoch
    tx = await vlCvxContract.checkpointEpoch();
    await tx.wait();

    tx = await afEth.relockCvx();
    await tx.wait();

    await tx.wait();
    await expect(afEth.withdrawCvx(2)).to.be.revertedWith("Invalid positionId");
  });
});

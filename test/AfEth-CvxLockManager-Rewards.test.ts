import { ethers, upgrades } from "hardhat";
import { CRV_POOL_FACTORY, VL_CVX } from "./helpers/constants";
import {
  SnapshotRestorer,
  takeSnapshot,
  time,
} from "@nomicfoundation/hardhat-network-helpers";
import { AfEth, CvxStrategy, SafEth } from "../typechain-types";
import { BigNumber } from "ethers";
import { crvPoolFactoryAbi } from "./abi/crvPoolFactoryAbi";
import { expect } from "chai";
import { vlCvxAbi } from "./abi/vlCvxAbi";
import { deploySafEth } from "./helpers/upgradeHelpers";

describe.only("AfEth (CvxLockManager Rewards)", async function () {
  let afEth: AfEth;
  let safEth: SafEth;
  let cvxStrategy: CvxStrategy;
  let snapshot: SnapshotRestorer;

  const deployContracts = async () => {
    safEth = (await deploySafEth()) as SafEth;

    const AfEth = await ethers.getContractFactory("AfEth");
    afEth = (await AfEth.deploy("Asymmetry Finance ETH", "afETh")) as AfEth;
    await afEth.deployed();

    const CvxStrategy = await ethers.getContractFactory("CvxStrategy");
    cvxStrategy = (await upgrades.deployProxy(CvxStrategy, [
      safEth.address,
      afEth.address,
    ])) as CvxStrategy;
    await cvxStrategy.deployed();

    await afEth.setMinter(cvxStrategy.address);
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
      "Af Cvx Strategy",
      "afCvxStrat",
      [afEth.address, safEth.address],
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
    await cvxStrategy.updateCrvPool(afEthCrvPoolAddress);

    snapshot = await takeSnapshot();
  });

  afterEach(async () => {
    await snapshot.restore();
  });

  it("Should withdraw owed rewards when withdrawCvxAndRewards() is called", async function () {
    let tx;
    const accounts = await ethers.getSigners();
    const vlCvxContract = new ethers.Contract(VL_CVX, vlCvxAbi, accounts[0]);
    const depositAmount = ethers.utils.parseEther("5");

    // open position
    tx = await cvxStrategy.stake({ value: depositAmount });

    // close position
    tx = await cvxStrategy.unstake(false, 0);
    await tx.wait();

    // wait 17 weeks
    await time.increase(60 * 60 * 24 * 7 * 17);
    // this is necessary in tests every time we have increased time past a new epoch
    tx = await vlCvxContract.checkpointEpoch();
    const balanceBefore = await ethers.provider.getBalance(accounts[0].address);
    tx = await cvxStrategy.withdrawCvxAndRewards(0);
    const mined = await tx.wait();
    const networkFee = mined.gasUsed.mul(mined.effectiveGasPrice);
    const balanceAfter = await ethers.provider.getBalance(accounts[0].address);
    const ethReceived = balanceAfter.sub(balanceBefore).add(networkFee);
    expect(ethReceived.gt(0));
  });
  it("Should cost less gas to call withdrawCvxAndRewards() if claimRewards() was already called in the same epoch", async function () {
    // TODO
  });
  it("Should increase strategy contract eth balance when claimRewards() is called", async function () {
    // TODO
  });
});

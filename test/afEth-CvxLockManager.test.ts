import { ethers, upgrades } from "hardhat";
import {
  CRV_POOL_FACTORY,
  CVX_ADDRESS,
  VL_CVX,
  WETH_ADDRESS,
} from "./helpers/constants";
import ERC20 from "@openzeppelin/contracts/build/contracts/ERC20.json";
import {
  SnapshotRestorer,
  takeSnapshot,
  time,
} from "@nomicfoundation/hardhat-network-helpers";
import { AfCVX1155, AfEth } from "../typechain-types";
import { BigNumber } from "ethers";
import { crvPoolFactoryAbi } from "./abi/crvPoolFactoryAbi";
import { expect } from "chai";
import { vlCvxAbi } from "./abi/vlCvxAbi";

describe("AfEth (CvxLockManager)", async function () {
  let afEth: AfEth;
  let afCvx1155: AfCVX1155;
  let snapshot: SnapshotRestorer;

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

    snapshot = await takeSnapshot();
  });

  afterEach(async () => {
    await snapshot.restore();
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
    let tx;
    const accounts = await ethers.getSigners();
    const depositAmount = ethers.utils.parseEther("5");

    tx = await afEth.stake({ value: depositAmount });
    await tx.wait();

    tx = await afEth.unstake(1);
    await tx.wait();

    await time.increase(60 * 60 * 24 * 7 * 17);
    const vlCvxContract = new ethers.Contract(VL_CVX, vlCvxAbi, accounts[0]);

    // makes sure epoch is correct
    // this is necessary in tests every time we have increased time past a new epoch
    tx = await vlCvxContract.checkpointEpoch();

    await tx.wait();

    tx = await afEth.withdrawCvx(1);
    await tx.wait();
    await expect(afEth.withdrawCvx(1)).to.be.revertedWith("No cvx to withdraw");
  });

  it("Should fail to withdraw from a non-existent positionId", async function () {
    let tx;
    const accounts = await ethers.getSigners();
    const depositAmount = ethers.utils.parseEther("5");

    tx = await afEth.stake({ value: depositAmount });
    await tx.wait();

    tx = await afEth.unstake(1);
    await tx.wait();

    await time.increase(60 * 60 * 24 * 7 * 17);
    const vlCvxContract = new ethers.Contract(VL_CVX, vlCvxAbi, accounts[0]);

    // this is necessary in tests every time we have increased time past a new epoch
    tx = await vlCvxContract.checkpointEpoch();
    await tx.wait();

    await tx.wait();
    await expect(afEth.withdrawCvx(2)).to.be.revertedWith("Invalid positionId");
  });

  it("Should allow a user to lock, unlock & withdraw after 17 weeks", async function () {
    let tx;
    const accounts = await ethers.getSigners();
    const cvx = new ethers.Contract(CVX_ADDRESS, ERC20.abi, accounts[0]);
    const vlCvxContract = new ethers.Contract(VL_CVX, vlCvxAbi, accounts[0]);
    const depositAmount = ethers.utils.parseEther("5");

    // open position
    tx = await afEth.stake({ value: depositAmount });

    // wait 8 weeks
    await time.increase(60 * 60 * 24 * 7 * 8);
    // this is necessary in tests every time we have increased time past a new epoch
    tx = await vlCvxContract.checkpointEpoch();
    await tx.wait();

    // close position
    tx = await afEth.unstake(1);
    await tx.wait();

    // wait 9 weeks more weeks
    await time.increase(60 * 60 * 24 * 7 * 9);
    // this is necessary in tests every time we have increased time past a new epoch
    tx = await vlCvxContract.checkpointEpoch();
    await tx.wait();

    const cvxBalanceBefore = await cvx.balanceOf(accounts[0].address);

    const lockedPositionAmount = (await afEth.cvxPositions(1)).cvxAmount;

    tx = await afEth.withdrawCvx(1);
    await tx.wait();

    const cvxBalanceAfter = await cvx.balanceOf(accounts[0].address);

    expect(lockedPositionAmount).eq(cvxBalanceAfter.sub(cvxBalanceBefore));
  });

  it("Should fail to withdraw 1 minute before unlock epoch and succeed after unlock epoch has started", async function () {
    let tx;
    const accounts = await ethers.getSigners();
    const cvx = new ethers.Contract(CVX_ADDRESS, ERC20.abi, accounts[0]);
    const vlCvxContract = new ethers.Contract(VL_CVX, vlCvxAbi, accounts[0]);
    const depositAmount = ethers.utils.parseEther("5");

    // open position
    tx = await afEth.stake({ value: depositAmount });

    // close position
    tx = await afEth.unstake(1);
    await tx.wait();

    const nextEpoch = (await vlCvxContract.epochCount()).sub(1);

    const nextEpochStartTime = BigNumber.from(
      (await vlCvxContract.epochs(nextEpoch)).date
    );

    const unlockEpochStartTime = nextEpochStartTime.add(
      await vlCvxContract.lockDuration()
    );

    // 1 minute before expected unlock epoch
    await time.increaseTo(unlockEpochStartTime.sub(60));

    // this is necessary in tests every time we have increased time past a new epoch
    tx = await vlCvxContract.checkpointEpoch();
    await tx.wait();

    // expect it to fail because not yet unlocked

    await expect(afEth.withdrawCvx(1)).to.be.revertedWith("Cvx still locked");

    // 1 minute after unlock epoch has started
    await time.increaseTo(unlockEpochStartTime.add(60));

    // this is necessary in tests every time we have increased time past a new epoch
    tx = await vlCvxContract.checkpointEpoch();
    await tx.wait();

    const cvxBalanceBefore = await cvx.balanceOf(accounts[0].address);

    const lockedPositionAmount = (await afEth.cvxPositions(1)).cvxAmount;

    tx = await afEth.withdrawCvx(1);
    await tx.wait();

    const cvxBalanceAfter = await cvx.balanceOf(accounts[0].address);

    expect(lockedPositionAmount).eq(cvxBalanceAfter.sub(cvxBalanceBefore));
  });

  it("Should cost less gas to withdraw if relockCvx() has been called in the same epoch before withdrawCvx()", async function () {
    let tx;
    const accounts = await ethers.getSigners();
    const vlCvxContract = new ethers.Contract(VL_CVX, vlCvxAbi, accounts[0]);
    const depositAmount = ethers.utils.parseEther("5");

    // open position
    tx = await afEth.stake({ value: depositAmount });

    // close position
    tx = await afEth.unstake(1);
    await tx.wait();

    // wait 10 more lock durations

    await time.increase((await vlCvxContract.lockDuration()) * 10);
    // this is necessary in tests every time we have increased time past a new epoch
    tx = await vlCvxContract.checkpointEpoch();
    await tx.wait();

    tx = await afEth.withdrawCvx(1);
    const mined = await tx.wait();
    const gasUsedWithoutRelock = mined.gasUsed;

    // open position
    tx = await afEth.stake({ value: depositAmount });

    // close position
    tx = await afEth.unstake(2);
    await tx.wait();

    // wait 10 more lock durations
    await time.increase((await vlCvxContract.lockDuration()) * 10);
    // this is necessary in tests every time we have increased time past a new epoch
    tx = await vlCvxContract.checkpointEpoch();
    await tx.wait();

    await afEth.relockCvx();

    tx = await afEth.withdrawCvx(2);
    const mined2 = await tx.wait();
    const gasUsedWithRelock = mined2.gasUsed;

    expect(gasUsedWithRelock).lt(gasUsedWithoutRelock);
  });

  it("Should show that cvxToLeaveUnlocked has expected values always equals cvx balance", async function () {
    let tx;
    const accounts = await ethers.getSigners();
    const cvx = new ethers.Contract(CVX_ADDRESS, ERC20.abi, accounts[0]);
    const vlCvxContract = new ethers.Contract(VL_CVX, vlCvxAbi, accounts[0]);
    const depositAmount = ethers.utils.parseEther("5");

    // open position (1)
    tx = await afEth.stake({ value: depositAmount });
    await tx.wait();

    // wait 3 days
    await time.increase(60 * 60 * 24 * 3);
    // this is necessary in tests every time we have increased time past a new epoch
    tx = await vlCvxContract.checkpointEpoch();
    await tx.wait();

    // open position (2) 3 days later but in the same epoch
    tx = await afEth.stake({ value: depositAmount });

    // close position
    tx = await afEth.unstake(1);
    await tx.wait();

    const leaveUnlocked0 = await afEth.cvxToLeaveUnlocked();
    const cvxBalance0 = await cvx.balanceOf(afEth.address);
    // initially nothing to hold unlocked
    expect(leaveUnlocked0).eq(cvxBalance0).eq(0);

    // 8 weeks later relock
    // relocking after 8 weeks wont have anything to hold unlocked yet
    await time.increase(60 * 60 * 24 * 7 * 8);
    // this is necessary in tests every time we have increased time past a new epoch
    tx = await vlCvxContract.checkpointEpoch();
    await tx.wait();
    tx = await afEth.relockCvx();
    await tx.wait();
    const leaveUnlocked1 = await afEth.cvxToLeaveUnlocked();
    const cvxBalance1 = await cvx.balanceOf(afEth.address);

    // relocking after 8 weeks wont have anything to hold unlocked yet
    expect(leaveUnlocked1).eq(cvxBalance1).eq(0);

    // 9 weeks later relock
    await time.increase(60 * 60 * 24 * 7 * 9);
    // this is necessary in tests every time we have increased time past a new epoch
    tx = await vlCvxContract.checkpointEpoch();
    await tx.wait();
    tx = await afEth.relockCvx();
    await tx.wait();

    const leaveUnlocked2 = await afEth.cvxToLeaveUnlocked();
    const cvxBalance2 = await cvx.balanceOf(afEth.address);

    // relocking 17 weeks after the initial unlock request should add unlockable position balances to cvxToLeaveUnlocked
    expect(leaveUnlocked2).eq(cvxBalance2).eq("473659828597469628956");

    // request unlock position 2
    tx = await afEth.unstake(2);
    await tx.wait();

    // 9 weeks later relock again
    await time.increase(60 * 60 * 24 * 7 * 9);
    // this is necessary in tests every time we have increased time past a new epoch
    tx = await vlCvxContract.checkpointEpoch();
    await tx.wait();
    tx = await afEth.relockCvx();
    await tx.wait();

    const leaveUnlocked21 = await afEth.cvxToLeaveUnlocked();
    const cvxBalance21 = await cvx.balanceOf(afEth.address);
    // relocking again shouldnt change anything because the second unlock request is not done yet
    expect(leaveUnlocked21).eq(cvxBalance21).eq("473659828597469628956");

    // 8 weeks later relock again
    await time.increase(60 * 60 * 24 * 7 * 8);
    // this is necessary in tests every time we have increased time past a new epoch
    tx = await vlCvxContract.checkpointEpoch();
    await tx.wait();
    tx = await afEth.relockCvx();
    await tx.wait();

    const leaveUnlocked22 = await afEth.cvxToLeaveUnlocked();
    const cvxBalance22 = await cvx.balanceOf(afEth.address);
    // relocking this time enough time has passed so both positions are ready for withdraw
    expect(leaveUnlocked22).eq(cvxBalance22).eq("945143254217498881564");

    const position1 = await afEth.cvxPositions(1);
    const position2 = await afEth.cvxPositions(2);
    const totalUnlockedPositionsCvx = position1.cvxAmount.add(
      position2.cvxAmount
    );

    // cvxToLeaveUnlocked should equal the sum of all unlocked positions that are ready to withdraw
    expect(totalUnlockedPositionsCvx).eq(leaveUnlocked22);

    // withdraw the first position
    tx = await afEth.withdrawCvx(1);
    await tx.wait();

    const leaveUnlocked44 = await afEth.cvxToLeaveUnlocked();
    const cvxBalance44 = await cvx.balanceOf(afEth.address);
    const userCvxBalance44 = await cvx.balanceOf(accounts[0].address);

    // withdrawing first position gives user first position amount & leaves some in contract
    expect(leaveUnlocked44).eq(cvxBalance44).eq(position2.cvxAmount);
    expect(userCvxBalance44).eq(position1.cvxAmount);

    // withdraw the second position
    tx = await afEth.withdrawCvx(2);
    await tx.wait();

    const leaveUnlocked6 = await afEth.cvxToLeaveUnlocked();
    const cvxBalance6 = await cvx.balanceOf(afEth.address);
    const userCvxBalance = await cvx.balanceOf(accounts[0].address);

    // withdrawing will put cvxToLeaveUnlocked back to 0
    expect(leaveUnlocked6).eq(cvxBalance6).eq(0);
    expect(userCvxBalance).eq("945143254217498881564");
  });

  it("Should correctly calculate the unlock epoch and unlock a position that has been relocked multiple times", async function () {
    let tx;
    const accounts = await ethers.getSigners();
    const cvx = new ethers.Contract(CVX_ADDRESS, ERC20.abi, accounts[0]);
    const vlCvxContract = new ethers.Contract(VL_CVX, vlCvxAbi, accounts[0]);
    const depositAmount = ethers.utils.parseEther("5");

    // open position (1)
    tx = await afEth.stake({ value: depositAmount });

    // wait 65 weeks (just over 4 lock periods)
    await time.increase(60 * 60 * 24 * 7 * 68);
    // this is necessary in tests every time we have increased time past a new epoch
    tx = await vlCvxContract.checkpointEpoch();
    await tx.wait();

    tx = await afEth.unstake(1);
    await tx.wait();

    const position1 = await afEth.cvxPositions(1);
    const unlockEpoch = position1.unlockEpoch;
    const currentEpoch = await afEth.getCurrentEpoch();
    const startingEpoch = position1.startingEpoch;
    // unlock epoch should be <= 16 weeks from now
    expect(unlockEpoch.sub(currentEpoch)).lte(16);
    const unlockDifference = unlockEpoch.sub(startingEpoch).toNumber();
    // should be in 16 week intervals from the original starting epoch
    expect(unlockDifference % 16).eq(0);
    const startingEpochTime = BigNumber.from(
      (await vlCvxContract.epochs(startingEpoch)).date
    );
    const unlockEpochTime = startingEpochTime.add(
      unlockDifference * 24 * 60 * 60 * 7
    );

    // wait until we theoretically can unlock
    await time.increaseTo(unlockEpochTime);
    // this is necessary in tests every time we have increased time past a new epoch
    tx = await vlCvxContract.checkpointEpoch();
    await tx.wait();

    const position1Before = await afEth.cvxPositions(1);
    const userCvxBalanceBefore = await cvx.balanceOf(accounts[0].address);
    // unlock
    tx = await afEth.withdrawCvx(1);
    await tx.wait();

    const userCvxBalanceAfter = await cvx.balanceOf(accounts[0].address);
    const diff = userCvxBalanceAfter.sub(userCvxBalanceBefore);

    expect(diff).eq(position1Before.cvxAmount);
  });
});

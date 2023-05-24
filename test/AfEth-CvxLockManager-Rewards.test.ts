import { ethers } from "hardhat";
import { CRV_POOL_FACTORY, VL_CVX } from "./helpers/constants";
import {
  SnapshotRestorer,
  takeSnapshot,
  time,
} from "@nomicfoundation/hardhat-network-helpers";
import {
  AfEth,
  CvxStrategy,
  ExtraRewardsStream,
  SafEth,
} from "../typechain-types";
import { BigNumber } from "ethers";
import { crvPoolFactoryAbi } from "./abi/crvPoolFactoryAbi";
import { expect } from "chai";
import { vlCvxAbi } from "./abi/vlCvxAbi";
import {
  epochDuration,
  getCurrentEpoch,
  getCurrentEpochEndTime,
} from "./helpers/lockManagerHelpers";
import { deployStrategyContract } from "./helpers/afEthTestHelpers";
import { getDifferenceRatio } from "./helpers/functions";

describe("AfEth (CvxLockManager Rewards)", async function () {
  let afEth: AfEth;
  let safEth: SafEth;
  let cvxStrategy: CvxStrategy;
  let snapshot: SnapshotRestorer;
  let extraRewardsStream: ExtraRewardsStream;

  beforeEach(async () => {
    const accounts = await ethers.getSigners();
    const crvPoolFactory = new ethers.Contract(
      CRV_POOL_FACTORY,
      crvPoolFactoryAbi,
      accounts[0]
    );

    const deployResults = await deployStrategyContract();
    afEth = deployResults.afEth;
    safEth = deployResults.safEth;
    cvxStrategy = deployResults.cvxStrategy;
    extraRewardsStream = deployResults.extraRewardsStream;
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

    const seedAmount = ethers.utils.parseEther("10");
    await cvxStrategy.updateCrvPool(afEthCrvPoolAddress, {
      value: seedAmount,
    });
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
    await tx.wait();

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
    expect(ethReceived).gt(0);
  });
  it("Should increase strategy contract eth balance when claimRewards() is called", async function () {
    let tx;
    const accounts = await ethers.getSigners();
    const vlCvxContract = new ethers.Contract(VL_CVX, vlCvxAbi, accounts[0]);
    const depositAmount = ethers.utils.parseEther("5");
    // open position
    tx = await cvxStrategy.stake({ value: depositAmount });
    // wait some time for rewards to acrue
    await time.increase(60 * 60 * 24 * 7 * 4);
    // this is necessary in tests every time we have increased time past a new epoch
    tx = await vlCvxContract.checkpointEpoch();
    await tx.wait();

    const balanceBefore = await ethers.provider.getBalance(cvxStrategy.address);
    tx = await cvxStrategy.claimRewards();
    await tx.wait();
    const balanceAfter = await ethers.provider.getBalance(cvxStrategy.address);
    expect(balanceAfter).gt(balanceBefore);
  });
  it("Should cost less gas to call withdrawCvxAndRewards() if claimRewards() was already called in the same epoch", async function () {
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
    tx = await cvxStrategy.withdrawCvxAndRewards(0);
    const mined = await tx.wait();
    const networkFeeExpensive = mined.gasUsed.mul(mined.effectiveGasPrice);

    await snapshot.restore();

    // open position
    tx = await cvxStrategy.stake({ value: depositAmount });

    // close position
    tx = await cvxStrategy.unstake(false, 0);
    await tx.wait();

    // wait 17 weeks
    await time.increase(60 * 60 * 24 * 7 * 17);
    // this is necessary in tests every time we have increased time past a new epoch
    tx = await vlCvxContract.checkpointEpoch();
    tx = await cvxStrategy.claimRewards();
    await tx.wait();
    tx = await cvxStrategy.withdrawCvxAndRewards(0);
    const mined2 = await tx.wait();
    const networkFeeCheap = mined2.gasUsed.mul(mined2.effectiveGasPrice);
    expect(networkFeeCheap).lt(networkFeeExpensive);
  });
  it("Should decrease strategy contract eth balance from previous claimRewards() calls when withdrawCvxAndRewards() is called", async function () {
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
    tx = await cvxStrategy.claimRewards();
    await tx.wait();
    const balanceBefore = await ethers.provider.getBalance(cvxStrategy.address);
    tx = await cvxStrategy.withdrawCvxAndRewards(0);
    const balanceAfter = await ethers.provider.getBalance(cvxStrategy.address);
    await tx.wait();
    expect(balanceAfter).lt(balanceBefore);
  });

  it("Should update rewardsClaimed & lastEpochFullyClaimed if claimRewards() is called for the first time in an epoch and a full epoch has passed since staking", async function () {
    let tx;
    const accounts = await ethers.getSigners();
    const vlCvxContract = new ethers.Contract(VL_CVX, vlCvxAbi, accounts[0]);
    const depositAmount = ethers.utils.parseEther("5");

    tx = await vlCvxContract.checkpointEpoch();
    await tx.wait();

    // open position
    tx = await cvxStrategy.stake({ value: depositAmount });
    await tx.wait();
    const currentEpochData = await vlCvxContract.epochs(
      await getCurrentEpoch()
    );
    const currentEpochStartTime = currentEpochData.date;

    const nextEpochStartTime = BigNumber.from(currentEpochStartTime).add(
      epochDuration
    );

    await time.increaseTo(nextEpochStartTime);

    await time.increase(epochDuration);
    // this is necessary in tests every time we have increased time past a new epoch
    tx = await vlCvxContract.checkpointEpoch();
    await tx.wait();

    const rewardsClaimedBefore = await cvxStrategy.rewardsClaimed(
      (await getCurrentEpoch()) - 1
    );
    const lastEpochFullyClaimedBefore =
      await cvxStrategy.lastEpochFullyClaimed();
    tx = await cvxStrategy.claimRewards();
    await tx.wait();
    const lastEpochFullyClaimedAfter =
      await cvxStrategy.lastEpochFullyClaimed();

    const rewardsClaimedAfter = await cvxStrategy.rewardsClaimed(
      (await getCurrentEpoch()) - 1
    );
    expect(lastEpochFullyClaimedAfter).gt(lastEpochFullyClaimedBefore);
    expect(rewardsClaimedAfter).gt(rewardsClaimedBefore);
  });
  it("Should not update rewardsClaimed & lastEpochFullyClaimed if claimRewards() is called more than once in the same epoch", async function () {
    let tx;
    const accounts = await ethers.getSigners();
    const vlCvxContract = new ethers.Contract(VL_CVX, vlCvxAbi, accounts[0]);
    const depositAmount = ethers.utils.parseEther("5");

    tx = await vlCvxContract.checkpointEpoch();
    await tx.wait();

    // open position
    tx = await cvxStrategy.stake({ value: depositAmount });
    await tx.wait();
    const currentEpochData = await vlCvxContract.epochs(
      await getCurrentEpoch()
    );
    const currentEpochStartTime = currentEpochData.date;

    const nextEpochStartTime = BigNumber.from(currentEpochStartTime).add(
      epochDuration
    );

    await time.increaseTo(nextEpochStartTime);

    await time.increase(epochDuration);
    // this is necessary in tests every time we have increased time past a new epoch
    tx = await vlCvxContract.checkpointEpoch();
    await tx.wait();

    tx = await cvxStrategy.claimRewards();
    await tx.wait();

    const rewardsClaimedBefore = await cvxStrategy.rewardsClaimed(
      (await getCurrentEpoch()) - 1
    );
    const lastEpochFullyClaimedBefore =
      await cvxStrategy.lastEpochFullyClaimed();
    tx = await cvxStrategy.claimRewards();
    await tx.wait();
    const lastEpochFullyClaimedAfter =
      await cvxStrategy.lastEpochFullyClaimed();

    const rewardsClaimedAfter = await cvxStrategy.rewardsClaimed(
      (await getCurrentEpoch()) - 1
    );
    expect(lastEpochFullyClaimedAfter).eq(lastEpochFullyClaimedBefore);
    expect(rewardsClaimedAfter).eq(rewardsClaimedBefore);
  });
  it("Should increase leftoverRewards when claimRewards is called before a full epoch has passed", async function () {
    let tx;
    const accounts = await ethers.getSigners();
    const vlCvxContract = new ethers.Contract(VL_CVX, vlCvxAbi, accounts[0]);
    const depositAmount = ethers.utils.parseEther("5");
    // open position
    tx = await cvxStrategy.stake({ value: depositAmount });
    // wait some time for rewards to acrue but not a full epoch
    await time.increase(60 * 60 * 24 * 3);
    // this is necessary in tests every time we have increased time past a new epoch
    tx = await vlCvxContract.checkpointEpoch();
    await tx.wait();

    const leftoverRewards0 = await cvxStrategy.leftoverRewards();
    tx = await cvxStrategy.claimRewards();
    await tx.wait();

    const leftoverRewards1 = await cvxStrategy.leftoverRewards();

    // wait some time for rewards to acrue but not a full epoch
    await time.increase(60 * 60 * 24 * 3);
    // this is necessary in tests every time we have increased time past a new epoch
    tx = await vlCvxContract.checkpointEpoch();
    await tx.wait();

    tx = await cvxStrategy.claimRewards();
    await tx.wait();

    const leftoverRewards2 = await cvxStrategy.leftoverRewards();

    expect(leftoverRewards0).lt(leftoverRewards1).lt(leftoverRewards2);
  });
  it("Should decrease leftoverRewards when claimRewards() is called late in an epoch and then early in the next", async function () {
    let tx;
    const depositAmount = ethers.utils.parseEther("5");

    tx = await extraRewardsStream.reset(
      60 * 60 * 24 * 7 * 16 * 16, // 16 lock periods (256 weeks) plenty of time to streaming rewards during all tests
      cvxStrategy.address
    );
    await tx.wait();

    // open position
    tx = await cvxStrategy.stake({ value: depositAmount });

    // increase to end of next epoch
    await incrementToBeginningOfNextEpoch();
    await incrementToEndOfCurrentEpoch();

    tx = await cvxStrategy.claimRewards();
    await tx.wait();
    const leftoverRewards0 = await cvxStrategy.leftoverRewards();

    await incrementToBeginningOfNextEpoch();

    tx = await cvxStrategy.claimRewards();
    await tx.wait();
    const leftoverRewards1 = await cvxStrategy.leftoverRewards();

    expect(leftoverRewards0).gt(leftoverRewards1);
  });
  it("Should increase leftoverRewards when claimRewards() is called early in an epoch and then late in the next", async function () {
    let tx;
    const accounts = await ethers.getSigners();
    const vlCvxContract = new ethers.Contract(VL_CVX, vlCvxAbi, accounts[0]);
    const depositAmount = ethers.utils.parseEther("5");
    // open position
    tx = await cvxStrategy.stake({ value: depositAmount });

    const currentEpochData = await vlCvxContract.epochs(
      await getCurrentEpoch()
    );
    const currentEpochStartTime = BigNumber.from(currentEpochData.date);
    const nextEpochStartTime = currentEpochStartTime.add(epochDuration);

    // increase time 1 hour
    await time.increase(60 * 60);
    // this is necessary in tests every time we have increased time past a new epoch
    tx = await vlCvxContract.checkpointEpoch();
    await tx.wait();

    tx = await cvxStrategy.claimRewards();
    await tx.wait();
    const leftoverRewards0 = await cvxStrategy.leftoverRewards();

    await time.increaseTo(nextEpochStartTime.add(60 * 60 * 24 * 6));
    // this is necessary in tests every time we have increased time past a new epoch
    tx = await vlCvxContract.checkpointEpoch();
    await tx.wait();

    tx = await cvxStrategy.claimRewards();
    await tx.wait();
    const leftoverRewards1 = await cvxStrategy.leftoverRewards();

    expect(leftoverRewards1).gt(leftoverRewards0);
  });
  it("Should award roughly same reward amount for 2 users that staked the same amount", async function () {
    let tx;
    const accounts = await ethers.getSigners();
    const vlCvxContract = new ethers.Contract(VL_CVX, vlCvxAbi, accounts[0]);
    const depositAmount = ethers.utils.parseEther("1");

    const cvxStrategy1 = cvxStrategy.connect(accounts[1]);
    const cvxStrategy2 = cvxStrategy.connect(accounts[2]);

    tx = await cvxStrategy1.stake({ value: depositAmount });
    await tx.wait();
    tx = await cvxStrategy2.stake({ value: depositAmount });
    await tx.wait();

    // close position (account 0)
    tx = await cvxStrategy1.unstake(false, 0);
    await tx.wait();
    tx = await cvxStrategy2.unstake(false, 1);
    await tx.wait();

    // wait 17 weeks
    await time.increase(60 * 60 * 24 * 7 * 17);
    // this is necessary in tests every time we have increased time past a new epoch
    tx = await vlCvxContract.checkpointEpoch();
    const balanceBefore1 = await ethers.provider.getBalance(
      accounts[1].address
    );

    tx = await cvxStrategy1.withdrawCvxAndRewards(0);
    const mined1 = await tx.wait();
    const networkFee1 = mined1.gasUsed.mul(mined1.effectiveGasPrice);
    const balanceAfter1 = await ethers.provider.getBalance(accounts[1].address);
    const ethReceived1 = balanceAfter1.sub(balanceBefore1).add(networkFee1);

    const balanceBefore2 = await ethers.provider.getBalance(
      accounts[2].address
    );
    tx = await cvxStrategy2.withdrawCvxAndRewards(1);
    const mined2 = await tx.wait();
    const networkFee2 = mined2.gasUsed.mul(mined2.effectiveGasPrice);
    const balanceAfter2 = await ethers.provider.getBalance(accounts[2].address);
    const ethReceived2 = balanceAfter2.sub(balanceBefore2).add(networkFee2);

    expect(within1Percent(ethReceived1, ethReceived2)).eq(true);
  });
  it("Should award roughly twice as much if a user stakes twice as much as another user", async function () {
    let tx;
    const accounts = await ethers.getSigners();
    const vlCvxContract = new ethers.Contract(VL_CVX, vlCvxAbi, accounts[0]);
    const depositAmount = ethers.utils.parseEther("1");

    const cvxStrategy1 = cvxStrategy.connect(accounts[1]);
    const cvxStrategy2 = cvxStrategy.connect(accounts[2]);

    tx = await cvxStrategy1.stake({ value: depositAmount });
    await tx.wait();
    tx = await cvxStrategy2.stake({ value: depositAmount.mul(2) });
    await tx.wait();

    // close position (account 0)
    tx = await cvxStrategy1.unstake(false, 0);
    await tx.wait();
    tx = await cvxStrategy2.unstake(false, 1);
    await tx.wait();

    // wait 17 weeks
    await time.increase(60 * 60 * 24 * 7 * 17);
    // this is necessary in tests every time we have increased time past a new epoch
    tx = await vlCvxContract.checkpointEpoch();
    const balanceBefore1 = await ethers.provider.getBalance(
      accounts[1].address
    );

    tx = await cvxStrategy1.withdrawCvxAndRewards(0);
    const mined1 = await tx.wait();
    const networkFee1 = mined1.gasUsed.mul(mined1.effectiveGasPrice);
    const balanceAfter1 = await ethers.provider.getBalance(accounts[1].address);
    const ethReceived1 = balanceAfter1.sub(balanceBefore1).add(networkFee1);

    const balanceBefore2 = await ethers.provider.getBalance(
      accounts[2].address
    );
    tx = await cvxStrategy2.withdrawCvxAndRewards(1);
    const mined2 = await tx.wait();
    const networkFee2 = mined2.gasUsed.mul(mined2.effectiveGasPrice);
    const balanceAfter2 = await ethers.provider.getBalance(accounts[2].address);
    const ethReceived2 = balanceAfter2.sub(balanceBefore2).add(networkFee2);

    expect(within1Percent(ethReceived1, ethReceived2.div(2))).eq(true);
  });
  it("Should be able to call claimRewards() multiple times or none and not effect rewards received from withdrawCvxAndRewards()", async function () {
    let tx;
    const accounts = await ethers.getSigners();
    const vlCvxContract = new ethers.Contract(VL_CVX, vlCvxAbi, accounts[0]);
    const depositAmount = ethers.utils.parseEther("5");

    tx = await vlCvxContract.checkpointEpoch();
    await tx.wait();

    // open position
    tx = await cvxStrategy.stake({ value: depositAmount });
    tx = await cvxStrategy.claimRewards();
    await tx.wait();
    tx = await cvxStrategy.claimRewards();
    await tx.wait();

    tx = await cvxStrategy.unstake(false, 0);
    await tx.wait();

    await time.increase(epochDuration * 17);
    // this is necessary in tests every time we have increased time past a new epoch
    tx = await vlCvxContract.checkpointEpoch();
    await tx.wait();

    const balanceBefore0 = await ethers.provider.getBalance(
      accounts[0].address
    );

    tx = await cvxStrategy.withdrawCvxAndRewards(0);
    const mined0 = await tx.wait();
    const networkFee0 = mined0.gasUsed.mul(mined0.effectiveGasPrice);
    const balanceAfter0 = await ethers.provider.getBalance(accounts[0].address);
    const ethReceived0 = balanceAfter0.sub(balanceBefore0).add(networkFee0);

    await snapshot.restore();

    tx = await vlCvxContract.checkpointEpoch();
    await tx.wait();

    // open position
    tx = await cvxStrategy.stake({ value: depositAmount });
    await tx.wait();

    tx = await cvxStrategy.unstake(false, 0);
    await tx.wait();

    await time.increase(epochDuration * 17);
    // this is necessary in tests every time we have increased time past a new epoch
    tx = await vlCvxContract.checkpointEpoch();
    await tx.wait();

    const balanceBefore1 = await ethers.provider.getBalance(
      accounts[0].address
    );

    tx = await cvxStrategy.withdrawCvxAndRewards(0);
    const mined1 = await tx.wait();
    const networkFee1 = mined1.gasUsed.mul(mined1.effectiveGasPrice);
    const balanceAfter1 = await ethers.provider.getBalance(accounts[0].address);
    const ethReceived1 = balanceAfter1.sub(balanceBefore1).add(networkFee1);

    expect(within1Percent(ethReceived0, ethReceived1)).eq(true);
  });

  it("Should award roughly double the rewards for staking twice as long", async function () {
    let tx;
    const accounts = await ethers.getSigners();
    const depositAmount = ethers.utils.parseEther("1");
    // this incremements us into a new year (assuming hardhat starts at block 17070569)
    // we do this to be sure it doesnt change years during the test which
    // can cause stakes to behave differently because they are using different asym ratios (crv emissions changes)
    tx = await extraRewardsStream.reset(
      60 * 60 * 24 * 7 * 16 * 16, // 16 lock periods (256 weeks) plenty of time to streaming rewards during all tests
      cvxStrategy.address
    );
    await tx.wait();

    const cvxStrategy1 = cvxStrategy.connect(accounts[1]);
    tx = await cvxStrategy1.stake({ value: depositAmount });
    tx = await cvxStrategy1.unstake(false, 0);
    await tx.wait();

    await incrementEpochs(17);

    const balanceBefore1 = await ethers.provider.getBalance(
      accounts[1].address
    );

    tx = await cvxStrategy1.withdrawCvxAndRewards(0);
    const mined1 = await tx.wait();

    const networkFee1 = mined1.gasUsed.mul(mined1.effectiveGasPrice);
    const balanceAfter1 = await ethers.provider.getBalance(accounts[1].address);
    const ethReceived1 = balanceAfter1.sub(balanceBefore1).add(networkFee1);

    const cvxStrategy2 = cvxStrategy.connect(accounts[2]);
    await incrementToBeginningOfNextEpoch();
    tx = await cvxStrategy2.stake({ value: depositAmount });
    await tx.wait();
    await incrementEpochs(17);
    tx = await cvxStrategy2.unstake(false, 1);
    await tx.wait();

    await incrementEpochs(17);

    const balanceBefore2 = await ethers.provider.getBalance(
      accounts[2].address
    );

    tx = await cvxStrategy2.withdrawCvxAndRewards(1);
    const mined2 = await tx.wait();
    const networkFee2 = mined2.gasUsed.mul(mined2.effectiveGasPrice);
    const balanceAfter2 = await ethers.provider.getBalance(accounts[2].address);
    const ethReceived2 = balanceAfter2.sub(balanceBefore2).add(networkFee2);
    expect(within1Pip(ethReceived1.mul(2), ethReceived2)).eq(true);
  });

  it("Should award the same amount for the same staked amount over the same amount of time even if claimRewards() is called multiple times at different times", async function () {
    // TODO
  });
  it("Should allow multiple overlapping users to stake & unstake at different times and receive fair rewards", async function () {
    // TODO
  });

  const within1Pip = (amount1: BigNumber, amount2: BigNumber) => {
    if (amount1.eq(amount2)) return true;
    return getDifferenceRatio(amount1, amount2).gt("10000");
  };

  const within1Percent = (amount1: BigNumber, amount2: BigNumber) => {
    if (amount1.eq(amount2)) return true;
    return getDifferenceRatio(amount1, amount2).gt("100");
  };

  // incrment time to end of current epoch
  const incrementToEndOfCurrentEpoch = async () => {
    const nextEpochStartTime = await getCurrentEpochEndTime();
    let tx;
    tx = await cvxStrategy.relockCvx();
    await tx.wait();
    await time.increaseTo(nextEpochStartTime.sub(15)); // 15 seconds before end of epoch
    const accounts = await ethers.getSigners();
    const vlCvxContract = new ethers.Contract(VL_CVX, vlCvxAbi, accounts[0]);
    tx = await vlCvxContract.checkpointEpoch();
  };

  // incrment time to next epoch start time
  const incrementToBeginningOfNextEpoch = async () => {
    const nextEpochStartTime = await getCurrentEpochEndTime();
    let tx;
    await time.increaseTo(nextEpochStartTime.add(15)); // 15 seconds after end of epoch
    const accounts = await ethers.getSigners();
    const vlCvxContract = new ethers.Contract(VL_CVX, vlCvxAbi, accounts[0]);
    tx = await vlCvxContract.checkpointEpoch();
    await tx.wait();
    tx = await cvxStrategy.relockCvx();
    await tx.wait();
    tx = await cvxStrategy.claimRewards();
    await tx.wait();
  };

  // incremement by X epochs (weeks) and claim reward each week
  // simulates real world behavior
  const incrementEpochs = async (count: number) => {
    const block = await ethers.provider.getBlock("latest");
    const blockTime = block.timestamp;
    for (let i = 0; i < count; i++) {
      const accounts = await ethers.getSigners();
      const vlCvxContract = new ethers.Contract(VL_CVX, vlCvxAbi, accounts[0]);
      await time.increaseTo(blockTime + (i + 1) * epochDuration);
      let tx;
      tx = await vlCvxContract.checkpointEpoch();
      await tx.wait();
      tx = await cvxStrategy.relockCvx();
      await tx.wait();
      tx = await cvxStrategy.claimRewards();
      await tx.wait();
    }
  };
});

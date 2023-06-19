import { ethers, network, waffle } from "hardhat";
import {
  CRV_POOL_FACTORY,
  CVX_ADDRESS,
  CVX_WHALE,
  VL_CVX,
  SNAPSHOT_DELEGATE_REGISTRY,
} from "./helpers/constants";
import ERC20 from "@openzeppelin/contracts/build/contracts/ERC20.json";
import {
  SnapshotRestorer,
  takeSnapshot,
  time,
} from "@nomicfoundation/hardhat-network-helpers";
import { expect } from "chai";
import { crvPoolFactoryAbi } from "./abi/crvPoolFactoryAbi";
import { BigNumber } from "ethers";
import { AfEth, SafEth, CvxStrategy } from "../typechain-types";
import { vlCvxAbi } from "./abi/vlCvxAbi";
import { crvPoolAbi } from "./abi/crvPoolAbi";
import { snapshotDelegationRegistryAbi } from "./abi/snapshotDelegationRegistry";
import { deployStrategyContract } from "./helpers/afEthTestHelpers";
import { within1Percent } from "./helpers/functions";

describe.skip("CvxStrategy", async function () {
  let afEth: AfEth;
  let safEth: SafEth;
  let cvxStrategy: CvxStrategy;
  let crvPool: any;
  let snapshot: SnapshotRestorer;

  const deployContracts = async () => {
    const deployResults = await deployStrategyContract();
    afEth = deployResults.afEth;
    safEth = deployResults.safEth;
    cvxStrategy = deployResults.cvxStrategy;
  };

  before(async () => {
    await network.provider.request({
      method: "hardhat_reset",
      params: [
        {
          forking: {
            jsonRpcUrl: process.env.MAINNET_URL,
            blockNumber: Number(process.env.BLOCK_NUMBER),
          },
        },
      ],
    });
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
    crvPool = new ethers.Contract(afEthCrvPoolAddress, crvPoolAbi, accounts[0]);
    const seedAmount = ethers.utils.parseEther("0.1");
    await cvxStrategy.updateCrvPool(afEthCrvPoolAddress, {
      value: seedAmount,
    });

    snapshot = await takeSnapshot();
  });

  it("Should seed CRV Pool", async function () {
    const crvPoolBalance0 = await crvPool.balances(0);
    expect(crvPoolBalance0).gt(0);
    const crvPoolBalance1 = await crvPool.balances(1);
    expect(crvPoolBalance1).gt(0);
    await snapshot.restore();
  });
  it("Should stake", async function () {
    await time.increase(15);
    const accounts = await ethers.getSigners();
    const depositAmount = ethers.utils.parseEther("5");
    const vlCvxContract = new ethers.Contract(VL_CVX, vlCvxAbi, accounts[0]);

    const stakeTx = await cvxStrategy.stake({ value: depositAmount });
    await stakeTx.wait();

    const vlCvxBalance = await vlCvxContract.lockedBalanceOf(
      cvxStrategy.address
    );

    expect(vlCvxBalance).eq(BigNumber.from("699096623630552985791"));

    // check crv liquidity pool
    const crvPoolAfEthAmount = await crvPool.balances(0);
    const crvPoolSafEthAmount = await crvPool.balances(1);

    expect(crvPoolAfEthAmount).eq("3668643452353053778");
    expect(crvPoolSafEthAmount).eq("3668643452353053778");

    // check position struct
    const positions = await cvxStrategy.positions(0);
    expect(positions.afEthAmount).eq(BigNumber.from("3568718952055251547"));
    expect(positions.curveBalance).eq(BigNumber.from("3568683264865730994"));
  });
  it("Should unstake", async function () {
    const accounts = await ethers.getSigners();
    const depositAmount = ethers.utils.parseEther("5");

    const ethBalanceBefore = await ethers.provider.getBalance(
      accounts[0].address
    );

    // check crv liquidity pool before staking
    const crvPoolAfEthAmountBefore = await crvPool.balances(0);
    const crvPoolSafEthAmountBefore = await crvPool.balances(1);
    expect(crvPoolAfEthAmountBefore).eq("3668643452353053778");
    expect(crvPoolSafEthAmountBefore).eq("3668643452353053778");

    const afEthStrategyBalanceBefore = await afEth.balanceOf(
      cvxStrategy.address
    );
    const safEthStrategyBalanceBefore = await safEth.balanceOf(
      cvxStrategy.address
    );

    const stakeTx = await cvxStrategy.stake({ value: depositAmount });
    await stakeTx.wait();

    // check crv liquidity pool after staking
    const crvPoolAfEthAmount = await crvPool.balances(0);
    const crvPoolSafEthAmount = await crvPool.balances(1);
    expect(crvPoolAfEthAmount).eq("7237341043084230561");
    expect(crvPoolSafEthAmount).eq("7237341043084230561");

    // check cvx locked positions
    let position1 = await cvxStrategy.cvxPositions(1);
    let unlockEpoch = position1.unlockEpoch;
    expect(unlockEpoch).eq(0);

    // check eth balance was deducted
    const ethBalanceDuring = await ethers.provider.getBalance(
      accounts[0].address
    );
    expect(ethBalanceBefore.sub(ethBalanceDuring)).gt(depositAmount);

    const unstakeTx = await cvxStrategy.unstake(false, 1);
    await unstakeTx.wait();

    // check crv liquidity pool after unstaking
    const crvPoolAfEthAmountAfter = await crvPool.balances(0);
    const crvPoolSafEthAmountAfter = await crvPool.balances(1);
    expect(crvPoolAfEthAmountAfter).eq("3668661542344294255");
    expect(crvPoolSafEthAmountAfter).eq("3668661542344294255");

    // verify no loss in crv pool after unstake
    expect(crvPoolAfEthAmountAfter).gte(crvPoolAfEthAmountBefore);
    expect(crvPoolSafEthAmountAfter).gte(crvPoolSafEthAmountAfter);

    // verify token balances do not change
    expect(afEthStrategyBalanceBefore).eq(
      await afEth.balanceOf(cvxStrategy.address)
    );
    expect(safEthStrategyBalanceBefore).eq(
      await safEth.balanceOf(cvxStrategy.address)
    );

    const ethBalanceAfter = await ethers.provider.getBalance(
      accounts[0].address
    );
    position1 = await cvxStrategy.cvxPositions(1);

    // check cvx locked positions to have unlock epoch
    unlockEpoch = position1.unlockEpoch;
    expect(unlockEpoch).gt(0);

    within1Percent(
      ethBalanceAfter.sub(ethBalanceDuring),
      depositAmount.mul(70).div(100)
    ); // 70% AAA ratio is in ETH, 30% will be in CVX
    await snapshot.restore();
  });
  it("Should unstake everything and still be able to stake", async function () {
    await time.increase(15);
    const depositAmount = ethers.utils.parseEther("5");

    const tx = await cvxStrategy.stake({ value: depositAmount });
    await tx.wait();

    const unstakeTx = await cvxStrategy.unstake(false, 0);
    await unstakeTx.wait();

    let crvPoolAfEthAmount = await crvPool.balances(0);
    let crvPoolSafEthAmount = await crvPool.balances(1);
    expect(crvPoolAfEthAmount).eq("99925472335372925");
    expect(crvPoolSafEthAmount).eq("99925472335372925");

    const stakeTx = await cvxStrategy.stake({ value: depositAmount });
    await stakeTx.wait();

    crvPoolAfEthAmount = await crvPool.balances(0);
    crvPoolSafEthAmount = await crvPool.balances(1);
    expect(crvPoolAfEthAmount).eq("3668643818239489942");
    expect(crvPoolSafEthAmount).eq("3668643818239489942");
    await snapshot.restore();
  });
  it("Shouldn't be able to unstake seed amount", async function () {
    await expect(cvxStrategy.unstake(false, 0)).to.be.revertedWith("NotOwner");
    await snapshot.restore();
  });
  it("Should fail to unstake if not owner", async function () {
    const accounts = await ethers.getSigners();
    const depositAmount = ethers.utils.parseEther("5");
    const stakeTx = await cvxStrategy.stake({ value: depositAmount });
    await stakeTx.wait();
    const userStrategySigner = cvxStrategy.connect(accounts[1]);

    await expect(userStrategySigner.unstake(false, 3)).to.be.revertedWith(
      "NotOwner"
    );
    await snapshot.restore();
  });
  it("Should trigger withdrawing of vlCVX rewards", async function () {
    const depositAmount = ethers.utils.parseEther("5");
    // impersonate an account that has rewards to withdraw at the current block
    await network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [CVX_WHALE],
    });
    const whaleSigner = await ethers.getSigner(CVX_WHALE);
    const cvx = new ethers.Contract(CVX_ADDRESS, ERC20.abi, whaleSigner);

    const cvxAmount = ethers.utils.parseEther("100");
    await cvx.transfer(cvxStrategy.address, cvxAmount);

    const stakeTx = await cvxStrategy.stake({ value: depositAmount });
    await stakeTx.wait();

    await time.increase(1000);

    const provider = waffle.provider;
    const startingBalance = await provider.getBalance(cvxStrategy.address);

    const tx2 = await cvxStrategy.claimRewards();
    await tx2.wait();
    const endingBalance = await provider.getBalance(cvxStrategy.address);

    expect(endingBalance.gt(startingBalance)).eq(true);
    await snapshot.restore();
  });
  it("Should return correct asym ratio values", async function () {
    // this test always needs to happen on the same block so values are consistent
    resetToBlock(16871866);
    await deployContracts();

    const r1 = await cvxStrategy.getAsymmetryRatio("150000000000000000");
    expect(r1).eq("298361212712598375"); // 29.94%

    const r2 = await cvxStrategy.getAsymmetryRatio("300000000000000000");
    expect(r2).eq("459596620403112401"); // 46.09%

    const r3 = await cvxStrategy.getAsymmetryRatio("500000000000000000");
    expect(r3).eq("586340851502091146"); // 58.76%
  });
  it("Should verify that vote delegation is set to the contract owner", async function () {
    const accounts = await ethers.getSigners();
    const snapshotDelegateRegistry = new ethers.Contract(
      SNAPSHOT_DELEGATE_REGISTRY,
      snapshotDelegationRegistryAbi,
      accounts[0]
    );

    const vlCvxVoteDelegationId =
      "0x6376782e65746800000000000000000000000000000000000000000000000000";
    const voter = await snapshotDelegateRegistry.delegation(
      cvxStrategy.address,
      vlCvxVoteDelegationId
    );

    expect(voter).eq(accounts[0].address);
    expect(voter).eq(await cvxStrategy.owner());
  });

  it("Should update emissions per year", async function () {
    const year0EmissionsBefore = await cvxStrategy.crvEmissionsPerYear(0);

    const tx = await cvxStrategy.setEmissionsPerYear(0, 1234567890);
    await tx.wait();
    const year0EmissionsAfter = await cvxStrategy.crvEmissionsPerYear(0);

    expect(year0EmissionsBefore).eq(BigNumber.from(0));
    expect(year0EmissionsAfter).eq(BigNumber.from(1234567890));
  });

  it("Should test crvPerCvx()", async function () {
    const crvPerCvx = await cvxStrategy.crvPerCvx();
    expect(crvPerCvx).eq("5638769963118260689");
  });
});

const resetToBlock = async (blockNumber: number) => {
  await network.provider.request({
    method: "hardhat_reset",
    params: [
      {
        forking: {
          jsonRpcUrl: process.env.MAINNET_URL,
          blockNumber,
        },
      },
    ],
  });
};

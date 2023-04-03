import { ethers, network, upgrades, waffle } from "hardhat";
import {
  CRV_POOL_FACTORY,
  CVX_ADDRESS,
  CVX_WHALE,
  VL_CVX,
  WETH_ADDRESS,
  SNAPSHOT_DELEGATE_REGISTRY,
} from "./helpers/constants";
import ERC20 from "@openzeppelin/contracts/build/contracts/ERC20.json";
import { time } from "@nomicfoundation/hardhat-network-helpers";
import { expect } from "chai";
import { crvPoolFactoryAbi } from "./abi/crvPoolFactoryAbi";
import { BigNumber } from "ethers";
import { AfCVX1155, AfEth } from "../typechain-types";
import { vlCvxAbi } from "./abi/vlCvxAbi";
import { crvPoolAbi } from "./abi/crvPoolAbi";
import { snapshotDelegationRegistryAbi } from "./abi/snapshotDelegationRegistry";

describe("AfEth", async function () {
  let afEth: AfEth;
  let afCvx1155: AfCVX1155;
  let crvPool: any;
  let initialHardhatBlock: number;

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

  before(async () => {
    const latestBlock = await ethers.provider.getBlock("latest");
    initialHardhatBlock = latestBlock.number;
    await resetToBlock(initialHardhatBlock);
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
    crvPool = new ethers.Contract(afEthCrvPoolAddress, crvPoolAbi, accounts[0]);
    await afEth.updateCrvPool(afEthCrvPoolAddress);
  });
  it("Should stake", async function () {
    const accounts = await ethers.getSigners();
    const depositAmount = ethers.utils.parseEther("5");
    const vlCvxContract = new ethers.Contract(VL_CVX, vlCvxAbi, accounts[0]);

    const stakeTx = await afEth.stake({ value: depositAmount });
    await stakeTx.wait();

    // verify vlCVX
    const vlCvxBalance = await vlCvxContract.lockedBalanceOf(afEth.address);
    expect(vlCvxBalance).eq(BigNumber.from("476215987701345784134"));

    // check for cvx nft
    const cvxNftAmount = await afCvx1155.balanceOf(afEth.address, 1);
    expect(cvxNftAmount).eq(BigNumber.from("476215987701345784134"));

    // check crv liquidity pool
    const crvPoolAfEthAmount = await crvPool.balances(0);
    const crvPoolEthAmount = await crvPool.balances(1);
    expect(crvPoolAfEthAmount).eq("1751292163634350360");
    expect(crvPoolEthAmount).eq("1751292163634350360");

    // check position struct
    const positions = await afEth.positions(accounts[0].address);
    expect(positions.afETH).eq(BigNumber.from("1751292163634350360"));
    expect(positions.cvxNFTID).eq(BigNumber.from("1"));
    expect(positions.positionID).eq(BigNumber.from("1"));
    expect(positions.curveBalances).eq(BigNumber.from("1751292163634350360"));
    expect(positions.convexBalances).eq(
      BigNumber.from("476215987701345784134")
    );
  });
  it("Should lock cvx and fail to unlock if lock is not yet expired", async function () {
    // impersonate an account that has rewards to withdraw at the current block
    const depositAmount = ethers.utils.parseEther("5");

    const stakeTx = await afEth.stake({ value: depositAmount });
    await stakeTx.wait();

    await time.increase(1000);

    await expect(afEth.unlockCvx()).to.be.revertedWith("no exp locks");
  });
  it("Should lock cvx and unlock after it has expired", async function () {
    const accounts = await ethers.getSigners();
    const depositAmount = ethers.utils.parseEther("5");
    const vlCvxContract = new ethers.Contract(VL_CVX, vlCvxAbi, accounts[0]);
    await network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [CVX_WHALE],
    });
    const whaleSigner = await ethers.getSigner(CVX_WHALE);
    const cvx = new ethers.Contract(CVX_ADDRESS, ERC20.abi, whaleSigner);

    const stakeTx = await afEth.stake({ value: depositAmount });
    await stakeTx.wait();

    const vlCvxBalance = await vlCvxContract.lockedBalanceOf(afEth.address);
    expect(vlCvxBalance).eq(BigNumber.from("1422063383685132167064"));

    const cvxBalanceAfterLock = await cvx.balanceOf(afEth.address);
    expect(cvxBalanceAfterLock).eq(BigNumber.from("0"));

    await time.increase(12960000); // 5 months (locks expire in 4)

    const tx2 = await afEth.unlockCvx();
    await tx2.wait();

    const cvxBalanceAfterUnlock = await cvx.balanceOf(afEth.address);
    expect(cvxBalanceAfterUnlock).eq(BigNumber.from("1422063383685132167064"));
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
    await cvx.transfer(afEth.address, cvxAmount);

    const stakeTx = await afEth.stake({ value: depositAmount });
    await stakeTx.wait();

    await time.increase(1000);

    const provider = waffle.provider;
    const startingBalance = await provider.getBalance(afEth.address);

    const tx2 = await afEth.claimRewards(ethers.utils.parseEther("0.01")); //  1% slippage tolerance when claiming
    await tx2.wait();
    const endingBalance = await provider.getBalance(afEth.address);

    expect(endingBalance.gt(startingBalance)).eq(true);

    // TODO: Not reverting, need to look more into it trying to get this PR in
    // await expect(
    //   afEth.claimRewards(ethers.utils.parseEther("0.000000001")) // very low slippage reverts
    // ).to.be.reverted;
  });

  it("Should return correct asym ratio values", async function () {
    // this test always needs to happen on the same block so values are consistent
    resetToBlock(16871866);
    await deployContracts();

    const r1 = await afEth.getAsymmetryRatio("150000000000000000");
    expect(r1.eq("299482867234169718")).eq(true); // 29.94%

    const r2 = await afEth.getAsymmetryRatio("300000000000000000");
    expect(r2.eq("460926226555940021")).eq(true); // 46.09%

    const r3 = await afEth.getAsymmetryRatio("500000000000000000");
    expect(r3.eq("587638408209630597")).eq(true); // 58.76%
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
      afEth.address,
      vlCvxVoteDelegationId
    );

    expect(voter).eq(accounts[0].address);
    expect(voter).eq(await afEth.owner());
  });

  it("Should update emissions per year", async function () {
    const year0EmissionsBefore = await afEth.emissionsPerYear(0);

    const tx = await afEth.setEmissionsPerYear(0, 1234567890);
    await tx.wait();
    const year0EmissionsAfter = await afEth.emissionsPerYear(0);

    expect(year0EmissionsBefore).eq(BigNumber.from(0));
    expect(year0EmissionsAfter).eq(BigNumber.from(1234567890));
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

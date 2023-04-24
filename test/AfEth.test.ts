import { ethers, network, upgrades, waffle } from "hardhat";
import {
  CRV_POOL_FACTORY,
  CVX_ADDRESS,
  CVX_WHALE,
  VL_CVX,
  SNAPSHOT_DELEGATE_REGISTRY,
} from "./helpers/constants";
import ERC20 from "@openzeppelin/contracts/build/contracts/ERC20.json";
import { time } from "@nomicfoundation/hardhat-network-helpers";
import { expect } from "chai";
import { crvPoolFactoryAbi } from "./abi/crvPoolFactoryAbi";
import { BigNumber } from "ethers";
import { AfEth, SafEth, CvxStrategy } from "../typechain-types";
import { vlCvxAbi } from "./abi/vlCvxAbi";
import { crvPoolAbi } from "./abi/crvPoolAbi";
import { snapshotDelegationRegistryAbi } from "./abi/snapshotDelegationRegistry";
import { deploySafEth } from "./helpers/upgradeHelpers";

describe("CvxStrategy", async function () {
  let afEth: AfEth;
  let safEth: SafEth;
  let cvxStrategy: CvxStrategy;
  let crvPool: any;

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
    await cvxStrategy.updateCrvPool(afEthCrvPoolAddress);
  });
  it("Should stake", async function () {
    const accounts = await ethers.getSigners();
    const depositAmount = ethers.utils.parseEther("5");
    const vlCvxContract = new ethers.Contract(VL_CVX, vlCvxAbi, accounts[0]);

    const stakeTx = await cvxStrategy.stake({ value: depositAmount });
    await stakeTx.wait();

    const vlCvxBalance = await vlCvxContract.lockedBalanceOf(
      cvxStrategy.address
    );
    const cvxBalance = "508354031579118550620";
    const crvPoolBalance = "1747636431031518475";

    expect(vlCvxBalance).eq(BigNumber.from(cvxBalance));

    // check crv liquidity pool
    const crvPoolAfEthAmount = await crvPool.balances(0);
    const crvPoolEthAmount = await crvPool.balances(1);
    expect(crvPoolAfEthAmount).eq(crvPoolBalance);
    expect(crvPoolEthAmount).eq(crvPoolBalance);

    // check position struct
    const positions = await cvxStrategy.positions(0);
    expect(positions.afEthAmount).eq(BigNumber.from(crvPoolBalance));
    expect(positions.curveBalance).eq(BigNumber.from(crvPoolBalance));
    expect(positions.convexBalance).eq(BigNumber.from(cvxBalance));
  });
  it("Should unstake", async function () {
    const accounts = await ethers.getSigners();
    const depositAmount = ethers.utils.parseEther("5");
    // const vlCvxContract = new ethers.Contract(VL_CVX, vlCvxAbi, accounts[0]);
    console.log(await ethers.provider.getBalance(accounts[0].address));

    const stakeTx = await cvxStrategy.stake({ value: depositAmount });
    await stakeTx.wait();
    console.log(await ethers.provider.getBalance(accounts[0].address));

    const unstakeTx = await cvxStrategy.unstake(false, 0);
    await unstakeTx.wait();
    console.log(await ethers.provider.getBalance(accounts[0].address));

    // TODO: check every scenario for unstaking
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

    const tx2 = await cvxStrategy.claimRewards(ethers.utils.parseEther("0.01")); //  1% slippage tolerance when claiming
    await tx2.wait();
    const endingBalance = await provider.getBalance(cvxStrategy.address);

    expect(endingBalance.gt(startingBalance)).eq(true);

    await expect(
      cvxStrategy.claimRewards(ethers.utils.parseEther("0.000000001")) // very low slippage reverts
    ).to.be.reverted;
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

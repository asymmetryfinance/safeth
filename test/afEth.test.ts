import { ethers, network, upgrades, waffle } from "hardhat";
import {
  CRV_POOL_FACTORY,
  CVX_ADDRESS,
  CVX_WHALE,
  WETH_ADDRESS,
} from "./helpers/constants";
import ERC20 from "@openzeppelin/contracts/build/contracts/ERC20.json";
import { time } from "@nomicfoundation/hardhat-network-helpers";
import { expect } from "chai";
import { crvPoolAbi } from "./abi/crvPoolAbi";
import { BigNumber } from "ethers";
import { AfEth } from "../typechain-types";

describe.only("AfEth", async function () {
  let afEth: AfEth;

  before(async () => {
    const accounts = await ethers.getSigners();

    const AfEth = await ethers.getContractFactory("AfEth");
    // The address params dont matter for this test.
    const address = "0x0000000000000000000000000000000000000000";
    afEth = (await upgrades.deployProxy(AfEth, [
      address,
      address,
      address,
      address,
      address,
      "Asymmetry Finance ETH",
      "afETh",
    ])) as AfEth;
    await afEth.deployed();

    const crvPool = new ethers.Contract(
      CRV_POOL_FACTORY,
      crvPoolAbi,
      accounts[0]
    );

    const deployCrv = await crvPool.deploy_pool(
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

    console.log("afEthCrvPoolAddress", afEthCrvPoolAddress);
  });

  it("Should trigger withdrawing of vlCVX rewards", async function () {
    const AfEth = await ethers.getContractFactory("AfEth");
    // The address params dont matter for this test.
    const address = "0x0000000000000000000000000000000000000000";
    const afEth = await AfEth.deploy(address, address, address, address);
    await afEth.deployed();
    // impersonate an account that has rewards to withdraw at the current block
    await network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [CVX_WHALE],
    });
    const whaleSigner = await ethers.getSigner(CVX_WHALE);
    const cvx = new ethers.Contract(CVX_ADDRESS, ERC20.abi, whaleSigner);

    const cvxAmount = ethers.utils.parseEther("100");
    await cvx.transfer(afEth.address, cvxAmount);

    const tx1 = await afEth.lockCvx(cvxAmount);
    await tx1.wait();
    await time.increase(1000);

    const provider = waffle.provider;
    const startingBalance = await provider.getBalance(afEth.address);

    const tx2 = await afEth.claimRewards(ethers.utils.parseEther("0.01")); //  1% slippage tolerance when claiming
    await tx2.wait();
    const endingBalance = await provider.getBalance(afEth.address);

    expect(endingBalance.gt(startingBalance)).eq(true);

    await expect(
      afEth.claimRewards(ethers.utils.parseEther("0.0000001")) // very low slippage reverts
    ).to.be.reverted;
  });

  it("Should return correct asym ratio values", async function () {
    // this test always needs to happen on the same block so values are consistent
    resetToBlock(16871866);

    const AfEth = await ethers.getContractFactory("AfEth");
    // The address params dont matter for this test.
    const address = "0x0000000000000000000000000000000000000000";
    const afEth = await AfEth.deploy(address, address, address, address);
    await afEth.deployed();

    const r1 = await afEth.getAsymmetryRatio("150000000000000000");
    expect(r1.eq("299482867234169718")).eq(true); // 29.94%

    const r2 = await afEth.getAsymmetryRatio("300000000000000000");
    expect(r2.eq("460926226555940021")).eq(true); // 46.09%

    const r3 = await afEth.getAsymmetryRatio("500000000000000000");
    expect(r3.eq("587638408209630597")).eq(true); // 56.76%
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

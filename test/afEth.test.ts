import { ethers, network } from "hardhat";
import { FXS_ADDRESS } from "./helpers/constants";
import ERC20 from "@openzeppelin/contracts/build/contracts/ERC20.json";

describe.only("AfEth", async function () {
  it("Should trigger withdrawing of vlCVX rewards", async function () {
    const AfEth = await ethers.getContractFactory("AfEth");

    // The address params dont matter for this test.
    const address = "0x0000000000000000000000000000000000000000";
    const afEth = await AfEth.deploy(address, address, address, address);
    await afEth.deployed();

    console.log("deployed", afEth.address);

    console.log("block is", await ethers.provider.getBlock("latest"));

    // impersonate an account that has rewards to withdraw at the current block
    await network.provider.request({
      method: "hardhat_impersonateAccount",
      params: ["0x8a65ac0e23f31979db06ec62af62b132a6df4741"],
    });

    const rewardSigner = await ethers.getSigner(
      "0x8a65ac0e23f31979db06ec62af62b132a6df4741"
    );

    // This was derived from looking at etherscan claimRewards() transactions.
    // I couldnt get it working from solidity but this is a start.
    const data =
      "0x5a7b87f20000000000000000000000000000000000000000000000000000000000000120000000000000000000000000000000000000000000000000000000000000014000000000000000000000000000000000000000000000000000000000000001600000000000000000000000000000000000000000000000000000000000000180000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";
    const tx = await rewardSigner.sendTransaction({
      to: "0x3f29cb4111cbda8081642da1f75b3c12decf2516", // ClaimZap contract
      data,
    });
    const mined = await tx.wait();
    console.log("mined", mined);

    const accounts = await ethers.getSigners();

    const fxs = new ethers.Contract(FXS_ADDRESS, ERC20.abi, accounts[0]);

    const fxsBalance = await fxs.balanceOf(
      "0x8a65ac0e23f31979db06ec62af62b132a6df4741"
    );

    console.log("fxsBalance", fxsBalance);
  });
});

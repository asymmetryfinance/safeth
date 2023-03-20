import { ethers, network } from "hardhat";
import { FXS_ADDRESS } from "./helpers/constants";
import ERC20 from "@openzeppelin/contracts/build/contracts/ERC20.json";
import { claimZapAbi } from "./abi/claimZapAbi";

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

    const accounts = await ethers.getSigners();

    const claimZap = new ethers.Contract(
      "0x3f29cb4111cbda8081642da1f75b3c12decf2516",
      claimZapAbi,
      rewardSigner
    );
    const result = await claimZap.claimRewards([], [], [], [], 0, 0, 0, 0, 8);
    const mined = await result.wait();
    console.log('mined is', mined);

    const fxs = new ethers.Contract(FXS_ADDRESS, ERC20.abi, accounts[0]);
    const fxsBalance = await fxs.balanceOf(
      "0x8a65ac0e23f31979db06ec62af62b132a6df4741"
    );
    console.log("fxsBalance", fxsBalance);
  });
});

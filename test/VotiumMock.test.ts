import { ethers, network, upgrades } from "hardhat";
import { VotiumPosition } from "../typechain-types";
import { CVX_ADDRESS, CVX_WHALE } from "./helpers/constants";
import ERC20 from "@openzeppelin/contracts/build/contracts/ERC20.json";
import { expect } from "chai";

describe.skip("VotiumPosition", async function () {
  let votiumMock: VotiumPosition;

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
    const votiumMockFactory = await ethers.getContractFactory("VotiumPosition");
    votiumMock = (await upgrades.deployProxy(
      votiumMockFactory
    )) as VotiumPosition;
  });

  it("Should set delegate and lock cvx", async function () {
    await network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [CVX_WHALE],
    });
    const whaleSigner = await ethers.getSigner(CVX_WHALE);
    const cvx = new ethers.Contract(CVX_ADDRESS, ERC20.abi, whaleSigner);
    const cvxAmount = ethers.utils.parseEther("100");
    await cvx.transfer(votiumMock.address, cvxAmount);

    await votiumMock.setDelegate();
    await votiumMock.lockCvx(cvxAmount);
  });
  it("Should have owner be admin account", async function () {
    const accounts = await ethers.getSigners();
    const owner = await votiumMock.owner();
    expect(owner).to.equal(accounts[0].address);
  });
});

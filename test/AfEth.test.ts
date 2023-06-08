import { ethers, network } from "hardhat";
import { CRV_POOL_FACTORY } from "./helpers/constants";
import { crvPoolFactoryAbi } from "./abi/crvPoolFactoryAbi";
import { BigNumber } from "ethers";
import { AfEth, SafEth, CvxStrategy } from "../typechain-types";
import { deployStrategyContract } from "./helpers/afEthTestHelpers";

describe.only("AfEth (CvxStrategy)", async function () {
  let afEth: AfEth;
  let safEth: SafEth;
  let cvxStrategy: CvxStrategy;

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
    const seedAmount = ethers.utils.parseEther("0.1");
    await cvxStrategy.updateCrvPool(afEthCrvPoolAddress, {
      value: seedAmount,
    });
  });
  it.only("Should stake", async function () {
    const depositAmount = ethers.utils.parseEther("5");

    console.log(
      "block time 1 is",
      (await ethers.provider.getBlock()).timestamp
    );
    const stakeTx = await cvxStrategy.stake({ value: depositAmount });
    await stakeTx.wait();
    console.log(
      "block time 2 is",
      (await ethers.provider.getBlock()).timestamp
    );
  });
});

import { ethers, getNamedAccounts, network } from "hardhat";
import { expect } from "chai";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { BigNumber, Contract, Signer, utils } from "ethers";

import ERC20 from "@openzeppelin/contracts/build/contracts/ERC20.json";
import {
  RETH_WHALE,
  SFRAXETH_ADDRESS,
  SFRAXETH_WHALE,
  WSTETH_ADRESS,
  WSTETH_WHALE,
} from "./constants";
import { AfETH, AfStrategy } from "../typechain-types";
import { sfrxEthAbi } from "./abi/sfrxEthAbi";
import { balWeightedPoolFactoryAbi } from "./abi/balWeightedPoolFactoryAbi";
import { balWeightedPoolAbi } from "./abi/balWeightedPoolAbi";
import { balVaultAbi } from "./abi/balVaultAbi";

import { WeightedPoolEncoder } from "@balancer-labs/balancer-js";

describe("Af Strategy", function () {
  let accounts: SignerWithAddress[];
  let afEth: AfETH;
  let strategy: AfStrategy;
  let aliceSigner: Signer;
  let wstEth: Contract;
  let rEth: Contract;
  let sfrxeth: Contract;

  beforeEach(async () => {
    const { admin, alice } = await getNamedAccounts();
    accounts = await ethers.getSigners();

    const afETHDeployment = await ethers.getContractFactory("afETH");
    afEth = (await afETHDeployment.deploy(
      "Asymmetry Finance ETH",
      "afETH"
    )) as AfETH;

    const strategyDeployment = await ethers.getContractFactory("AfStrategy");
    strategy = (await strategyDeployment.deploy(afEth.address)) as AfStrategy;
    const rethAddress = await strategy.rethAddress();

    await afEth.setMinter(strategy.address);

    // initialize derivative contracts
    wstEth = new ethers.Contract(WSTETH_ADRESS, ERC20.abi, accounts[0]);
    rEth = new ethers.Contract(rethAddress, ERC20.abi, accounts[0]);
    sfrxeth = new ethers.Contract(SFRAXETH_ADDRESS, ERC20.abi, accounts[0]);

    // signing defaults to admin, use this to sign for other wallets
    // you can add and name wallets in hardhat.config.ts
    aliceSigner = accounts.find(
      (account) => account.address === alice
    ) as Signer;

    // Send wstETH derivative to admin
    await network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [WSTETH_WHALE],
    });
    let transferAmount = ethers.utils.parseEther("50");
    let whaleSigner = await ethers.getSigner(WSTETH_WHALE);
    const wstEthWhale = wstEth.connect(whaleSigner);
    await wstEthWhale.transfer(admin, transferAmount);
    const wstEthBalance = await wstEth.balanceOf(admin);
    expect(BigNumber.from(wstEthBalance)).gte(transferAmount);

    // Send rETH derivative to admin
    await network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [RETH_WHALE],
    });
    transferAmount = ethers.utils.parseEther("50");
    whaleSigner = await ethers.getSigner(RETH_WHALE);
    const rEthWhale = rEth.connect(whaleSigner);
    await rEthWhale.transfer(admin, transferAmount);
    const rEthBalance = await rEth.balanceOf(admin);
    expect(BigNumber.from(rEthBalance)).gte(transferAmount);

    // Send sfrxeth derivative to admin
    await network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [SFRAXETH_WHALE],
    });
    transferAmount = ethers.utils.parseEther("50");
    whaleSigner = await ethers.getSigner(SFRAXETH_WHALE);
    const sfrxethWhale = sfrxeth.connect(whaleSigner);
    await sfrxethWhale.transfer(admin, transferAmount);
  });

  describe("Deposit/Withdraw", function () {
    it("Should deposit", async () => {
      const aliceStrategySigner = strategy.connect(aliceSigner as Signer);
      const depositAmount = ethers.utils.parseEther("10");
      await aliceStrategySigner.stake({ value: depositAmount });

      // TODO: verify stake
      //   const sfraxRedeem = await sfraxEthVault.maxRedeem(strategy.address);
      //   expect(sfraxRedeem).eq("3285663926776079232");
      //   const rEthRedeem = await rEthVault.maxRedeem(strategy.address);
      //   expect(rEthRedeem).eq("3125945585858020916");
      //   const wstEthRedeem = await wstEthVault.maxRedeem(strategy.address);
      //   expect(wstEthRedeem).eq("3018933015541626171");
    });
    it("Should withdraw", async () => {
      const aliceStrategySigner = strategy.connect(aliceSigner as Signer);
      const depositAmount = ethers.utils.parseEther("2");
      await aliceStrategySigner.stake({ value: depositAmount });

      await aliceStrategySigner.unstake();
    });
  });

  describe("Prices", async () => {
    it("Should get rethPrice which is higher than eth price", async () => {
      const oneReth = BigNumber.from("1000000000000000000"); // 10^18 wei
      const oneEth = BigNumber.from("1000000000000000000"); // 10^18 wei
      const rethPrice = await strategy.rethPrice(oneReth);
      expect(rethPrice.gt(oneEth)).eq(true);
    });

    it("Should get sfrxEthPrice which is higher than eth price", async () => {
      const oneSfrxEth = BigNumber.from("1000000000000000000"); // 10^18 wei
      const oneEth = BigNumber.from("1000000000000000000"); // 10^18 wei
      const sfrxPrice = await strategy.sfrxEthPrice(oneSfrxEth);
      expect(sfrxPrice.gt(oneEth)).eq(true);
    });
  });

  describe("Frax", async () => {
    it("Should deposit eth in exchange for the expected amount of sfrx", async () => {
      const aliceStrategySigner = strategy.connect(aliceSigner as Signer);

      const oneEth = BigNumber.from("1000000000000000000"); // 10^18 wei

      const sfrxContract = new ethers.Contract(
        SFRAXETH_ADDRESS,
        sfrxEthAbi,
        accounts[0]
      );
      const expectedSfrxOutput = await sfrxContract.convertToShares(oneEth);

      await aliceStrategySigner.depositSfrax(oneEth, {
        value: oneEth,
      });

      const sfrxBalance = await sfrxContract.balanceOf(strategy.address);

      // how different is the expected amount vs received amount
      // its always slightly off but only by a tiny amount
      const sfrxBalanceDiff = expectedSfrxOutput.sub(sfrxBalance);

      // ratio of sfrxBalanceDiff to our original balance
      const sfrxBalanceDiffRatio = sfrxBalance.div(sfrxBalanceDiff);

      // check to be sure the difference percent is within 0.00001 of our expected output ( ratio is > 100,000)
      expect(sfrxBalanceDiffRatio.gt("100000")).eq(true);

      // We should always receive less sfrx out than eth in because the price is always rising
      expect(sfrxBalance.lt(oneEth)).eq(true);
    });
  });

  describe.only("Balancer Deployment Tests", async () => {
    it("Should create a new weighted balancer pool with sfraxeth, reth and wsteth and deposit to that pool. also do a deposit", async () => {
      // https://docs.balancer.fi/reference/contracts/deployment-addresses/mainnet.html
      const FACTORY_ADDRESS = "0x5Dd94Da3644DDD055fcf6B3E1aa310Bb7801EB8b";
      const BALANCER_VAULT = "0xBA12222222228d8Ba445958a75a0704d566BF2C8";

      const RETH_ADDRESS = await strategy.rethAddress();

      const weightedPoolFactory = new ethers.Contract(
        FACTORY_ADDRESS,
        balWeightedPoolFactoryAbi,
        accounts[0]
      );

      const txResult = await weightedPoolFactory.create(
        "Test Pool", // name
        "TP", // symbol
        [WSTETH_ADRESS, SFRAXETH_ADDRESS, RETH_ADDRESS], // these must be in sorted order
        ["333333333333333333", "333333333333333333", "333333333333333334"], // weights
        [WSTETH_ADRESS, SFRAXETH_ADDRESS, RETH_ADDRESS],
        "2500000000000000", // fee. I think this is 0.25%
        accounts[0].address // owner
      );

      const txReceipt = await (
        accounts[0] as any
      ).provider.getTransactionReceipt(txResult.hash);

      const topic = txReceipt.logs[6].topics[1];
      const newPoolAddress =
        "0x" + topic.slice(topic.length - 40, topic.length);

      const weightedPool = new ethers.Contract(
        newPoolAddress,
        balWeightedPoolAbi,
        accounts[0]
      );

      const poolId = await weightedPool.getPoolId();

      console.log("poolId: ", poolId);

      const balancerVault = new ethers.Contract(
        BALANCER_VAULT,
        balVaultAbi,
        accounts[0]
      );

      const abi = ethers.utils.defaultAbiCoder;

      // ***********
      // I think this is whats wrong. I cant get this function to generate the same params as other txs I see on chain
      // ***********
      // const params = abi.encode(
      //   ["uint", "uint256[]"],
      //   ["1", ["0", "82500000000000000"]]
      // );

      const amountsIn = [ethers.utils.parseEther("50"), ethers.utils.parseEther("50"), ethers.utils.parseEther("50")];

      const params2 = WeightedPoolEncoder.joinInit(amountsIn);

      console.log('params2', params2)

      const params = abi.encode(
        ["uint256", "uint256[]"],
        [
          1,
          [
            ethers.utils.parseEther("50"),
            ethers.utils.parseEther("50"),
            ethers.utils.parseEther("50"),
          ],
        ]
      );

      console.log("params is", params);

      // await rEth.approve(BALANCER_VAULT, ethers.utils.parseEther("50"));
      // await wstEth.approve(BALANCER_VAULT, ethers.utils.parseEther("50"));

      // await sfrxeth.approve(BALANCER_VAULT, ethers.utils.parseEther("50"));

      console.log("rEth balance", await rEth.balanceOf(accounts[0].address));
      console.log(
        "wstEth balance",
        await wstEth.balanceOf(accounts[0].address)
      );
      console.log(
        "sfrxeth balance",
        await sfrxeth.balanceOf(accounts[0].address)
      );

      console.log(
        "Join Pool Params",
        poolId,
        accounts[0].address,
        accounts[0].address,
        {
          assets: [WSTETH_ADRESS, SFRAXETH_ADDRESS, RETH_ADDRESS],
          maxAmountsIn: [
            ethers.utils.parseEther("50"),
            ethers.utils.parseEther("50"),
            ethers.utils.parseEther("50"),
          ],
          userData: params,
          fromInternalBalance: false,
        }
      );
      const result = await balancerVault.joinPool(
        poolId,
        accounts[0].address,
        accounts[0].address,
        [
          [WSTETH_ADRESS, SFRAXETH_ADDRESS, RETH_ADDRESS],
          [
            ethers.utils.parseEther("50"),
            ethers.utils.parseEther("50"),
            ethers.utils.parseEther("50"),
          ],
          params,
          false,
        ]
      );

      console.log("result is", result);
    });
  });
});

import { ethers, getNamedAccounts, network, upgrades } from "hardhat";
import { expect } from "chai";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { BigNumber, Contract, Signer } from "ethers";
import ERC20 from "@openzeppelin/contracts/build/contracts/ERC20.json";
import {
  CRV_POOL_FACTORY,
  RETH_ADDRESS,
  RETH_WHALE,
  ROCKET_STORAGE_ADDRESS,
  WETH_ADDRESS,
  WSTETH_ADRESS,
  WSTETH_WHALE,
} from "./constants";
import {
  AfBundle1155,
  AfCVX1155,
  AfETH,
  AsymmetryStrategy,
  Vault,
} from "../typechain-types";
import { crvPoolAbi } from "./abi/crvPoolAbi";
import { crvTokenAbi } from "./abi/crvTokenAbi";

describe("Asymmetry Finance Strategy", function () {
  let accounts: SignerWithAddress[];
  let afEth: AfETH;
  let rEthVault: Vault;
  let strategy: AsymmetryStrategy;
  let afCvx1155: AfCVX1155;
  let afBundle1155: AfBundle1155;
  let aliceSigner: Signer;
  let wstEth: Contract;
  let wstEthVault: Vault;
  let rEth: Contract;
  let rEThVault: Vault;

  beforeEach(async () => {
    const { admin, alice } = await getNamedAccounts();
    accounts = await ethers.getSigners();

    // Deploy contracts and store them in the variables above

    const afCVX1155Deployment = await ethers.getContractFactory("afCVX1155");
    afCvx1155 = (await afCVX1155Deployment.deploy()) as AfCVX1155;

    const afBundle1155Deployment = await ethers.getContractFactory(
      "afBundle1155"
    );
    afBundle1155 = (await afBundle1155Deployment.deploy()) as AfBundle1155;

    const afETHDeployment = await ethers.getContractFactory("afETH");
    afEth = (await afETHDeployment.deploy(
      "Asymmetry Finance ETH",
      "afETH"
    )) as AfETH;
    const crvPool = new ethers.Contract(
      CRV_POOL_FACTORY,
      crvPoolAbi,
      accounts[0]
    ) as any;
    const signer = await ethers.getSigner(crvPool.address);
    const count = await signer.getTransactionCount();
    const address = ethers.utils.getContractAddress({
      from: crvPool.address,
      nonce: count + 1,
    });
    console.log("address", address);

    const address2 = ethers.utils.getContractAddress({
      from: crvPool.address,
      nonce: count,
    });
    console.log("address token", address2);

    console.log("afeth add", afEth.address);
    console.log("account", accounts[0].address);
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
      BigNumber.from("963627746451487500")
    );

    // await network.provider.request({ method: "evm_mine", params: [] });
    // await network.provider.request({ method: "evm_mine", params: [] });
    // await network.provider.request({ method: "evm_mine", params: [] });
    // await network.provider.request({ method: "evm_mine", params: [] });
    // await network.provider.request({ method: "evm_mine", params: [] });
    // await network.provider.request({ method: "evm_mine", params: [] });

    // const crvPoolReceipt = await deployCrv.wait();
    // console.log("crvPoolReceipt logs", await crvPoolReceipt?.events);
    const pool = await crvPool["find_pool_for_coins(address,address)"](afEth.address, WETH_ADDRESS)
      console.log('pool', pool)
    const mint = new Contract(
      address2,
      ['function minter() external view returns (address)'],
      accounts[0]
    );
    console.log("mint", await mint.minter());
    console.log("address", address);


    // const crvToken = await crvPoolReceipt?.events?.[0]?.address
    // console.log('crveToken', crvToken)

    // const crvAddress = new ethers.Contract(crvToken,  crvTokenAbi , accounts[0])
    // const minter = await crvAddress.minter()
    // console.log('minter', minter)
    //   const logs = await ethers.provider.getLogs({
    //     address: "0xF18056Bbd320E96A48e3Fbf8bC061322531aac99",
    //     topics: ["0x0394cb40d7dbe28dad1d4ee890bdd35bbb0d89e17924a80a542535e83d54ba14"]
    // });
    // console.log('logs', logs)

    const strategyDeployment = await ethers.getContractFactory(
      "AsymmetryStrategy"
    );
    strategy = (await strategyDeployment.deploy(
      afEth.address,
      ROCKET_STORAGE_ADDRESS,
      afCvx1155.address,
      afBundle1155.address,
      address
    )) as AsymmetryStrategy;

    const VaultDeployment = await ethers.getContractFactory("Vault");
    rEthVault = (await VaultDeployment.deploy(
      RETH_ADDRESS,
      "Asymmetry Rocket Pool Vault",
      "afrEthVault"
    )) as Vault;
    wstEthVault = (await VaultDeployment.deploy(
      WSTETH_ADRESS,
      "Asymmetry Lido Vault",
      "afwstEthETH"
    )) as Vault;

    await strategy.setVault(RETH_ADDRESS, rEthVault.address);
    await strategy.setVault(WSTETH_ADRESS, wstEthVault.address);

    await afEth.initialize(strategy.address);
    await afCvx1155.initialize(strategy.address);
    await afBundle1155.initialize(strategy.address);

    // initialize derivative contracts
    wstEth = new ethers.Contract(WSTETH_ADRESS, ERC20.abi, accounts[0]);
    rEth = new ethers.Contract(RETH_ADDRESS, ERC20.abi, accounts[0]);

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
    let transferAmount = ethers.utils.parseEther("1000");
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
    transferAmount = ethers.utils.parseEther("1000");
    whaleSigner = await ethers.getSigner(RETH_WHALE);
    const rEthWhale = rEth.connect(whaleSigner);
    await rEthWhale.transfer(admin, transferAmount);
    const rEthBalance = await rEth.balanceOf(admin);
    expect(BigNumber.from(rEthBalance)).gte(transferAmount);
  });

  describe("initialize", function () {
    it("Should have correct name", async () => {
      expect(await strategy.getName()).eq("AsymmetryFinance Strategy");
    });
  });

  describe("deposit/withdraw", function () {
    it("Should deposit", async () => {
      const aliceStrategySigner = strategy.connect(aliceSigner as Signer);
      const depositAmount = ethers.utils.parseEther("48");
      await aliceStrategySigner.stake({ value: depositAmount });
      const rEthRedeem = await rEthVault.maxRedeem(strategy.address);
      expect(rEthRedeem).eq("7929950091941014379");
      const wstEthRedeem = await wstEthVault.maxRedeem(strategy.address);
      expect(wstEthRedeem).eq("7635498782886781147");

      // Old code written in Solidity
      //         console.log("Alice depositing 48ETH into vault...");
      //         vm.prank(address(alice));
      //         vault._deposit{value: 48e18}();
      //         uint256 aliceMaxRedeem = vault.maxRedeem(address(alice));
      //         assertEq(aliceMaxRedeem, 48e18);
      //         address pool = strategy.getPool();
      //         assertEq(IERC20(pool).balanceOf(address(strategy)), 32e18);
      //         console.log("Alice withdrawing 48ETH from vault...");
      //         vm.warp(block.timestamp + 1500000);
      //         vm.prank(alice);
      //         vault.withdraw(48e18, msg.sender, msg.sender, true);
      //         assertEq(IERC20(pool).balanceOf(address(strategy)), 0);
      //         assertEq(IERC20(address(grETHToken)).balanceOf(address(strategy)), 0);
    });
  });
});

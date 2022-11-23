import { ethers, getNamedAccounts, network, upgrades } from 'hardhat'
import { expect } from 'chai'
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'
import { BigNumber, Contract, Signer } from 'ethers'
import ERC20 from '@openzeppelin/contracts/build/contracts/ERC20.json'
import {
  RETH_ADDRESS,
  RETH_WHALE,
  ROCKET_STORAGE_ADDRESS,
  WETH_ADDRESS,
  WSTETH_ADRESS,
  WSTETH_WHALE,
} from './constants'
import {
  Controller,
  AfBundle1155,
  AfCVX1155,
  AfETH,
  StrategyAsymmetryFinance,
  Vault,
} from '../typechain-types'

describe('Asymmetry Finance Strategy', function () {
  let accounts: SignerWithAddress[]
  let afEth: AfETH
  let controller: Controller
  let rEthVault: Vault
  let strategy: StrategyAsymmetryFinance
  let afCvx1155: AfCVX1155
  let afBundle1155: AfBundle1155
  let aliceSigner: Signer
  let wstEth: Contract
  let rEth: Contract

  beforeEach(async () => {
    const { admin, alice } = await getNamedAccounts()
    accounts = await ethers.getSigners()

    // Deploy contracts and store them in the variables above
    const afCVX1155Deployment = await ethers.getContractFactory('afCVX1155')
    afCvx1155 = (await afCVX1155Deployment.deploy()) as AfCVX1155

    const afBundle1155Deployment = await ethers.getContractFactory('afBundle1155')
    afBundle1155 = (await afBundle1155Deployment.deploy()) as AfBundle1155

    const controllerDeployment = await ethers.getContractFactory('Controller')
    controller = (await controllerDeployment.deploy()) as Controller

    const rEthVaultDeployment = await ethers.getContractFactory('Vault')
    rEthVault = (await rEthVaultDeployment.deploy(
      RETH_ADDRESS,
      'AF rETH Vault',
      'vrETH',
      admin,
      controller.address,
    )) as Vault

    const strategyDeployment = await ethers.getContractFactory('StrategyAsymmetryFinance')
    strategy = (await strategyDeployment.deploy(
      RETH_ADDRESS,
      controller.address,
      ROCKET_STORAGE_ADDRESS,
      afCvx1155.address,
      afBundle1155.address,
    )) as StrategyAsymmetryFinance

    const afETHDeployment = await ethers.getContractFactory('afETH')
    afEth = (await afETHDeployment.deploy(
      strategy.address,
      'Asymmetry Finance ETH',
      'afETH',
    )) as AfETH

    // initialize derivative contracts
    wstEth = new ethers.Contract(WSTETH_ADRESS, ERC20.abi, accounts[0])
    rEth = new ethers.Contract(RETH_ADDRESS, ERC20.abi, accounts[0])

    // signing defaults to admin, use this to sign for other wallets
    // you can add and name wallets in hardhat.config.ts
    aliceSigner = accounts.find(account => account.address === alice) as Signer

    controller.setVault(WETH_ADDRESS, rEthVault.address) // TODO: Vaults should be set by derivatives
    controller.approveStrategy(WETH_ADDRESS, strategy.address)
    controller.setStrategy(WETH_ADDRESS, strategy.address)

    // Send wstETH derivative to admin
    await network.provider.request({
      method: 'hardhat_impersonateAccount',
      params: [WSTETH_WHALE],
    })
    let transferAmount = ethers.utils.parseEther('1000')
    let whaleSigner = await ethers.getSigner(WSTETH_WHALE)
    const wstEthWhale = wstEth.connect(whaleSigner)
    await wstEthWhale.transfer(admin, transferAmount)
    const wstEthBalance = await wstEth.balanceOf(admin)
    expect(BigNumber.from(wstEthBalance)).gte(transferAmount)

    // Send rETH derivative to admin
    await network.provider.request({
      method: 'hardhat_impersonateAccount',
      params: [RETH_WHALE],
    })
    transferAmount = ethers.utils.parseEther('1000')
    whaleSigner = await ethers.getSigner(RETH_WHALE)
    const rEthWhale = rEth.connect(whaleSigner)
    await rEthWhale.transfer(admin, transferAmount)
    const rEthBalance = await rEth.balanceOf(admin)
    expect(BigNumber.from(rEthBalance)).gte(transferAmount)
  })

  describe('initialize', function () {
    it('Should have correct name', async () => {
      expect(await strategy.getName()).eq('StrategyAsymmetryFinance')
    })
  })

  describe('deposit/withdraw', function () {
    it('Should deposit', async () => {
      const { admin, alice } = await getNamedAccounts() // addresses of named wallets
      console.log('bal', await ethers.provider.getBalance(alice))
      console.log('reth bal', await rEth.balanceOf(alice))
      const aliceVaultSigner = rEthVault.connect(aliceSigner as Signer)
      const depositAmount = ethers.utils.parseEther('48')
      console.log('depositamount', depositAmount)
      await aliceVaultSigner._deposit({ value: depositAmount })
      console.log('bal', await ethers.provider.getBalance(alice))
      const aliceMaxRedeem = rEthVault.maxRedeem(alice)
      expect(aliceMaxRedeem).eq(depositAmount)

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
    })
  })
})

// old tests

// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.13;

// import "forge-std/Test.sol";
// import "forge-std/console.sol";
// import "../src/StrategyAsymmetryFinance.sol";
// import "../src/Vault.sol";
// import "../src/Controller.sol";
// import "../src/interfaces/IController.sol";
// import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
// import "../src/interfaces/IWETH.sol";
// import {ERC20Mock} from "./mocks/ERC20Mock.sol";
// import "../src/interfaces/lido/IWStETH.sol";
// import {IERC20} from "../src/interfaces/IERC20.sol";
// import "../src/tokens/grETH.sol";

// // maybe
// //import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
// //import "../interfaces/IStrategy.sol";

// contract GoldenRatioTest is Test {
//     address public constant WETH9 = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
//     address constant wStEthToken = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
//     address constant RETH = 0xae78736Cd615f374D3085123A210448E74Fc6393;
//     IWStETH private wstEth = IWStETH(payable(wStEthToken));
//     IERC20 private reth = IERC20(RETH);
//     //ERC20 wethToken = ERC20Mock(WETH9);
//     IWETH public weth = IWETH(WETH9);
//     Controller public controller;
//     Vault public vault;
//     StrategyAsymmetryFinance public strategy;
//     // test user account
//     address constant alice = address(0xABCD);
//     grETH grETHToken;

//     function setUp() public {
//         // deploy tokens
//         grETHToken = new grETH("Golden Ratio ETH", "grETH", 18);
//         grCVX1155 cvxNft = new grCVX1155();
//         grBundle1155 bundleNft = new grBundle1155();
//         // init new controller, vault, strategy
//         controller = new Controller();
//         vault = new Vault(
//             WETH9,
//             "Golden Ratio Vault",
//             "grVault",
//             msg.sender,
//             address(controller)
//         );
//         strategy = new StrategyAsymmetryFinance(
//             address(grETHToken),
//             address(controller),
//             0x1d8f8f00cfa6758d7bE78336684788Fb0ee0Fa46,
//             address(cvxNft),
//             address(bundleNft)
//         );
//         // setup connections between controller, vault, and strategy
//         controller.setVault(address(WETH9), address(vault));
//         controller.approveStrategy(address(WETH9), address(strategy));
//         controller.setStrategy(address(WETH9), address(strategy));
//     }

//     function testSetStrategy() public {
//         address currentStrat = controller.strategies(address(WETH9));
//         assertEq(currentStrat, address(strategy));
//     }

//     function testSetVault() public {
//         address currentVault = controller.vaults(address(WETH9));
//         assertEq(currentVault, address(vault));
//     }

//     function testDeposit() public {
//         console.log("Current Strategy:", strategy.getName());
//         (bool sent, ) = address(alice).call{value: 48e18}("");
//         require(sent, "Failed to send Ether");
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
//     }
// }

/* eslint-disable new-cap */
import { network, upgrades, ethers } from "hardhat";
import { expect } from "chai";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { BigNumber } from "ethers";
import { SafEth, SafEthReentrancyTest } from "../typechain-types";

import {
  deploySafEth,
  upgrade,
  getLatestContract,
  deployDerivatives,
} from "./helpers/upgradeHelpers";
import {
  SnapshotRestorer,
  takeSnapshot,
  time,
} from "@nomicfoundation/hardhat-network-helpers";
import { WSTETH_ADDRESS, WSTETH_WHALE } from "./helpers/constants";
import { derivativeAbi } from "./abi/derivativeAbi";
import ERC20 from "@openzeppelin/contracts/build/contracts/ERC20.json";
import { getUserAccounts } from "./helpers/integrationHelpers";
import { within1Percent } from "./helpers/functions";

describe("SafEth", function () {
  let adminAccount: SignerWithAddress;
  let safEth: SafEth;
  let safEthReentrancyTest: SafEthReentrancyTest;
  let snapshot: SnapshotRestorer;
  let initialHardhatBlock: number; // incase we need to reset to where we started

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

    safEth = (await deploySafEth()) as SafEth;

    const SafEthReentrancyTestFactory = await ethers.getContractFactory(
      "SafEthReentrancyTest"
    );
    safEthReentrancyTest = (await SafEthReentrancyTestFactory.deploy(
      safEth.address
    )) as SafEthReentrancyTest;
    await safEthReentrancyTest.deployed();

    const accounts = await ethers.getSigners();
    adminAccount = accounts[0];
  };

  before(async () => {
    await resetToBlock(Number(process.env.BLOCK_NUMBER));
    await safEth.setMaxPreMintAmount("3000000000000000000");
  });

  describe("Large Amounts", function () {
    it("Should deposit and withdraw a large amount with minimal loss from slippage", async function () {
      const startingBalance = await adminAccount.getBalance();
      const depositAmount = ethers.utils.parseEther("200");
      const tx1 = await safEth.stake(0, { value: depositAmount });
      const mined1 = await tx1.wait();
      const networkFee1 = mined1.gasUsed.mul(mined1.effectiveGasPrice);

      const contractEthBalance = await ethers.provider.getBalance(
        safEth.address
      );
      expect(contractEthBalance).eq(0);

      const tx2 = await safEth.unstake(
        await safEth.balanceOf(adminAccount.address),
        0
      );
      const mined2 = await tx2.wait();
      const networkFee2 = mined2.gasUsed.mul(mined2.effectiveGasPrice);
      const finalBalance = await adminAccount.getBalance();

      expect(
        within1Percent(
          finalBalance.add(networkFee1).add(networkFee2),
          startingBalance
        )
      ).eq(true);
    });
    it("Should fail unstake on zero safEthAmount", async function () {
      await expect(safEth.unstake(0, 0)).revertedWith("amount too low");
    });
    it("Should fail unstake on invalid safEthAmount", async function () {
      await expect(safEth.unstake(10, 0)).revertedWith("insufficient balance");
    });
    it("Should fail with wrong min/max", async function () {
      let depositAmount = ethers.utils.parseEther(".002");
      await expect(
        safEth.stake(0, { value: depositAmount })
      ).to.be.revertedWith("amount too low");

      depositAmount = ethers.utils.parseEther("2050");
      await expect(
        safEth.stake(0, { value: depositAmount })
      ).to.be.revertedWith("amount too high");
    });
  });

  describe("Slippage", function () {
    it("Should set slippage derivatives via the safEth contract", async function () {
      const depositAmount = ethers.utils.parseEther("1");
      const derivativeCount = (await safEth.derivativeCount()).toNumber();

      for (let i = 0; i < derivativeCount; i++) {
        await safEth.setMaxSlippage(i, ethers.utils.parseEther("0.01")); // 1%
      }
      await safEth.stake(0, { value: depositAmount });

      for (let i = 0; i < derivativeCount; i++) {
        await safEth.setMaxSlippage(i, ethers.utils.parseEther("0.02")); // 2%
      }
      await safEth.stake(0, { value: depositAmount });
    });
  });
  describe("Pre-mint", function () {
    it("User should receive premint if under max premint amount & has premint funds", async function () {
      const depositAmount = ethers.utils.parseEther("2");
      expect(depositAmount).lte(await safEth.maxPreMintAmount());

      // premint eth
      let tx = await safEth.preMint(0, false, {
        value: depositAmount,
      });
      let receipt = await tx.wait();
      let event = await receipt?.events?.[receipt?.events?.length - 1];
      const preMintedAmount = event?.args?.[1];
      // stake ~2 eth to get preminted safeth
      // need to use a little less than 2 ETH due to price going up after staking
      tx = await safEth.stake(0, { value: preMintedAmount });
      receipt = await tx.wait();
      event = await receipt?.events?.[receipt?.events?.length - 1];
      const amountMinted = await receipt?.events?.[0]?.args?.[2];

      expect(event?.args?.[4]).eq(true); // uses preminted safeth
      expect(within1Percent(preMintedAmount, amountMinted)).eq(true);
      expect(await safEth.preMintedSupply()).lt(
        ethers.utils.parseEther(".0000001")
      );
    });
    it("Should mint safEth if under max premint amount but over premint available", async function () {
      const depositAmount = ethers.utils.parseEther("1");
      const preMintSupply = await safEth.preMintedSupply();
      expect(depositAmount).gt(preMintSupply);
      expect(preMintSupply).gt(0);

      const tx = await safEth.stake(0, { value: depositAmount });
      const receipt = await tx.wait();
      const event = await receipt?.events?.[receipt?.events?.length - 1];

      expect(event?.args?.[4]).eq(false); // mints safeth
    });
    it("Shouldn't premint safEth if over max premint amount", async function () {
      const depositAmount = (await safEth.maxPreMintAmount()).add(1);
      const preMintSupply = await safEth.preMintedSupply();

      expect(depositAmount).gt(await safEth.maxPreMintAmount());
      expect(depositAmount).gt(preMintSupply);
      expect(preMintSupply).gt(0);

      const tx = await safEth.stake(0, { value: depositAmount });
      const receipt = await tx.wait();
      const event = await receipt?.events?.[receipt?.events?.length - 1];

      expect(event?.args?.[4]).eq(false); // mints safeth
    });
    it("Should use approx price if approxPrice > floorPrice", async function () {
      const preMintAmount = ethers.utils.parseEther("2");
      // premint eth
      let tx = await safEth.preMint(0, false, {
        value: preMintAmount,
      });
      await tx.wait();

      const depositAmount = ethers.utils.parseEther("1");
      const preMintSupply = await safEth.preMintedSupply();

      expect(depositAmount).lt(await safEth.maxPreMintAmount());
      expect(depositAmount).lt(preMintSupply);

      tx = await safEth.stake(0, { value: depositAmount });
      const receipt = await tx.wait();
      const event = await receipt?.events?.[receipt?.events?.length - 1];

      expect(await safEth.floorPrice()).lt(event?.args?.[3]);
    });
    it("Should use floor price if approxPrice <= floorPrice", async function () {
      // upgrade contract to support mocking floorPrice
      const safEth2 = await upgrade(safEth.address, "SafEthV2Mock");
      await safEth2.deployed();

      const preMintAmount = ethers.utils.parseEther("2");

      // premint eth
      let tx = await safEth2.preMint(0, false, {
        value: preMintAmount,
      });
      await tx.wait();
      let floorPrice = await safEth2.floorPrice();
      const depositAmount = ethers.utils.parseEther("1");
      const preMintSupply = await safEth2.preMintedSupply();

      expect(depositAmount).lt(await safEth2.maxPreMintAmount());
      expect(depositAmount).lt(preMintSupply);

      const mockedFloorPrice = floorPrice.mul(2);
      await safEth2.setMockFloorPrice(mockedFloorPrice);

      floorPrice = await safEth2.floorPrice();
      const price = await safEth2.approxPrice(true);

      expect(floorPrice).gt(price);

      tx = await safEth2.stake(0, { value: depositAmount });
      const receipt = await tx.wait();
      const event = await receipt?.events?.[receipt?.events?.length - 1];

      const contractEthBalance = await ethers.provider.getBalance(
        safEth.address
      );
      expect(contractEthBalance.sub(await safEth.ethToClaim())).eq(0);

      expect(await safEth2.floorPrice()).eq(event?.args?.[3]);
    });
    it("Owner can withdraw ETH from their preMinted funds", async function () {
      const ethToClaim = await safEth.ethToClaim();
      expect(ethToClaim).gt(ethers.utils.parseEther("3"));

      const beforeBalance = await ethers.provider.getBalance(
        adminAccount.address
      );

      await safEth.withdrawEth();
      const afterBalance = await ethers.provider.getBalance(
        adminAccount.address
      );

      expect(within1Percent(afterBalance.sub(beforeBalance), ethToClaim)).eq(
        true
      );
    });
    it("Can't claim funds if not owner", async function () {
      const accounts = await ethers.getSigners();
      const nonOwnerSigner = safEth.connect(accounts[2]);
      await expect(nonOwnerSigner.withdrawEth()).to.be.revertedWith(
        "Ownable: caller is not the owner"
      );
    });
    it("Can't premint if not owner", async function () {
      const preMintAmount = ethers.utils.parseEther("2");

      const accounts = await ethers.getSigners();
      const nonOwnerSigner = safEth.connect(accounts[2]);
      await expect(
        nonOwnerSigner.preMint(0, false, {
          value: preMintAmount,
        })
      ).to.be.revertedWith("Ownable: caller is not the owner");
    });
    it("Can't change max premint if not owner", async function () {
      const accounts = await ethers.getSigners();
      const nonOwnerSigner = safEth.connect(accounts[2]);
      await expect(
        nonOwnerSigner.setMaxPreMintAmount(ethers.utils.parseEther("2.5"))
      ).to.be.revertedWith("Ownable: caller is not the owner");
    });
    it("Should change max premint amount", async function () {
      await safEth.setMaxPreMintAmount(ethers.utils.parseEther("2.5"));
      expect(await safEth.maxPreMintAmount()).to.eq(
        ethers.utils.parseEther("2.5")
      );
    });
    it("User be able to call preMint() passing _useBalance as true", async function () {
      const depositAmount = ethers.utils.parseEther("2");
      const ethToClaimBefore = await safEth.ethToClaim();
      const expectedEthToClaimAfter = ethToClaimBefore.add(depositAmount);
      const tx = await safEth.preMint(0, true, {
        value: depositAmount,
      });
      await tx.wait();
      const ethToClaimAfter = await safEth.ethToClaim();
      expect(ethToClaimAfter).eq(expectedEthToClaimAfter);
    });
  });
  describe("Receive Eth", function () {
    it("Should revert if sent eth by a user", async function () {
      await expect(
        adminAccount.sendTransaction({
          to: safEth.address,
          value: ethers.utils.parseEther("1.0"),
        })
      ).to.be.revertedWith("Not a derivative contract");
    });
  });
  describe("Re-entrancy", function () {
    it("Should revert if re-entering unstake", async function () {
      const tx0 = await adminAccount.sendTransaction({
        to: safEthReentrancyTest.address,
        value: ethers.utils.parseEther("10.0"),
      });
      await tx0.wait();
      safEthReentrancyTest.testUnstake();

      await expect(safEthReentrancyTest.testUnstake()).to.be.revertedWith(
        "Failed to send Ether"
      );
    });
  });
  describe("Min Out", function () {
    it("Should fail staking through preMint with minOut higher than expected safEth output", async function () {
      const depositAmount = ethers.utils.parseEther("1");
      const minOut = ethers.utils.parseEther("2");
      await expect(
        safEth.stake(minOut, { value: depositAmount })
      ).to.be.revertedWith("preMint amount less than minOut");
    });
    it("Should fail staking with minOut higher than expected safEth output", async function () {
      const depositAmount = ethers.utils.parseEther("5");
      const minOut = ethers.utils.parseEther("6");
      await expect(
        safEth.stake(minOut, { value: depositAmount })
      ).to.be.revertedWith("mint amount less than minOut");
    });
  });

  describe("Sfrx", function () {
    it("Should revert ethPerDerivative for sfrx if frxEth has depegged from eth", async function () {
      // a block where frxEth prices are abnormally depegged from eth by ~0.2%
      await resetToBlock(15946736);

      const factory = await ethers.getContractFactory("SfrxEth");
      const sfrxEthDerivative = await upgrades.deployProxy(factory, [
        adminAccount.address,
      ]);
      await sfrxEthDerivative.deployed();

      await expect(sfrxEthDerivative.ethPerDerivative(true)).to.be.revertedWith(
        "frxEth possibly depegged"
      );

      await resetToBlock(initialHardhatBlock);
    });
  });
  describe("Enable / Disable", function () {
    it("Should fail to enable / disable a non-existent derivative", async function () {
      await expect(safEth.disableDerivative(999)).to.be.revertedWith(
        "derivative index out of bounds"
      );
      await expect(safEth.enableDerivative(999)).to.be.revertedWith(
        "derivative index out of bounds"
      );
    });
    it("Should fail to enable / disable an already enabled / disabled derivative", async function () {
      await expect(safEth.enableDerivative(0)).to.be.revertedWith(
        "derivative already enabled"
      );
      const tx = await safEth.disableDerivative(0);
      await tx.wait();
      await expect(safEth.disableDerivative(0)).to.be.revertedWith(
        "derivative not enabled"
      );
      // re enable derivative so other tests behave as expected
      const tx2 = await safEth.enableDerivative(0);
      await tx2.wait();
    });

    it("Should lower price for everyone when a derivative is disabled and raise price when enabled", async () => {
      const depositAmount = ethers.utils.parseEther("1");
      const tx1 = await safEth.stake(0, { value: depositAmount });
      await tx1.wait();
      const priceBefore = await safEth.approxPrice(true);
      await safEth.disableDerivative(0);
      const priceAfter = await safEth.approxPrice(true);

      await safEth.enableDerivative(0);

      const priceFinal = await safEth.approxPrice(true);

      expect(priceBefore).gt(priceAfter);
      expect(priceFinal).gt(priceAfter);

      // check within 1 percent because price will have gone up due to blocks passing
      expect(within1Percent(priceFinal, priceBefore)).eq(true);
    });

    it("Should allow disabling of a broken derivative so the others still work", async () => {
      const factory = await ethers.getContractFactory("BrokenDerivative");
      const brokenDerivative = await upgrades.deployProxy(factory, [
        safEth.address,
      ]);
      const broken = await brokenDerivative.deployed();

      const depositAmount = ethers.utils.parseEther("1");

      // staking works before adding the bad derivative
      const tx1 = await safEth.stake(0, { value: depositAmount });
      await tx1.wait();

      await safEth.addDerivative(broken.address, 100);

      // staking is broken after deploying broken derivative
      await expect(
        safEth.stake(0, { value: depositAmount })
      ).to.be.revertedWith("Broken Derivative");

      // unstaking is broken after deploying broken derivative
      await expect(
        safEth.unstake(await safEth.balanceOf(adminAccount.address), 0)
      ).to.be.revertedWith("Broken Derivative");

      const tx2 = await safEth.disableDerivative(
        (await safEth.derivativeCount()).sub(1)
      );
      await tx2.wait();

      // stake and unstake both work after disabling the problematic derivative
      await safEth.stake(0, { value: depositAmount });
      await safEth.unstake(await safEth.balanceOf(adminAccount.address), 0);
    });
  });

  describe("Owner functions", function () {
    it("Should pause staking / unstaking", async function () {
      snapshot = await takeSnapshot();
      const tx1 = await safEth.setPauseStaking(true);
      await tx1.wait();
      const depositAmount = ethers.utils.parseEther("1");

      const derivativeCount = (await safEth.derivativeCount()).toNumber();
      const initialWeight = BigNumber.from("1000000000000000000");

      for (let i = 0; i < derivativeCount; i++) {
        if (!(await safEth.derivatives(i)).enabled) continue;
        const tx2 = await safEth.adjustWeight(i, initialWeight);
        await tx2.wait();
      }
      await expect(
        safEth.stake(0, { value: depositAmount })
      ).to.be.revertedWith("staking is paused");

      const tx3 = await safEth.setPauseUnstaking(true);
      await tx3.wait();

      await expect(safEth.unstake(1000, 0)).to.be.revertedWith(
        "unstaking is paused"
      );

      // dont stay paused
      await snapshot.restore();
    });

    it("Should fail to call setPauseStaking() if setting the same value", async function () {
      snapshot = await takeSnapshot();
      const tx1 = await safEth.setPauseStaking(true);
      await expect(safEth.setPauseStaking(true)).to.be.revertedWith(
        "already set"
      );
      await tx1.wait();
      await snapshot.restore();
    });

    it("Should fail to call setPauseUnstaking() if setting the same value", async function () {
      snapshot = await takeSnapshot();
      const tx1 = await safEth.setPauseUnstaking(true);
      await expect(safEth.setPauseUnstaking(true)).to.be.revertedWith(
        "already set"
      );
      await tx1.wait();
      await snapshot.restore();
    });

    it("Should fail with adding non erc 165 compliant derivative", async function () {
      await expect(
        safEth.addDerivative(WSTETH_ADDRESS, "1000000000000000000")
      ).to.be.revertedWith("invalid contract");
    });
    it("Should fail with adding invalid erc165 derivative", async function () {
      const derivativeFactory0 = await ethers.getContractFactory(
        "InvalidErc165Derivative"
      );
      const derivative0 = await upgrades.deployProxy(derivativeFactory0, [
        safEth.address,
      ]);
      await derivative0.deployed();
      await expect(
        safEth.addDerivative(derivative0.address, "1000000000000000000")
      ).to.be.revertedWith("invalid derivative");
    });
    it("Should only allow owner to call pausing functions", async function () {
      const accounts = await ethers.getSigners();
      const nonOwnerSigner = safEth.connect(accounts[2]);
      await expect(nonOwnerSigner.setPauseStaking(true)).to.be.revertedWith(
        "Ownable: caller is not the owner"
      );
      await expect(nonOwnerSigner.setPauseUnstaking(true)).to.be.revertedWith(
        "Ownable: caller is not the owner"
      );
    });
    it("Should be able to change min/max", async function () {
      snapshot = await takeSnapshot();
      await safEth.setMinAmount(100);
      const minAmount = await safEth.minAmount();
      expect(minAmount).eq(100);

      await safEth.setMaxAmount(999);
      const maxAmount = await safEth.maxAmount();
      expect(maxAmount).eq(999);

      await snapshot.restore();
    });
    it("Should only allow owner to call min/max functions", async function () {
      const accounts = await ethers.getSigners();
      const nonOwnerSigner = safEth.connect(accounts[2]);
      await expect(nonOwnerSigner.setMinAmount(100000000)).to.be.revertedWith(
        "Ownable: caller is not the owner"
      );
      await expect(nonOwnerSigner.setMinAmount(900000000)).to.be.revertedWith(
        "Ownable: caller is not the owner"
      );
    });
    it("Should revert if enableDerivative or disableDerivative is called by non-owner", async function () {
      const accounts = await ethers.getSigners();
      const nonOwnerSigner = safEth.connect(accounts[2]);
      await expect(nonOwnerSigner.enableDerivative(0)).to.be.revertedWith(
        "Ownable: caller is not the owner"
      );
      await expect(nonOwnerSigner.disableDerivative(0)).to.be.revertedWith(
        "Ownable: caller is not the owner"
      );
    });
    it("Should two step transfer", async function () {
      const accounts = await ethers.getSigners();
      safEth.transferOwnership(accounts[1].address);
      await safEth.setPauseStaking(true);
      expect(await safEth.pauseStaking()).eq(true);

      const newOwnerSigner = safEth.connect(accounts[1]);
      await expect(newOwnerSigner.setPauseStaking(false)).to.be.revertedWith(
        "Ownable: caller is not the owner"
      );

      await newOwnerSigner.acceptOwnership();
      await newOwnerSigner.setPauseStaking(false);
      expect(await safEth.pauseStaking()).eq(false);
    });
  });

  describe("Derivatives", async () => {
    let derivatives = [] as any;
    before(async () => {
      await resetToBlock(Number(process.env.BLOCK_NUMBER));
    });
    beforeEach(async () => {
      derivatives = await deployDerivatives(adminAccount.address);
      snapshot = await takeSnapshot();
    });
    afterEach(async () => {
      await snapshot.restore();
    });
    it("Should not be able to steal funds by sending derivative tokens", async function () {
      const userAccounts = await getUserAccounts();

      const userSafEthSigner = safEth.connect(userAccounts[0]);
      const userSafEthSigner2 = safEth.connect(userAccounts[1]);
      const ethAmount = "100";
      const depositAmount = ethers.utils.parseEther(ethAmount);

      const stakeResult = await userSafEthSigner.stake(0, {
        value: depositAmount,
      });

      const userSfEthBalance = await safEth.balanceOf(userAccounts[0].address);
      const userSfWithdraw = userSfEthBalance.sub(1);

      await network.provider.request({
        method: "hardhat_impersonateAccount",
        params: [WSTETH_WHALE],
      });
      const whaleSigner = await ethers.getSigner(WSTETH_WHALE);
      const erc20 = new ethers.Contract(
        WSTETH_ADDRESS,
        ERC20.abi,
        userAccounts[0]
      );

      const derivative = derivatives[2].address;

      // remove all but 1 sfToken
      await userSafEthSigner.unstake(userSfWithdraw, 0);

      const erc20Whale = erc20.connect(whaleSigner);
      const erc20Amount = ethers.utils.parseEther("10");

      // transfer tokens directly to the derivative (done by attacker)
      await erc20Whale.transfer(derivative, erc20Amount);

      // NEW USER ENTERS
      const ethAmount2 = "1.5";
      const depositAmount2 = ethers.utils.parseEther(ethAmount2);

      await userSafEthSigner2.stake(0, {
        value: depositAmount2,
      });

      await stakeResult.wait();

      const userSafEthBalance2 = await safEth.balanceOf(
        userAccounts[1].address
      );
      expect(userSafEthBalance2).gt(0);

      // attacker has 1 sfToken
      const attakcerSafEthBalance = await safEth.balanceOf(
        userAccounts[0].address
      );
      expect(attakcerSafEthBalance).eq(1);

      // total supply is gt 1.
      const totalSupply = await safEth.totalSupply();
      expect(totalSupply).gt(1);
    });
    it("Should withdraw reth on amm if deposit contract empty", async () => {
      const factory = await ethers.getContractFactory("Reth");
      const rEthDerivative = await upgrades.deployProxy(factory, [
        adminAccount.address,
      ]);
      await rEthDerivative.deployed();

      const ethDepositAmount = "6000"; // Will use AMM as deposit contract can't hold that much
      const weiDepositAmount = ethers.utils.parseEther(ethDepositAmount);

      const tx1 = await rEthDerivative.deposit({ value: weiDepositAmount });
      await tx1.wait();

      const ethBalancePre = await ethers.provider.getBalance(
        rEthDerivative.address
      );
      expect(ethBalancePre).eq(0);

      const balance = await rEthDerivative.balance();
      expect(balance).gt(0);

      const tx2 = await rEthDerivative.withdraw(balance);
      await tx2.wait();

      const balanceAfter = await rEthDerivative.balance();
      expect(balanceAfter).eq(0);

      const ethBalancePost = await ethers.provider.getBalance(
        rEthDerivative.address
      );
      expect(ethBalancePost).eq(0);
    });
    it("Should force a reth to revert ethPerDerivative() with a bad chainlink feed", async () => {
      const factory = await ethers.getContractFactory("Reth");
      const rEthDerivative = await upgrades.deployProxy(factory, [
        adminAccount.address,
      ]);
      await rEthDerivative.deployed();

      await rEthDerivative.setChainlinkFeed(
        "0x8a65ac0E23F31979db06Ec62Af62b132a6dF4741"
      );

      await expect(rEthDerivative.ethPerDerivative(true)).to.be.revertedWith(
        "call revert exception"
      );
    });
    it("Should test deposit & withdraw, ethPerDerivative & getName on each derivative contract", async () => {
      const weiDepositAmount = ethers.utils.parseEther("50");
      for (let i = 0; i < derivatives.length; i++) {
        const name = await derivatives[i].name();
        expect(name.length).gt(0);
        // no balance before deposit
        const preStakeBalance = await derivatives[i].balance();
        expect(preStakeBalance.eq(0)).eq(true);

        const ethPerDerivative = await derivatives[i].ethPerDerivative(true);
        const ethPerDerivativeNotValidated = await derivatives[
          i
        ].ethPerDerivative(false);
        expect(ethPerDerivative).eq(ethPerDerivativeNotValidated);

        const derivativePerEth = BigNumber.from(
          "1000000000000000000000000000000000000"
        ).div(ethPerDerivative);
        const derivativeBalanceEstimate = BigNumber.from(weiDepositAmount)
          .mul(derivativePerEth)
          .div("1000000000000000000");
        const tx1 = await derivatives[i].deposit({ value: weiDepositAmount });
        await tx1.wait();
        const postStakeBalance = await derivatives[i].balance();

        // roughly expected derivative balance after deposit
        expect(within1Percent(postStakeBalance, derivativeBalanceEstimate)).eq(
          true
        );

        const preWithdrawEthBalance = await adminAccount.getBalance();
        const tx2 = await derivatives[i].withdraw(
          await derivatives[i].balance()
        );
        const mined2 = await tx2.wait();
        const networkFee2 = mined2.gasUsed.mul(mined2.effectiveGasPrice);
        const postWithdrawEthBalance = await adminAccount.getBalance();

        const ethReceived = postWithdrawEthBalance
          .sub(preWithdrawEthBalance)
          .add(networkFee2);

        // roughly same amount of eth received as originally deposited
        expect(within1Percent(ethReceived, weiDepositAmount)).eq(true);

        // no balance after withdrawing all
        const postWithdrawBalance = await derivatives[i].balance();
        expect(postWithdrawBalance.eq(0)).eq(true);
      }
    });

    it("Should show that reth deposit reverts when slippage is set to 0 and a large deposit", async () => {
      const rEthDerivative = derivatives[0];
      const weiDepositAmount = ethers.utils.parseEther("9000");

      await rEthDerivative.setMaxSlippage(0);
      await expect(
        rEthDerivative.deposit({ value: weiDepositAmount })
      ).to.be.revertedWith("BAL#507");
    });

    it("Should upgrade a derivative contract, stake and unstake with the new functionality", async () => {
      const derivativeToUpgrade = derivatives[1];

      const upgradedDerivative = await upgrade(
        derivativeToUpgrade.address,
        "DerivativeMock"
      );
      await upgradedDerivative.deployed();

      const depositAmount = ethers.utils.parseEther("1");

      const tx1 = await upgradedDerivative.deposit({ value: depositAmount });
      const mined1 = await tx1.wait();
      const networkFee1 = mined1.gasUsed.mul(mined1.effectiveGasPrice);

      const balanceBeforeWithdraw = await adminAccount.getBalance();

      // new functionality
      const tx2 = await upgradedDerivative.withdrawAll();
      const mined2 = await tx2.wait();
      const networkFee2 = mined2.gasUsed.mul(mined2.effectiveGasPrice);

      const balanceAfterWithdraw = await adminAccount.getBalance();
      const withdrawAmount = balanceAfterWithdraw.sub(balanceBeforeWithdraw);

      // Value in and out approx same
      expect(
        within1Percent(
          depositAmount,
          withdrawAmount.add(networkFee1).add(networkFee2)
        )
      ).eq(true);
    });
    it("Should successfully call setChainlinkFeed() on all derivatives", async function () {
      const derivativeCount = await safEth.derivativeCount();
      for (let i = 0; i < derivativeCount.toNumber(); i++) {
        await safEth.setChainlinkFeed(
          i,
          "0x8a65ac0E23F31979db06Ec62Af62b132a6dF4741"
        );
      }
    });
  });

  describe("Upgrades", async () => {
    beforeEach(async () => {
      snapshot = await takeSnapshot();
    });
    afterEach(async () => {
      await snapshot.restore();
    });

    it("Should have the same proxy address before and after upgrading", async () => {
      const addressBefore = safEth.address;
      const safEth2 = await upgrade(safEth.address, "SafEthV2Mock");
      await safEth2.deployed();
      const addressAfter = safEth2.address;
      expect(addressBefore).eq(addressAfter);
    });
    it("Should allow v2 functionality to be used after upgrading", async () => {
      const safEth2 = await upgrade(safEth.address, "SafEthV2Mock");
      await safEth2.deployed();
      expect(await safEth2.newFunctionCalled()).eq(false);
      const tx = await safEth2.newFunction();
      await tx.wait();
      expect(await safEth2.newFunctionCalled()).eq(true);
    });

    it("Should get latest version of an already upgraded contract and use new functionality", async () => {
      await upgrade(safEth.address, "SafEthV2Mock");
      const latestContract = await getLatestContract(
        safEth.address,
        "SafEthV2Mock"
      );
      await latestContract.deployed();
      expect(await latestContract.newFunctionCalled()).eq(false);
      const tx = await latestContract.newFunction();
      await tx.wait();
      expect(await latestContract.newFunctionCalled()).eq(true);
    });

    it("Should be able to upgrade both the safEth contract and its derivatives and still function correctly", async () => {
      const safEth2 = await upgrade(safEth.address, "SafEthV2Mock");

      const derivativeAddressToUpgrade = (await safEth2.derivatives(1))
        .derivative;

      const upgradedDerivative = await upgrade(
        derivativeAddressToUpgrade,
        "DerivativeMock"
      );
      await upgradedDerivative.deployed();

      const depositAmount = ethers.utils.parseEther("1");
      const tx1 = await safEth2.stake(0, { value: depositAmount });
      const mined1 = await tx1.wait();
      const networkFee1 = mined1.gasUsed.mul(mined1.effectiveGasPrice);

      const balanceBeforeWithdraw = await adminAccount.getBalance();

      const tx2 = await safEth2.unstake(
        await safEth.balanceOf(adminAccount.address),
        0
      );
      const mined2 = await tx2.wait();
      const networkFee2 = mined2.gasUsed.mul(mined1.effectiveGasPrice);
      const balanceAfterWithdraw = await adminAccount.getBalance();

      const withdrawAmount = balanceAfterWithdraw.sub(balanceBeforeWithdraw);

      // Value in and out approx same
      expect(
        within1Percent(
          depositAmount,
          withdrawAmount.add(networkFee1).add(networkFee2)
        )
      ).eq(true);
    });

    it("Should allow owner to use admin features on upgraded contracts", async () => {
      const safEth2 = await upgrade(safEth.address, "SafEthV2Mock");
      await safEth2.deployed();
      const depositAmount = ethers.utils.parseEther("1");
      const tx1 = await safEth2.stake(0, { value: depositAmount });
      await tx1.wait();
      const derivativeCount = await safEth2.derivativeCount();

      for (let i = 0; i < derivativeCount; i++) {
        const derivativeAddress = (await safEth2.derivatives(i)).derivative;

        const derivative = new ethers.Contract(
          derivativeAddress,
          derivativeAbi,
          adminAccount
        );
        const ethBalanceBeforeWithdraw = await adminAccount.getBalance();
        // admin withdraw from the derivatives in case of emergency
        const tx2 = await safEth2.adminWithdrawDerivative(
          i,
          derivative.balance()
        );
        const mined2 = await tx2.wait();
        const networkFee2 = mined2.gasUsed.mul(mined2.effectiveGasPrice);
        const ethBalanceAfterWithdraw = await adminAccount.getBalance();

        const amountWithdrawn = ethBalanceAfterWithdraw
          .sub(ethBalanceBeforeWithdraw)
          .add(networkFee2);

        expect(within1Percent(depositAmount, amountWithdrawn));
      }

      // accidentally send the contract some erc20
      await network.provider.request({
        method: "hardhat_impersonateAccount",
        params: [WSTETH_WHALE],
      });

      const whaleSigner = await ethers.getSigner(WSTETH_WHALE);
      const erc20 = new ethers.Contract(
        WSTETH_ADDRESS,
        ERC20.abi,
        adminAccount
      );
      const erc20Whale = erc20.connect(whaleSigner);
      const erc20Amount = ethers.utils.parseEther("1000");
      await erc20Whale.transfer(safEth2.address, erc20Amount);

      const erc20BalanceBefore = await erc20.balanceOf(adminAccount.address);

      // recover accidentally deposited erc20 with new admin functionality
      const tx4 = await safEth2.adminWithdrawErc20(
        WSTETH_ADDRESS,
        await erc20.balanceOf(safEth2.address)
      );
      await tx4.wait();
      const erc20BalanceAfter = await erc20.balanceOf(adminAccount.address);

      const erc20Received = erc20BalanceAfter.sub(erc20BalanceBefore);

      expect(erc20Received).eq(erc20Amount);
    });
  });

  describe("Weights & Rebalance", async () => {
    beforeEach(async () => {
      snapshot = await takeSnapshot();
    });
    afterEach(async () => {
      await snapshot.restore();
    });

    it("Should rebalance the underlying values to current weights", async () => {
      const derivativeCount = (await safEth.derivativeCount()).toNumber();

      const initialWeight = BigNumber.from("1000000000000000000"); // 10^18
      const initialDeposit = ethers.utils.parseEther("1");

      // set all derivatives to the same weight and stake
      // if there are 3 derivatives this is 33/33/33
      for (let i = 0; i < derivativeCount; i++) {
        const tx1 = await safEth.adjustWeight(i, initialWeight);
        await tx1.wait();
      }
      const tx2 = await safEth.stake(0, { value: initialDeposit });
      await tx2.wait();
      // set weight of derivative0 as equal to the sum of the other weights and rebalance
      // this is like 33/33/33 -> 50/25/25 (3 derivatives)
      safEth.adjustWeight(0, initialWeight.mul(derivativeCount - 1));
      await rebalanceToWeights();

      const ethBalances = await estimatedDerivativeValues();

      const derivative0Balance = ethBalances[0];
      const balanceSum = ethBalances.reduce(
        (acc, val) => acc.add(val),
        BigNumber.from(0)
      );
      let remainingBalanceSum = BigNumber.from(0);

      for (let i = 1; i < ethBalances.length; i++) {
        remainingBalanceSum = remainingBalanceSum.add(ethBalances[i]);
      }

      expect(within1Percent(derivative0Balance, remainingBalanceSum)).eq(true);
      expect(within1Percent(balanceSum, initialDeposit)).eq(true);
    });

    it("Should stake with a weight set to 0", async () => {
      const derivativeCount = (await safEth.derivativeCount()).toNumber();

      const initialWeight = BigNumber.from("1000000000000000000");
      const initialDeposit = ethers.utils.parseEther("1");

      // set all derivatives to the same weight and stake
      // if there are 3 derivatives this is 33/33/33
      for (let i = 0; i < derivativeCount; i++) {
        const tx1 = await safEth.adjustWeight(i, initialWeight);
        await tx1.wait();
      }

      const tx2 = await safEth.adjustWeight(0, 0);
      await tx2.wait();
      const tx3 = await safEth.stake(0, { value: initialDeposit });
      await tx3.wait();

      const ethBalances = await estimatedDerivativeValues();

      const balanceSum = ethBalances.reduce(
        (acc, val) => acc.add(val),
        BigNumber.from(0)
      );
      let remainingBalanceSum = BigNumber.from(0);

      for (let i = 1; i < ethBalances.length; i++) {
        remainingBalanceSum = remainingBalanceSum.add(ethBalances[i]);
      }

      expect(within1Percent(balanceSum, initialDeposit)).eq(true);
      expect(within1Percent(remainingBalanceSum, initialDeposit)).eq(true);
    });

    it("Should stake, set a weight to 0, rebalance, & unstake", async () => {
      const derivativeCount = (await safEth.derivativeCount()).toNumber();

      const initialWeight = BigNumber.from("1000000000000000000");
      const initialDeposit = ethers.utils.parseEther("1");

      const balanceBefore = await adminAccount.getBalance();

      let totalNetworkFee = BigNumber.from(0);
      // set all derivatives to the same weight and stake
      // if there are 3 derivatives this is 33/33/33
      for (let i = 0; i < derivativeCount; i++) {
        const tx1 = await safEth.adjustWeight(i, initialWeight);
        const mined1 = await tx1.wait();
        const networkFee1 = mined1.gasUsed.mul(mined1.effectiveGasPrice);
        totalNetworkFee = totalNetworkFee.add(networkFee1);
      }
      const tx2 = await safEth.stake(0, { value: initialDeposit });
      const mined2 = await tx2.wait();
      const networkFee2 = mined2.gasUsed.mul(mined2.effectiveGasPrice);
      totalNetworkFee = totalNetworkFee.add(networkFee2);

      // set derivative 0 to 0, rebalance and stake
      // This is like 33/33/33 -> 0/50/50
      const tx3 = await safEth.adjustWeight(0, 0);
      const mined3 = await tx3.wait();
      const networkFee3 = mined3.gasUsed.mul(mined3.effectiveGasPrice);
      totalNetworkFee = totalNetworkFee.add(networkFee3);

      await rebalanceToWeights();

      const tx5 = await safEth.unstake(
        await safEth.balanceOf(adminAccount.address),
        0
      );
      const mined5 = await tx5.wait();
      const networkFee5 = mined5.gasUsed.mul(mined5.effectiveGasPrice);
      totalNetworkFee = totalNetworkFee.add(networkFee5);

      const balanceAfter = await adminAccount.getBalance();

      expect(
        within1Percent(balanceBefore, balanceAfter.add(totalNetworkFee))
      ).eq(true);
    });
  });

  it("Should revert if totalWeight is 0", async () => {
    const derivativeCount = (await safEth.derivativeCount()).toNumber();

    const initialDeposit = ethers.utils.parseEther("1");

    // set all derivatives to the same weight and stake
    // if there are 3 derivatives this is 33/33/33
    for (let i = 0; i < derivativeCount; i++) {
      const tx1 = await safEth.adjustWeight(i, 0);
      await tx1.wait();
    }

    await expect(safEth.stake(0, { value: initialDeposit })).to.be.revertedWith(
      "total weight is zero"
    );
  });

  it("Should stake, sell all of a derivative into another and unstake", async () => {
    const derivativeCount = (await safEth.derivativeCount()).toNumber();

    const initialWeight = BigNumber.from("1000000000000000000");
    const initialDeposit = ethers.utils.parseEther("1");

    const balanceBefore = await adminAccount.getBalance();

    let totalNetworkFee = BigNumber.from(0);
    // set all derivatives to the same weight and stake
    // if there are 3 derivatives this is 33/33/33
    for (let i = 0; i < derivativeCount; i++) {
      const tx1 = await safEth.adjustWeight(i, initialWeight);
      const mined1 = await tx1.wait();
      const networkFee1 = mined1.gasUsed.mul(mined1.effectiveGasPrice);
      totalNetworkFee = totalNetworkFee.add(networkFee1);
    }
    const tx2 = await safEth.stake(0, { value: initialDeposit });
    const mined2 = await tx2.wait();
    const networkFee2 = mined2.gasUsed.mul(mined2.effectiveGasPrice);
    totalNetworkFee = totalNetworkFee.add(networkFee2);

    // do rebalance stuff

    const derivative0Address = (await safEth.derivatives(0)).derivative;
    const derivative0 = new ethers.Contract(
      derivative0Address,
      derivativeAbi,
      adminAccount
    );
    const derivative1Address = (await safEth.derivatives(1)).derivative;
    const derivative1 = new ethers.Contract(
      derivative1Address,
      derivativeAbi,
      adminAccount
    );

    const derivative0BalanceBefore = await derivative0.balance();
    const derivative1BalanceBefore = await derivative1.balance();

    await safEth.derivativeRebalance(0, 1, derivative0BalanceBefore);

    const derivative0BalanceAfter = await derivative0.balance();
    const derivative1BalanceAfter = await derivative1.balance();

    expect(derivative0BalanceAfter).eq(0);
    expect(
      within1Percent(derivative1BalanceBefore.mul(2), derivative1BalanceAfter)
    ).eq(true);

    const tx5 = await safEth.unstake(
      await safEth.balanceOf(adminAccount.address),
      0
    );
    const mined5 = await tx5.wait();
    const networkFee5 = mined5.gasUsed.mul(mined5.effectiveGasPrice);
    totalNetworkFee = totalNetworkFee.add(networkFee5);

    const balanceAfter = await adminAccount.getBalance();

    expect(within1Percent(balanceBefore, balanceAfter.add(totalNetworkFee))).eq(
      true
    );
  });

  describe("Price", function () {
    it("Should correctly get approxPrice()", async function () {
      const depositAmount = ethers.utils.parseEther("1");
      const startingPrice = await safEth.approxPrice(true);
      // starting price = 1 Eth
      expect(startingPrice).eq("1000000000000000000");

      await safEth.stake(0, { value: depositAmount });

      const priceAfterStake = await safEth.approxPrice(true);
      // after initial stake price = 1 Eth
      expect(priceAfterStake).eq("1000000000000000000");

      await time.increase(100);
      const priceAfterTimeIncrease = await safEth.approxPrice(true);

      // price has increased after some time
      expect(priceAfterTimeIncrease).gt(priceAfterStake);
    });
  });

  describe("Blacklist", function () {
    let blacklistedRecipientAddress: string;
    let nonWhitelistedSafEthUser: SafEth;
    let whitelistedSafEthUser: SafEth;

    before(async () => {
      const accounts = await ethers.getSigners();
      nonWhitelistedSafEthUser = safEth.connect(accounts[0]);
      whitelistedSafEthUser = safEth.connect(accounts[1]);
      blacklistedRecipientAddress = accounts[2].address;

      await safEth.setWhitelistedSender(
        await whitelistedSafEthUser.signer.getAddress(),
        true
      );
      await safEth.setBlacklistedRecipient(blacklistedRecipientAddress, true);
    });

    it("Should fail transfer() to blacklisted address from a non whitelisted address", async function () {
      const depositAmount = ethers.utils.parseEther("1");
      await nonWhitelistedSafEthUser.stake(0, { value: depositAmount });
      await expect(
        nonWhitelistedSafEthUser.transfer(blacklistedRecipientAddress, 1)
      ).to.be.revertedWith("blacklisted address");
    });

    it("Should fail transferFrom() to blacklisted address from a non whitelisted address", async function () {
      const depositAmount = ethers.utils.parseEther("1");
      await nonWhitelistedSafEthUser.stake(0, { value: depositAmount });
      await nonWhitelistedSafEthUser.approve(
        await nonWhitelistedSafEthUser.signer.getAddress(),
        1
      );
      await expect(
        nonWhitelistedSafEthUser.transferFrom(
          await nonWhitelistedSafEthUser.signer.getAddress(),
          blacklistedRecipientAddress,
          1
        )
      ).to.be.revertedWith("blacklisted address");
    });

    it("Should successfilly transfer() from a whitelisted address to blacklisted address", async function () {
      const depositAmount = ethers.utils.parseEther("1");
      await whitelistedSafEthUser.stake(0, { value: depositAmount });
      await whitelistedSafEthUser.transfer(blacklistedRecipientAddress, 1);
    });

    it("Should successfilly transferFrom() from a whitelisted address to blacklisted address", async function () {
      const depositAmount = ethers.utils.parseEther("1");
      await whitelistedSafEthUser.stake(0, { value: depositAmount });
      await whitelistedSafEthUser.approve(
        await nonWhitelistedSafEthUser.signer.getAddress(),
        1
      );
      await nonWhitelistedSafEthUser.transferFrom(
        await whitelistedSafEthUser.signer.getAddress(),
        blacklistedRecipientAddress,
        1
      );
    });

    it("Should allow owner to edit the whitelist and blacklist", async function () {
      await safEth.setWhitelistedSender(
        await whitelistedSafEthUser.signer.getAddress(),
        false
      );
      await safEth.setBlacklistedRecipient(blacklistedRecipientAddress, false);
      await safEth.setWhitelistedSender(
        await whitelistedSafEthUser.signer.getAddress(),
        true
      );
      await safEth.setBlacklistedRecipient(blacklistedRecipientAddress, true);
    });

    it("Should fail if non-owner tries to edit the whitelist and blacklist", async function () {
      const accounts = await ethers.getSigners();
      const nonOwner = accounts[1];
      const nonOwnerSafEthUser = safEth.connect(nonOwner);
      await expect(
        nonOwnerSafEthUser.setWhitelistedSender(
          await nonOwnerSafEthUser.signer.getAddress(),
          false
        )
      ).to.be.revertedWith("Ownable: caller is not the owner");
    });
  });

  // get estimated total eth value of each derivative
  const estimatedDerivativeValues = async () => {
    const derivativeCount = (await safEth.derivativeCount()).toNumber();

    const ethBalances: BigNumber[] = [];
    for (let i = 0; i < derivativeCount; i++) {
      const derivativeAddress = (await safEth.derivatives(i)).derivative;
      const derivative = new ethers.Contract(
        derivativeAddress,
        derivativeAbi,
        adminAccount
      );
      const ethPerDerivative = await derivative.ethPerDerivative(true);
      const ethBalanceEstimate = (await derivative.balance())
        .mul(ethPerDerivative)
        .div("1000000000000000000");

      ethBalances.push(ethBalanceEstimate);
    }
    return ethBalances;
  };

  // function to show safEth.derivativeRebalance() can do everything safEth.rebalanceToWeights() used to do
  const rebalanceToWeights = async () => {
    const derivativeCount = (await safEth.derivativeCount()).toNumber();
    // first sell them all into derivative0
    for (let i = 1; i < derivativeCount; i++) {
      const derivativeAddress = (await safEth.derivatives(i)).derivative;
      const derivative = new ethers.Contract(
        derivativeAddress,
        derivativeAbi,
        adminAccount
      );
      const derivativeBalance = await derivative.balance();
      await safEth.derivativeRebalance(i, 0, derivativeBalance);
    }

    const derivative0Address = (await safEth.derivatives(0)).derivative;
    const derivative0 = new ethers.Contract(
      derivative0Address,
      derivativeAbi,
      adminAccount
    );
    const derivative0StartingBalance = await derivative0.balance();
    const totalWeight = await safEth.totalWeight();
    // then rebalance to weights
    for (let i = 1; i < derivativeCount; i++) {
      const derivativeInfo = await safEth.derivatives(i);
      const weight = derivativeInfo.weight;
      const derivative0SellAmount = derivative0StartingBalance
        .mul(weight)
        .div(totalWeight);
      await safEth.derivativeRebalance(0, i, derivative0SellAmount);
    }
  };
});

/* eslint-disable new-cap */
import { network, upgrades, ethers } from "hardhat";
import { expect } from "chai";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { BigNumber } from "ethers";
import { Reth, SafEth, SafEthReentrancyTest, WstEth } from "../typechain-types";

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
import { MULTI_SIG, WSTETH_ADDRESS, WSTETH_WHALE } from "./helpers/constants";
import { derivativeAbi } from "./abi/derivativeAbi";
import ERC20 from "@openzeppelin/contracts/build/contracts/ERC20.json";
import { getUserAccounts } from "./helpers/integrationHelpers";
import {
  setMaxSlippage,
  within1Percent,
  within1Pip,
  withinHalfPercent,
} from "./helpers/functions";

describe("SafEth", function () {
  let adminAccount: SignerWithAddress;
  let safEth: SafEth;
  let safEthReentrancyTest: SafEthReentrancyTest;
  let snapshot: SnapshotRestorer;

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
    await safEth.setMaxPreMintAmount(ethers.utils.parseEther("0.5"));
  };

  before(async () => {
    await resetToBlock(Number(process.env.BLOCK_NUMBER));
    await safEth.setMaxPreMintAmount("3000000000000000000");

    // Seed multi-sig with ETH
    const signers = await ethers.getSigners();
    await signers[9].sendTransaction({
      to: MULTI_SIG,
      value: "100000000000000000000",
    });
  });

  describe("Pre-mint", function () {
    beforeEach(async () => {
      snapshot = await takeSnapshot();
    });

    afterEach(async () => {
      await snapshot.restore();
    });
    it("Should unstake around the same amount through premint and multi", async function () {
      await safEth.setMaxPreMintAmount(ethers.utils.parseEther("1"));

      await safEth.stake(0, {
        value: ethers.utils.parseEther("5"),
      });
      let safEthBalance = await safEth.balanceOf(adminAccount.address);

      const ethBalanceBeforeUnstake = await adminAccount.getBalance();
      let tx = await safEth.unstake(safEthBalance, 0);
      let mined = await tx.wait();
      // eslint-disable-next-line no-unused-vars
      const gasUsedUnstake = mined.gasUsed.mul(mined.effectiveGasPrice);

      const ethBalanceAfterUnstake = await adminAccount.getBalance();
      const ethReceivedUnstake = ethBalanceAfterUnstake.sub(
        ethBalanceBeforeUnstake
      );

      await safEth.fundPreMintStake(0, 0, false, {
        value: ethers.utils.parseEther("10"),
      });
      await safEth.fundPreMintUnstake(false, {
        value: ethers.utils.parseEther("10"),
      });
      await safEth.setMaxPreMintAmount(ethers.utils.parseEther("10"));

      await safEth.stake(0, {
        value: ethers.utils.parseEther("5"),
      });
      safEthBalance = await safEth.balanceOf(adminAccount.address);

      const ethBalanceBeforeUnstakePremint = await adminAccount.getBalance();
      tx = await safEth.preMintUnstake(safEthBalance, 0);
      mined = await tx.wait();
      // eslint-disable-next-line no-unused-vars
      const gasUsedUnstakePremint = mined.gasUsed.mul(mined.effectiveGasPrice);

      const ethBalanceAfterUnstakePremint = await adminAccount.getBalance();
      const ethReceivedUnstakePremint = ethBalanceAfterUnstakePremint.sub(
        ethBalanceBeforeUnstakePremint
      );
      expect(
        withinHalfPercent(ethReceivedUnstake, ethReceivedUnstakePremint)
      ).eq(true);
    });
    it("Should unstake through preminted ETH from staking", async function () {
      expect(await safEth.safEthToClaim()).eq(0);
      expect(await safEth.ethToClaim()).eq(0);

      await safEth.fundPreMintStake(0, 0, false, {
        value: ethers.utils.parseEther("10"),
      });
      await safEth.setMaxPreMintAmount(ethers.utils.parseEther("10"));
      expect(await safEth.ethToClaim()).eq(0);
      expect(
        within1Percent(
          await safEth.safEthToClaim(), // 10.000985
          ethers.utils.parseEther("10")
        )
      ).eq(true);
      const premintedSupply = await safEth.safEthToClaim();
      expect(within1Percent(premintedSupply, ethers.utils.parseEther("10"))).eq(
        true
      );

      await safEth.stake(0, {
        value: ethers.utils.parseEther("10"),
      });
      expect(await safEth.ethToClaim()).eq(ethers.utils.parseEther("10"));
      expect(
        BigNumber.from(premintedSupply).sub(ethers.utils.parseEther("10")) // almost zero
      ).eq(await safEth.safEthToClaim());

      await safEth.preMintUnstake(ethers.utils.parseEther("5"), 0);
      expect(
        within1Percent(await safEth.ethToClaim(), ethers.utils.parseEther("5"))
      ).eq(true);
      expect(
        within1Percent(
          await safEth.safEthToClaim(), // 5.009
          ethers.utils.parseEther("5")
        )
      ).eq(true);
    });
    it("Should unstake the correct amount based on price", async function () {
      await safEth.fundPreMintStake(0, 0, false, {
        value: ethers.utils.parseEther("10"),
      });
      await safEth.fundPreMintUnstake(false, {
        value: ethers.utils.parseEther("10"),
      });
      await safEth.setMaxPreMintAmount(ethers.utils.parseEther("10"));
      await safEth.stake(0, {
        value: ethers.utils.parseEther("5"),
      });
      const safEthBalance = await safEth.balanceOf(adminAccount.address);

      const ethBalanceBeforeUnstake = await adminAccount.getBalance();
      const tx = await safEth.preMintUnstake(safEthBalance, 0);
      const price = await safEth.approxPrice(true);

      const amountToUnstake = price
        .mul(safEthBalance)
        .div(ethers.utils.parseEther("1"));
      const ethBalanceAfterUnstake = await adminAccount.getBalance();

      const mined = await tx.wait();
      const networkFee = mined.gasUsed.mul(mined.effectiveGasPrice);
      expect(amountToUnstake).eq(
        ethBalanceAfterUnstake.sub(ethBalanceBeforeUnstake).add(networkFee)
      );
    });
    it("Should fail preMintUnstake if ethToClaim is under amount", async function () {
      await safEth.fundPreMintStake(0, 0, false, {
        value: ethers.utils.parseEther("10"),
      });
      await safEth.setMaxPreMintAmount(ethers.utils.parseEther("10"));
      await safEth.stake(0, {
        value: ethers.utils.parseEther("1"),
      });
      const ethToClaim = await safEth.ethToClaim();
      const safEthBalance = await safEth.balanceOf(adminAccount.address);
      const price = await safEth.approxPrice(true);

      expect(safEthBalance.mul(price).div(ethers.utils.parseEther("1"))).gt(
        ethToClaim
      );
      await expect(safEth.preMintUnstake(safEthBalance, 0)).to.be.revertedWith(
        "AmountTooLow"
      );
    });
    it("Should fund premint unstake", async function () {
      expect(await safEth.ethToClaim()).eq(0);
      await safEth.fundPreMintUnstake(false, {
        value: ethers.utils.parseEther("10"),
      });
      expect(await safEth.ethToClaim()).eq(ethers.utils.parseEther("10"));
    });
    it("Should fund premint ethToClaim balance", async function () {
      expect(await safEth.safEthToClaim()).eq(0);

      await safEth.fundPreMintUnstake(false, {
        value: ethers.utils.parseEther("10"),
      });
      await safEth.fundPreMintStake(0, await safEth.ethToClaim(), false);
      expect(
        within1Percent(
          await safEth.safEthToClaim(), // 10.000985
          ethers.utils.parseEther("10")
        )
      ).eq(true);
    });
    it("Should fund premint half ethToClaim balance", async function () {
      expect(await safEth.safEthToClaim()).eq(0);

      await safEth.fundPreMintUnstake(false, {
        value: ethers.utils.parseEther("10"),
      });
      await safEth.fundPreMintStake(
        0,
        (await safEth.ethToClaim()).div(2),
        false
      );
      expect(
        within1Percent(
          await safEth.safEthToClaim(), // 5.0049
          ethers.utils.parseEther("5")
        )
      ).eq(true);
    });
    it("Should fund premint both ethToClaim balance and msg.value", async function () {
      expect(await safEth.safEthToClaim()).eq(0);

      await safEth.fundPreMintUnstake(false, {
        value: ethers.utils.parseEther("10"),
      });
      await safEth.fundPreMintStake(0, await safEth.ethToClaim(), false, {
        value: ethers.utils.parseEther("10"),
      });
      expect(
        within1Percent(
          await safEth.safEthToClaim(), // 20.0019
          ethers.utils.parseEther("20")
        )
      ).eq(true);
    });
    it("User should receive premint if under max premint amount & has premint funds", async function () {
      await safEth.setMaxPreMintAmount(ethers.utils.parseEther("2.999"));

      await expect(
        safEth.fundPreMintStake(0, 0, false, {
          value: ethers.utils.parseEther("1"),
        })
      ).to.be.revertedWith("PremintTooLow");

      // premint eth
      let tx = await safEth.fundPreMintStake(0, 0, false, {
        value: ethers.utils.parseEther("6"),
      });
      let receipt = await tx.wait();
      let event = await receipt?.events?.[receipt?.events?.length - 1];

      tx = await safEth.stake(0, { value: ethers.utils.parseEther("1") });
      receipt = await tx.wait();
      event = await receipt?.events?.[receipt?.events?.length - 1];
      expect(event?.args?.[4]).eq(true); // uses preminted safeth
    });
    it("Should not receive premint if under max premint amount but over premint available", async function () {
      let tx = await safEth.fundPreMintStake(0, 0, false, {
        value: ethers.utils.parseEther("6"),
      });
      await tx.wait();
      const depositAmount = ethers.utils.parseEther("8");
      const preMintSupply = await safEth.safEthToClaim();

      expect(depositAmount).gt(preMintSupply);
      expect(preMintSupply).gt(0);

      tx = await safEth.stake(0, { value: depositAmount });
      const receipt = await tx.wait();
      const event = await receipt?.events?.[receipt?.events?.length - 1];

      expect(event?.args?.[4]).eq(false); // mints safeth
    });
    it("Should not receive premint if over max premint amount", async function () {
      let tx = await safEth.fundPreMintStake(0, 0, false, {
        value: ethers.utils.parseEther("6"),
      });
      await tx.wait();

      const depositAmount = (await safEth.maxPreMintAmount()).add(1);
      const preMintSupply = await safEth.safEthToClaim();

      expect(depositAmount).gt(await safEth.maxPreMintAmount());
      expect(preMintSupply).gt(0);

      tx = await safEth.stake(0, { value: depositAmount });
      const receipt = await tx.wait();
      const event = await receipt?.events?.[receipt?.events?.length - 1];

      expect(event?.args?.[4]).eq(false); // mints safeth
    });
    it("Owner can withdraw ETH from their preMinted funds", async function () {
      let tx = await safEth.fundPreMintStake(0, 0, false, {
        value: ethers.utils.parseEther("6"),
      });
      await tx.wait();

      tx = await safEth.stake(0, { value: ethers.utils.parseEther("1") });
      await tx.wait();

      const ethToClaim = await safEth.ethToClaim();
      expect(ethToClaim).gte(ethers.utils.parseEther("1"));

      const beforeBalance = await ethers.provider.getBalance(
        adminAccount.address
      );

      await safEth.withdrawPremintedEth();
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
      await expect(nonOwnerSigner.withdrawPremintedEth()).to.be.revertedWith(
        "Ownable: caller is not the owner"
      );
    });
    it("Can't premint if not owner", async function () {
      const preMintAmount = ethers.utils.parseEther("2");

      const accounts = await ethers.getSigners();
      const nonOwnerSigner = safEth.connect(accounts[2]);
      await expect(
        nonOwnerSigner.fundPreMintStake(0, 0, false, {
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
    it("Should fail staking through fundPreMintStake with minOut higher than expected safEth output", async function () {
      const tx = await safEth.fundPreMintStake(0, 0, false, {
        value: ethers.utils.parseEther("6"),
      });
      await tx.wait();
      const depositAmount = ethers.utils.parseEther("1");
      const minOut = ethers.utils.parseEther("2");
      await expect(
        safEth.stake(minOut, { value: depositAmount })
      ).to.be.revertedWith("PremintTooLow");
    });
    it("Should continue to stake with a similar price before and after all pre minted funds are used up", async function () {
      // do a large initial stake so all derivatives have some balance like real world
      let tx = await safEth.stake(0, {
        value: ethers.utils.parseEther("20"),
      });
      await tx.wait();

      await safEth.setMaxPreMintAmount(ethers.utils.parseEther("2"));
      let maxPremintAmount = await safEth.maxPreMintAmount();
      tx = await safEth.fundPreMintStake(0, 0, false, {
        value: ethers.utils.parseEther("2.5"),
      });
      await tx.wait();

      const balance0 = await safEth.balanceOf(adminAccount.address);

      const ethAmount1 = maxPremintAmount;
      // this should be premint
      tx = await safEth.stake(0, {
        value: ethAmount1,
      });
      await tx.wait();

      const balance1 = await safEth.balanceOf(adminAccount.address);
      const safEthReceived1 = balance1.sub(balance0);

      const ethAmount2 = ethers.utils.parseEther("1");
      // this should be single derivative stake (not enough premint funds)
      tx = await safEth.stake(0, {
        value: ethAmount2,
      });
      await tx.wait();

      const balance2 = await safEth.balanceOf(adminAccount.address);
      const safEthReceived2 = balance2.sub(balance1);

      const ethAmount3 = ethers.utils.parseEther("10");
      // this should be multi derivative stake (not enough premint funds)
      tx = await safEth.stake(0, {
        value: ethAmount3,
      });
      await tx.wait();

      const balance3 = await safEth.balanceOf(adminAccount.address);
      const safEthReceived3 = balance3.sub(balance2);

      await safEth.setMaxPreMintAmount(ethers.utils.parseEther("11"));
      maxPremintAmount = (await safEth.maxPreMintAmount()).add(1);
      tx = await safEth.fundPreMintStake(0, 0, false, {
        value: maxPremintAmount,
      });
      await tx.wait();

      const ethAmount4 = ethers.utils.parseEther("10");
      // this should be a premint stake (instead of a multi derivative stake)
      tx = await safEth.stake(0, {
        value: ethAmount4,
      });
      await tx.wait();

      const balance4 = await safEth.balanceOf(adminAccount.address);
      const safEthReceived4 = balance4.sub(balance3);

      // price should be ~1 because safEth just launched
      expect(withinHalfPercent(safEthReceived1, ethAmount1)).eq(true);
      expect(withinHalfPercent(safEthReceived2, ethAmount2)).eq(true);
      expect(withinHalfPercent(safEthReceived3, ethAmount3)).eq(true);
      expect(withinHalfPercent(safEthReceived4, ethAmount4)).eq(true);
    });

    it("Should not effect the price when staking via premint", async function () {
      // do a large initial stake so all derivatives have some balance like real world
      let tx = await safEth.stake(0, {
        value: ethers.utils.parseEther("11"),
      });
      await tx.wait();

      tx = await safEth.setMaxPreMintAmount(ethers.utils.parseEther("2"));
      await tx.wait();
      const maxPremintAmount = await safEth.maxPreMintAmount();
      tx = await safEth.fundPreMintStake(0, 0, false, {
        value: ethers.utils.parseEther("3"),
      });
      await tx.wait();

      const price0 = await safEth.approxPrice(true);
      tx = await safEth.stake(0, {
        value: maxPremintAmount,
      });
      await tx.wait();
      const price1 = await safEth.approxPrice(true);
      expect(within1Pip(price0, price1)).eq(true);
    });
  });

  describe("Various Fails", function () {
    it("Should fail unstake on zero safEthAmount", async function () {
      await expect(safEth.unstake(0, 0)).revertedWith("AmountTooLow");
    });
    it("Should fail unstake on invalid safEthAmount", async function () {
      await expect(safEth.unstake(10, 0)).revertedWith("InsufficientBalance");
    });
    it("Should fail with wrong min/max", async function () {
      let depositAmount = ethers.utils.parseEther(".002");
      await expect(
        safEth.stake(0, { value: depositAmount })
      ).to.be.revertedWith("AmountTooLow");

      depositAmount = ethers.utils.parseEther("2050");
      await expect(
        safEth.stake(0, { value: depositAmount })
      ).to.be.revertedWith("AmountTooHigh");
    });
  });

  describe("Slippage", function () {
    it("Should set slippage derivatives for each derivatives contract", async function () {
      const depositAmount = ethers.utils.parseEther("1");
      const derivativeCount = (await safEth.derivativeCount()).toNumber();

      for (let i = 0; i < derivativeCount; i++) {
        const derivativeAddress = (await safEth.derivatives(i)).derivative;
        const derivative = new ethers.Contract(
          derivativeAddress,
          derivativeAbi,
          adminAccount
        );
        await setMaxSlippage(derivative, ethers.utils.parseEther("0.01"));
      }
      let tx;
      tx = await safEth.stake(0, { value: depositAmount });
      await tx.wait();
      for (let i = 0; i < derivativeCount; i++) {
        const derivativeAddress = (await safEth.derivatives(i)).derivative;
        const derivative = new ethers.Contract(
          derivativeAddress,
          derivativeAbi,
          adminAccount
        );
        await setMaxSlippage(derivative, ethers.utils.parseEther("0.02"));
      }
      tx = await safEth.stake(0, { value: depositAmount });
      await tx.wait();
    });
  });
  describe("Receive Eth", function () {
    it("Should revert if sent eth by a user", async function () {
      await expect(
        adminAccount.sendTransaction({
          to: safEth.address,
          value: ethers.utils.parseEther("1.0"),
        })
      ).to.be.revertedWith("InvalidDerivative");
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
        "FailedToSend"
      );
    });
  });
  describe("Min Out", function () {
    it("Should fail staking with minOut higher than expected safEth output", async function () {
      const depositAmount = ethers.utils.parseEther("5");
      const minOut = ethers.utils.parseEther("6");
      await expect(
        safEth.stake(minOut, { value: depositAmount })
      ).to.be.revertedWith("MintedAmountTooLow");
    });
  });
  describe("Enable / Disable", function () {
    it("InitializeV2 should set the correct values", async function () {
      const snapshot = await takeSnapshot();
      await safEth.initializeV2();
      const enabledDerivativeCount = await safEth.enabledDerivativeCount();
      const enabledDerivatives0 = await safEth.enabledDerivatives(0);
      const enabledDerivatives1 = await safEth.enabledDerivatives(1);
      const enabledDerivatives2 = await safEth.enabledDerivatives(2);

      await expect(safEth.enabledDerivatives(3)).to.be.reverted;
      expect(enabledDerivativeCount).eq(3);
      expect(enabledDerivatives0).eq(0);
      expect(enabledDerivatives1).eq(1);
      expect(enabledDerivatives2).eq(2);

      await expect(safEth.initializeV2()).to.be.reverted;
      snapshot.restore();
    });
    it("Should keep track of derivative indexes when enabling and disabling derivatives", async () => {
      const enabledDerivativeCountBefore =
        await safEth.enabledDerivativeCount();

      await safEth.disableDerivative(0);

      let count = await safEth.enabledDerivativeCount();
      for (let i = 0; i < count.toNumber(); i++) {
        expect(await safEth.enabledDerivatives(i)).to.not.eq(0);
      }

      const enabledDerivativeCountAfter = await safEth.enabledDerivativeCount();
      expect(enabledDerivativeCountBefore).eq(
        enabledDerivativeCountAfter.add(1)
      );

      await safEth.enableDerivative(0);

      count = await safEth.enabledDerivativeCount();
      expect(count).eq(6);
      let containsZeroIndex = false;
      for (let i = 0; i < count.toNumber(); i++) {
        if ((await safEth.enabledDerivatives(i)).eq(0)) {
          containsZeroIndex = true;
        }
      }
      expect(containsZeroIndex).eq(true);

      await safEth.disableDerivative(1);
      await safEth.disableDerivative(2);
      await safEth.disableDerivative(3);

      count = await safEth.enabledDerivativeCount();
      expect(count).eq(3);
      for (let i = 0; i < count.toNumber(); i++) {
        expect(await safEth.enabledDerivatives(i)).to.not.eq(1);
        expect(await safEth.enabledDerivatives(i)).to.not.eq(2);
        expect(await safEth.enabledDerivatives(i)).to.not.eq(3);
      }

      await safEth.enableDerivative(1);
      await safEth.enableDerivative(2);

      count = await safEth.enabledDerivativeCount();
      expect(count).eq(5);
      let containsFirstIndex = false;
      let containsSecondIndex = false;
      let containsThirdIndex = false;
      for (let i = 0; i < count.toNumber(); i++) {
        const derivative = await safEth.enabledDerivatives(i);
        if (derivative.eq(1)) {
          containsFirstIndex = true;
        }
        if (derivative.eq(2)) {
          containsSecondIndex = true;
        }
        if (derivative.eq(3)) {
          containsThirdIndex = true;
        }
      }

      expect(containsFirstIndex).eq(true);
      expect(containsSecondIndex).eq(true);
      expect(containsThirdIndex).eq(false);

      await safEth.enableDerivative(3);
      await safEth.disableDerivative(2);

      count = await safEth.enabledDerivativeCount();
      expect(count).eq(5);
      containsSecondIndex = false;
      containsThirdIndex = false;
      for (let i = 0; i < count.toNumber(); i++) {
        const derivative = await safEth.enabledDerivatives(i);
        if (derivative.eq(1)) {
          containsFirstIndex = true;
        }
        if (derivative.eq(2)) {
          containsSecondIndex = true;
        }
        if (derivative.eq(3)) {
          containsThirdIndex = true;
        }
      }
      expect(containsSecondIndex).eq(false);
      expect(containsThirdIndex).eq(true);
    });
    it("Should fail to enable / disable a non-existent derivative", async function () {
      await expect(safEth.disableDerivative(999)).to.be.revertedWith(
        "IndexOutOfBounds"
      );
      await expect(safEth.enableDerivative(999)).to.be.revertedWith(
        "IndexOutOfBounds"
      );
    });
    it("Should fail to enable / disable an already enabled / disabled derivative", async function () {
      await expect(safEth.enableDerivative(0)).to.be.revertedWith(
        "AlreadyEnabled"
      );
      const tx = await safEth.disableDerivative(0);
      await tx.wait();
      await expect(safEth.disableDerivative(0)).to.be.revertedWith(
        "NotEnabled"
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
      const enabledDerivativeCountBefore =
        await safEth.enabledDerivativeCount();
      await safEth.disableDerivative(0);
      const enabledDerivativeCountAfter = await safEth.enabledDerivativeCount();
      expect(enabledDerivativeCountBefore).eq(
        enabledDerivativeCountAfter.add(1)
      );
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

      const depositAmount = ethers.utils.parseEther("11");

      // staking works before adding the bad derivative
      const tx1 = await safEth.stake(0, { value: depositAmount });
      await tx1.wait();
      const enabledDerivativeCountBefore =
        await safEth.enabledDerivativeCount();
      await safEth.addDerivative(broken.address, 100);
      const enabledDerivativeCountAfter = await safEth.enabledDerivativeCount();
      expect(enabledDerivativeCountBefore).eq(
        enabledDerivativeCountAfter.sub(1)
      );

      // staking is broken after deploying broken derivative
      await expect(
        safEth.stake(0, { value: depositAmount })
      ).to.be.revertedWith("BrokenDerivativeError");

      // unstaking is broken after deploying broken derivative
      await expect(
        safEth.unstake(await safEth.balanceOf(adminAccount.address), 0)
      ).to.be.revertedWith("BrokenDerivativeError");

      const tx2 = await safEth.disableDerivative(
        (await safEth.derivativeCount()).sub(1)
      );
      await tx2.wait();

      let tx;
      // stake and unstake both work after disabling the problematic derivative
      tx = await safEth.stake(0, { value: depositAmount });
      await tx.wait();
      tx = await safEth.unstake(
        await safEth.balanceOf(adminAccount.address),
        0
      );
      await tx.wait();
    });
  });

  describe("Owner functions", function () {
    beforeEach(async () => {
      snapshot = await takeSnapshot();
    });
    afterEach(async () => {
      await snapshot.restore();
    });

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
      ).to.be.revertedWith("StakingPausedError");

      const tx3 = await safEth.setPauseUnstaking(true);
      await tx3.wait();

      await expect(safEth.unstake(1000, 0)).to.be.revertedWith(
        "UnstakingPausedError"
      );

      // dont stay paused
      await snapshot.restore();
    });

    it("Should fail to call setPauseStaking() if setting the same value", async function () {
      snapshot = await takeSnapshot();
      const tx1 = await safEth.setPauseStaking(true);
      await expect(safEth.setPauseStaking(true)).to.be.revertedWith(
        "AlreadySet"
      );
      await tx1.wait();
      await snapshot.restore();
    });

    it("Should fail to call setPauseUnstaking() if setting the same value", async function () {
      snapshot = await takeSnapshot();
      const tx1 = await safEth.setPauseUnstaking(true);
      await expect(safEth.setPauseUnstaking(true)).to.be.revertedWith(
        "AlreadySet"
      );
      await tx1.wait();
      await snapshot.restore();
    });

    it("Should fail with adding non erc 165 compliant derivative", async function () {
      await expect(
        safEth.addDerivative(WSTETH_ADDRESS, "1000000000000000000")
      ).to.be.revertedWith("InvalidDerivative");
    });
    it("Should fail with adding invalid erc165 derivative", async function () {
      const derivativeFactory0 = await ethers.getContractFactory(
        "InvalidErc165Derivative"
      );
      const derivative0 = await upgrades.deployProxy(derivativeFactory0, [
        safEth.address,
      ]);
      await derivative0.deployed();
      const enabledDerivativeCountBefore =
        await safEth.enabledDerivativeCount();
      await expect(
        safEth.addDerivative(derivative0.address, "1000000000000000000")
      ).to.be.revertedWith("InvalidDerivative");
      const enabledDerivativeCountAfter = await safEth.enabledDerivativeCount();
      expect(enabledDerivativeCountBefore).eq(enabledDerivativeCountAfter);
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
      const signers = await ethers.getSigners();
      await signers[9].sendTransaction({
        to: MULTI_SIG,
        value: "100000000000000000000",
      });
    });
    beforeEach(async () => {
      derivatives = await deployDerivatives(adminAccount.address);
      snapshot = await takeSnapshot();
    });
    afterEach(async () => {
      await snapshot.restore();
    });
    it("Should fail transfer() in wstEth deposit", async function () {
      const RevertCallFactory = await ethers.getContractFactory("RevertCall");
      const revertCall = await RevertCallFactory.deploy();
      await revertCall.deployed();

      const factory = await ethers.getContractFactory("WstEth");
      const derivative = (await upgrades.deployProxy(factory, [
        revertCall.address,
      ])) as WstEth;
      await derivative.deployed();

      await expect(
        revertCall.testDeposit(derivative.address)
      ).to.be.revertedWith("FailedToSend");
    });
    it("Should fail transfer() in finalCall", async function () {
      const RevertCallFactory = await ethers.getContractFactory("RevertCall");
      const revertCall = await RevertCallFactory.deploy();
      await revertCall.deployed();

      const factory = await ethers.getContractFactory("Reth");
      const derivative = (await upgrades.deployProxy(factory, [
        revertCall.address,
      ])) as Reth;
      await derivative.deployed();

      await revertCall.testDeposit(derivative.address, { value: "10000000" });
      const balance = await derivative.balance();

      await expect(
        revertCall.testWithdraw(derivative.address, balance)
      ).to.be.revertedWith("FailedToSend");
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
    it("Shouldn't deploy derivative with zero address", async () => {
      const factory = await ethers.getContractFactory("Reth");
      await expect(
        upgrades.deployProxy(factory, [ethers.constants.AddressZero])
      ).to.be.revertedWith("InvalidAddress");
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
      await rEthDerivative.initializeV2();
      await network.provider.request({
        method: "hardhat_impersonateAccount",
        params: [MULTI_SIG],
      });

      const multiSigSigner = await ethers.getSigner(MULTI_SIG);
      const multiSig = rEthDerivative.connect(multiSigSigner);
      await multiSig.setChainlinkFeed(
        "0x8a65ac0E23F31979db06Ec62Af62b132a6dF4741"
      );

      await expect(rEthDerivative.ethPerDerivative(true)).to.be.revertedWith(
        "call revert exception"
      );
    });
    it("Should not allow calling initializeV2 after first time", async () => {
      const factory = await ethers.getContractFactory("Reth");
      const rEthDerivative = await upgrades.deployProxy(factory, [
        adminAccount.address,
      ]);
      await rEthDerivative.deployed();
      await rEthDerivative.initializeV2();

      await expect(rEthDerivative.initializeV2()).to.be.revertedWith(
        "AlreadyInitialized"
      );
    });
    it("Should setDepegSlippage() on sfrxEth derivative", async function () {
      const factory = await ethers.getContractFactory("SfrxEth");
      const SfrxEthDerivative = await upgrades.deployProxy(factory, [
        adminAccount.address,
      ]);
      await SfrxEthDerivative.deployed();
      await SfrxEthDerivative.initializeV2();
      await network.provider.request({
        method: "hardhat_impersonateAccount",
        params: [MULTI_SIG],
      });

      const multiSigSigner = await ethers.getSigner(MULTI_SIG);
      const multiSig = SfrxEthDerivative.connect(multiSigSigner);
      const depegSlippageBefore = await multiSig.depegSlippage();
      await multiSig.setDepegSlippage(123456);
      const depegSlippageAfter = await multiSig.depegSlippage();
      expect(depegSlippageBefore).eq(0);
      expect(depegSlippageAfter).eq(123456);
    });
    it("Should test deposit & withdraw, ethPerDerivative, getName & updateManager on each derivative contract", async () => {
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

        await network.provider.request({
          method: "hardhat_impersonateAccount",
          params: [MULTI_SIG],
        });

        // fail when called by non manager
        await expect(
          derivatives[i].updateManager(MULTI_SIG)
        ).to.be.revertedWith("Unauthorized");

        const multiSigSigner = await ethers.getSigner(MULTI_SIG);
        const multiSig = derivatives[i].connect(multiSigSigner);
        const tx3 = await multiSig.updateManager(adminAccount.address);
        await tx3.wait();

        // fail when zero address
        await expect(
          derivatives[i].updateManager(ethers.constants.AddressZero)
        ).to.be.revertedWith("InvalidAddress");

        const newManager1 = await derivatives[i].manager();
        expect(newManager1).eq(adminAccount.address);
        const tx4 = await derivatives[i].updateManager(MULTI_SIG);
        await tx4.wait();
        const newManager2 = await derivatives[i].manager();
        expect(newManager2).eq(MULTI_SIG);
      }
    });

    it("Should deposit huge amounts to each derivative with minimal slippage", async () => {
      // we assume these small deposits do not have any slippage
      const postStakeBalancesSmall = [];
      for (let i = 0; i < derivatives.length; i++) {
        const tx1 = await derivatives[i].deposit({
          value: ethers.utils.parseEther("0.3"),
        });
        await tx1.wait();
        const postStakeBalance = await derivatives[i].balance();
        postStakeBalancesSmall.push(postStakeBalance);
      }

      for (let i = 0; i < derivatives.length; i++) {
        const tx1 = await derivatives[i].deposit({
          value: ethers.utils.parseEther("300"),
        });
        await tx1.wait();
        const postStakeBalance = await derivatives[i].balance();

        expect(
          withinHalfPercent(
            postStakeBalance,
            postStakeBalancesSmall[i].mul(1000)
          )
        ).eq(true);
      }
    });

    it("Should withdraw 50 eth from each derivative with minimal slippage", async () => {
      const rethAddress = "0xae78736cd615f374d3085123a210448e74fc6393";
      const fraxAddress = "0xac3e018457b222d93114458476f3e3416abbe38f";
      const wstAddress = "0x7f39c581f595b53c5cb19bd0b3f8da6c935e2ca0";
      const swethAddress = "0xf951E335afb289353dc249e82926178EaC7DEd78";
      const stafiAddress = "0x9559aaa82d9649c7a7b220e7c461d2e74c9a3593";
      const ankrAddress = "0xE95A203B1a91a908F9B9CE46459d101078c2c3cb";

      const rethWhale = "0x7d6149ad9a573a6e2ca6ebf7d4897c1b766841b4";
      const fraxWhale = "0xfe4ad60c8ec639ca7002d7612d5987ddfc16a4fb";
      const wstWhale = "0xa0456eaae985bdb6381bd7baac0796448933f04f";
      const swethWhale = "0x0c67f4ffc902140c972ecab356c9993e6ce8caf3";
      const stafiWhale = "0x61573115459b0e565853112fd0361faa4700183c";
      const ankrWhale = "0x8cbee4b481112e44b92817b26f96918221489485";

      // order is important here
      const derivativeWhales = [
        rethWhale,
        fraxWhale,
        wstWhale,
        swethWhale,
        stafiWhale,
        ankrWhale,
      ];
      const derivativeAddresses = [
        rethAddress,
        fraxAddress,
        wstAddress,
        swethAddress,
        stafiAddress,
        ankrAddress,
      ];

      const derivativeUpgrades = [
        "SlippageReth",
        "SlippageFrax",
        "SlippageWst",
        "SlippageSweth",
        "SlipageStafi",
        "SlippageAnkr",
      ];

      // Staking 50 eth in the above test @ block 17836150 gives the following amounts back:
      // we now withdraw these amounts from each derivative to see how much eth we get back
      const withdrawAmounts = [
        "46297492041285200792", // 46.297492041285200792 reth
        "47541784416297659563", // 47.541784416297659563 frax
        "44070109768089069400", // 44.070109768089069400 wst
        "48826688634955242972", // 48.826688634955242972 swell
        "47228511358806498771", // 47.228511358806498771stafi
        "44434957812815529550", // 44.434957812815529550 ankr
      ];
      // for block 17836150 50 eth gives back:
      // 49.96176783034190661 eth from  RocketPool
      // 49.868340382070075657 eth from  Frax
      // 49.962390972092423888 eth from  Lido
      // 49.925107285811638515 eth from  Swell
      // 49.910949042763672728 eth from  Stafi
      // 49.628382712896473889 eth from  AnkrEth

      let tx;
      // fund the derivative contracts with plenty of tokens to sell
      for (let i = 0; i < derivatives.length; i++) {
        const whale = derivativeWhales[i];

        tx = await adminAccount.sendTransaction({
          to: whale,
          value: "100000000000000000",
        });
        await tx.wait();

        const derivativeToken = new ethers.Contract(
          derivativeAddresses[i],
          ERC20.abi,
          adminAccount
        );

        await network.provider.request({
          method: "hardhat_impersonateAccount",
          params: [whale],
        });
        const whaleSigner = derivativeToken.connect(
          await ethers.getSigner(whale)
        );

        tx = await whaleSigner.transfer(
          derivatives[i].address,
          await derivativeToken.balanceOf(whale)
        );
        await tx.wait();

        // upgrade derivative so we can call setUnderlying()
        const upgradedDerivative: any = await upgrade(
          derivatives[i].address,
          derivativeUpgrades[i]
        );
        await upgradedDerivative.deployed();

        await upgradedDerivative.setUnderlying(
          await derivativeToken.balanceOf(derivatives[i].address)
        );

        const ethBal1 = await (adminAccount as any).provider.getBalance(
          adminAccount.address
        );
        const tx2 = await derivatives[i].withdraw(withdrawAmounts[i]);
        await tx2.wait();
        const ethBal2 = await (adminAccount as any).provider.getBalance(
          adminAccount.address
        );

        const ethReceived = ethBal2.sub(ethBal1);

        expect(
          within1Percent(
            ethReceived,
            BigNumber.from(ethers.utils.parseEther("50"))
          )
        ).eq(true);
      }
    });

    it("Should show that reth deposit reverts when slippage is set to 0 and a large deposit", async () => {
      const rEthDerivative = derivatives[0];
      const weiDepositAmount = ethers.utils.parseEther("9000");

      await setMaxSlippage(rEthDerivative, BigNumber.from(0));
      await expect(
        rEthDerivative.deposit({ value: weiDepositAmount })
      ).to.be.revertedWith("SlippageTooHigh");
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
    it("Should successfully call setChainlinkFeed() on derivatives that support it", async function () {
      const derivativeCount = await safEth.derivativeCount();
      for (let i = 0; i < derivativeCount.toNumber(); i++) {
        await network.provider.request({
          method: "hardhat_impersonateAccount",
          params: [MULTI_SIG],
        });
        const multiSigSigner = await ethers.getSigner(MULTI_SIG);
        const multiSig = derivatives[i].connect(multiSigSigner);
        if (typeof multiSig.setChainlinkFeed !== "function") continue;
        const tx3 = await multiSig.setChainlinkFeed(adminAccount.address);
        await tx3.wait();
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
      const depositAmount = ethers.utils.parseEther("11");
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
      const initialDeposit = ethers.utils.parseEther("11");

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

    it("Should stake a large amount with a weight set to 0", async () => {
      const derivativeCount = (await safEth.derivativeCount()).toNumber();

      const initialWeight = BigNumber.from("1000000000000000000");
      const initialDeposit = ethers.utils.parseEther("11");

      // set all derivatives to the same weight and stake
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

    it("Should stake a small amount with a weight set to 0", async () => {
      const derivativeCount = (await safEth.derivativeCount()).toNumber();

      const initialWeight = BigNumber.from("1000000000000000000");
      const initialDeposit = ethers.utils.parseEther("1");

      // set all derivatives to the same weight and stake
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
    });

    it("Should stake, set a weight to 0, rebalance, & unstake", async () => {
      const derivativeCount = (await safEth.derivativeCount()).toNumber();

      const initialWeight = BigNumber.from("1000000000000000000");
      const initialDeposit = ethers.utils.parseEther("11");

      const balanceBefore = await adminAccount.getBalance();

      let totalNetworkFee = BigNumber.from(0);
      // set all derivatives to the same weight and stake
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
      "TotalWeightZero"
    );
  });

  it("Should stake, sell all of a derivative into another and unstake", async () => {
    const derivativeCount = (await safEth.derivativeCount()).toNumber();

    const initialWeight = BigNumber.from("1000000000000000000");
    const initialDeposit = ethers.utils.parseEther("11");

    const balanceBefore = await adminAccount.getBalance();

    let totalNetworkFee = BigNumber.from(0);
    // set all derivatives to the same weight and stake
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
      const depositAmount = ethers.utils.parseEther("11");
      const startingPrice = await safEth.approxPrice(true);
      // starting price = 1 Eth
      expect(startingPrice).eq("1000000000000000000");

      const tx = await safEth.stake(0, { value: depositAmount });
      await tx.wait();

      const priceAfterStake = await safEth.approxPrice(true);
      // after initial stake price = 1 Eth
      expect(priceAfterStake).eq("1000000000000000000");

      await time.increase(100);
      const priceAfterTimeIncrease = await safEth.approxPrice(true);

      // price has increased after some time
      expect(priceAfterTimeIncrease).gt(priceAfterStake);
    });
  });

  describe("Various Stake Sizes (Premint, Multi Derivative)", function () {
    beforeEach(async () => {
      let tx = await safEth.fundPreMintStake(0, 0, false, {
        value: ethers.utils.parseEther("10"),
      });
      await tx.wait();
      tx = await safEth.setMaxPreMintAmount(ethers.utils.parseEther("2"));
      await tx.wait();
    });

    it("Should stake with minimal slippage for all 2 stake sizes", async function () {
      const safEthBalance0 = await safEth.balanceOf(adminAccount.address);
      const ethAmount0 = (await safEth.maxPreMintAmount()).sub(1);
      // this should be a premint tx
      let tx = await safEth.stake(0, {
        value: ethAmount0,
      });
      await tx.wait();

      // this should be a multi derive stake
      const safEthBalance1 = await safEth.balanceOf(adminAccount.address);
      const ethAmount1 = (await safEth.maxPreMintAmount()).add(1);
      tx = await safEth.stake(0, {
        value: ethAmount1,
      });
      await tx.wait();

      const safEthBalance2 = await safEth.balanceOf(adminAccount.address);

      const safEthReceived0 = safEthBalance1.sub(safEthBalance0);
      const safEthReceived1 = safEthBalance2.sub(safEthBalance1);

      expect(withinHalfPercent(safEthReceived0, ethAmount0)).eq(true);
      expect(withinHalfPercent(safEthReceived1, ethAmount1)).eq(true);
    });
    it("Should be more than 10x cheaper to stake with premint", async function () {
      const ethAmount0 = (await safEth.maxPreMintAmount()).sub(1);
      // this should be a premint tx
      let tx = await safEth.stake(0, {
        value: ethAmount0,
      });
      const receipt1 = await tx.wait();
      // this should be a multi derive stake
      const ethAmount1 = (await safEth.maxPreMintAmount()).add(1);
      tx = await safEth.stake(0, {
        value: ethAmount1,
      });
      const receipt2 = await tx.wait();
      expect(receipt1.gasUsed.lt(receipt2.gasUsed.mul(10))).eq(true);
    });
  });
  describe("Sfrx", function () {
    it("Should revert ethPerDerivative for sfrx if frxEth has depegged from eth", async function () {
      const factory = await ethers.getContractFactory("SfrxEth");
      const sfrxEthDerivative = await upgrades.deployProxy(factory, [
        adminAccount.address,
      ]);
      await sfrxEthDerivative.deployed();
      await sfrxEthDerivative.initializeV2();
      await network.provider.request({
        method: "hardhat_impersonateAccount",
        params: [MULTI_SIG],
      });
      const signers = await ethers.getSigners();
      await signers[9].sendTransaction({
        to: MULTI_SIG,
        value: "100000000000000000000",
      });
      const multiSigSigner = await ethers.getSigner(MULTI_SIG);
      const multiSig = sfrxEthDerivative.connect(multiSigSigner);
      await multiSig.setDepegSlippage(1);

      await expect(sfrxEthDerivative.ethPerDerivative(true)).to.be.revertedWith(
        "FrxDepegged"
      );
    });
    it("Should get correct price difference if value over 1", async function () {
      resetToBlock(16080532);
      await network.provider.request({
        method: "hardhat_reset",
        params: [
          {
            forking: {
              jsonRpcUrl: process.env.MAINNET_URL,
              blockNumber: 16080532,
            },
          },
        ],
      });
      const factory = await ethers.getContractFactory("SfrxEth");
      const sfrxEthDerivative = await upgrades.deployProxy(factory, [
        adminAccount.address,
      ]);
      await sfrxEthDerivative.deployed();
      await sfrxEthDerivative.initializeV2();
      const price = await sfrxEthDerivative.ethPerDerivative(false);
      expect(price).gt(0);

      await resetToBlock(Number(process.env.BLOCK_NUMBER));
    });
  });
  describe("Floor Price", () => {
    it("Should store the highest floor price", async function () {
      await resetToBlock(17627525);

      const preMintAmount = ethers.utils.parseEther("2");

      // premint eth until the approx price is lower than floor price
      let tx = await safEth.fundPreMintStake(0, 0, false, {
        value: preMintAmount,
      });
      tx = await safEth.fundPreMintStake(0, 0, false, {
        value: preMintAmount,
      });
      tx = await safEth.fundPreMintStake(0, 0, false, {
        value: preMintAmount,
      });
      await tx.wait();
      const floorPrice = await safEth.floorPrice();
      const approxPrice = await safEth.approxPrice(false);

      expect(approxPrice).lt(floorPrice);
      const newFloorPrice = await safEth.floorPrice();
      expect(floorPrice).eq(newFloorPrice);

      await resetToBlock(Number(process.env.BLOCK_NUMBER));
    });
    it("Should overwrite floor price if override is set to true", async function () {
      await resetToBlock(17627525);

      const preMintAmount = ethers.utils.parseEther("2");

      // premint eth until the approx price is lower than floor price
      let tx = await safEth.fundPreMintStake(0, 0, true, {
        value: preMintAmount,
      });
      tx = await safEth.fundPreMintStake(0, 0, true, {
        value: preMintAmount,
      });
      tx = await safEth.fundPreMintStake(0, 0, true, {
        value: preMintAmount,
      });
      await tx.wait();
      const floorPrice = await safEth.floorPrice();
      const approxPrice = await safEth.approxPrice(false);

      expect(approxPrice).eq(floorPrice);
      const newFloorPrice = await safEth.floorPrice();
      expect(floorPrice).eq(newFloorPrice);

      await resetToBlock(Number(process.env.BLOCK_NUMBER));
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
    const derivative0Info = await safEth.derivatives(0);
    const derivative0Weight = derivative0Info.weight;

    const totalWeight = await safEth.totalWeight();

    let lastDerivativeWithWeight;
    for (let i = 1; i < derivativeCount; i++) {
      const derivativeInfo = await safEth.derivatives(i);
      const weight = derivativeInfo.weight;
      if (weight.gt(0)) {
        lastDerivativeWithWeight = i;
      }
    }

    // then rebalance to weights
    for (let i = 1; i < derivativeCount; i++) {
      const derivativeInfo = await safEth.derivatives(i);
      const weight = derivativeInfo.weight;

      let derivative0SellAmount;

      // spercial case if derivative0 has 0 weight we must get rid of the dust
      if (derivative0Weight.eq(0) && i === lastDerivativeWithWeight) {
        derivative0SellAmount = await derivative0.balance();
        await safEth.derivativeRebalance(0, i, derivative0SellAmount);
      } else {
        derivative0SellAmount = derivative0StartingBalance
          .mul(weight)
          .div(totalWeight);
        await safEth.derivativeRebalance(0, i, derivative0SellAmount);
      }
    }
  };
});

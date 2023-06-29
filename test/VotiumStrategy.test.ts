import { network, ethers, upgrades } from "hardhat";
import { VotiumStrategy } from "../typechain-types";
import axios from "axios";
import ERC20 from "@openzeppelin/contracts/build/contracts/ERC20.json";
import { expect } from "chai";

describe("VotiumStrategy", async function () {
  let votiumStrategy: any;

  // mapping of token address to whale address
  const tokenWhales = {
    // ALCX
    "0xdbdb4d16eda451d0503b854cf79d55697f90c8df":
      "0x60457450ea6b05402e262df59a1b63539bd3403d",

    // CLEV
    "0x72953a5C32413614d24C29c84a66AE4B59581Bbf":
      "0xaf297dec752c909092a117a932a8ca4aaaff9795",

    // CNC
    "0x9aE380F0272E2162340a5bB646c354271c0F5cFC":
      "0x94dfce828c3daaf6492f1b6f66f9a1825254d24b",

    // CRV
    "0xD533a949740bb3306d119CC777fa900bA034cd52":
      "0x68bede1d0bc6be6d215f8f8ee4ee8f9fab97fe7a",

    // CVX
    "0x4e3fbd56cd56c3e72c1403e103b45db9da5b9d2b":
      "0x15a5f10cc2611bb18b18322e34eb473235efca39",

    // FXS
    "0x3432b6a60d23ca0dfca7761b7ab56459d9c964d0":
      "0xd53e50c63b0d549f142a2dcfc454501aaa5b7f3f",

    // GNO
    "0x6810e776880C02933D47DB1b9fc05908e5386b96":
      "0xa4a6a282a7fc7f939e01d62d884355d79f5046c1",

    // INV
    "0x41D5D79431A913C4aE7d69a668ecdfE5fF9DFB68":
      "0x4bef7e110d1a59a384220ede433fabd9aa2f4e06",

    // MET
    "0x2Ebd53d035150f328bd754D6DC66B99B0eDB89aa":
      "0xae362a72935dac355be989bf490a7d929f88c295",

    // OGV
    "0x9c354503C38481a7A7a51629142963F98eCC12D0":
      "0x1eb724a446ea4af61fb5f98ab15accd903583ccf",

    // SPELL
    "0x090185f2135308bad17527004364ebcc2d37e5f6":
      "0x7db408d4a2dee9da7cd8f45127badbaeac72ac29",

    // STG
    "0xaf5191b0de278c7286d6c7cc6ab6bb8a73ba2cd6":
      "0xd8d6ffe342210057bf4dcc31da28d006f253cef0",

    // TUSD
    "0x0000000000085d4780B73119b644AE5ecd22b376":
      "0x5ac8d87924255a30fec53793c1e976e501d44c78",

    // USDC
    "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48":
      "0x7713974908be4bed47172370115e8b1219f4a5f0",

    // USDD
    "0x0C10bF8FcB7Bf5412187A595ab97a3609160b5c6":
      "0x44aa0930648738b39a21d66c82f69e45b2ce3b47",
  };

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
    const votiumStrategyFactory = await ethers.getContractFactory(
      "VotiumStrategy"
    );
    votiumStrategy = (await upgrades.deployProxy(
      votiumStrategyFactory
    )) as VotiumStrategy;
    await votiumStrategy.deployed();
  };

  before(async () => {
    const result = await axios.get(
      `https://api.etherscan.io/api?module=proxy&action=eth_blockNumber&apikey=${process.env.ETHERSCAN_API_KEY}`
    );
    // Because of dependence on 0x api
    // These tests needs to run close to the latest block
    await resetToBlock(Number(result.data.result) - 6);
  });

  it("Should send the contract erc20s (mock rewards) and sell them all with sellErc20s()", async function () {
    const accounts = await ethers.getSigners();

    const tokens = Object.keys(tokenWhales);
    const whales = Object.values(tokenWhales);

    // send the whales some eth so they can send tokens
    for (let i = 0; i < whales.length; i++) {
      await accounts[0].sendTransaction({
        to: whales[i],
        value: "100000000000000000",
      });
    }
    // send the token some of each reward token
    for (let i = 0; i < tokens.length; i++) {
      await network.provider.request({
        method: "hardhat_impersonateAccount",
        params: [whales[i]],
      });
      const whaleSigner = await ethers.getSigner(whales[i]);
      const tokenContract = new ethers.Contract(
        tokens[i],
        ERC20.abi,
        whaleSigner
      );

      // special case for usdc 6 decimals
      const tokenAmount =
        tokens[i].toLowerCase() ===
        "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48".toLowerCase()
          ? "1000000"
          : "1000000000000000000"; // 1 token (assuming 1e18 = 1)
      await tokenContract.transfer(votiumStrategy.address, tokenAmount);
    }

    const swapsData = [];
    // swap reward tokens for eth
    for (let i = 0; i < tokens.length; i++) {
      const sellToken = tokens[i];
      const buyToken = "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE"; // weth

      // special case usdc 6 decimals
      const sellAmount =
        sellToken.toLowerCase() ===
        "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48".toLowerCase()
          ? "1000000"
          : "1000000000000000000"; // 1 token (assuming 1e18 = 1)

      // quote for cvx -> weth
      // TODO slippage protection
      const result = await axios.get(
        `https://api.0x.org/swap/v1/quote?buyToken=${buyToken}&sellToken=${sellToken}&sellAmount=${sellAmount}`,
        {
          headers: {
            "0x-api-key":
              process.env.API_KEY_0X || "35aa607c-1e98-4404-ad87-4bed10a538ae",
          },
        }
      );
      swapsData.push({
        sellToken,
        buyToken,
        spender: result.data.allowanceTarget,
        swapTarget: result.data.to,
        swapCallData: result.data.data,
      });
    }

    const erc20BalancesBefore = [];
    for (let i = 0; i < tokens.length; i++) {
      const tokenContract = new ethers.Contract(
        tokens[i],
        ERC20.abi,
        accounts[0]
      );
      erc20BalancesBefore.push(
        await tokenContract.balanceOf(votiumStrategy.address)
      );
    }
    const ethBalanceBefore = await ethers.provider.getBalance(
      votiumStrategy.address
    );
    const tx = await votiumStrategy.sellErc20s(swapsData);
    await tx.wait();

    const erc20BalancesAfter = [];
    for (let i = 0; i < tokens.length; i++) {
      const tokenContract = new ethers.Contract(
        tokens[i],
        ERC20.abi,
        accounts[0]
      );
      erc20BalancesAfter.push(
        await tokenContract.balanceOf(votiumStrategy.address)
      );
    }
    const ethBalanceAfter = await ethers.provider.getBalance(
      votiumStrategy.address
    );

    // check that it sold all erc20s in the strategy contract
    for (let i = 0; i < tokens.length; i++) {
      expect(erc20BalancesBefore[i]).to.be.gt(erc20BalancesAfter[i]);
      expect(erc20BalancesAfter[i]).to.be.eq(0);
    }

    // check that the strategy contract received eth
    expect(ethBalanceAfter).to.be.gt(ethBalanceBefore);
  });
});

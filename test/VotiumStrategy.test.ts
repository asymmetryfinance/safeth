import { network, ethers, upgrades } from "hardhat";
import { VotiumStrategy } from "../typechain-types";
import axios from "axios";
import { CVX_ADDRESS, CVX_WHALE } from "./helpers/constants";
import ERC20 from "@openzeppelin/contracts/build/contracts/ERC20.json";

describe.only("VotiumStrategy", async function () {
  let votiumStrategy: any;

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
    const result = await axios.get(`https://api.etherscan.io/api?module=proxy&action=eth_blockNumber&apikey=${process.env.ETHERSCAN_API_KEY}`)
    // Because of dependence on 0x api
    // These tests needs to run close to the latest block
    await resetToBlock(Number(result.data.result) - 6);
  });

  // TODO do this for the same tokens we would be rewarded by votium (add them to swapsData and transfer from whale accounts)
  it("Should send the contract erc20s (mock rewards) and sell them all with sellErc20s()", async function () {
    // send the strategy contract some cvx
    await network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [CVX_WHALE],
    });
    const whaleSigner = await ethers.getSigner(CVX_WHALE);
    const cvx = new ethers.Contract(CVX_ADDRESS, ERC20.abi, whaleSigner);
    const cvxAmount = ethers.utils.parseEther("100");
    await cvx.transfer(votiumStrategy.address, cvxAmount);

    const sellToken = CVX_ADDRESS;
    const buyToken = "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE"; // weth
    const sellAmount = "100000000000000000"; // 0.1 cvx

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

    const swapsData = [
      {
        sellToken,
        buyToken,
        spender: result.data.allowanceTarget,
        swapTarget: result.data.to,
        swapCallData: result.data.data,
      },
    ];

    console.log("about to swap erc20s");
    const tx = await votiumStrategy.sellErc20s(swapsData);
    await tx.wait();
    console.log("swaps done", tx);
  });
});

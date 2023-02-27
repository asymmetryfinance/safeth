import { BigNumberish, Contract, ethers } from "ethers";
import { balWeightedPoolFactoryAbi } from "./abi/balWeightedPoolFactoryAbi";
import { balWeightedPoolAbi } from "./abi/balWeightedPoolAbi";
import { WeightedPoolEncoder } from "@balancer-labs/balancer-js";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

export const WETH_ADDRESS = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2";
export const WSTETH_ADRESS = "0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0";
export const WSTETH_WHALE = "0xa0456eaae985bdb6381bd7baac0796448933f04f";
export const RETH_WHALE = "0xd1eeb369f312d0de3dd4812cfaabe052327d6b54";
export const ROCKET_STORAGE_ADDRESS =
  "0x1d8f8f00cfa6758d7bE78336684788Fb0ee0Fa46";
export const CRV_POOL_FACTORY = "0xF18056Bbd320E96A48e3Fbf8bC061322531aac99";
export const SFRAXETH_ADDRESS = "0xac3E018457B222d93114458476f3E3416Abbe38F";
export const SFRAXETH_WHALE = "0x4a41d76b0524a3989998380c033f12bfeb5f7201";
export const BALANCER_FACTORY_ADDRESS =
  "0x5Dd94Da3644DDD055fcf6B3E1aa310Bb7801EB8b";
export const BALANCER_VAULT_ADDRESS =
  "0xBA12222222228d8Ba445958a75a0704d566BF2C8";

export const createEqualWeightedPool = async (
  wstEth: Contract,
  sfrxEth: Contract,
  rEth: Contract,
  accounts: SignerWithAddress[]
) => {
  const assets = [wstEth.address, sfrxEth.address, rEth.address];

  // these must be sorted by address
  // must add up to 10^18
  const weights = [
    "533333333333333333",
    "133333333333333333",
    "333333333333333334",
  ];
  const name = "Test Pool";
  const symbol = "TP";

  // TODO verify that these are solid
  const priceFeeds = [
    "0x72D07D7DcA67b8A406aD1Ec34ce969c90bFEE768",
    "0x302013E7936a39c358d07A3Df55dc94EC417E3a1",
    "0x1a8F81c256aee9C640e14bB0453ce247ea0DFE6F",
  ];

  // 0.05%
  const swapFeePercentage = "500000000000000";

  const weightedPoolFactory = new ethers.Contract(
    BALANCER_FACTORY_ADDRESS,
    balWeightedPoolFactoryAbi,
    accounts[0]
  );
  const txResult = await weightedPoolFactory.create(
    name,
    symbol,
    assets,
    weights,
    priceFeeds,
    swapFeePercentage,
    accounts[0].address
  );

  const txReceipt = await (accounts[0] as any).provider.getTransactionReceipt(
    txResult.hash
  );

  const topic = txReceipt.logs[6].topics[1];

  const newPoolAddress = "0x" + topic.slice(topic.length - 40, topic.length);
  return new ethers.Contract(newPoolAddress, balWeightedPoolAbi, accounts[0]);
};

export const initJoinPool = async (
  wstEth: Contract,
  sfrxEth: Contract,
  rEth: Contract,
  accounts: SignerWithAddress[],
  amounts: BigNumberish[],
  balancerVault: Contract,
  balancerPool: Contract
) => {
  const assets = [wstEth.address, sfrxEth.address, rEth.address];

  const amountsIn = [amounts[0], amounts[1], amounts[2]];

  const result = await balancerVault.joinPool(
    await balancerPool.getPoolId(),
    accounts[0].address,
    accounts[0].address,
    {
      assets,
      maxAmountsIn: amountsIn,
      userData: WeightedPoolEncoder.joinInit(amountsIn),
      fromInternalBalance: false,
    }
  );

  return result.hash;
};

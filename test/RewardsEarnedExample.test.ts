import { BigNumber } from "ethers";
import { SafEth } from "../typechain-types";

import { getLatestContract } from "./helpers/upgradeHelpers";
import { expect } from "chai";

describe.only("Rewards Earned Example (SafEth)", function () {
  let safEthProxy: SafEth;

  before(async () => {
    safEthProxy = (await getLatestContract(
      "0x6732efaf6f39926346bef8b821a04b6361c4f3e5", // mainnet safEth
      "SafEth"
    )) as SafEth;
    await safEthProxy.deployed();
  });

  it("Should calculate all time rewards earned for an individual user (Including Trade Slippage)", async function () {
    // Expected to be negative because calculating it this way takes slippage into account
    // this account has had stakes & unstakes in a short period of time which eats into calculated rewards
    expect(await totalRewards("0x8a65ac0e23f31979db06ec62af62b132a6df4741")).eq(
      "-1157597513435707"
    );
  });

  const totalEthAdded = async (address: string) => {
    let ethIn = BigNumber.from(0);
    let ethOut = BigNumber.from(0);

    const stakeEvents = await getAllStakedEvents(address);
    const unstakeEvents = await getAllUnstakedEvents(address);

    for (let i = 0; i < stakeEvents.length; i++)
      ethIn = ethIn.add(stakeEvents[i]?.args?.ethIn ?? 0);
    for (let i = 0; i < unstakeEvents.length; i++)
      ethOut = ethOut.sub(unstakeEvents[i]?.args?.ethOut ?? 0);

    return ethIn.add(ethOut);
  };

  const totalRewards = async (address: string) => {
    const price = await safEthProxy.approxPrice();
    const balance = await safEthProxy.balanceOf(address);
    const totalEthValue = balance.mul(price).div("1000000000000000000");
    return totalEthValue.sub(await totalEthAdded(address));
  };

  // Staked (index_topic_1 address recipient, index_topic_2 uint256 ethIn, index_topic_3 uint256 totalStakeValue, uint256 price)
  const getAllStakedEvents = async (address: string) => {
    const safEthProxy = await getLatestContract(
      "0x6732efaf6f39926346bef8b821a04b6361c4f3e5", // mainnet safEth
      "SafEth"
    );
    await safEthProxy.deployed();

    const events = await safEthProxy.queryFilter("Staked", 0, "latest");
    return events.filter(
      (event) => event?.args?.recipient.toLowerCase() === address.toLowerCase()
    );
  };

  // Unstaked (index_topic_1 address recipient, index_topic_2 uint256 ethOut, index_topic_3 uint256 safEthIn)View Source
  const getAllUnstakedEvents = async (address: string) => {
    const safEthProxy = await getLatestContract(
      "0x6732efaf6f39926346bef8b821a04b6361c4f3e5", // mainnet safEth
      "SafEth"
    );
    await safEthProxy.deployed();
    const events = await safEthProxy.queryFilter("Unstaked", 0, "latest");
    return events.filter(
      (event) => event?.args?.recipient.toLowerCase() === address.toLowerCase()
    );
  };
});

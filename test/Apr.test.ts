import { ethers } from "hardhat";
import { BigNumber } from "ethers";

import { getLatestContract } from "./helpers/upgradeHelpers";
import { time } from "@nomicfoundation/hardhat-network-helpers";
import { expect } from "chai";

describe.only("Apr Example", async () => {
  it("Should get apr for mainnet deployed safEth", async () => {
    // get all past stake events
    const events = await getAllStakeEvents();

    // get the first event at least 7 days old
    // if no events > 7 days old it returns the oldest event
    const event = await getEventForApr(events, 60 * 60 * 24 * 7);

    // calculate apr between event and now
    const apr = await getAprFromEvent(event);

    // 4.15589% at block #17117200 (Apr-24-2023 04:17:11 PM +UTC)
    expect(apr).eq("0.041558983712487399");
  });
});

// calculate apr from the event time+price and current time+price
const getAprFromEvent = async (event: any) => {
  const safEthProxy = await getLatestContract(
    "0xc57319e15d5d78ba73c08c4e09d320705bd4478d", // mainnet safEth
    "SafEth"
  );
  await safEthProxy.deployed();

  const currentTime = BigNumber.from(
    (await ethers.provider.getBlock("latest")).timestamp
  );
  const currentPrice = await safEthProxy.approxPrice();

  const eventPrice = BigNumber.from(event?.args?.price);
  const eventTime = BigNumber.from(
    (await ethers.provider.getBlock(event?.blockNumber as number)).timestamp
  );

  const timeDiff = currentTime.sub(eventTime);
  const priceDiff = currentPrice.sub(eventPrice);
  // normalized in terms of wei for math because ethers BigNumber doesnt have decimals
  const priceDiffPerYear = ethers.utils.parseEther(
    priceDiff
      .mul(60 * 60 * 24 * 365)
      .div(timeDiff)
      .toString()
  );
  return ethers.utils.formatEther(priceDiffPerYear.div(eventPrice));
};

// find the first event that was at lease lengthOfTime ago
// return the oldest event if none are older than lengthOfTime
const getEventForApr = async (events: any, lengthOfTime: any) => {
  for (let i = events.length - 1; i >= 0; i--) {
    const block = await events[i].getBlock();
    const blockTime = block.timestamp;
    const currentTime = await time.latest();
    if (currentTime - blockTime >= lengthOfTime) {
      return events[i];
    }
  }
  return events[0];
};

const getAllStakeEvents = async () => {
  const safEthProxy = await getLatestContract(
    "0xc57319e15d5d78ba73c08c4e09d320705bd4478d", // mainnet safEth
    "SafEth"
  );
  await safEthProxy.deployed();
  return safEthProxy.queryFilter("Staked", 0, "latest");
};

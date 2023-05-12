import { BigNumber, utils } from "ethers";
import { SafEth } from "../typechain-types";
import { getLatestContract } from "./helpers/upgradeHelpers";
import { expect } from "chai";

describe.only("Rewards Earned Example (SafEth)", function () {
  let safEthProxy: SafEth;

  type StakeUnstakeEvent = {
    ethBalanceChange: BigNumber;
    safEthBalanceChange: BigNumber;
    price: BigNumber;
    txid: string;
  };

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
      "-1343020514632141"
    );
  });

  const totalEthInOut = async (address: string) => {
    const events = await getAllStakeUnstakeEvents(address);
    let total = BigNumber.from(0);

    for (let i = 0; i < events.length; i++)
      total = total.add(events[i].ethBalanceChange);
    return total.mul(-1);
  };

  const totalRewards = async (address: string) => {
    const price = await safEthProxy.approxPrice();
    const balance = await safEthProxy.balanceOf(address);
    const totalEthValue = balance.mul(price).div("1000000000000000000");
    console.log("totalEthValue", totalEthValue);
    const totalAdded = await totalEthInOut(address);

    console.log("totalEthAdded", totalAdded);
    console.log("totalEthValue", totalEthValue);
    return totalEthValue.sub(totalAdded);
  };

  // Staked (index_topic_1 address recipient, index_topic_2 uint256 ethIn, index_topic_3 uint256 totalStakeValue, uint256 price)
  const getAllStakeUnstakeEvents = async (
    address: string
  ): Promise<StakeUnstakeEvent[]> => {
    const safEthProxy = await getLatestContract(
      "0x6732efaf6f39926346bef8b821a04b6361c4f3e5", // mainnet safEth
      "SafEth"
    );
    await safEthProxy.deployed();

    const stakedEvents = await safEthProxy.queryFilter("Staked", 0, "latest");
    const filteredStakedEvents = stakedEvents.filter(
      (stakedEvent) =>
        stakedEvent?.args?.recipient.toLowerCase() === address.toLowerCase()
    );

    const formattedStakedEvents: StakeUnstakeEvent[] = filteredStakedEvents.map(
      (stakedEvent) => {
        return {
          ethBalanceChange: BigNumber.from(stakedEvent?.args?.ethIn).mul(-1),
          safEthBalanceChange: BigNumber.from(
            stakedEvent?.args?.totalStakeValue
          ).div(stakedEvent?.args?.price),
          price: stakedEvent?.args?.price,
          txid: stakedEvent?.transactionHash,
        };
      }
    );

    const formattedUnstakedEvents = await getAllUnstakedEvents(address);

    return formattedStakedEvents.concat(formattedUnstakedEvents);
  };

  const getAllUnstakedEvents = async (address: string) => {
    const safEthProxy = await getLatestContract(
      "0x6732efaf6f39926346bef8b821a04b6361c4f3e5", // mainnet safEth
      "SafEth"
    );
    await safEthProxy.deployed();

    const logsLegacy = await safEthProxy.provider.getLogs({
      fromBlock: 0,
      toBlock: "latest",
      address: safEthProxy.address,
      topics: [utils.id("Unstaked(address,uint256,uint256)")],
    });

    const logs = await safEthProxy.provider.getLogs({
      fromBlock: 0,
      toBlock: "latest",
      address: safEthProxy.address,
      topics: [utils.id("Unstaked(address,uint256,uint256,uint256)")],
    });

    const allLogs = logs.concat(logsLegacy);

    console.log("allLogs is", allLogs);
    const allLogsFiltered = allLogs.filter((log) =>
      log.topics[1].includes(address.toLowerCase().slice(2, 42))
    );

    return allLogsFiltered.map((log) => {
      return {
        ethBalanceChange: BigNumber.from(log.topics[2]),
        safEthBalanceChange: BigNumber.from(log.topics[3]).mul(-1),
        price: log.data !== "0x" ? BigNumber.from(log.data) : BigNumber.from(0),
        txid: log.transactionHash,
      };
    });
  };
});

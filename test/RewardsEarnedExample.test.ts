import { BigNumber, utils } from "ethers";
import { SafEth } from "../typechain-types";
import { getLatestContract } from "./helpers/upgradeHelpers";

describe.only("Rewards Earned Example (SafEth)", function () {
  let safEthProxy: SafEth;

  type StakeUnstakeEvent = {
    ethBalanceChange: BigNumber;
    safEthBalanceChange: BigNumber;
    price: BigNumber;
    txid: string;
    blockNumber: number;
  };

  type StakeRewardRange = {
    safEthBalance: BigNumber;
    priceChange: BigNumber;
  };

  before(async () => {
    safEthProxy = (await getLatestContract(
      "0x6732efaf6f39926346bef8b821a04b6361c4f3e5", // mainnet safEth
      "SafEth"
    )) as SafEth;
    await safEthProxy.deployed();
  });

  it.only("Should calculate all time rewards earned for an individual user (Excluding Trade Slippage)", async function () {
    console.log(
      "totalRewards",
      await totalRewards("0x8a65ac0e23f31979db06ec62af62b132a6df4741")
    );
  });

  const totalRewards = async (address: string) => {
    const events = await getAllStakeUnstakeEvents(address);

    let runningTotal = BigNumber.from(0);

    const rewardRanges: StakeRewardRange[] = [];

    for (let i = 0; i < events.length - 1; i++) {
      runningTotal = runningTotal.add(events[i].safEthBalanceChange ?? "0");
      const priceChange = events[i + 1].price.sub(events[i].price);
      const safEthBalance = runningTotal;
      rewardRanges.push({ safEthBalance, priceChange });
    }

    const currentPrice = await safEthProxy.approxPrice();
    // special case: add the range from from last event to now
    rewardRanges.push({
      safEthBalance: runningTotal,
      priceChange: currentPrice.sub(events[events.length - 1].price),
    });

    let sum = BigNumber.from(0);

    for (let i = 0; i < rewardRanges.length; i++) {
      const reward = rewardRanges[i].safEthBalance
        .mul(rewardRanges[i].priceChange)
        .div("1000000000000000000");
      sum = sum.add(reward);
    }

    return sum;
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
          blockNumber: stakedEvent?.blockNumber,
        };
      }
    );

    const formattedUnstakedEvents = await getAllUnstakedEvents(address);

    const allFormattedEvents = formattedStakedEvents.concat(
      formattedUnstakedEvents
    );

    // sort by block number
    const allFormattedEventsSorted = allFormattedEvents.sort((a, b) => {
      return a.blockNumber - b.blockNumber;
    });

    let index;
    for (let i = allFormattedEventsSorted.length - 1; i >= 0; i--) {
      if (allFormattedEventsSorted[i].price.eq("1000000000000000000")) {
        index = i;
        break;
      }
    }
    // Only include events from the last time price was exactly 10e18
    // Anything before is us testing staking and unstaking and will be inaccurate
    const eventsFromStart = allFormattedEventsSorted.slice(
      index,
      allFormattedEventsSorted.length
    );

    // fill in price for any unstaked events from before the upgrade that dont have it
    // use the closest non-zero previous price price (this should be the last stake event)
    for (let i = 0; i < eventsFromStart.length; i++) {
      if (eventsFromStart[i].price.eq(0)) {
        let j = i - 1;
        while (j > 0 && eventsFromStart[j].price.eq(0)) {
          j--;
        }
        eventsFromStart[i].price = eventsFromStart[j].price;
      }
    }

    return eventsFromStart;
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

    const allLogsFiltered = allLogs.filter((log) =>
      log.topics[1].includes(address.toLowerCase().slice(2, 42))
    );

    return allLogsFiltered.map((log) => {
      return {
        ethBalanceChange: BigNumber.from(log.topics[2]),
        safEthBalanceChange: BigNumber.from(log.topics[3]).mul(-1),
        price: log.data !== "0x" ? BigNumber.from(log.data) : BigNumber.from(0),
        txid: log.transactionHash,
        blockNumber: log.blockNumber,
      };
    });
  };
});

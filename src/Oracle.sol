// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/// @title CVX/ETH Conversion Contract
/// @notice Contract that returns the latest Chainlink price feed CVX/ETH pair
contract Conversion {
    AggregatorV3Interface internal immutable priceFeed;

    // @notice Executes once when a contract is created to initialize state variables
    // @param _priceFeed - Price Feed Address
    // Network: Mainnet
    // Aggregator: CVX/ETH
    // Address: 0xc9cbf687f43176b302f03f5e58470b77d07c61c6
    constructor() {
        priceFeed = AggregatorV3Interface(
            0xC9CbF687f43176B302F03f5e58470b77D07c61c6
        );
    }

    // @notice Returns the latest price of CVX for 16ETH (CVX/ETH pair)
    // @return latest price
    function getLatestPrice() public view returns (int256) {
        (, int256 price, , , ) = priceFeed.latestRoundData();
        int256 newVal = 16000000000000000000 / price;
        return newVal;
    }

    // @notice Returns the Price Feed address
    // @return Price Feed address
    function getPriceFeed() public view returns (AggregatorV3Interface) {
        return priceFeed;
    }
}

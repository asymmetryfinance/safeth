// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "../SafEth/SafEth.sol";
import "./SafEthV2MockStorage.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/chainlink/IChainlinkFeed.sol";

contract ChainLinkWstFeedMock is IChainlinkFeed {
    constructor() {}

    function latestRoundData()
        external
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        return (
            uint80(18446744073709552224),
            int256(998601010000000000),
            0,
            block.timestamp,
            0
        );
    }
}

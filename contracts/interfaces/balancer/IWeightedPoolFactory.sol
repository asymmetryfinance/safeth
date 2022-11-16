// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "../IERC20.sol";
import "./IRateProvider.sol";

interface IWeightedPoolFactory {
    function create(
        string memory name,
        string memory symbol,
        IERC20[] memory tokens,
        uint256[] memory normalizedWeights,
        uint256 swapFeePercentage,
        address owner
    ) external returns (address);
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "../IERC20.sol";

interface IInvestmentPoolFactory {
    function create(
        string memory name,
        string memory symbol,
        IERC20[] memory tokens,
        uint256[] memory weights,
        uint256 swapFeePercentage,
        address owner,
        bool swapEnabledOnStart,
        uint256 managementSwapFeePercentage
    ) external returns (address);
}

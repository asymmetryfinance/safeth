// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IWarden {
    function buyDelegationBoost(
        address delegator,
        address receiver,
        uint256 amount,
        uint256 duration,
        uint256 maxFeeAmount
    ) external returns (uint256);

    function estimateFees(
        address delegator,
        uint256 amount,
        uint256 duration
    ) external view returns (uint256);
}

//interface IWarden {}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IStrategy {
    function want() external view returns (address);

    function stake(address user, uint256 assets) external;

    function unstake(address user, bool decision) external;

    function balanceOf() external view returns (uint256);

    function getPool() external view returns (address);
}

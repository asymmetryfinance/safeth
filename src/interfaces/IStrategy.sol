// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IStrategy {
    function want() external view returns (address);

    function openPosition(address user, uint256 assets) external;

    function closePosition(address user) external;

    function balanceOf() external view returns (uint256);

    function getPool() external view returns (address);
}

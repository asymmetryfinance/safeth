// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IStrategy {
    function want() external view returns (address);

    function deposit(address currentDepositor, uint256 assets) external;

    function withdraw() external;

    function balanceOf() external view returns (uint256);

    function getPool() external view returns (address);
}

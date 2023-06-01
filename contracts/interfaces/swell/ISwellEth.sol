// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

// I couldnt find an official interface so I added the functions we need here
// https://etherscan.io/address/0x3ed1dfbccf893b7d2d730ead3e5edbf1f8f95a48#code
interface ISwellEth {
    function deposit() external payable;

    function swETHToETHRate() external view returns (uint256);
}

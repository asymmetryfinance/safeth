// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface ISwellEth {
    function deposit() external payable;

    function swETHToETHRate() external view returns (uint256);
}

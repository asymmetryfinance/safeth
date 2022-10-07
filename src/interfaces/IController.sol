// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IController {
    function deposit(
        address,
        address,
        uint256
    ) external;

    function withdraw(
        address,
        address,
        uint256,
        bool
    ) external;

    function balanceOf(address) external view returns (uint256);

    //function vaults(address) external view returns (address);

    function getStrategy(address) external view returns (address);

    function getVault(address) external view returns (address);
}

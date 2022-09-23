// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IController {
    function deposit(
        address,
        address,
        uint256
    ) external;

    function withdraw(
        address _token,
        address user,
        uint256 amount
    ) external;

    function balanceOf(address) external view returns (uint256);

    function vaults(address) external view returns (address);

    function getStrategy(address _token) external view returns (address strat);
}

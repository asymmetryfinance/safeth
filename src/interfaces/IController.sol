// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IController {
    function deposit(
        address,
        address,
        uint256
    ) external;

    function withdraw(address, uint256) external;

    function balanceOf(address) external view returns (uint256);

    function earn(address, uint256) external;

    function want(address) external view returns (address);

    function rewards() external view returns (address);

    function vaults(address) external view returns (address);

    function getStrategy(address _token) external view returns (address strat);
}

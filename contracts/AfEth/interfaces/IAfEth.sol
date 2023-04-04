// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IAfEth is IERC20 {
    function mint(address recipient, uint256 amount) external;

    function burn(address from, uint256 amount) external;
}


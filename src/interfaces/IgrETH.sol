// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./IERC20.sol";

interface IgrETH is IERC20 {
    function mint(address to, uint256 amount) external;
}

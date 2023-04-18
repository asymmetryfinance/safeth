// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IStakewiseStaker is IERC20 {
    function stake() external payable;

    function minActivatingDeposit() external returns (uint256);
}

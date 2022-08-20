// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// import "./interfaces/RocketStorageInterface.sol";
// import "./interfaces/RocketDepositPoolInterface.sol";
// import "./interfaces/RocketETHTokenInterface.sol";

import "./interfaces/IStrategy.sol";
import "./interfaces/ICurve.sol";

/// @title Golden Ratio grETH Curve autocompounding strategy
/// @notice This strategy autocompounds Curve rewards from the ETH/grETH Curve pool.
/// @dev The strategy deposits ETH into the Curve Pool
/// The strategy will also deposit funds into the Balancer whitelisted index of liquid staked ETH tokens
contract GRStrategy is IStrategy {
    address public curveFi_Deposit;

    function setup(address _depositContract, address _gaugeContract) external {}

    function crvDeposit() external {}
}

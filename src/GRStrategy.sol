// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./interfaces/curve/ICurve.sol";

/**
 * @title Golden Ratio Base ETH Strategy
 * @notice This strategy autocompounds Convex rewards from the PUSD/USDC/USDT/DAI Curve pool
 * @dev The strategy deposits 33.3% ETH in the ETH/grETH Curve pool, swaps 33.3% ETH for CVX and locks up CVX,
 * and deposits remaining 33.3% ETH into liquid staked ETH Balancer pool
 */
contract GRStrategy {

}

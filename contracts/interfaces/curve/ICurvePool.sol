// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/**
 * @dev Interface for Curve.Fi deposit contract for 3pool.
 * @dev See original implementation in official repository:
 * https://github.com/curvefi/curve-contract/blob/master/contracts/pools/3pool/StableSwap3Pool.vy
 */
interface ICurvePool {
    function deploy_pool(
        string memory _name,
        string memory _symbol,
        address[2] memory _coins,
        uint256 _A,
        uint256 _gamma,
        uint256 _mid_fee,
        uint256 _out_fee,
        uint256 _allowed_extra_profit,
        uint256 _fee_gamma,
        uint256 _adjustment_step,
        uint256 _admin_fee,
        uint256 _ma_half_time,
        uint256 _initial_price
    ) external returns (address);
}

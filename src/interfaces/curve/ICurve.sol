// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @dev Interface for Curve.Fi exchange.
 * @dev See original implementation in official repository:
 * https://github.com/curvefi/curve-contract/blob/master/contracts/pool-templates/base/SwapTemplateBase.vy
 */
interface ICurve is IERC20 {
    function balances(uint256 index) external view returns (uint256);

    function exchange(
        uint256 i,
        uint256 j,
        uint256 _dx,
        uint256 _min_dy
    ) external payable returns (uint256);
}

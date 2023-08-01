// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

abstract contract IStafiRateProvider is IERC20 {
    function getRate() external view virtual returns (uint256);
}

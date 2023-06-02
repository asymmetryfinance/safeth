// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

abstract contract IStafi is IERC20 {
    function getExchangeRate() external view virtual returns (uint256);
}

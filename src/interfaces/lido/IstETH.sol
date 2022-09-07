// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {ERC20} from "solmate/tokens/ERC20.sol";

abstract contract IStETH is ERC20 {
    function getTotalShares() external view virtual returns (uint256);
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {ERC20} from "solmate/tokens/ERC20.sol";

abstract contract IWStETH is ERC20 {
    function unwrap(uint256 _wstETHAmount) external virtual returns (uint256);

    function getWstETHByStETH(uint256 _stETHAmount)
        external
        view
        virtual
        returns (uint256);

    function getStETHByWstETH(uint256 _wstETHAmount)
        external
        view
        virtual
        returns (uint256);

    /**
     * @notice Get amount of stETH for a one wstETH
     * @return Amount of stETH for 1 wstETH
     */
    function stEthPerToken() external view virtual returns (uint256);

    receive() external payable virtual;
}

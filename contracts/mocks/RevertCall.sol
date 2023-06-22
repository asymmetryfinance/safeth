// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "../SafEth/derivatives/WstEth.sol";
import "../SafEth/derivatives/Reth.sol";

/// @title Derivative contract for testing contract upgrades
/// @author Asymmetry Finance
contract RevertCall {
    constructor() {}

    function testDeposit(address payable _contract) external payable {
        WstEth(_contract).deposit{value: msg.value}();
    }

    function testWithdraw(address payable _contract, uint256 _amount) external {
        WstEth(_contract).withdraw(_amount);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "../SafEth/derivatives/WstEth.sol";

/// @title Derivative contract for testing contract upgrades
/// @author Asymmetry Finance
contract RevertCall {
    constructor() {}

    function testFinalCall(address payable _contract) external {
        WstEth(_contract).deposit();
    }
}

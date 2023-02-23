// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "../../interfaces/Iderivative.sol";

// Upgradeability Rules:
// DO NOT change existing variable names or types
// DO NOT change order of variables
// DO NOT remove any variables
// ONLY add new variables at the end
// Constant values CAN be modified on upgrade
contract AfStrategyV2MockStorage {
    address public afETH;
    bool public pauseStaking;
    bool public pauseUnstaking;
    uint256 public derivativeCount;
    mapping(uint => IDERIVATIVE) public derivatives;
    mapping(uint => uint) public weights;

    bool public newFunctionCalled;
}
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "../interfaces/IDerivative.sol";

// Upgradeability Rules:
// DO NOT change existing variable names or types
// DO NOT change order of variables
// DO NOT remove any variables
// ONLY add new variables at the end
// Constant values CAN be modified on upgrade
contract AfStrategyStorage {
    address public safETH;
    bool public pauseStaking;
    bool public pauseUnstaking;
    uint256 public derivativeCount;
    uint256 public totalWeight;
    uint256 public minAmount;
    uint256 public maxAmount;
    mapping(uint256 => IDerivative) public derivatives;
    mapping(uint256 => uint256) public weights;
}

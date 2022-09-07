// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

contract StrategyGoldenRatio {
    address public governance;
    address public controller;
    address public strategist;

    constructor(address _controller) {
        governance = msg.sender;
        strategist = msg.sender;
        controller = _controller;
    }

    function getName() external pure returns (string memory) {
        return "StrategyGoldenRatio";
    }
}

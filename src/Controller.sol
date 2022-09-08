// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IERC20} from "./interfaces/IERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import "./StrategyGoldenRatio.sol";

contract Controller {
    address public governance;
    address public strategist;

    address public rewards;
    mapping(address => address) public vaults;
    mapping(address => address) public strategies;

    mapping(address => mapping(address => bool)) public approvedStrategies;

    constructor(address _rewards) {
        governance = msg.sender;
        strategist = msg.sender;
        rewards = _rewards;
    }

    function setRewards(address _rewards) public {
        require(msg.sender == governance, "!governance");
        rewards = _rewards;
    }

    function setStrategist(address _strategist) public {
        require(msg.sender == governance, "!governance");
        strategist = _strategist;
    }

    function setGovernance(address _governance) public {
        require(msg.sender == governance, "!governance");
        governance = _governance;
    }

    function setVault(address _token, address _vault) public {
        require(
            msg.sender == strategist || msg.sender == governance,
            "!strategist"
        );
        require(vaults[_token] == address(0), "vault");
        vaults[_token] = _vault;
    }

    function approveStrategy(address _token, address _strategy) public {
        require(msg.sender == governance, "!governance");
        approvedStrategies[_token][_strategy] = true;
    }

    function revokeStrategy(address _token, address _strategy) public {
        require(msg.sender == governance, "!governance");
        approvedStrategies[_token][_strategy] = false;
    }

    function setStrategy(address _token, address _strategy) public {
        require(
            msg.sender == strategist || msg.sender == governance,
            "!strategist"
        );
        require(approvedStrategies[_token][_strategy] == true, "!approved");

        //address _current = strategies[_token];
        strategies[_token] = _strategy;
    }
}

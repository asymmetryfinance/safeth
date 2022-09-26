// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IERC20} from "./interfaces/IERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import "./StrategyGoldenRatio.sol";
import "./interfaces/IStrategy.sol";

contract Controller {
    address public governance;
    address public strategist;

    mapping(address => address) public vaults;
    mapping(address => address) public strategies;

    mapping(address => mapping(address => bool)) public approvedStrategies;

    constructor() {
        governance = msg.sender;
        strategist = msg.sender;
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

        address _current = strategies[_token];
        if (_current != address(0)) {
            // withdraw all funds from current strategy
            //IStrategy(_current).withdraw();
        }
        strategies[_token] = _strategy;
    }

    function getStrategy(address _token) public view returns (address strat) {
        return (strategies[_token]);
    }

    function deposit(
        address _token,
        address _user,
        uint256 amount
    ) public {
        require(msg.sender == vaults[_token], "!vault");
        IStrategy(strategies[_token]).deposit(_user, amount);
    }

    function withdraw(
        address _token,
        address _user,
        uint256 _amount
    ) public {
        require(msg.sender == vaults[_token], "!vault");
        IStrategy(strategies[_token]).withdraw(_user);
    }
}

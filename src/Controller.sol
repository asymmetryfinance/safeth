// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IERC20} from "./interfaces/IERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import "./interfaces/IStrategy.sol";

contract Controller {
    address public strategist;
    address owner;

    address public rewards;
    mapping(address => address) public vaults;
    mapping(address => address) public strategies;

    mapping(address => mapping(address => bool)) public approvedStrategies;

    uint256 public constant max = 10000;

    constructor(address _rewards) {
        owner = msg.sender;
        strategist = msg.sender;
        rewards = _rewards;
    }

    function setRewards(address _rewards) public {
        require(msg.sender == owner, "!owner");
        rewards = _rewards;
    }

    function setStrategist(address _strategist) public {
        require(msg.sender == owner, "!owner");
        strategist = _strategist;
    }

    function setVault(address _token, address _vault) public {
        require(msg.sender == strategist || msg.sender == owner, "!strategist");
        require(vaults[_token] == address(0), "vault");
        vaults[_token] = _vault;
    }

    function approveStrategy(address _token, address _strategy) public {
        require(msg.sender == owner, "!owner");
        approvedStrategies[_token][_strategy] = true;
    }

    function revokeStrategy(address _token, address _strategy) public {
        require(msg.sender == owner, "!owner");
        approvedStrategies[_token][_strategy] = false;
    }

    function setStrategy(address _token, address _strategy) public {
        require(msg.sender == strategist || msg.sender == owner, "!strategist");
        require(approvedStrategies[_token][_strategy] == true, "!approved");

        address _current = strategies[_token];
        if (_current != address(0)) {
            IStrategy(_current).withdrawAll();
        }
        strategies[_token] = _strategy;
    }

    function earn(address _token, uint256 _amount) public {
        address _strategy = strategies[_token];
        address _want = IStrategy(_strategy).want();
        if (_want != _token) {
            IERC20(_want).transfer(_strategy, _amount);
        } else {
            IERC20(_token).transfer(_strategy, _amount);
            IStrategy(_strategy).deposit();
        }
    }

    function balanceOf(address _token) external view returns (uint256) {
        return IStrategy(strategies[_token]).balanceOf();
    }

    function withdrawAll(address _token) public {
        require(msg.sender == strategist || msg.sender == owner, "!strategist");
        IStrategy(strategies[_token]).withdrawAll();
    }

    function inCaseTokensGetStuck(address _token, uint256 _amount) public {
        require(msg.sender == strategist || msg.sender == owner, "!owner");
        IERC20(_token).transfer(msg.sender, _amount);
    }

    function inCaseStrategyTokenGetStuck(address _strategy, address _token)
        public
    {
        require(msg.sender == strategist || msg.sender == owner, "!owner");
        IStrategy(_strategy).withdraw(_token);
    }

    function withdraw(address _token, uint256 _amount) public {
        require(msg.sender == vaults[_token], "!vault");
        IStrategy(strategies[_token]).withdraw(_amount);
    }
}

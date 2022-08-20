// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IStrategy.sol";

/// @title Golden Ratio vault
/// @notice Allows users to deposit ETH/CVX into autocompounding strategy contract (e.g. {GRStrategy}).
contract Vault {
    // event Deposit(address indexed from, address indexed to, uint256 value);

    struct Rate {
        uint128 numerator;
        uint128 denominator;
    }

    IStrategy public strategy;

    address[] private funders;

    address public feeRecipient;

    uint256 public assetsDeposited;

    Rate public depositFeeRate;

    mapping(address => uint256) private addressToAmountFunded;

    /// @notice Allows users to deposit `token`. Contracts can't call this function
    /// @param _amount The amount to deposit
    function deposit(uint256 _amount) external {
        require(_amount == 48 ether, "INVALID_AMOUNT");

        IStrategy _strategy = strategy;
        require(address(_strategy) != address(0), "NO_STRATEGY");

        uint256 depositFee = (depositFeeRate.numerator * _amount) /
            depositFeeRate.denominator;
        uint256 amountAfterFee = _amount - depositFee;

        addressToAmountFunded[msg.sender] += amountAfterFee;
        assetsDeposited += amountAfterFee;
        funders.push(msg.sender);

        // emit Deposit(msg.sender, _to, amountAfterFee);
    }

    function totalAssets() public view returns (uint256) {
        return assetsDeposited;
    }
}

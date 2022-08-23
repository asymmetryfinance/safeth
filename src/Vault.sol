// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {ERC4626} from "solmate/mixins/ERC4626.sol";

/// @title Golden Ratio vault
/// @notice Allows users to deposit ETH/CVX into autocompounding strategy contract (e.g. {GRStrategy}).
contract Vault is ERC4626 {
    // event Deposit(address indexed from, address indexed to, uint256 value);

    struct Rate {
        uint128 numerator;
        uint128 denominator;
    }

    address[] private funders;

    address public feeRecipient;

    uint256 public assetsDeposited;

    Rate public depositFeeRate;

    mapping(address => uint256) private addressToAmountFunded;

    /// @notice Allows users to deposit `token`. Contracts can't call this function
    /// @param _amount The amount to deposit
    function deposit(uint256 _amount) external {
        require(_amount == 48 ether, "INVALID_AMOUNT");

        //uint256 depositFee = (depositFeeRate.numerator * _amount) /
        //depositFeeRate.denominator;
        // uint256 amountAfterFee = _amount - depositFee;

        addressToAmountFunded[msg.sender] += _amount;
        assetsDeposited += _amount;
        funders.push(msg.sender);

        // emit Deposit(msg.sender, _to, amountAfterFee);
    }
}

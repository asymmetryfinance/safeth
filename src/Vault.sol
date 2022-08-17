// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";

/// @title Golden Ratio vault
/// @notice Allows users to deposit ETH/CVX into autocompounding strategy contracts (e.g. {CrvDepositor}).
contract Vault {
    // event Deposit(uint256 value);
    // event Deposit(address indexed from, address indexed to, uint256 value);

    struct Rate {
        uint128 numberator;
        uint128 denominator;
    }

    address[] private funders;
    address public feeRecipient;
    uint256 public assetsDeposited;
    Rate public depositFeeRate;
    mapping(address => uint256) private addressToAmountFunded;

    // function initialize() external initializer {}

    /// @notice Allows users to deposit `token`. Contracts can't call this function
    /// @param _amount The amount to deposit
    function deposit(uint256 _amount) external {
        uint256 amount = _amount;
        require(amount == 48 ether, "INVALID_AMOUNT");

        addressToAmountFunded[msg.sender] += amount;
        assetsDeposited += amount;
        funders.push(msg.sender);

        // emit Deposit(amount);
        // emit Deposit(msg.sender, _to, amountAfterFee);
    }

    function totalAssets() public view returns (uint256) {
        return assetsDeposited;
    }
}

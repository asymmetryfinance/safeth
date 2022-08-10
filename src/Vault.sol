// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

// imports
// import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title Golden Ratio vault
/// @notice Allows users to deposit ETH/CVX into autocompounding strategy contracts (e.g. {StrategyCRV}).
contract Vault {
    event Deposit(uint256 value);

    address[] private funders;
    mapping(address => uint256) private addressToAmountFunded;

    /// @notice Allows users to deposit `token`. Contracts can't call this function
    /// @param _amount The amount to deposit
    function deposit(uint256 _amount) public payable {
        uint256 amount = _amount;
        require(amount == 48 ether, "INVALID_AMOUNT");

        addressToAmountFunded[msg.sender] += amount;
        funders.push(msg.sender);

        emit Deposit(amount);
    }
}

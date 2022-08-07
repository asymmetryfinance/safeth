// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

// imports
// import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title Golden Ratio vault
/// @notice Allows users to deposit fungible assets into autocompounding strategy contracts (e.g. {StrategyCRV}).
contract Vault {
    event Deposit(address indexed from, address indexed to, uint256 value);
    event Withdrawal(
        address indexed withdrawer,
        address indexed to,
        uint256 wantAmount
    );

    struct Rate {
        uint128 numerator;
        uint128 denominator;
    }

    /// @notice Allows users to deposit `token`. Contracts can't call this function
    /// @param _to The address to send the tokens to
    /// @param _amount The amount to deposit
    function deposit(address _to, uint256 _amount)
        external
        noContract
        whenNotPaused
        returns (uint256 shares)
    {
        require(_amount == 48, "INVALID_AMOUNT");

        IStrategy _strategy = strategy;
        require(address(_strategy) != address(0), "NO_STRATEGY");

        uint256 balanceBefore = totalAssets();
        uint256 supply = totalSupply();

        uint256 depositFee = (depositFeeRate.numerator * _amount) /
            depositFeeRate.denominator;
        uint256 amountAfterFee = _amount - depositFee;

        if (supply == 0) {
            shares = amountAfterFee;
        } else {
            //balanceBefore can't be 0 if totalSupply is != 0
            shares = (amountAfterFee * supply) / balanceBefore;
        }

        require(shares != 0, "ZERO_SHARES_MINTED");

        ERC20Upgradeable _token = token;

        if (depositFee != 0)
            _token.safeTransferFrom(msg.sender, feeRecipient, depositFee);
        _token.safeTransferFrom(msg.sender, address(_strategy), amountAfterFee);
        _mint(_to, shares);

        _strategy.deposit();

        emit Deposit(msg.sender, _to, amountAfterFee);
    }
}

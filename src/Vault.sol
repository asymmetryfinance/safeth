// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

// imports
// import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title Golden Ratio vault
/// @notice Allows users to deposit ETH/CVX into autocompounding strategy contracts (e.g. {StrategyCRV}).
contract Vault {
    event Deposit(address indexed from, address indexed to, uint256 value);
    // event Withdrawal(address indexed withdrawer, address indexed to, uint256 wantAmount);

    struct Rate {
        uint128 numberator;
        uint128 denominator;
    }

    /// @return assets The total amount of tokens managed by this vault
    function totalAssets() public view returns (uint256 assets) {
        assets = token.balanceOf(address(this));
    }

    /// @notice Allows users to deposit `token`. Contracts can't call this function
    /// @param _to The address to send the tokens to
    /// @param _amount The amount to deposit
    function deposit(address _to, uint256 _amount)
        external
        returns (uint256 shares)
    {
        require(_amount != 0, "INVALID_AMOUNT");

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
    }
}

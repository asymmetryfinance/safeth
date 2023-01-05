// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./interfaces/IWETH.sol";
import "hardhat/console.sol";

contract Vault is ERC4626 {
    using SafeERC20 for IERC20;
    ERC20 public immutable token;

    constructor(
        address _token,
        string memory _name,
        string memory _symbol
    ) ERC4626(IERC20(_token)) ERC20(_name, _symbol) {
        token = ERC20(_token);
    }

    // function deposit(uint256 amount, address receiver)
    //     public
    //     override
    //     returns (uint256 shares)
    // {
    //     // Check for rounding error since we round down in previewDeposit.
    //     require((shares = previewDeposit(amount)) != 0, "ZERO_SHARES");

    //     // No need to transfer 'want' token as ETH has already been sent
    //     // asset.safeTransferFrom(msg.sender, address(this), assets);
    //     _mint(receiver, shares);

    //     emit Deposit(msg.sender, receiver, amount, shares);

    // }

    // function withdraw(
    //     uint256 assets,
    //     address receiver,
    //     address owner,
    //     bool cvxNftDecision
    // ) public returns (uint256 shares) {
    //     shares = previewWithdraw(assets);
    //     // beforeWithdraw(assets, cvxNftDecision);

    //     //_burn(owner, shares);

    //     //emit Withdraw(msg.sender, receiver, owner, assets, shares);

    //     // Send deposited ETH back to user
    //     //(bool sent, ) = receiver.call{value: assets}("");
    //     //require(sent, "Failed to send Ether");
    // }

    // Primary entrance into Asymmetry Finance Vault
    // vault can receive ether and wrap as underlying token (WETH)
    // function _deposit() public payable returns (uint256 shares) {
    //     // update balance of ETH deposited in AF Vault
    //     totalEthAmount += msg.value;
    //     // update count of funds in vault
    //     WETH.deposit{value: msg.value}();
    //     uint256 sharesMinted = deposit(msg.value, msg.sender);
    //     return sharesMinted;
    // }

    /// @notice Total amount of the underlying asset that
    /// is "managed" by Vault.
    // function totalAssets() public view override returns (uint256) {
    //     return totalEthAmount;
    // }
}

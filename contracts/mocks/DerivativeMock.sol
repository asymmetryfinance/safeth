// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "./IDerivativeMock.sol";
import "../interfaces/frax/IsFrxEth.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/curve/ICrvEthPool.sol";
import "hardhat/console.sol";
import "../AfStrategy/derivatives/SfrxEth.sol";

/// @title Derivative contract for testing contract upgrades
/// @author Asymmetry Finance
contract DerivativeMock is SfrxEth {
    /**
        @notice - New function to test upgrading a contract and using new functionality
        */
    function withdrawAll() public onlyOwner {
        IsFrxEth(sfrxEthAddress).redeem(
            balance(),
            address(this),
            address(this)
        );
        uint256 frxEthBalance = IERC20(frxEthAddress).balanceOf(address(this));
        IsFrxEth(frxEthAddress).approve(frxEthCrvPoolAddress, frxEthBalance);
        ICrvEthPool(frxEthCrvPoolAddress).exchange(1, 0, frxEthBalance, 0);
        (bool sent, ) = address(msg.sender).call{value: address(this).balance}(
            ""
        );
        require(sent, "Failed to send Ether");
    }
}
